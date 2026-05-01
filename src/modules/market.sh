# FusionBox App Market Module
# One-click software installation

# App database: category, name, pkg_manager_packages, description
MARKET_APPS=(
  "dev:Git:git:Version control system"
  "dev:Python3:python3:Python programming language"
  "dev:Node.js:nodejs:JavaScript runtime"
  "dev:Go:golang:Go programming language"
  "dev:Rust:rustc:Rust programming language"
  "dev:Redis:redis:In-memory data structure store"
  "dev:Memcached:memcached:Distributed memory caching"
  "dev:SQLite:sqlite3:Lightweight embedded database"
  "dev:Docker CE:docker-ce:Containerization platform"

  "net:Wget:wget:Network downloader"
  "net:Curl:curl:Data transfer tool"
  "net:Netcat:netcat:Network debugging tool"
  "net:Socat:socat:Multipurpose relay tool"
  "net:MTR:mtr:Network diagnostic tool"
  "net:Iperf3:iperf3:Network bandwidth test"
  "net:Nmap:nmap:Network scanner"
  "net:Speedtest CLI:speedtest-cli:Internet speed test"
  "net:FRP:frp:Fast Reverse Proxy"
  "net:Rclone:rclone:Cloud storage sync"

  "sys:Htop:htop:Interactive process viewer"
  "sys:BTN:btop:Resource monitor"
  "sys:Glances:glances:System monitoring"
  "sys:Nano:nano:Text editor"
  "sys:Vim:vim:Advanced text editor"
  "sys:Screen:screen:Terminal multiplexer"
  "sys:TMUX:tmux:Terminal multiplexer"
  "sys:Unzip:unzip:File extraction"
  "sys:Zip:zip:File compression"
  "sys:Tmux:tmux:Terminal multiplexer"
  "sys:Fail2Ban:fail2ban:SSH brute force protection"
  "sys:UFW:ufw:Uncomplicated firewall"
  "sys:Certbot:certbot:SSL certificate tool"
  "sys:rsync:rsync:File synchronization"
  "sys:cron:cron:Task scheduler"
  "sys:supervisor:supervisor:Process control system"
  "sys:Prometheus:prometheus:Monitoring system"
  "sys:Node_Exporter:node_exporter:Prometheus metrics exporter"

  "web:Nginx:nginx:Web server"
  "web:Apache:apache2:Web server"
  "web:Caddy:caddy:Web server with auto TLS"
  "web:PHP:php:PHP scripting language"
  "web:MySQL/MariaDB:mariadb-server:Database server"
  "web:PostgreSQL:postgresql:Advanced database"
  "web:phpMyAdmin:phpmyadmin:MySQL web admin"
  "web:WordPress:wordpress:CMS platform"

  "proxy:Shadowsocks-libev:shadowsocks-libev:Lightweight proxy"
  "proxy:V2ray-core:v2ray:V2Ray proxy platform"
  "proxy:Xray-core:xray:XRay proxy platform"
  "proxy:HAProxy:haproxy:TCP/HTTP proxy"
  "proxy:Nginx_Plus:nginx-plus:Advanced load balancer"

  "media:FFmpeg:ffmpeg:Multimedia processing"
  "media:ImageMagick:imagemagick:Image processing"
  "media:ExifTool:exiftool:Metadata tool"
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
          dev)   msg "  ${F_BOLD}${F_CYAN}[Development Tools]${F_RESET}" ;;
          net)   msg "  ${F_BOLD}${F_CYAN}[Network Tools]${F_RESET}" ;;
          sys)   msg "  ${F_BOLD}${F_CYAN}[System Tools]${F_RESET}" ;;
          web)   msg "  ${F_BOLD}${F_CYAN}[Web Servers & Databases]${F_RESET}" ;;
          proxy) msg "  ${F_BOLD}${F_CYAN}[Proxy & Tunnel]${F_RESET}" ;;
          media) msg "  ${F_BOLD}${F_CYAN}[Media Tools]${F_RESET}" ;;
        esac
      fi
      # Check if installed
      local installed=""
      if command -v "$(echo "$pkg" | cut -d' ' -f1)" &>/dev/null; then
        installed=" ${F_GREEN}[installed]${F_RESET}"
      fi
      msg "  ${F_GREEN}$name${F_RESET} - $desc$installed"
    fi
  done
  msg ""
  msg_info "Use: fusionbox market install <name>"
  pause
}

# ---- Search ----
market_search() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    read -p "$(tr MSG_INPUT "Search term"): " query
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
  [[ $found -eq 0 ]] && msg "  No results found"
  pause
}

# ---- Install ----
market_install() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    market_list
    read -p "$(tr MSG_INPUT "App name to install"): " app_name
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
    msg_err "App '$app_name' not found"
    msg_info "Try: fusionbox market list"
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
      msg_info "Installing Caddy..."
      curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy 2>/dev/null && \
        chmod +x /usr/local/bin/caddy && \
        msg_ok "Caddy installed at /usr/local/bin/caddy" || \
        _install_caddy_from_pkg
      _log_write "Caddy installed"
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
  msg_info "Installing $found (${pkgs[*]})..."
  if _install_pkg "${pkgs[@]}"; then
    msg_ok "$found installed successfully"
    _log_write "App installed: $found"
  else
    msg_err "Failed to install $found"
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
  msg_info "Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>/dev/null || \
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - 2>/dev/null || \
    _install_pkg nodejs
  if command -v node &>/dev/null; then
    msg_ok "Node.js: $(node --version 2>/dev/null)"
    msg_ok "npm: $(npm --version 2>/dev/null)"
  fi
  _log_write "Node.js installed"
  pause
}

_install_go() {
  msg_info "Installing Go..."
  local go_ver; go_ver=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1)
  [[ -z "$go_ver" ]] && go_ver="go1.22.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  curl -fsSL "https://go.dev/dl/${go_ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz 2>/dev/null && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go && \
    msg_ok "Go installed: $go_ver" || msg_err "Go install failed"
  rm -f /tmp/go.tar.gz
  _log_write "Go installed"
  pause
}

_install_rust() {
  msg_info "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y 2>/dev/null
  if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
    msg_ok "Rust installed: $($HOME/.cargo/bin/rustc --version)"
  fi
  _log_write "Rust installed"
  pause
}

_install_wordpress() {
  _require_root
  msg_info "Installing WordPress..."

  # Check prerequisites
  if ! command -v nginx &>/dev/null && ! command -v apache2 &>/dev/null; then
    msg_warn "Web server not found. Install LNMP first? (fusionbox web lnmp)"
    if ! confirm "Continue anyway?"; then return; fi
  fi

  read -p "$(tr MSG_INPUT "Domain for WordPress"): " wp_domain
  [[ -z "$wp_domain" ]] && wp_domain="localhost"

  local wp_root="/var/www/$wp_domain"
  mkdir -p "$wp_root"

  # Download WordPress
  curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz 2>/dev/null || {
    msg_err "Download failed"
    pause; return
  }
  tar xzf /tmp/wordpress.tar.gz -C /tmp
  cp -r /tmp/wordpress/* "$wp_root/"
  chmod -R 755 "$wp_root"
  rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

  msg_ok "WordPress downloaded to $wp_root"
  msg_info "Create a database: fusionbox web mysql"
  msg_info "Then visit http://$wp_domain to configure"
  _log_write "WordPress installed at $wp_root"
  pause
}

_install_prometheus() {
  _require_root
  local ver="2.52.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "Installing Prometheus v$ver..."
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/prometheus/releases/download/v${ver}/prometheus-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/prometheus.tar.gz" || { msg_err "Download failed"; rm -rf "$tmpdir"; return; }

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
  msg_ok "Prometheus running on http://localhost:9090"
  rm -rf "$tmpdir"
  _log_write "Prometheus installed"
  pause
}

_install_node_exporter() {
  _require_root
  local ver="1.7.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "Installing Node Exporter v$ver..."
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/ne.tar.gz" || { msg_err "Download failed"; rm -rf "$tmpdir"; return; }

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
  msg_ok "Node Exporter running on http://localhost:9100"
  rm -rf "$tmpdir"
  _log_write "Node Exporter installed"
  pause
}

# ---- Remove ----
market_remove() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    read -p "$(tr MSG_INPUT "App name to remove"): " app_name
  fi

  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      local pkg="${rest2%%:*}"
      if confirm "$(tr MSG_CONFIRM "Remove $name?")"; then
        case "$F_PKG_MGR" in
          apt) apt-get remove -y "$pkg" ;;
          yum) yum remove -y "$pkg" ;;
          apk) apk del "$pkg" ;;
        esac
        msg_ok "$name removed"
        _log_write "App removed: $name"
      fi
      pause
      return
    fi
  done
  msg_err "App '$app_name' not found"
  pause
}

# ---- Category View ----
market_category() {
  local cat="${1:-}"
  if [[ -z "$cat" ]]; then
    msg_title "$(tr MARKET_LIST "App Categories")"
    msg ""
    msg "  ${F_GREEN}dev${F_RESET})     Development Tools"
    msg "  ${F_GREEN}net${F_RESET})     Network Tools"
    msg "  ${F_GREEN}sys${F_RESET})     System Tools"
    msg "  ${F_GREEN}web${F_RESET})     Web Servers & Databases"
    msg "  ${F_GREEN}proxy${F_RESET})   Proxy & Tunnel"
    msg "  ${F_GREEN}media${F_RESET})   Media Tools"
    msg ""
    read -p "$(tr MSG_SELECT "Category"): " cat
  fi
  market_list "$cat"
}

# ---- Help ----
market_help() {
  msg_title "$(tr MOD_MARKET "App Market") Help"
  msg ""
  msg "  fusionbox market list             $(tr MARKET_LIST "List all available apps")"
  msg "  fusionbox market search <term>    $(tr MSG_INFO "Search for an app")"
  msg "  fusionbox market install <app>    $(tr MARKET_INSTALL "Install an app")"
  msg "  fusionbox market remove <app>     $(tr MARKET_REMOVE "Remove an app")"
  msg "  fusionbox market category <cat>   $(tr MSG_INFO "Browse by category")"
  msg ""
  msg "  Categories: dev, net, sys, web, proxy, media"
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
    msg "  ${F_GREEN}2${F_RESET}) Browse by Category"
    msg "  ${F_GREEN}3${F_RESET}) Search"
    msg "  ${F_GREEN}4${F_RESET}) $(tr MARKET_INSTALL "Install App")"
    msg "  ${F_GREEN}5${F_RESET}) $(tr MARKET_REMOVE "Remove App")"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "$(tr MSG_SELECT "Select") [0-5]: " choice
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
