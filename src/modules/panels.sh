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
    msg_info "Docker 已安装: $(docker --version)"
    return
  fi

  msg_info "正在安装 Docker..."
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
    msg_ok "Docker 安装完成: $(docker --version 2>/dev/null)"
    docker compose version 2>/dev/null | xargs -I{} msg_ok "Docker Compose: {}"
    _log_write "Docker 已安装"
  fi
}

panels_docker_ps() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"
    return
  fi
  msg_title "Docker 容器"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_images() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"
    return
  fi
  msg_title "Docker 镜像"
  msg ""
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_prune() {
  _require_root
  if ! confirm "是否清理未使用的 Docker 资源？"; then
    return
  fi
  docker system prune -a -f --volumes 2>/dev/null
  msg_ok "Docker 清理完成"
  _log_write "Docker 已清理"
  pause
}

panels_docker_compose() {
  _require_root
  local project="${2:-}"
  local compose_dir="/opt/docker"
  mkdir -p "$compose_dir"

  if [[ -z "$project" ]]; then
    msg_title "Docker Compose 项目"
    msg ""
    find "$compose_dir" -name "docker-compose.yml" -o -name "compose.yaml" 2>/dev/null | while read -r f; do
      msg "  $(dirname "$f" | xargs basename)"
    done

    msg ""
    msg "  1) 创建新项目"
    msg "  2) 部署现有项目"
    read -p "请选择: " comp_choice

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
          msg_ok "项目 '$project' 已创建于 $proj_dir"
        fi
        ;;
      2)
        msg_info "正在自动部署所有项目..."
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "  Deployed: $(basename "$(dirname "$f")")"
        done
        ;;
    esac
  else
    local proj_file="$compose_dir/$project/docker-compose.yml"
    if [[ -f "$proj_file" ]]; then
      docker compose -f "$proj_file" up -d 2>/dev/null && msg_ok "$project 已部署" || msg_err "部署失败"
    else
      msg_err "未找到项目: $project"
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
      msg "  容器: $running 运行中, $total 总计"
    else
      msg "  Docker 未安装"
    fi
    msg ""
    msg "  1) 安装 Docker"
    msg "  2) 列出容器"
    msg "  3) 列出镜像"
    msg "  4) Docker Compose / 项目"
    msg "  5) 清理 (prune)"
    msg "  0) 返回"
    msg ""
    read -p "请选择 [0-5]: " dk_choice
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
  msg_title "安装宝塔面板"
  msg ""
  msg_warn "宝塔面板是第三方服务器管理面板。"
  if confirm "确认继续安装？"; then
    case "$F_PKG_MGR" in
      apt|yum)
        curl -sSO http://download.bt.cn/install/install_panel.sh 2>/dev/null && \
          bash install_panel.sh 2>/dev/null || \
          msg_err "宝塔安装脚本下载失败"
        ;;
      *)
        msg_err "宝塔面板仅支持 apt/yum 系统"
        ;;
    esac
  fi
  pause
}

# ---- Aapanel ----
panels_aa() {
  _require_root
  msg_title "安装 Aapanel"
  if confirm "确认继续安装？"; then
    curl -sSO http://www.aapanel.com/script/install_7.0_en.sh 2>/dev/null && \
      bash install_7.0_en.sh 2>/dev/null || \
      msg_err "Aapanel 安装脚本下载失败"
  fi
  pause
}

# ---- X-UI ----
panels_xui() {
  _require_root
  msg_title "安装 X-UI 面板"
  msg ""
  if confirm "将安装 X-UI (xray 面板)，确认继续？"; then
    bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh) 2>/dev/null || \
    bash <(curl -Ls https://raw.githubusercontent.com/FranzKafkaYu/x-ui/master/install_en.sh) 2>/dev/null || \
      msg_err "X-UI 安装失败"
    _log_write "X-UI installed"
  fi
  pause
}

# ---- Aria2 ----
panels_aria2() {
  _require_root
  msg_title "安装 Aria2"
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
      msg_ok "Aria2 安装完成。RPC 密钥: fusionbox"
      msg_info "配置文件: /etc/aria2/aria2.conf"
      _log_write "Aria2 已安装"
      ;;
    *)
      msg_err "不支持的包管理器"
      ;;
  esac
  pause
}

# ---- Rclone ----
panels_rclone() {
  _require_root
  msg_title "配置 Rclone"
  msg ""
  if ! command -v rclone &>/dev/null; then
    msg_info "正在安装 rclone..."
    curl -fsSL https://rclone.org/install.sh 2>/dev/null | bash || \
      _install_pkg rclone
  fi

  if command -v rclone &>/dev/null; then
    msg_ok "rclone 已安装: $(rclone version --client 2>/dev/null | head -1)"
    msg ""
    msg "  1) 配置新远程存储（交互式）"
    msg "  2) 列出已配置的远程存储"
    read -p "请选择: " rc_choice
    case "$rc_choice" in
      1) rclone config ;;
      2) rclone listremotes 2>/dev/null | while read -r r; do msg "    $r"; done ;;
    esac
    _log_write "Rclone 已配置"
  fi
  pause
}

# ---- FRP ----
panels_frp() {
  _require_root
  msg_title "安装 FRP (内网穿透)"
  msg ""
  msg "  1) 安装 FRP 服务端"
  msg "  2) 安装 FRP 客户端"
  read -p "请选择: " frp_choice

  local frp_ver="0.58.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  local tmpdir=$(mktemp -d)
  local dl_url="https://github.com/fatedier/frp/releases/download/v${frp_ver}/frp_${frp_ver}_linux_${arch}.tar.gz"

  msg_info "正在下载 FRP v${frp_ver}..."
  _download "$dl_url" "$tmpdir/frp.tar.gz" || {
    msg_err "下载失败"
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
      msg_ok "FRP 服务端已安装"
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
      msg_ok "FRP 客户端已安装"
      ;;
  esac
  rm -rf "$tmpdir"
  _log_write "FRP 已安装 (类型: $frp_choice)"
  pause
}

# ---- Nezha Monitoring ----
panels_nezha() {
  _require_root
  msg_title "安装哪吒监控 Agent"
  msg ""
  if ! command -v curl &>/dev/null; then
    _install_pkg curl
  fi

  msg_info "正在安装哪吒监控 Agent..."
  msg_info "需要先运行哪吒监控服务端。"
  msg ""
  read -p "服务端地址（如 example.com:8008）: " nezha_server
  read -p "客户端密钥: " nezha_secret

  if [[ -n "$nezha_server" && -n "$nezha_secret" ]]; then
    curl -sL https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh 2>/dev/null | \
      bash -s -- -s "$nezha_server" -p "$nezha_secret" 2>/dev/null || \
      msg_err "安装失败"
    _log_write "Nezha agent configured"
  fi
  pause
}

# ---- Help ----
panels_help() {
  msg_title "面板与工具 帮助"
  msg ""
  msg "  fusionbox panels docker           Docker 管理"
  msg "  fusionbox panels bt               安装宝塔面板"
  msg "  fusionbox panels aa               安装 Aapanel"
  msg "  fusionbox panels xui              安装 X-UI"
  msg "  fusionbox panels aria2            安装 Aria2"
  msg "  fusionbox panels rclone           配置 Rclone"
  msg "  fusionbox panels frp              安装 FRP"
  msg "  fusionbox panels nezha            安装哪吒监控 Agent"
  msg ""
}

# ---- Interactive Menu ----
panels_menu() {
  while true; do
    clear
    _print_banner
    msg_title "面板与工具"
    msg ""
    msg "  1) Docker 管理"
    msg "  2) 安装宝塔面板"
    msg "  3) 安装 Aapanel"
    msg "  4) 安装 X-UI"
    msg "  5) 安装 Aria2"
    msg "  6) 配置 Rclone"
    msg "  7) 安装 FRP"
    msg "  8) 安装哪吒监控 Agent"
    msg "  0) 返回主菜单"
    msg ""
    read -p "请选择 [0-8]: " choice
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
