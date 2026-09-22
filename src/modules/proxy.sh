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

# ---- 随机密钥生成（128-bit hex，可用于 UUID 回退与协议密码） ----
_proxy_gen_secret() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 16
  else
    head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

# ---- 233boy/sing-box 集成 ----
# 社区最佳实践的 sing-box 管理脚本：https://github.com/233boy/sing-box
# 真实内核装在 /etc/sing-box/bin/（与 FusionBox 自有内核目录不冲突），
# 管理命令为 /usr/local/bin/sing-box，服务名 sing-box，配置 /etc/sing-box/conf/
SB_SH_BIN="/usr/local/bin/sing-box"
SB_CORE_DIR="/etc/sing-box"

_singbox_233_installed() {
  [[ -x "$SB_SH_BIN" ]] && _proxy_link_points_to "$SB_SH_BIN" "$SB_CORE_DIR/sh/sing-box.sh"
}

# Resolve ownership without executing commands, including dangling native links.
_proxy_link_points_to() {
  [[ -L "$1" && "$(readlink -m -- "$1")" == "$(readlink -m -- "$2")" ]]
}

# 233boy/sing-box 安装（脚本落地临时文件再执行；官方安装器全程无交互）
_singbox_233_install() {
  _singbox_233_installed && return 0
  local path
  for path in "$SB_SH_BIN" "$(dirname "$SB_SH_BIN")/sb" "$SB_CORE_DIR" \
    "$P_SERVICE_DIR/sing-box.service" /var/log/sing-box; do
    if [[ -e "$path" || -L "$path" ]]; then
      msg_err "$(L MSG_PROXY_0001 "$path")"
      return 1
    fi
  done
  msg_info "$(L MSG_PROXY_0002)"
  local tmpf
  tmpf=$(mktemp) || return $?
  local rc=0
  _download "https://raw.githubusercontent.com/233boy/sing-box/main/install.sh" "$tmpf" || rc=$?
  if [[ $rc -ne 0 ]]; then
    msg_err "$(L MSG_PROXY_0003)"
    rm -f "$tmpf"
    return "$rc"
  fi
  bash "$tmpf" || rc=$?
  rm -f "$tmpf"
  if [[ $rc -ne 0 ]]; then
    msg_err "$(L MSG_PROXY_0004 "$rc")"
    return "$rc"
  fi
  if ! _singbox_233_installed; then
    msg_err "$(L MSG_PROXY_0005)"
    return 1
  fi
  msg_ok "$(L MSG_PROXY_0006)"
  msg_info "$(L MSG_PROXY_0007)"
  _log_write "$(L MSG_PROXY_0008)"
}

# 入口: fusionbox proxy sb [参数] —— 无参数进 233boy 交互主菜单，带参数原样透传
proxy_sb() {
  _require_root || return $?
  if ! _singbox_233_installed; then
    confirm "$(L MSG_PROXY_0009)" || return 1
    _singbox_233_install || return $?
    return
  fi
  if [[ $# -gt 0 ]]; then
    "$SB_SH_BIN" "$@"
  else
    "$SB_SH_BIN"
  fi
}

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
    sb|singbox)     proxy_sb "$@" ;;
    url|share)      proxy_url "$@" ;;
    menu|main)      proxy_menu ;;
    help|h)         proxy_help ;;
    *)              _module_unknown_cmd "proxy" "$cmd" ;;
  esac
}

# ---- 安装代理核心 ----
proxy_install() {
  _require_root || return $?
  msg_title "$(L MSG_PROXY_0010)"
  msg ""

  # 选择后端
  msg "$(L MSG_PROXY_0011)"
  local i=1
  for be in "${P_BACKENDS[@]}"; do
    local name="${be%%:*}"; local rest="${be#*:}"; local label="${rest%%:*}"
    local installed=""
    [[ -f "$P_BIN_DIR/$name" ]] && installed="$(L MSG_PROXY_0012 "${F_GREEN}" "${F_RESET}")"
    msg "  ${F_GREEN}$i${F_RESET}) $label$installed"
    i=$((i+1))
  done
  msg ""
  read -p "$(L MSG_PROXY_0013 "${#P_BACKENDS[@]}")" be_choice
  [[ "$be_choice" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_PROXY_0014)"; return 1; }
  be_choice=$((be_choice - 1))

  if [[ $be_choice -lt 0 || $be_choice -ge ${#P_BACKENDS[@]} ]]; then
    msg_err "$(L MSG_PROXY_0014)"
    return 1
  fi

  local be_entry="${P_BACKENDS[$be_choice]}"
  local be_name="${be_entry%%:*}"
  local rest="${be_entry#*:}"
  local be_label="${rest%%:*}"
  local be_repo="${rest#*:}"

  # sing-box 后端交由 233boy 脚本接管（社区最佳实践，自动 REALITY + 全协议管理）
  if [[ "$be_name" == "sing-box" ]]; then
    if _singbox_233_installed; then
      msg_ok "$(L MSG_PROXY_0008)"
      proxy_sb
      return
    fi
    confirm "$(L MSG_PROXY_0015)" || return
    _singbox_233_install
    return
  fi

  local command_path="/usr/local/bin/$be_name"
  if [[ -e "$command_path" || -L "$command_path" ]] && \
    ! _proxy_link_points_to "$command_path" "$P_BIN_DIR/$be_name"; then
    msg_err "$(L MSG_PROXY_0016 "$command_path")"
    return 1
  fi

  # 检查是否已安装
  if [[ -f "$P_BIN_DIR/$be_name" ]]; then
    msg_warn "$(L MSG_PROXY_0017 "$be_label")"
    confirm "$(L MSG_PROXY_0018)" || return
  fi

  # 创建目录（配置目录存放密钥，权限收紧）
  mkdir -p "$P_BIN_DIR" "$P_CONF_DIR" "$P_LOG_DIR"
  chmod 700 "$P_CONF_DIR"

  # 检测架构
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  # 下载安装（长等待，给出阶段反馈）
  progress_begin 4
  progress_step "$(_tr MSG_PROXY_STAGES_1)"
  local tmpdir=$(mktemp -d)

  case "$be_name" in
    xray)      _proxy_download_xray "$tmpdir" "$arch" ;;
    v2ray)     _proxy_download_v2ray "$tmpdir" "$arch" ;;
    sing-box)  _proxy_download_singbox "$tmpdir" "$arch" ;;
    clash-meta) _proxy_download_clash "$tmpdir" "$arch" ;;
  esac

  if [[ ! -f "$tmpdir/$be_name" ]]; then
    msg_err "$(L MSG_PROXY_0019)"
    rm -rf "$tmpdir"
    progress_end
    return 1
  fi

  progress_step "$(_tr MSG_PROXY_STAGES_2)"
  cp "$tmpdir/$be_name" "$P_BIN_DIR/$be_name"
  chmod +x "$P_BIN_DIR/$be_name"
  ln -sf "$P_BIN_DIR/$be_name" "/usr/local/bin/$be_name" 2>/dev/null
  rm -rf "$tmpdir"

  # 保存当前后端
  echo "$be_name" > "$P_BASE_DIR/current_backend"

  # 安装 systemd 服务
  progress_step "$(_tr MSG_PROXY_STAGES_3)"
  _proxy_install_service "$be_name"

  progress_step "$(_tr MSG_PROXY_STAGES_4)"
  local ver=$($P_BIN_DIR/$be_name version 2>/dev/null | head -1)
  progress_end
  msg_ok "$(L MSG_PROXY_0020 "$be_label" "$ver")"
  _log_write "$(L MSG_PROXY_0021 "$be_label" "$ver")"
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
  chmod 600 "$P_CONF_DIR/config.json"   # 合并后的配置含全部入站密钥
}

# ---- 安装 systemd 服务 ----
_proxy_install_service() {
  local backend="$1"
  cat > "$P_SERVICE_DIR/fusionbox-proxy.service" << SEOF
[Unit]
Description=FusionBox Proxy Service ($backend)
After=network.target
# 每次增删配置都会 restart，连续操作会触发 systemd 默认启动限速（5次/10s）
StartLimitIntervalSec=0

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
  _require_root || return $?
  msg_title "$(L MSG_PROXY_0022)"

  # Snapshot both owners before native removal can break the legacy shared link.
  local native=0 upstream=0 path be rc=0
  local native_links=()
  [[ -d "$P_BASE_DIR" ]] && native=1
  _singbox_233_installed && upstream=1
  for be in xray v2ray sing-box clash-meta; do
    path="/usr/local/bin/$be"
    _proxy_link_points_to "$path" "$P_BIN_DIR/$be" && native_links+=("$path")
  done
  if [[ $native -eq 0 && $upstream -eq 0 ]]; then
    msg_warn "$(L MSG_PROXY_0023)"
    return 0
  fi

  if [[ $native -eq 1 ]] && confirm "$(L MSG_PROXY_0024)"; then
    local unit="$P_SERVICE_DIR/fusionbox-proxy.service" owned_unit=0
    for be in xray v2ray sing-box clash-meta; do
      if [[ ! -L "$unit" ]] && grep -Fxq "ExecStart=$P_BIN_DIR/$be run -c $P_CONF_DIR/config.json" "$unit" 2>/dev/null; then
        owned_unit=1
      fi
    done
    if [[ $owned_unit -eq 1 ]]; then
      systemctl stop fusionbox-proxy || return $?
      systemctl disable fusionbox-proxy || return $?
      rm -f "$unit" || return $?
      systemctl daemon-reload || return $?
    fi
    for path in "${native_links[@]}"; do
      rm -f "$path" || return $?
    done
    rm -rf "$P_BASE_DIR" "$P_LOG_DIR" || return $?
    msg_ok "$(L MSG_PROXY_0025)"
    _log_write "$(L MSG_PROXY_0025)"
  fi

  if [[ $upstream -eq 1 ]] && confirm "$(L MSG_PROXY_0026)"; then
    _singbox_233_installed || return 1
    "$SB_SH_BIN" uninstall || rc=$?
    if [[ $rc -ne 0 ]]; then
      msg_err "$(L MSG_PROXY_0027 "$rc")"
      return "$rc"
    fi
    msg_ok "$(L MSG_PROXY_0028)"
    _log_write "$(L MSG_PROXY_0028)"
  fi
  pause
  return 0
}

# ---- 后端-协议支持矩阵 ----
# xray/v2ray 不支持 hysteria2/tuic 入站；sing-box/clash-meta 使用完全不同的
# 配置格式（本模块生成的是 Xray JSON），当前一律拒绝，避免配置写入后服务起不来
_proxy_proto_supported() {
  local backend="$1" ptype="$2"
  case "$backend" in
    xray)
      [[ "$ptype" == "hysteria2" || "$ptype" == "tuic" ]] && return 1
      return 0 ;;
    v2ray)
      [[ "$ptype" == "hysteria2" || "$ptype" == "tuic" || "$ptype" == "trojan" ]] && return 1
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# ---- 添加配置 ----
proxy_add() {
  _require_root
  # 只装了 233boy sing-box 时（自有目录不存在）也要正确引导
  if [[ ! -d "$P_BASE_DIR" ]] && _singbox_233_installed; then
    msg_info "$(L MSG_PROXY_0029)"
    msg_info "$(L MSG_PROXY_0030)"
    return 1
  fi
  if [[ ! -d "$P_BASE_DIR" ]]; then
    msg_err "$(L MSG_PROXY_0031)"
    return 1
  fi

  local backend=$(cat "$P_BASE_DIR/current_backend" 2>/dev/null)
  if [[ -z "$backend" ]]; then
    if _singbox_233_installed; then
      msg_info "$(L MSG_PROXY_0029)"
      msg_info "$(L MSG_PROXY_0030)"
      return 1
    fi
    msg_err "$(L MSG_PROXY_0032)"
    return 1
  fi

  # 选择协议
  msg_title "$(L MSG_PROXY_0033)"
  msg ""
  msg "$(L MSG_PROXY_0034 "${F_CYAN}" "$backend" "${F_RESET}")"
  msg ""
  _proxy_show_protocols
  read -p "$(L MSG_PROXY_0035 "${#P_PROTOCOLS[@]}")" proto_idx
  [[ "$proto_idx" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_PROXY_0014)"; return 1; }
  proto_idx=$((proto_idx - 1))

  local p_name="${P_PROTOCOLS[$((proto_idx * 3))]}"
  local p_type="${P_PROTOCOLS[$((proto_idx * 3 + 1))]}"
  local p_transport="${P_PROTOCOLS[$((proto_idx * 3 + 2))]}"

  if [[ -z "$p_name" ]]; then
    msg_err "$(L MSG_PROXY_0036)"
    return 1
  fi

  if ! _proxy_proto_supported "$backend" "$p_type"; then
    msg_err "$(L MSG_PROXY_0037 "$backend" "$p_name")"
    return 1
  fi

  msg_info "$(L MSG_PROXY_0038 "$p_name")"

  # 生成 UUID 和端口
  local uuid
  uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null)
  if [[ -z "$uuid" ]]; then
    # /proc 与 uuidgen 均不可用时的回退：16 字节 CSPRNG 构造 v4 格式 UUID
    local h
    h="$(_proxy_gen_secret)"
    uuid="${h:0:8}-${h:8:4}-4${h:13:3}-8${h:17:3}-${h:20:12}"
  fi
  local port=$(_proxy_gen_port)

  # 生成配置文件
  local conf_file="$P_CONF_DIR/${p_name,,}-${port}.json"
  _proxy_generate_config "$p_name" "$p_type" "$p_transport" "$uuid" "$port" "$conf_file"

  if [[ -f "$conf_file" ]]; then
    msg_ok "$(L MSG_PROXY_0039 "$p_name" "$conf_file")"
    msg_info "$(L MSG_PROXY_0040 "$port" "$uuid")"
    _proxy_rebuild_config
    proxy_service "restart" 2>/dev/null
    _log_write "$(L MSG_PROXY_0041 "$p_name" "$port")"
  else
    msg_err "$(L MSG_PROXY_0042)"
    return 1
  fi
  pause
}

_proxy_show_protocols() {
  msg "$(L MSG_PROXY_0043)"
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
  # 128-bit 随机密钥（旧版用 sha256(date +%s)，熵≈0，可离线爆破）
  local pass
  pass="$(_proxy_gen_secret)"

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

  # 配置文件含明文密钥，禁止其他用户读取
  chmod 600 "$conf_file" 2>/dev/null
}

# ---- 列出配置 ----
proxy_list() {
  if [[ ! -d "$P_CONF_DIR" ]]; then
    msg_info "$(L MSG_PROXY_0044)"
    return
  fi

  local configs=()
  for f in "$P_CONF_DIR"/*.json; do
    [[ -f "$f" ]] && [[ "$(basename "$f")" != "config.json" ]] && configs+=("$f")
  done

  if [[ ${#configs[@]} -eq 0 ]]; then
    msg_info "$(L MSG_PROXY_0044)"
    return
  fi

  msg_title "$(L MSG_PROXY_0045)"
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
    read -p "$(L MSG_PROXY_0046)" name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "$(L MSG_PROXY_0047 "$name")"
    return 1
  fi

  msg_title "$(L MSG_PROXY_0048 "$(basename "$conf_file" .json)")"
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
    read -p "$(L MSG_PROXY_0049)" name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "$(L MSG_PROXY_0047 "$name")"
    return 1
  fi

  confirm "$(L MSG_PROXY_0050 "$(basename "$conf_file")")" || return
  rm -f "$conf_file"
  _proxy_rebuild_config
  msg_ok "$(L MSG_PROXY_0051)"
  proxy_service "restart" 2>/dev/null
  _log_write "$(L MSG_PROXY_0052 "$(basename "$conf_file")")"
}

# ---- 服务管理 ----
proxy_service_menu() {
  msg "$(L MSG_PROXY_0053)"
  read -p "$(L MSG_PROXY_0054)" act
  case "$act" in 1) proxy_service "start" ;; 2) proxy_service "stop" ;; 3) proxy_service "restart" ;; esac
  pause
}

proxy_service() {
  local action="$1"
  case "$action" in
    start)
      systemctl reset-failed fusionbox-proxy 2>/dev/null
      systemctl start fusionbox-proxy 2>/dev/null
      if systemctl is-active fusionbox-proxy &>/dev/null; then
        msg_ok "$(L MSG_PROXY_0055)"
      else
        msg_err "$(L MSG_PROXY_0056)"
      fi
      ;;
    stop)
      systemctl stop fusionbox-proxy 2>/dev/null
      msg_info "$(L MSG_PROXY_0057)"
      ;;
    restart)
      systemctl reset-failed fusionbox-proxy 2>/dev/null
      systemctl restart fusionbox-proxy 2>/dev/null
      sleep 1
      if systemctl is-active fusionbox-proxy &>/dev/null; then
        msg_ok "$(L MSG_PROXY_0058)"
      else
        msg_err "$(L MSG_PROXY_0059)"
      fi
      ;;
  esac
}

# ---- 状态 ----
proxy_status() {
  msg_title "$(L MSG_PROXY_0060)"

  local backend=""
  [[ -f "$P_BASE_DIR/current_backend" ]] && backend=$(cat "$P_BASE_DIR/current_backend")

  # 无自有后端且无 233boy 实例才是真正的"未安装"
  if [[ -z "$backend" ]] && ! _singbox_233_installed; then
    msg "$(L MSG_PROXY_0061 "${F_BOLD}" "${F_RESET}" "${F_RED}" "${F_RESET}")"
    msg ""
    return
  fi

  if [[ -n "$backend" ]]; then
    local ver=$($P_BIN_DIR/$backend version 2>/dev/null | head -1)
    msg "$(L MSG_PROXY_0062 "${F_BOLD}" "${F_RESET}" "$backend" "$ver")"

    if systemctl is-active fusionbox-proxy &>/dev/null; then
      msg "$(L MSG_PROXY_0063 "${F_BOLD}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
      local pid=$(systemctl show fusionbox-proxy --property=MainPID --value 2>/dev/null)
      msg "  ${F_BOLD}PID:${F_RESET} $pid"
    else
      msg "$(L MSG_PROXY_0064 "${F_BOLD}" "${F_RESET}" "${F_YELLOW}" "${F_RESET}")"
    fi

    local count=$(find "$P_CONF_DIR" -name "*.json" 2>/dev/null | wc -l)
    msg "$(L MSG_PROXY_0065 "${F_BOLD}" "${F_RESET}" "$count")"
  fi

  # 233boy/sing-box 实例（独立于 FusionBox 自有后端）
  if _singbox_233_installed; then
    local sb_status
    if systemctl is-active sing-box &>/dev/null; then
      sb_status="$(L MSG_PROXY_0066 "${F_GREEN}" "${F_RESET}")"
    else
      sb_status="$(L MSG_PROXY_0067 "${F_YELLOW}" "${F_RESET}")"
    fi
    local sb_count
    sb_count=$(find "$SB_CORE_DIR/conf" -name "*.json" 2>/dev/null | wc -l)
    msg "$(L MSG_PROXY_0068 "${F_BOLD}" "${F_RESET}" "$sb_status" "$sb_count")"
  fi
  msg ""
}

# ---- 日志 ----
proxy_log() {
  local log_file="$P_LOG_DIR/access.log"
  if [[ -f "$log_file" ]]; then
    msg_info "$(L MSG_PROXY_0069)"
    tail -f "$log_file" 2>/dev/null
  else
    journalctl -u fusionbox-proxy --no-pager -n 50 2>/dev/null || msg_info "$(L MSG_PROXY_0070)"
  fi
}

# ---- BBR ----
proxy_bbr() {
  _require_root
  local cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  if [[ "$cc" == "bbr" ]]; then
    msg_ok "$(L MSG_PROXY_0071)"
    return
  fi

  local kmaj=$(uname -r | cut -d. -f1)
  local kmin=$(uname -r | cut -d. -f2)
  if [[ $kmaj -lt 4 ]] || [[ $kmaj -eq 4 && $kmin -lt 9 ]]; then
    msg_err "$(L MSG_PROXY_0072 "$(uname -r)")"
    return 1
  fi

  # 幂等：已配置则原地更新，避免重复追加
  if grep -q '^net.ipv4.tcp_congestion_control' /etc/sysctl.conf 2>/dev/null; then
    sed -i 's/^net.ipv4.tcp_congestion_control.*/net.ipv4.tcp_congestion_control = bbr/' /etc/sysctl.conf
  else
    echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
  fi
  if grep -q '^net.core.default_qdisc' /etc/sysctl.conf 2>/dev/null; then
    sed -i 's/^net.core.default_qdisc.*/net.core.default_qdisc = fq/' /etc/sysctl.conf
  else
    echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf
  fi
  sysctl -p 2>/dev/null
  msg_ok "$(L MSG_PROXY_0071)"
  _log_write "$(L MSG_PROXY_0071)"
}

# ---- 分享链接 ----
proxy_url() {
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "$(L MSG_PROXY_0046)" name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "$(L MSG_PROXY_0047 "$name")"
    return 1
  fi

  local port=$(grep -o '"port": [0-9]*' "$conf_file" | head -1 | awk '{print $2}')
  local proto=$(grep -o '"protocol": "[a-z]*' "$conf_file" | head -1 | cut -d'"' -f4)
  local uuid=$(grep -o '"id": "[^"]*"' "$conf_file" | head -1 | cut -d'"' -f4)
  local pass=$(grep -o '"password": "[^"]*"' "$conf_file" | head -1 | cut -d'"' -f4)
  local ip="${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "YOUR_IP")}"

  msg_title "$(L MSG_PROXY_0073)"
  case "$proto" in
    vless)   msg_tip "vless://$uuid@$ip:$port?type=tcp" ;;
    vmess)   msg_tip "vmess://$(echo -n "{\"v\":\"2\",\"add\":\"$ip\",\"port\":\"$port\",\"id\":\"$uuid\"}" | base64 -w0 2>/dev/null)" ;;
    trojan)  msg_tip "trojan://$pass@$ip:$port" ;;
    hysteria2) msg_tip "hysteria2://$pass@$ip:$port" ;;
    tuic)    msg_tip "tuic://$uuid:$pass@$ip:$port" ;;
    shadowsocks) msg_tip "ss://$(echo -n "aes-256-gcm:$pass" | base64 -w0 2>/dev/null)@$ip:$port" ;;
    *)       msg_info "$(L MSG_PROXY_0074 "$ip" "$port")" ;;
  esac
  msg ""
}

# ---- 帮助 ----
proxy_help() {
  msg_title "$(L MSG_PROXY_0075)"
  msg ""
  msg "$(L MSG_PROXY_0076 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0077 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0078 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0079 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0080 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0081 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0082 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0083 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0084 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0085 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0086 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0087 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0088 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_PROXY_0089 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0090 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_PROXY_0091 "${F_BOLD}" "${F_RESET}")"
  msg ""
}

# ---- 交互菜单 ----
proxy_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_PROXY_0092)"
    msg ""
    proxy_status
    msg "$(L MSG_PROXY_0093 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0094 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0095 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0096 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0097 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0098 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0099 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0100 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0101 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PROXY_0102 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_PROXY_0103)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) proxy_install ;;
      2) proxy_add ;;
      3) proxy_list; pause ;;
      4) proxy_info; pause ;;
      5) proxy_del ;;
      6) proxy_service_menu ;;
      7) proxy_bbr; pause ;;
      8) proxy_url; pause ;;
      9) proxy_sb; pause ;;
      0) break ;;
    esac
  done
}
