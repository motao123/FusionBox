# FusionBox Panels & Docker Management Module
# Docker, server panels, and utility tools

panels_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    docker|dk)            panels_docker "$@" ;;
    bt|baota)             panels_bt ;;
    aa|aapanel)           panels_aa ;;
    xui|x-ui)             panels_xui ;;
    aria2)                panels_aria2 ;;
    rclone)               panels_rclone ;;
    frp)                  panels_frp ;;
    nezha|nezuta)         panels_nezha ;;
    menu|main)            panels_menu ;;
    help|h)               panels_help ;;
    *)                    panels_menu ;;
  esac
}

# ---- Docker Management ----
panels_docker() {
  local action="${1:-menu}"

  case "$action" in
    install)      panels_docker_install ;;
    ps)           panels_docker_ps ;;
    images)       panels_docker_images ;;
    prune)        panels_docker_prune ;;
    compose|up)   panels_docker_compose "$@" ;;
    menu|"")      panels_docker_menu ;;
    *)            panels_docker_menu ;;
  esac
}

panels_docker_install() {
  _require_root
  if command -v docker &>/dev/null; then
    msg_info "Docker already installed: $(docker --version)"
    return
  fi

  msg_info "Installing Docker..."
  case "$F_PKG_MGR" in
    apt)
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    yum)
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    apk)
      _install_pkg docker docker-compose
      rc-update add docker default 2>/dev/null
      rc-service docker start 2>/dev/null
      return
      ;;
  esac

  systemctl enable docker 2>/dev/null
  systemctl start docker 2>/dev/null

  if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
    local compose_ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/$compose_ver/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null && \
      chmod +x /usr/local/bin/docker-compose
  fi

  if command -v docker &>/dev/null; then
    msg_ok "Docker installed: $(docker --version 2>/dev/null)"
    docker compose version 2>/dev/null | xargs -I{} msg_ok "Docker Compose: {}"
    _log_write "Docker installed"
  fi
}

panels_docker_ps() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker not installed"
    return
  fi
  msg_title "Docker Containers"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_images() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker not installed"
    return
  fi
  msg_title "Docker Images"
  msg ""
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_prune() {
  _require_root
  if ! confirm "Clean up unused Docker resources?"; then
    return
  fi
  docker system prune -a -f --volumes 2>/dev/null
  msg_ok "Docker cleaned"
  _log_write "Docker pruned"
  pause
}

panels_docker_compose() {
  _require_root
  local project="${2:-}"
  local compose_dir="/opt/docker"
  mkdir -p "$compose_dir"

  if [[ -z "$project" ]]; then
    msg_title "Docker Compose Projects"
    msg ""
    find "$compose_dir" -name "docker-compose.yml" -o -name "compose.yaml" 2>/dev/null | while read -r f; do
      msg "  $(dirname "$f" | xargs basename)"
    done

    msg ""
    msg "  1) Create new project"
    msg "  2) Deploy existing"
    read -p "Select: " comp_choice

    case "$comp_choice" in
      1)
        read -p "$(tr MSG_INPUT "Project name"): " project
        if [[ -n "$project" ]]; then
          local proj_dir="$compose_dir/$project"
          mkdir -p "$proj_dir"
          cat > "$proj_dir/docker-compose.yml" << YEOF
version: '3.8'
services:
  app:
    image: nginx:alpine
    container_name: ${project}_app
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
YEOF
          mkdir -p "$proj_dir/html"
          echo "Deployed by FusionBox" > "$proj_dir/html/index.html"
          msg_ok "Project '$project' created at $proj_dir"
        fi
        ;;
      2)
        msg_info "Auto-deploy all projects..."
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "  Deployed: $(basename "$(dirname "$f")")"
        done
        ;;
    esac
  else
    local proj_file="$compose_dir/$project/docker-compose.yml"
    if [[ -f "$proj_file" ]]; then
      docker compose -f "$proj_file" up -d 2>/dev/null && msg_ok "$project deployed" || msg_err "Deploy failed"
    else
      msg_err "Project not found: $project"
    fi
  fi
  pause
}

panels_docker_menu() {
  while true; do
    clear
    msg_title "$(tr PANEL_DOCKER "Docker Management")"
    msg ""
    if command -v docker &>/dev/null; then
      msg "  Docker: $(docker --version 2>/dev/null)"
      local running=$(docker ps -q 2>/dev/null | wc -l)
      local total=$(docker ps -aq 2>/dev/null | wc -l)
      msg "  Containers: $running running, $total total"
    else
      msg "  Docker not installed"
    fi
    msg ""
    msg "  1) Install Docker"
    msg "  2) List Containers"
    msg "  3) List Images"
    msg "  4) Docker Compose / Projects"
    msg "  5) Clean Up (prune)"
    msg "  0) Back"
    msg ""
    read -p "Select [0-5]: " dk_choice
    case "$dk_choice" in
      1) panels_docker_install; pause ;;
      2) panels_docker_ps ;;
      3) panels_docker_images ;;
      4) panels_docker_compose ;;
      5) panels_docker_prune ;;
      0) break ;;
    esac
  done
}

# ---- Baota Panel ----
panels_bt() {
  _require_root
  msg_title "Install Baota Panel"
  msg ""
  msg_warn "Baota Panel is a third-party server management panel."
  if confirm "Continue with installation?"; then
    case "$F_PKG_MGR" in
      apt|yum)
        curl -sSO http://download.bt.cn/install/install_panel.sh 2>/dev/null && \
          bash install_panel.sh 2>/dev/null || \
          msg_err "Failed to download Baota installer"
        ;;
      *)
        msg_err "Baota panel only supports apt/yum systems"
        ;;
    esac
  fi
  pause
}

# ---- Aapanel ----
panels_aa() {
  _require_root
  msg_title "Install Aapanel"
  if confirm "Continue with installation?"; then
    curl -sSO http://www.aapanel.com/script/install_7.0_en.sh 2>/dev/null && \
      bash install_7.0_en.sh 2>/dev/null || \
      msg_err "Failed to download Aapanel installer"
  fi
  pause
}

# ---- X-UI ----
panels_xui() {
  _require_root
  msg_title "Install X-UI Panel"
  msg ""
  if confirm "This will install X-UI (xray panel). Continue?"; then
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh) 2>/dev/null || \
    bash <(curl -Ls https://raw.githubusercontent.com/FranzKafkaYu/x-ui/master/install_en.sh) 2>/dev/null || \
      msg_err "Failed to install X-UI"
    _log_write "X-UI installed"
  fi
  pause
}

# ---- Aria2 ----
panels_aria2() {
  _require_root
  msg_title "Install Aria2"
  msg ""
  case "$F_PKG_MGR" in
    apt|yum|apk)
      _install_pkg aria2
      mkdir -p /etc/aria2
      cat > /etc/aria2/aria2.conf << AEOF
dir=/var/ftp
file-allocation=falloc
continue=true
daemon=true
max-connection-per-server=4
rpc-listen-all=true
rpc-allow-origin-all=true
rpc-secret=fusionbox
AEOF
      mkdir -p /var/ftp
      msg_ok "Aria2 installed. RPC secret: fusionbox"
      msg_info "Config: /etc/aria2/aria2.conf"
      _log_write "Aria2 installed"
      ;;
    *)
      msg_err "Package manager not supported"
      ;;
  esac
  pause
}

# ---- Rclone ----
panels_rclone() {
  _require_root
  msg_title "Configure Rclone"
  msg ""
  if ! command -v rclone &>/dev/null; then
    msg_info "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh 2>/dev/null | bash || \
      _install_pkg rclone
  fi

  if command -v rclone &>/dev/null; then
    msg_ok "rclone installed: $(rclone version --client 2>/dev/null | head -1)"
    msg ""
    msg "  1) Configure new remote (interactive)"
    msg "  2) List configured remotes"
    read -p "Select: " rc_choice
    case "$rc_choice" in
      1) rclone config ;;
      2) rclone listremotes 2>/dev/null | while read -r r; do msg "    $r"; done ;;
    esac
    _log_write "Rclone configured"
  fi
  pause
}

# ---- FRP ----
panels_frp() {
  _require_root
  msg_title "Install FRP (Fast Reverse Proxy)"
  msg ""
  msg "  1) Install FRP Server"
  msg "  2) Install FRP Client"
  read -p "Select: " frp_choice

  local frp_ver="0.58.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  local tmpdir=$(mktemp -d)
  local dl_url="https://github.com/fatedier/frp/releases/download/v${frp_ver}/frp_${frp_ver}_linux_${arch}.tar.gz"

  msg_info "Downloading FRP v${frp_ver}..."
  _download "$dl_url" "$tmpdir/frp.tar.gz" || {
    msg_err "Download failed"
    rm -rf "$tmpdir"
    pause; return
  }

  tar xzf "$tmpdir/frp.tar.gz" -C "$tmpdir"
  local frp_dir="$tmpdir/frp_${frp_ver}_linux_${arch}"

  case "$frp_choice" in
    1)
      cp "$frp_dir/frps" /usr/local/bin/
      chmod +x /usr/local/bin/frps
      cp "$frp_dir/frps.toml" /etc/frps.toml 2>/dev/null || true
      cat > /lib/systemd/system/frps.service << FE1
[Unit]
Description=FRP Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frps.toml
Restart=on-failure
[Install]
WantedBy=multi-user.target
FE1
      systemctl daemon-reload 2>/dev/null
      systemctl enable --now frps 2>/dev/null
      msg_ok "FRP server installed"
      ;;
    2)
      cp "$frp_dir/frpc" /usr/local/bin/
      chmod +x /usr/local/bin/frpc
      cp "$frp_dir/frpc.toml" /etc/frpc.toml 2>/dev/null || true
      cat > /lib/systemd/system/frpc.service << FE2
[Unit]
Description=FRP Client
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /etc/frpc.toml
Restart=on-failure
[Install]
WantedBy=multi-user.target
FE2
      systemctl daemon-reload 2>/dev/null
      systemctl enable --now frpc 2>/dev/null
      msg_ok "FRP client installed"
      ;;
  esac
  rm -rf "$tmpdir"
  _log_write "FRP installed (type: $frp_choice)"
  pause
}

# ---- Nezha Monitoring ----
panels_nezha() {
  _require_root
  msg_title "Install Nezha Monitoring Agent"
  msg ""
  if ! command -v curl &>/dev/null; then
    _install_pkg curl
  fi

  msg_info "Nezha monitoring agent install..."
  msg_info "You need a Nezha server running first."
  msg ""
  read -p "Server address (e.g., example.com:8008): " nezha_server
  read -p "Client secret: " nezha_secret

  if [[ -n "$nezha_server" && -n "$nezha_secret" ]]; then
    curl -sL https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh 2>/dev/null | \
      bash -s -- -s "$nezha_server" -p "$nezha_secret" 2>/dev/null || \
      msg_err "Installation failed"
    _log_write "Nezha agent configured"
  fi
  pause
}

# ---- Help ----
panels_help() {
  msg_title "Panel & Tools Help"
  msg ""
  msg "  fusionbox panels docker           Docker management"
  msg "  fusionbox panels bt               Install Baota Panel"
  msg "  fusionbox panels aa               Install Aapanel"
  msg "  fusionbox panels xui              Install X-UI"
  msg "  fusionbox panels aria2            Install Aria2"
  msg "  fusionbox panels rclone           Configure Rclone"
  msg "  fusionbox panels frp              Install FRP"
  msg "  fusionbox panels nezha            Install Nezha agent"
  msg ""
}

# ---- Interactive Menu ----
panels_menu() {
  while true; do
    clear
    _print_banner
    msg_title "Panel & Tools"
    msg ""
    msg "  1) Docker Management"
    msg "  2) Install Baota Panel"
    msg "  3) Install Aapanel"
    msg "  4) Install X-UI"
    msg "  5) Install Aria2"
    msg "  6) Configure Rclone"
    msg "  7) Install FRP"
    msg "  8) Install Nezha Agent"
    msg "  0) Back to Main Menu"
    msg ""
    read -p "Select [0-8]: " choice
    case "$choice" in
      1) panels_docker;;
      2) panels_bt ;;
      3) panels_aa ;;
      4) panels_xui ;;
      5) panels_aria2 ;;
      6) panels_rclone ;;
      7) panels_frp ;;
      8) panels_nezha ;;
      0) break ;;
    esac
  done
}
