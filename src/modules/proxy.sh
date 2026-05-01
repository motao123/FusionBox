# FusionBox 代理管理模块
# 支持多后端：Xray-core、v2ray-core、sing-box、Clash.Meta

# ---- 路径定义 ----
P_BASE_DIR="/etc/fusionbox/proxy"
P_BIN_DIR="$P_BASE_DIR/bin"
P_CONF_DIR="$P_BASE_DIR/conf"
P_LOG_DIR="/var/log/fusionbox-proxy"
P_SERVICE_DIR="/etc/systemd/system"

# ---- 支持的后端 ----
P_BACKENDS=(
  "xray:Xray:https://github.com/XTLS/Xray-core"
  "v2ray:v2ray:https://github.com/v2fly/v2ray-core"
  "sing-box:sing-box:https://github.com/SagerNet/sing-box"
  "clash-meta:Clash.Meta:https://github.com/MetaCubeX/mihomo"
)

# ---- 支持的协议 ----
P_PROTOCOLS=(
  "VLESS-TCP"       "vless"   "tcp"
  "VLESS-WS"        "vless"   "ws"
  "VLESS-GRPC"      "vless"   "grpc"
  "VLESS-HTTPUpgrade" "vless" "httpupgrade"
  "VMess-TCP"       "vmess"   "tcp"
  "VMess-WS"        "vmess"   "ws"
  "VMess-GRPC"      "vmess"   "grpc"
  "VMess-HTTPUpgrade" "vmess" "httpupgrade"
  "Trojan-TCP"      "trojan"  "tcp"
  "Trojan-WS"       "trojan"  "ws"
  "Trojan-GRPC"     "trojan"  "grpc"
  "Hysteria2"       "hysteria2" "udp"
  "TUIC"            "tuic"    "udp"
  "Shadowsocks"     "shadowsocks" "tcp"
  "SOCKS5"          "socks"   "tcp"
)

# ---- 主入口 ----
proxy_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    install|i)      proxy_install "$@" ;;
    uninstall|un)   proxy_uninstall "$@" ;;
    add|a)          proxy_add "$@" ;;
    del|d|remove)   proxy_del "$@" ;;
    list|l)         proxy_list ;;
    info)           proxy_info "$@" ;;
    start)          proxy_service "start" ;;
    stop)           proxy_service "stop" ;;
    restart)        proxy_service "restart" ;;
    status|s)       proxy_status ;;
    log)            proxy_log ;;
    bbr)            proxy_bbr "$@" ;;
    url|share)      proxy_url "$@" ;;
    menu|main)      proxy_menu ;;
    help|h)         proxy_help ;;
    *)              proxy_menu ;;
  esac
}

# ---- 安装代理核心 ----
proxy_install() {
  _require_root
  msg_title "安装代理核心"
  msg ""

  # 选择后端
  msg "  请选择代理后端："
  local i=1
  for be in "${P_BACKENDS[@]}"; do
    local name="${be%%:*}"; local rest="${be#*:}"; local label="${rest%%:*}"
    local installed=""
    [[ -f "$P_BIN_DIR/$name" ]] && installed=" ${F_GREEN}[已安装]${F_RESET}"
    msg "  ${F_GREEN}$i${F_RESET}) $label$installed"
    i=$((i+1))
  done
  msg ""
  read -p "请选择 [1-${#P_BACKENDS[@]}]: " be_choice
  be_choice=$((be_choice - 1))

  if [[ $be_choice -lt 0 || $be_choice -ge ${#P_BACKENDS[@]} ]]; then
    msg_err "无效选择"
    return 1
  fi

  local be_entry="${P_BACKENDS[$be_choice]}"
  local be_name="${be_entry%%:*}"
  local rest="${be_entry#*:}"
  local be_label="${rest%%:*}"
  local be_repo="${rest#*:}"

  # 检查是否已安装
  if [[ -f "$P_BIN_DIR/$be_name" ]]; then
    msg_warn "$be_label 已安装"
    confirm "是否重新安装？" || return
  fi

  # 创建目录
  mkdir -p "$P_BIN_DIR" "$P_CONF_DIR" "$P_LOG_DIR"

  # 检测架构
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  # 下载安装
  msg_info "正在下载 $be_label..."
  local tmpdir=$(mktemp -d)

  case "$be_name" in
    xray)      _proxy_download_xray "$tmpdir" "$arch" ;;
    v2ray)     _proxy_download_v2ray "$tmpdir" "$arch" ;;
    sing-box)  _proxy_download_singbox "$tmpdir" "$arch" ;;
    clash-meta) _proxy_download_clash "$tmpdir" "$arch" ;;
  esac

  if [[ ! -f "$tmpdir/$be_name" ]]; then
    msg_err "下载失败，请检查网络连接"
    rm -rf "$tmpdir"
    return 1
  fi

  cp "$tmpdir/$be_name" "$P_BIN_DIR/$be_name"
  chmod +x "$P_BIN_DIR/$be_name"
  ln -sf "$P_BIN_DIR/$be_name" "/usr/local/bin/$be_name" 2>/dev/null
  rm -rf "$tmpdir"

  # 保存当前后端
  echo "$be_name" > "$P_BASE_DIR/current_backend"

  # 安装 systemd 服务
  _proxy_install_service "$be_name"

  local ver=$($P_BIN_DIR/$be_name version 2>/dev/null | head -1)
  msg_ok "$be_label 安装成功: $ver"
  _log_write "代理核心安装: $be_label $ver"
  pause
}

# ---- 下载函数 ----
_proxy_download_xray() {
  local tmpdir="$1"; local arch="$2"
  local api_url="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
  local info=$(curl -s "$api_url" 2>/dev/null)
  local tag=$(echo "$info" | grep '"tag_name"' | cut -d'"' -f4)
  [[ -z "$tag" ]] && return 1
  # Xray uses "64" for amd64, "arm64-v8a" for arm64
  local xray_arch="64"
  [[ "$arch" == "arm64" ]] && xray_arch="arm64-v8a"
  local filename="Xray-linux-${xray_arch}.zip"
  local dl_url="https://github.com/XTLS/Xray-core/releases/download/$tag/$filename"
  _download "$dl_url" "$tmpdir/xray.zip" || return 1
  unzip -o "$tmpdir/xray.zip" xray -d "$tmpdir/" 2>/dev/null
}

_proxy_download_v2ray() {
  local tmpdir="$1"; local arch="$2"
  local api_url="https://api.github.com/repos/v2fly/v2ray-core/releases/latest"
  local info=$(curl -s "$api_url" 2>/dev/null)
  local tag=$(echo "$info" | grep '"tag_name"' | cut -d'"' -f4)
  [[ -z "$tag" ]] && return 1
  # v2ray uses "64" for amd64
  local v2ray_arch="64"
  [[ "$arch" == "arm64" ]] && v2ray_arch="arm64-v8a"
  local filename="v2ray-linux-${v2ray_arch}.zip"
  local dl_url="https://github.com/v2fly/v2ray-core/releases/download/$tag/$filename"
  _download "$dl_url" "$tmpdir/v2ray.zip" || return 1
  unzip -o "$tmpdir/v2ray.zip" v2ray -d "$tmpdir/" 2>/dev/null
}

_proxy_download_singbox() {
  local tmpdir="$1"; local arch="$2"
  local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local info=$(curl -s "$api_url" 2>/dev/null)
  local tag=$(echo "$info" | grep '"tag_name"' | cut -d'"' -f4)
  [[ -z "$tag" ]] && return 1
  # Try glibc first, then plain
  local ver="${tag#v}"
  local filename="sing-box-${ver}-linux-${arch}.tar.gz"
  local dl_url="https://github.com/SagerNet/sing-box/releases/download/$tag/$filename"
  if ! _download "$dl_url" "$tmpdir/sing-box.tar.gz" 2>/dev/null; then
    filename="sing-box-${ver}-linux-${arch}-glibc.tar.gz"
    dl_url="https://github.com/SagerNet/sing-box/releases/download/$tag/$filename"
    _download "$dl_url" "$tmpdir/sing-box.tar.gz" || return 1
  fi
  tar xzf "$tmpdir/sing-box.tar.gz" -C "$tmpdir" 2>/dev/null
  find "$tmpdir" -name "sing-box" -type f -not -path "*/sing-box.tar.gz" -exec cp {} "$tmpdir/" \; 2>/dev/null
  # Also check if binary is in extracted subdirectory
  if [[ ! -f "$tmpdir/sing-box" ]]; then
    local extracted_dir=$(find "$tmpdir" -maxdepth 1 -type d -name "sing-box-*" | head -1)
    [[ -f "$extracted_dir/sing-box" ]] && cp "$extracted_dir/sing-box" "$tmpdir/"
  fi
}

_proxy_download_clash() {
  local tmpdir="$1"; local arch="$2"
  local api_url="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
  local info=$(curl -s "$api_url" 2>/dev/null)
  local tag=$(echo "$info" | grep '"tag_name"' | cut -d'"' -f4)
  [[ -z "$tag" ]] && return 1
  # Try compatible version first
  local filename="mihomo-linux-${arch}-compatible-${tag}.gz"
  local dl_url="https://github.com/MetaCubeX/mihomo/releases/download/$tag/$filename"
  if ! _download "$dl_url" "$tmpdir/clash.gz" 2>/dev/null; then
    filename="mihomo-linux-${arch}-${tag}.gz"
    dl_url="https://github.com/MetaCubeX/mihomo/releases/download/$tag/$filename"
    _download "$dl_url" "$tmpdir/clash.gz" || return 1
  fi
  gunzip -f "$tmpdir/clash.gz" 2>/dev/null
  mv "$tmpdir/clash" "$tmpdir/clash-meta" 2>/dev/null || \
  mv "$tmpdir/mihomo" "$tmpdir/clash-meta" 2>/dev/null
}

# ---- 重建主配置文件（合并所有子配置） ----
_proxy_rebuild_config() {
  local all_inbounds=""
  local all_outbounds='[{"protocol": "freedom", "tag": "direct"}]'
  local first=1

  for f in "$P_CONF_DIR"/*.json; do
    [[ ! -f "$f" ]] && continue
    [[ "$(basename "$f")" == "config.json" ]] && continue

    # Use python3/jq to extract inbounds if available, else use sed with unique marker
    local inbound=""
    if command -v jq &>/dev/null; then
      inbound=$(jq -c '.inbounds[]' "$f" 2>/dev/null)
    elif command -v python3 &>/dev/null; then
      inbound=$(python3 -c "import json; d=json.load(open('$f')); [print(json.dumps(x)) for x in d.get('inbounds',[])]" 2>/dev/null)
    else
      # Fallback: use awk with a unique start marker and end at the line with only }],
      inbound=$(awk '/"inbounds"/{found=1; next} found && /^[[:space:]]*\}\],/{exit} found{print}' "$f")
      # Remove trailing }],
      inbound=$(echo "$inbound" | sed '$ s/}],.*//')
    fi
    if [[ -n "$inbound" ]]; then
      if [[ $first -eq 1 ]]; then
        all_inbounds="$inbound"
        first=0
      else
        all_inbounds="${all_inbounds},
$inbound"
      fi
    fi
  done

  cat > "$P_CONF_DIR/config.json" << MEOF
{
  "inbounds": [
$all_inbounds
  ],
  "outbounds": $all_outbounds
}
MEOF
}

# ---- 安装 systemd 服务 ----
_proxy_install_service() {
  local backend="$1"
  cat > "$P_SERVICE_DIR/fusionbox-proxy.service" << SEOF
[Unit]
Description=FusionBox Proxy Service ($backend)
After=network.target

[Service]
Type=simple
ExecStart=$P_BIN_DIR/$backend run -c $P_CONF_DIR/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
SEOF
  systemctl daemon-reload 2>/dev/null
  systemctl enable fusionbox-proxy 2>/dev/null
}

# ---- 卸载 ----
proxy_uninstall() {
  _require_root
  msg_title "卸载代理核心"

  if [[ ! -d "$P_BASE_DIR" ]]; then
    msg_warn "代理模块未安装"
    return
  fi

  confirm "将删除所有代理配置和核心文件，确认继续？" || return

  proxy_service "stop" 2>/dev/null
  systemctl disable fusionbox-proxy 2>/dev/null
  rm -f "$P_SERVICE_DIR/fusionbox-proxy.service"
  systemctl daemon-reload 2>/dev/null

  local backend=""
  [[ -f "$P_BASE_DIR/current_backend" ]] && backend=$(cat "$P_BASE_DIR/current_backend")

  rm -rf "$P_BASE_DIR" "$P_LOG_DIR"
  [[ -n "$backend" ]] && rm -f "/usr/local/bin/$backend"

  msg_ok "代理模块已卸载"
  _log_write "代理模块已卸载"
  pause
}

# ---- 添加配置 ----
proxy_add() {
  _require_root
  if [[ ! -d "$P_BASE_DIR" ]]; then
    msg_err "请先安装代理核心：fusionbox proxy install"
    return 1
  fi

  local backend=$(cat "$P_BASE_DIR/current_backend" 2>/dev/null)
  if [[ -z "$backend" ]]; then
    msg_err "未找到已安装的代理后端"
    return 1
  fi

  # 选择协议
  msg_title "添加代理配置"
  msg ""
  msg "  当前后端: ${F_CYAN}$backend${F_RESET}"
  msg ""
  _proxy_show_protocols
  read -p "请选择协议 [1-${#P_PROTOCOLS[@]}]: " proto_idx
  proto_idx=$((proto_idx - 1))

  local p_name="${P_PROTOCOLS[$((proto_idx * 3))]}"
  local p_type="${P_PROTOCOLS[$((proto_idx * 3 + 1))]}"
  local p_transport="${P_PROTOCOLS[$((proto_idx * 3 + 2))]}"

  if [[ -z "$p_name" ]]; then
    msg_err "无效的协议选择"
    return 1
  fi

  msg_info "正在添加 $p_name 配置..."

  # 生成 UUID 和端口
  local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$$-$RANDOM")
  local port=$(_proxy_gen_port)

  # 生成配置文件
  local conf_file="$P_CONF_DIR/${p_name,,}-${port}.json"
  _proxy_generate_config "$p_name" "$p_type" "$p_transport" "$uuid" "$port" "$conf_file"

  if [[ -f "$conf_file" ]]; then
    msg_ok "$p_name 配置已创建: $conf_file"
    msg_info "端口: $port | UUID: $uuid"
    _proxy_rebuild_config
    proxy_service "restart" 2>/dev/null
    _log_write "添加代理配置: $p_name (端口 $port)"
  else
    msg_err "配置创建失败"
    return 1
  fi
  pause
}

_proxy_show_protocols() {
  msg "  支持的协议："
  local i=1; local idx=0
  while [[ $idx -lt ${#P_PROTOCOLS[@]} ]]; do
    msg "  ${F_GREEN}$i${F_RESET}) ${P_PROTOCOLS[$idx]}"
    i=$((i+1)); idx=$((idx+3))
  done
  msg ""
}

_proxy_gen_port() {
  local port
  for i in $(seq 1 100); do
    port=$((RANDOM % 50000 + 10000))
    if ! ss -tlnp 2>/dev/null | grep -q ":$port "; then
      echo "$port"; return
    fi
  done
  echo $((RANDOM % 50000 + 10000))
}

_proxy_generate_config() {
  local p_name="$1" p_type="$2" p_transport="$3" uuid="$4" port="$5" conf_file="$6"
  local pass=$(date +%s | sha256sum | head -c 32)

  case "$p_type" in
    vless)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "${p_name,,}-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "vless",
    "settings": {"clients": [{"id": "$uuid"}], "decryption": "none"},
    "streamSettings": {"network": "$p_transport"}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    vmess)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "${p_name,,}-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "vmess",
    "settings": {"clients": [{"id": "$uuid", "alterId": 0}]},
    "streamSettings": {"network": "$p_transport"}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    trojan)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "${p_name,,}-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "trojan",
    "settings": {"clients": [{"password": "$pass"}]}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    hysteria2)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "hysteria2-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "hysteria2",
    "settings": {"users": [{"password": "$pass"}]}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    tuic)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "tuic-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "tuic",
    "settings": {"users": [{"uuid": "$uuid", "password": "$pass"}]}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    shadowsocks)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "ss-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "shadowsocks",
    "settings": {"method": "aes-256-gcm", "password": "$pass"}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
    socks)
      cat > "$conf_file" << JEOF
{
  "inbounds": [{
    "tag": "socks-in",
    "listen": "0.0.0.0",
    "port": $port,
    "protocol": "socks",
    "settings": {"auth": "password", "accounts": [{"user": "fusionbox", "pass": "$pass"}]}
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
JEOF
      ;;
  esac
}

# ---- 列出配置 ----
proxy_list() {
  if [[ ! -d "$P_CONF_DIR" ]]; then
    msg_info "暂无代理配置"
    return
  fi

  local configs=()
  for f in "$P_CONF_DIR"/*.json; do
    [[ -f "$f" ]] && [[ "$(basename "$f")" != "config.json" ]] && configs+=("$f")
  done

  if [[ ${#configs[@]} -eq 0 ]]; then
    msg_info "暂无代理配置"
    return
  fi

  msg_title "代理配置列表"
  local i=1
  for f in "${configs[@]}"; do
    local name=$(basename "$f" .json)
    local port=$(grep -o '"port": [0-9]*' "$f" 2>/dev/null | head -1 | awk '{print $2}')
    local proto=$(grep -o '"protocol": "[a-z]*' "$f" 2>/dev/null | head -1 | cut -d'"' -f4)
    msg "  ${F_GREEN}$i${F_RESET}) $name ${F_CYAN}($proto:$port)${F_RESET}"
    i=$((i+1))
  done
  msg ""
}

# ---- 查看配置 ----
proxy_info() {
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "请输入配置名称: " name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "未找到配置: $name"
    return 1
  fi

  msg_title "配置详情: $(basename "$conf_file" .json)"
  if command -v jq &>/dev/null; then
    jq . "$conf_file"
  else
    cat "$conf_file"
  fi
  msg ""
}

# ---- 删除配置 ----
proxy_del() {
  _require_root
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "请输入要删除的配置名称: " name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "未找到配置: $name"
    return 1
  fi

  confirm "确认删除配置 $(basename "$conf_file")？" || return
  rm -f "$conf_file"
  _proxy_rebuild_config
  msg_ok "配置已删除"
  proxy_service "restart" 2>/dev/null
  _log_write "删除代理配置: $(basename "$conf_file")"
}

# ---- 服务管理 ----
proxy_service() {
  local action="$1"
  case "$action" in
    start)
      systemctl start fusionbox-proxy 2>/dev/null
      if systemctl is-active fusionbox-proxy &>/dev/null; then
        msg_ok "代理服务已启动"
      else
        msg_err "代理服务启动失败"
      fi
      ;;
    stop)
      systemctl stop fusionbox-proxy 2>/dev/null
      msg_info "代理服务已停止"
      ;;
    restart)
      systemctl restart fusionbox-proxy 2>/dev/null
      sleep 1
      if systemctl is-active fusionbox-proxy &>/dev/null; then
        msg_ok "代理服务已重启"
      else
        msg_err "代理服务重启失败"
      fi
      ;;
  esac
}

# ---- 状态 ----
proxy_status() {
  msg_title "代理状态"

  local backend=""
  [[ -f "$P_BASE_DIR/current_backend" ]] && backend=$(cat "$P_BASE_DIR/current_backend")

  if [[ -z "$backend" ]]; then
    msg "  ${F_BOLD}状态:${F_RESET} ${F_RED}未安装${F_RESET}"
    msg ""
    return
  fi

  local ver=$($P_BIN_DIR/$backend version 2>/dev/null | head -1)
  msg "  ${F_BOLD}后端:${F_RESET} $backend ($ver)"

  if systemctl is-active fusionbox-proxy &>/dev/null; then
    msg "  ${F_BOLD}状态:${F_RESET} ${F_GREEN}运行中${F_RESET}"
    local pid=$(systemctl show fusionbox-proxy --property=MainPID --value 2>/dev/null)
    msg "  ${F_BOLD}PID:${F_RESET} $pid"
  else
    msg "  ${F_BOLD}状态:${F_RESET} ${F_YELLOW}已停止${F_RESET}"
  fi

  local count=$(find "$P_CONF_DIR" -name "*.json" 2>/dev/null | wc -l)
  msg "  ${F_BOLD}配置:${F_RESET} $count 个"
  msg ""
}

# ---- 日志 ----
proxy_log() {
  local log_file="$P_LOG_DIR/access.log"
  if [[ -f "$log_file" ]]; then
    msg_info "查看日志 (Ctrl+C 退出)..."
    tail -f "$log_file" 2>/dev/null
  else
    journalctl -u fusionbox-proxy --no-pager -n 50 2>/dev/null || msg_info "暂无日志"
  fi
}

# ---- BBR ----
proxy_bbr() {
  _require_root
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  if [[ "$cc" == "bbr" ]]; then
    msg_ok "BBR 已启用"
    return
  fi

  local kmaj=$(uname -r | cut -d. -f1)
  local kmin=$(uname -r | cut -d. -f2)
  if [[ $kmaj -lt 4 ]] || [[ $kmaj -eq 4 && $kmin -lt 9 ]]; then
    msg_err "BBR 需要内核 4.9+，当前内核: $(uname -r)"
    return 1
  fi

  cat >> /etc/sysctl.conf << 'SEOF'

# FusionBox BBR 加速
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
SEOF
  sysctl -p 2>/dev/null
  msg_ok "BBR 已启用"
  _log_write "BBR 已启用"
}

# ---- 分享链接 ----
proxy_url() {
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "请输入配置名称: " name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "未找到配置: $name"
    return 1
  fi

  local port=$(grep -o '"port": [0-9]*' "$conf_file" | head -1 | awk '{print $2}')
  local proto=$(grep -o '"protocol": "[a-z]*' "$conf_file" | head -1 | cut -d'"' -f4)
  local uuid=$(grep -o '"id": "[^"]*"' "$conf_file" | head -1 | cut -d'"' -f4)
  local pass=$(grep -o '"password": "[^"]*"' "$conf_file" | head -1 | cut -d'"' -f4)
  local ip="${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "YOUR_IP")}"

  msg_title "分享链接"
  case "$proto" in
    vless)   msg_tip "vless://$uuid@$ip:$port?type=tcp" ;;
    vmess)   msg_tip "vmess://$(echo -n "{\"v\":\"2\",\"add\":\"$ip\",\"port\":\"$port\",\"id\":\"$uuid\"}" | base64 -w0 2>/dev/null)" ;;
    trojan)  msg_tip "trojan://$pass@$ip:$port" ;;
    hysteria2) msg_tip "hysteria2://$pass@$ip:$port" ;;
    tuic)    msg_tip "tuic://$uuid:$pass@$ip:$port" ;;
    shadowsocks) msg_tip "ss://$(echo -n "aes-256-gcm:$pass" | base64 -w0 2>/dev/null)@$ip:$port" ;;
    *)       msg_info "地址: $ip:$port" ;;
  esac
  msg ""
}

# ---- 帮助 ----
proxy_help() {
  msg_title "代理管理 帮助"
  msg ""
  msg "  ${F_GREEN}fusionbox proxy install${F_RESET}        安装代理核心"
  msg "  ${F_GREEN}fusionbox proxy uninstall${F_RESET}      卸载代理模块"
  msg "  ${F_GREEN}fusionbox proxy add${F_RESET}            添加代理配置"
  msg "  ${F_GREEN}fusionbox proxy list${F_RESET}           列出所有配置"
  msg "  ${F_GREEN}fusionbox proxy info <名称>${F_RESET}    查看配置详情"
  msg "  ${F_GREEN}fusionbox proxy del <名称>${F_RESET}     删除配置"
  msg "  ${F_GREEN}fusionbox proxy start${F_RESET}          启动代理服务"
  msg "  ${F_GREEN}fusionbox proxy stop${F_RESET}           停止代理服务"
  msg "  ${F_GREEN}fusionbox proxy restart${F_RESET}        重启代理服务"
  msg "  ${F_GREEN}fusionbox proxy status${F_RESET}         查看代理状态"
  msg "  ${F_GREEN}fusionbox proxy log${F_RESET}            查看日志"
  msg "  ${F_GREEN}fusionbox proxy bbr${F_RESET}            启用 BBR 加速"
  msg "  ${F_GREEN}fusionbox proxy url <名称>${F_RESET}     生成分享链接"
  msg ""
  msg "  ${F_BOLD}支持的后端:${F_RESET} Xray-core、v2ray-core、sing-box、Clash.Meta"
  msg "  ${F_BOLD}支持的协议:${F_RESET} VLESS、VMess、Trojan、Hysteria2、TUIC、Shadowsocks、SOCKS5"
  msg ""
}

# ---- 交互菜单 ----
proxy_menu() {
  while true; do
    clear
    _print_banner
    msg_title "代理管理"
    msg ""
    proxy_status
    msg "  ${F_GREEN}1${F_RESET}) 安装代理核心"
    msg "  ${F_GREEN}2${F_RESET}) 添加代理配置"
    msg "  ${F_GREEN}3${F_RESET}) 列出配置"
    msg "  ${F_GREEN}4${F_RESET}) 查看配置详情"
    msg "  ${F_GREEN}5${F_RESET}) 删除配置"
    msg "  ${F_GREEN}6${F_RESET}) 启动/停止/重启"
    msg "  ${F_GREEN}7${F_RESET}) 启用 BBR"
    msg "  ${F_GREEN}8${F_RESET}) 生成分享链接"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-8]: " choice
    case "$choice" in
      1) proxy_install ;;
      2) proxy_add ;;
      3) proxy_list; pause ;;
      4) proxy_info; pause ;;
      5) proxy_del ;;
      6)
        msg "1) 启动  2) 停止  3) 重启"
        read -p "操作: " act
        case "$act" in 1) proxy_service "start" ;; 2) proxy_service "stop" ;; 3) proxy_service "restart" ;; esac
        pause
        ;;
      7) proxy_bbr; pause ;;
      8) proxy_url; pause ;;
      0) break ;;
    esac
  done
}
