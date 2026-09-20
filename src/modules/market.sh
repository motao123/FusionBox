# FusionBox App Market Module
# One-click software installation

# App database: category, name, pkg_manager_packages, description
MARKET_APPS=(
  "dev:Git:git:版本控制系统"
  "dev:Python3:python3:Python 编程语言"
  "dev:Node.js:nodejs:JavaScript 运行时"
  "dev:Go:golang:Go 编程语言"
  "dev:Rust:rustc:Rust 编程语言"
  "dev:Redis:redis:内存数据结构存储"
  "dev:Memcached:memcached:分布式内存缓存"
  "dev:SQLite:sqlite3:轻量级嵌入式数据库"

  "net:Wget:wget:网络下载工具"
  "net:Curl:curl:数据传输工具"
  "net:Netcat:netcat:网络调试工具"
  "net:Socat:socat:多功能中继工具"
  "net:MTR:mtr:网络诊断工具"
  "net:Iperf3:iperf3:网络带宽测试"
  "net:Nmap:nmap:网络扫描器"
  "net:Speedtest CLI:speedtest-cli:网络速度测试"
  "net:FRP:frp:内网穿透工具"
  "net:Rclone:rclone:云存储同步"

  "sys:Htop:htop:交互式进程查看器"
  "sys:BTN:btop:资源监控器"
  "sys:Glances:glances:系统监控"
  "sys:Nano:nano:文本编辑器"
  "sys:Vim:vim:高级文本编辑器"
  "sys:Unzip:unzip:文件解压工具"
  "sys:Zip:zip:文件压缩工具"
  "sys:Tmux:tmux:终端复用器"
  "sys:Fail2Ban:fail2ban:SSH 暴力破解防护"
  "sys:UFW:ufw:简易防火墙"
  "sys:Certbot:certbot:SSL 证书工具"
  "sys:rsync:rsync:文件同步工具"
  "sys:cron:cron:任务调度器"
  "sys:supervisor:supervisor:进程控制系统"
  "sys:Prometheus:prometheus:监控系统"
  "sys:Node_Exporter:node_exporter:Prometheus 指标导出器"

  "web:Nginx:nginx:Web 服务器"
  "web:Apache:apache2:Web 服务器"
  "web:Caddy:caddy:自动 TLS 的 Web 服务器"
  "web:PHP:php:PHP 脚本语言"
  "web:MySQL/MariaDB:mariadb-server:数据库服务器"
  "web:PostgreSQL:postgresql:高级数据库"
  "web:phpMyAdmin:phpmyadmin:MySQL Web 管理工具"
  "web:WordPress:wordpress:CMS 平台"

  "proxy:Shadowsocks-libev:shadowsocks-libev:轻量级代理"
  "proxy:V2ray-core:v2ray:V2Ray 代理平台"
  "proxy:Xray-core:xray:XRay 代理平台"
  "proxy:HAProxy:haproxy:TCP/HTTP 代理"
  "proxy:Nginx_Plus:nginx-plus:高级负载均衡器"

  "media:FFmpeg:ffmpeg:多媒体处理工具"
  "media:ImageMagick:imagemagick:图像处理工具"
  "media:ExifTool:exiftool:元数据工具"

  "docker:Docker CE:docker-ce:容器化平台"
  "docker:Docker Compose:docker-compose-plugin:容器编排工具"
  "docker:Portainer:portainer:容器管理 Web UI"
  "docker:cAdvisor:cadvisor:容器资源监控"

  "monitor:Netdata:netdata:实时系统监控"
  "monitor:Bashtop:bashtop:终端资源监控"
  "monitor:Neofetch:neofetch:系统信息显示"
  "monitor:Fastfetch:fastfetch:快速系统信息"

  "security:ClamAV:clamav:杀毒软件"
  "security:Rkhunter:rkhunter:Rootkit 检测"
  "security:Lynis:lynis:安全审计工具"
  "security:Unattended-upgrades:unattended-upgrades:自动安全更新"

  "utility:Aria2:aria2:多协议下载工具"
  "utility:FileBrowser:filebrowser:Web 文件管理器"
  "utility:Gost:gost:隧道工具"
  "utility:Warp:cloudflare-warp:Cloudflare WARP VPN"
  "utility:7zip:p7zip-full:7z 压缩工具"
  "utility:JQ:jq:JSON 处理工具"
  "utility:yq:yq:YAML 处理工具"
  "utility:Tree:tree:目录树显示"
  "utility:Lsof:lsof:打开文件查看"
  "utility:Strace:strace:系统调用追踪"
  "utility:Tcpdump:tcpdump:网络抓包工具"
  "utility:Hdparm:hdparm:硬盘性能工具"
  "utility:Ddrescue:ddrescue:数据恢复工具"
)

market_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    managed)
      _require_root
      [[ $# -ge 1 ]] || { market_managed_help; return 2; }
      if ! _require_python3 "受管应用市场"; then return 1; fi
      # Stage feedback: image pull + container up + health wait are the slow
      # parts. The Python layer keeps its stdout machine-readable, so tell the
      # user what to expect before the (possibly long) call instead of faking
      # per-phase timing we cannot observe from here.
      case "${1:-}" in
        install|reinstall)
          msg_info "$(_tr MSG_MARKET_STAGES "过程: 校验端口 → 拉取镜像 → 创建容器 → 等待健康检查（可能较慢，请勿中断）")"
          ;;
      esac
      python3 "$FUSION_SRC/lib/market_apps.py" "$@"
      ;;
    clamav|scan)      market_clamav "$@" ;;
    list|l)           market_list "$@" ;;
    search|s)         market_search "$@" ;;
    install|i)        market_install "$@" ;;
    remove|rm)        market_remove "$@" ;;
    category|cat)     market_category "$@" ;;
    menu|main)        market_menu ;;
    help|h)           market_help ;;
    *)                _module_unknown_cmd "market" "$cmd" ;;
  esac
}

# ---- List all apps ----# ---- ClamAV 病毒扫描动作 (G19)：为 market 的 clamav 安装条目补扫描能力 ----
market_clamav() {
  _require_root
  local path="${1:-}"
  [[ $# -eq 1 && -e "$path" ]] || { msg_err "用法: fusionbox market clamav <目录或文件>"; return 2; }
  if ! command -v clamscan &>/dev/null; then
    confirm "clamscan 未安装，安装 clamav（包较大，含病毒库下载）？" || return 1
    _install_pkg clamav || { msg_err "clamav 安装失败"; return 1; }
    freshclam 2>/dev/null || msg_warn "病毒库更新失败（freshclam），可稍后手动执行"
  fi
  local log="/root/clamav-scan-$(date +%Y%m%d%H%M%S).log"
  msg_info "扫描 $path（大目录耗时较长，结果摘要如下）..."
  local rc=0
  clamscan -ri --exclude-dir="^/sys" --exclude-dir="^/proc" --exclude-dir="^/dev" "$path" > "$log" 2>&1 || rc=$?
  grep -E "^(\[)?/?|SUMMARY|Infected files|Total errors|Infected:" "$log" 2>/dev/null | tail -15 || tail -15 "$log"
  if [[ $rc -eq 0 ]]; then
    msg_ok "扫描完成：未发现威胁"
  elif [[ $rc -eq 1 ]]; then
    msg_warn "扫描完成：发现威胁文件！完整日志: $log"
    return 1
  else
    msg_err "扫描出错（rc=$rc），日志: $log"
    return 1
  fi
  chmod 600 "$log"
}

market_list() {
  local filter="${1:-}"
  msg_title "可用应用"
  msg ""

  local current_cat=""
  for app in "${MARKET_APPS[@]}"; do
    local cat="${app%%:*}"
    local rest="${app#*:}"
    local name="${rest%%:*}"
    local rest2="${rest#*:}"
    local pkg="${rest2%%:*}"
    local desc="${rest2#*:}"

    if [[ -z "$filter" || "$cat" == "$filter" ]]; then
      if [[ "$cat" != "$current_cat" ]]; then
        current_cat="$cat"
        case "$cat" in
          dev)      msg "  ${F_BOLD}${F_CYAN}[开发工具]${F_RESET}" ;;
          net)      msg "  ${F_BOLD}${F_CYAN}[网络工具]${F_RESET}" ;;
          sys)      msg "  ${F_BOLD}${F_CYAN}[系统工具]${F_RESET}" ;;
          web)      msg "  ${F_BOLD}${F_CYAN}[Web 服务与数据库]${F_RESET}" ;;
          proxy)    msg "  ${F_BOLD}${F_CYAN}[代理与隧道]${F_RESET}" ;;
          media)    msg "  ${F_BOLD}${F_CYAN}[媒体工具]${F_RESET}" ;;
          docker)   msg "  ${F_BOLD}${F_CYAN}[容器相关]${F_RESET}" ;;
          monitor)  msg "  ${F_BOLD}${F_CYAN}[监控工具]${F_RESET}" ;;
          security) msg "  ${F_BOLD}${F_CYAN}[安全工具]${F_RESET}" ;;
          utility)  msg "  ${F_BOLD}${F_CYAN}[实用工具]${F_RESET}" ;;
        esac
      fi
      # Check if installed
      local installed=""
      if command -v "$(echo "$pkg" | cut -d' ' -f1)" &>/dev/null; then
        installed=" ${F_GREEN}[已安装]${F_RESET}"
      fi
      msg "  ${F_GREEN}$name${F_RESET} - $desc$installed"
    fi
  done
  msg ""
  msg_info "用法: fusionbox market install <应用名>"
  pause
}

# ---- Search ----
market_search() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    read -p "请输入搜索关键词: " query
  fi

  msg_title "搜索: $query"
  msg ""
  local found=0
  for app in "${MARKET_APPS[@]}"; do
    if echo "$app" | grep -qi "$query"; then
      local name="${app#*:}"; name="${name%%:*}"
      local desc="${app##*:}"
      msg "  ${F_GREEN}$name${F_RESET} - $desc"
      found=1
    fi
  done
  [[ $found -eq 0 ]] && msg "  未找到结果"
  pause
}

# ---- Install ----
market_install() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    market_list
    read -p "请输入要安装的应用名: " app_name
  fi

  local found=""
  local pkg_name=""
  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" || "${name,,}" == *"${app_name,,}"* ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      pkg_name="${rest2%%:*}"
      found="$name"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    msg_err "未找到应用 '$app_name'"
    msg_info "请尝试: fusionbox market list"
    pause
    return
  fi

  # Handle special installs
  case "$found" in
    "Docker CE")
      _load_module panels   # panels 函数未加载时会 command not found
      panels_docker_install
      return
      ;;
    "Caddy")
      msg_info "正在安装 Caddy..."
      curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy 2>/dev/null && \
        chmod +x /usr/local/bin/caddy && \
        msg_ok "Caddy 已安装于 /usr/local/bin/caddy" || \
        _install_caddy_from_pkg
      _log_write "Caddy 已安装"
      pause
      return
      ;;
    "Speedtest CLI")
      _install_pkg speedtest-cli 2>/dev/null || pip3 install speedtest-cli 2>/dev/null
      ;;
    "FRP")
      _load_module panels
      panels_frp
      return
      ;;
    "Rclone")
      _load_module panels
      panels_rclone
      return
      ;;
    "WordPress")
      _install_wordpress
      return
      ;;
    "Node.js")
      _install_nodejs
      return
      ;;
    "Go")
      _install_go
      return
      ;;
    "Rust")
      _install_rust
      return
      ;;
    "Prometheus")
      _install_prometheus
      return
      ;;
    "Node_Exporter")
      _install_node_exporter
      return
      ;;
  esac

  # Standard package install
  local pkgs=($pkg_name)
  msg_info "正在安装 $found (${pkgs[*]})..."
  if _install_pkg "${pkgs[@]}"; then
    msg_ok "$found 安装成功"
    _log_write "应用已安装: $found"
  else
    msg_err "$found 安装失败"
  fi
  pause
}

_install_caddy_from_pkg() {
  case "$F_PKG_MGR" in
    apt) _install_pkg caddy ;;
    yum) _install_pkg caddy ;;
    apk) _install_pkg caddy ;;
  esac
}

_install_nodejs() {
  msg_info "正在安装 Node.js..."
  # 下载到临时文件再执行，不再 curl|bash
  local ns_sh
  ns_sh=$(mktemp)
  if _download https://deb.nodesource.com/setup_20.x "$ns_sh" && bash "$ns_sh" && _install_pkg nodejs; then
    :
  elif _download https://rpm.nodesource.com/setup_20.x "$ns_sh" && bash "$ns_sh" && _install_pkg nodejs; then
    :
  else
    _install_pkg nodejs
  fi
  rm -f "$ns_sh"
  if command -v node &>/dev/null; then
    msg_ok "Node.js: $(node --version 2>/dev/null)"
    msg_ok "npm: $(npm --version 2>/dev/null)"
  else
    msg_err "Node.js 安装失败"
  fi
  _log_write "Node.js 已安装"
  pause
}

_install_go() {
  msg_info "正在安装 Go..."
  local go_ver; go_ver=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1)
  [[ -z "$go_ver" ]] && go_ver="go1.22.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  curl -fsSL "https://go.dev/dl/${go_ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz 2>/dev/null && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go && \
    msg_ok "Go 已安装: $go_ver" || msg_err "Go 安装失败"
  rm -f /tmp/go.tar.gz
  _log_write "Go 已安装"
  pause
}

_install_rust() {
  msg_info "正在安装 Rust..."
  # 下载到临时文件再执行，不再 curl|bash
  local rs_sh
  rs_sh=$(mktemp)
  if _download https://sh.rustup.rs "$rs_sh" && sh "$rs_sh" -y --profile minimal; then
    if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
      msg_ok "Rust 已安装: $($HOME/.cargo/bin/rustc --version)"
    fi
  else
    msg_err "Rust 安装失败"
  fi
  rm -f "$rs_sh"
  _log_write "Rust 已安装"
  pause
}

_install_wordpress() {
  _require_root
  msg_info "正在安装 WordPress..."

  # Check prerequisites
  if ! command -v nginx &>/dev/null && ! command -v apache2 &>/dev/null; then
    msg_warn "未找到 Web 服务器，请先安装 LNMP（fusionbox web lnmp）"
    if ! confirm "仍然继续？"; then return; fi
  fi

  read -p "请输入 WordPress 域名: " wp_domain
  [[ -z "$wp_domain" ]] && wp_domain="localhost"

  local wp_root="/var/www/$wp_domain"
  mkdir -p "$wp_root"

  # Download WordPress
  curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz 2>/dev/null || {
    msg_err "下载失败"
    pause; return
  }
  tar xzf /tmp/wordpress.tar.gz -C /tmp
  cp -r /tmp/wordpress/* "$wp_root/"
  chmod -R 755 "$wp_root"
  rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

  msg_ok "WordPress 已下载到 $wp_root"
  msg_info "请创建数据库: fusionbox web mysql"
  msg_info "然后访问 http://$wp_domain 进行配置"
  _log_write "WordPress 已安装于 $wp_root"
  pause
}

_install_prometheus() {
  _require_root
  local ver="2.52.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "正在安装 Prometheus v$ver..."
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/prometheus/releases/download/v${ver}/prometheus-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/prometheus.tar.gz" || { msg_err "下载失败"; rm -rf "$tmpdir"; return; }

  tar xzf "$tmpdir/prometheus.tar.gz" -C "$tmpdir"
  mkdir -p /etc/prometheus /var/lib/prometheus
  cp "$tmpdir/prometheus-${ver}.linux-${arch}"/{prometheus,promtool} /usr/local/bin/
  cp -r "$tmpdir/prometheus-${ver}.linux-${arch}"/{consoles,console_libraries} /etc/prometheus/
  cp "$tmpdir/prometheus-${ver}.linux-${arch}"/prometheus.yml /etc/prometheus/

  useradd -rs /bin/false prometheus 2>/dev/null || true
  chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

  cat > /lib/systemd/system/prometheus.service << PR2
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus
Restart=on-failure

[Install]
WantedBy=multi-user.target
PR2
  systemctl daemon-reload && systemctl enable --now prometheus 2>/dev/null
  msg_ok "Prometheus 运行于 http://localhost:9090"
  rm -rf "$tmpdir"
  _log_write "Prometheus 已安装"
  pause
}

_install_node_exporter() {
  _require_root
  local ver="1.7.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "正在安装 Node Exporter v$ver..."
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/ne.tar.gz" || { msg_err "下载失败"; rm -rf "$tmpdir"; return; }

  tar xzf "$tmpdir/ne.tar.gz" -C "$tmpdir"
  cp "$tmpdir/node_exporter-${ver}.linux-${arch}/node_exporter" /usr/local/bin/

  useradd -rs /bin/false node_exporter 2>/dev/null || true

  cat > /lib/systemd/system/node_exporter.service << NE2
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
NE2
  systemctl daemon-reload && systemctl enable --now node_exporter 2>/dev/null
  msg_ok "Node Exporter 运行于 http://localhost:9100"
  rm -rf "$tmpdir"
  _log_write "Node Exporter 已安装"
  pause
}

# ---- Remove ----
market_remove() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    read -p "请输入要移除的应用名: " app_name
  fi

  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      local pkg="${rest2%%:*}"
      if confirm "确认移除 $name？"; then
        case "$F_PKG_MGR" in
          apt) apt-get remove -y "$pkg" ;;
          yum) yum remove -y "$pkg" ;;
          apk) apk del "$pkg" ;;
        esac
        msg_ok "$name 已移除"
        _log_write "应用已移除: $name"
      fi
      pause
      return
    fi
  done
  msg_err "未找到应用 '$app_name'"
  pause
}

# ---- Category View ----
market_category() {
  local cat="${1:-}"
  if [[ -z "$cat" ]]; then
    msg_title "应用分类"
    msg ""
    msg "  ${F_GREEN}dev${F_RESET})       开发工具"
    msg "  ${F_GREEN}net${F_RESET})       网络工具"
    msg "  ${F_GREEN}sys${F_RESET})       系统工具"
    msg "  ${F_GREEN}web${F_RESET})       Web 服务与数据库"
    msg "  ${F_GREEN}proxy${F_RESET})     代理与隧道"
    msg "  ${F_GREEN}media${F_RESET})     媒体工具"
    msg "  ${F_GREEN}docker${F_RESET})    容器相关"
    msg "  ${F_GREEN}monitor${F_RESET})   监控工具"
    msg "  ${F_GREEN}security${F_RESET})  安全工具"
    msg "  ${F_GREEN}utility${F_RESET})   实用工具"
    msg ""
    read -p "请选择分类: " cat
  fi
  market_list "$cat"
}

# ---- Help ----
market_help() {
  msg_title "应用市场 帮助"
  msg ""
  msg "  fusionbox market managed catalog  查看真实受管目录与资源/更新限制"
  msg "  fusionbox market managed install ntfy --confirm  本机通知服务；无认证/域名/TLS；版本升级拒绝"
  msg "  fusionbox market managed domain nginx --domain example.com --confirm   HTTP-only owned host mapping"
  msg "  fusionbox market managed domain nginx --remove-domain --confirm  remove owned mapping"
  msg "  fusionbox market managed tls nginx --cert /path/fullchain.pem --key /path/key.pem --confirm"
  msg "  fusionbox market managed tls nginx --disable-tls --confirm  仅停用 TLS，保留证书文件"
  msg "  fusionbox market managed tls-refresh nginx --confirm  校验并重载已更新 PEM，验证本机实际证书"
  msg "  fusionbox market managed status nginx  查看本地证书校验与入口状态"
  msg "  reinstall nginx --confirm --reuse-data  确认复用卸载保留数据"
  msg "  install/reinstall --auto-port     最多探测 20 个 localhost 端口（不预留）"
  msg "  fusionbox market list             列出所有可用应用"
  msg "  fusionbox market search <关键词>  搜索应用"
  msg "  fusionbox market install <应用>   安装应用"
  msg "  fusionbox market remove <应用>    移除应用"
  msg "  fusionbox market category <分类>  按分类浏览"
  msg ""
  msg "  分类: dev, net, sys, web, proxy, media"
  msg ""
}

# Count of managed catalog entries, read live so the menu never goes stale.
_market_managed_count() {
  command -v python3 &>/dev/null || { printf '?'; return; }
  python3 "$FUSION_SRC/lib/market_apps.py" catalog 2>/dev/null | grep -c '^[a-z0-9][a-z0-9_-]*:' || printf '?'
}

# ---- Managed subcommand help (never let argparse leak English usage) ----
market_managed_help() {
  _require_root
  msg_title "受管应用生命周期 帮助"
  msg ""
  msg "  用法: fusionbox market managed <操作> [应用] [选项]"
  msg ""
  msg "  操作:"
  msg "  ${F_GREEN}catalog${F_RESET}                      查看受管目录（应用 ID、端口、资源限制）"
  msg "  ${F_GREEN}status${F_RESET} <应用>               查看本地证书校验与入口状态"
  msg "  ${F_GREEN}install${F_RESET} <应用> --confirm    安装（默认 localhost，端口可 --port/--auto-port）"
  msg "  ${F_GREEN}reinstall${F_RESET} <应用> --confirm --reuse-data  复用保留数据重装"
  msg "  ${F_GREEN}update${F_RESET} <应用> --confirm     更新（镜像版本升级默认拒绝）"
  msg "  ${F_GREEN}uninstall${F_RESET} <应用> --confirm  卸载（保留具名卷数据）"
  msg "  ${F_GREEN}domain${F_RESET} <应用> --domain <域名> --confirm    绑定自有域名（HTTP）"
  msg "  ${F_GREEN}tls${F_RESET} <应用> --cert <证书> --key <私钥> --confirm  使用已有 PEM"
  msg "  ${F_GREEN}tls-refresh${F_RESET} <应用> --confirm 校验并重载已更新的 PEM"
  msg ""
  msg "  常用选项:"
  msg "  --port <端口>       首选 localhost 端口（留空用默认/保留值）"
  msg "  --auto-port         占用时最多探测后续 20 个端口（不保证预留）"
  msg "  --nas-path <路径>   目录模板所需的宿主 NAS 根路径"
  msg "  --risk-ack <文本>   高权限应用要求的完整确认文本"
  msg ""
  msg "  示例: fusionbox market managed install nginx --confirm"
  msg "        fusionbox market managed catalog"
  msg ""
}

# ---- Interactive Menu ----
market_managed_menu() {
  _require_root
  local action port domain cert key app
  local -a args=()
  read -r -p "受管应用 ID（默认 nginx；可用 catalog 查看）: " app || return 1
  app="${app:-nginx}"
  # python3 is a hard dependency here: without it the catalog probe would fail
  # silently and the user would be told "不支持的受管应用 ID", which is wrong.
  if ! _require_python3 "受管应用市场"; then
    return 1
  fi
  local catalog_out
  if ! catalog_out=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog 2>&1); then
    msg_err "无法读取受管应用目录"
    msg "$catalog_out"
    return 1
  fi
  if ! grep -q "^${app}:" <<< "$catalog_out"; then
    msg_err "不支持的受管应用 ID: $app"
    msg_info "可用 ID 列表见: fusionbox market managed catalog"
    return 1
  fi
  read -r -p "操作 catalog/status/install/reinstall/update/uninstall/domain/tls/tls-refresh: " action || return 1
  case "$action" in
    tls-refresh)
      confirm "暂停外部证书写入者后校验并重载？不复制私钥；已覆盖原文件无法回滚，失败需修复后重试" || return 1
      args+=(--confirm) ;;
    tls)
      msg_warn "仅使用已有 PEM 文件；不签发证书。默认 HTTPS 443 并重定向 HTTP；key 需 0600/0400。"
      read -r -p "证书绝对路径（留空停用 TLS）: " cert || return 1
      if [[ -n "$cert" ]]; then
        read -r -p "私钥绝对路径: " key || return 1
        args+=(--cert "$cert" --key "$key")
      else args+=(--disable-tls); fi
      confirm "确认校验文件并重载自有映射？原证书/私钥不复制或删除" || return 1
      args+=(--confirm) ;;
    domain)
      msg_warn "需已有宿主 Nginx conf.d include；暂停其他配置写入者；已有 TLS 设置将保留。"
      read -r -p "域名（留空删除自有映射）: " domain || return 1
      confirm "确认修改并校验/重载宿主 Nginx？" || return 1
      args+=(--confirm)
      if [[ -n "$domain" ]]; then args+=(--domain "$domain"); else args+=(--remove-domain); fi ;;
    catalog|status) ;;
    install|reinstall|update|uninstall)
      if [[ "$action" == install ]]; then
        local details
        details=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog "$app" 2>/dev/null | grep -F "$app:" | head -1) || true
        if [[ "$details" == *"HIGH PRIVILEGE"* ]]; then
          msg_warn "高权限应用：可访问 Docker socket、宿主设备或 host 网络；等同授予宿主控制能力。仅允许 localhost 默认入口，不能配置受管域名。"
          read -r -p "输入目录要求的完整高权限确认文本: " risk_ack || return 1
          args+=(--risk-ack "$risk_ack")
        fi
      fi
      confirm "确认执行 $action？可能停机；卸载保留数据；失败需检查恢复状态" || return 1
      args+=(--confirm)
      if [[ "$action" == reinstall ]]; then
        confirm "确认复用此受管项目原有具名卷与镜像？" || return 1
        args+=(--reuse-data)
      fi
      if [[ "$action" == install || "$action" == reinstall ]]; then
        read -r -p "首选 localhost 端口（留空使用默认/保留值）: " port || return 1
        [[ -z "$port" ]] || args+=(--port "$port")
        if confirm "占用时最多探测后续 20 个端口？探测不保证预留"; then args+=(--auto-port); fi
      fi ;;
    *) msg_err "无效操作"; return 1 ;;
  esac
  python3 "$FUSION_SRC/lib/market_apps.py" "$action" "$app" "${args[@]}"
}

market_menu() {
  while true; do
    clear
    _print_banner
    msg_title "应用市场"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 列出所有应用"
    msg "  ${F_GREEN}2${F_RESET}) 按分类浏览"
    msg "  ${F_GREEN}3${F_RESET}) 搜索"
    msg "  ${F_GREEN}4${F_RESET}) 安装应用"
    msg "  ${F_GREEN}5${F_RESET}) 移除应用"
    msg "  ${F_GREEN}6${F_RESET}) 受管应用生命周期（catalog 查看全部 $(_market_managed_count) 个；localhost/保留数据）"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-6]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) market_list; pause ;;
      2) market_category; pause ;;
      3) market_search; pause ;;
      4) market_install; pause ;;
      5) market_remove; pause ;;
      6) market_managed_menu; pause ;;
      0) break ;;
    esac
  done
}
