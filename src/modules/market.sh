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
  "dev:Docker CE:docker-ce:容器化平台"

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
  "sys:Screen:screen:终端复用器"
  "sys:TMUX:tmux:终端复用器"
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
)

market_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    list|l)           market_list "$@" ;;
    search|s)         market_search "$@" ;;
    install|i)        market_install "$@" ;;
    remove|rm)        market_remove "$@" ;;
    category|cat)     market_category "$@" ;;
    menu|main)        market_menu ;;
    help|h)           market_help ;;
    *)                market_menu ;;
  esac
}

# ---- List all apps ----
market_list() {
  local filter="${1:-}"
  msg_title "$(tr MARKET_LIST "Available Apps")"
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
          dev)   msg "  ${F_BOLD}${F_CYAN}[开发工具]${F_RESET}" ;;
          net)   msg "  ${F_BOLD}${F_CYAN}[网络工具]${F_RESET}" ;;
          sys)   msg "  ${F_BOLD}${F_CYAN}[系统工具]${F_RESET}" ;;
          web)   msg "  ${F_BOLD}${F_CYAN}[Web 服务与数据库]${F_RESET}" ;;
          proxy) msg "  ${F_BOLD}${F_CYAN}[代理与隧道]${F_RESET}" ;;
          media) msg "  ${F_BOLD}${F_CYAN}[媒体工具]${F_RESET}" ;;
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

  msg_title "Search: $query"
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
      panels_frp
      return
      ;;
    "Rclone")
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

_caddy_from_pkg() {
  case "$F_PKG_MGR" in
    apt) _install_pkg caddy ;;
    yum) _install_pkg caddy ;;
    apk) _install_pkg caddy ;;
  esac
}

_install_nodejs() {
  msg_info "正在安装 Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null || \
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - 2>/dev/null || \
    _install_pkg nodejs
  if command -v node &>/dev/null; then
    msg_ok "Node.js: $(node --version 2>/dev/null)"
    msg_ok "npm: $(npm --version 2>/dev/null)"
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
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
  if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
    msg_ok "Rust 已安装: $($HOME/.cargo/bin/rustc --version)"
  fi
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
    msg_title "$(tr MARKET_LIST "App Categories")"
    msg ""
    msg "  ${F_GREEN}dev${F_RESET})     开发工具"
    msg "  ${F_GREEN}net${F_RESET})     网络工具"
    msg "  ${F_GREEN}sys${F_RESET})     系统工具"
    msg "  ${F_GREEN}web${F_RESET})     Web 服务与数据库"
    msg "  ${F_GREEN}proxy${F_RESET})   代理与隧道"
    msg "  ${F_GREEN}media${F_RESET})   媒体工具"
    msg ""
    read -p "请选择分类: " cat
  fi
  market_list "$cat"
}

# ---- Help ----
market_help() {
  msg_title "应用市场 帮助"
  msg ""
  msg "  fusionbox market list             列出所有可用应用"
  msg "  fusionbox market search <关键词>  搜索应用"
  msg "  fusionbox market install <应用>   安装应用"
  msg "  fusionbox market remove <应用>    移除应用"
  msg "  fusionbox market category <分类>  按分类浏览"
  msg ""
  msg "  分类: dev, net, sys, web, proxy, media"
  msg ""
}

# ---- Interactive Menu ----
market_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(tr MOD_MARKET "App Market")"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) $(tr MARKET_LIST "List All Apps")"
    msg "  ${F_GREEN}2${F_RESET}) 按分类浏览"
    msg "  ${F_GREEN}3${F_RESET}) 搜索"
    msg "  ${F_GREEN}4${F_RESET}) $(tr MARKET_INSTALL "Install App")"
    msg "  ${F_GREEN}5${F_RESET}) $(tr MARKET_REMOVE "Remove App")"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "请选择 [0-5]: " choice
    case "$choice" in
      1) market_list; pause ;;
      2) market_category; pause ;;
      3) market_search; pause ;;
      4) market_install; pause ;;
      5) market_remove; pause ;;
      0) break ;;
    esac
  done
}
