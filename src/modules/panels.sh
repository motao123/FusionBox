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
        read -p "请输入项目名: " project
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
          echo "由 FusionBox 部署" > "$proj_dir/html/index.html"
          msg_ok "项目 '$project' 已创建于 $proj_dir"
        fi
        ;;
      2)
        msg_info "正在自动部署所有项目..."
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "  已部署: $(basename "$(dirname "$f")")"
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

# ---- Docker 端口访问控制 ----
panels_docker_port_control() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "容器端口访问控制"
  msg ""

  docker ps --format "table {{.Names}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 开放容器端口到公网"
  msg "  2) 限制容器仅本地访问"
  msg "  3) 查看容器端口详情"
  msg "  0) 返回"
  read -p "请选择: " pc_choice

  case "$pc_choice" in
    1)
      read -p "要开放的端口: " port
      if [[ -n "$port" ]]; then
        iptables -I DOCKER-USER -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -I DOCKER-USER -p udp --dport "$port" -j ACCEPT 2>/dev/null
        if command -v ufw &>/dev/null; then ufw allow "$port" 2>/dev/null; fi
        msg_ok "端口 $port 已开放"
        _log_write "Docker 端口已开放: $port"
      fi
      ;;
    2)
      read -p "要限制的端口: " port
      if [[ -n "$port" ]]; then
        iptables -I DOCKER-USER -p tcp --dport "$port" -j DROP 2>/dev/null
        iptables -I DOCKER-USER -p udp --dport "$port" -j DROP 2>/dev/null
        msg_ok "端口 $port 已限制为仅本地"
      fi
      ;;
    3)
      read -p "容器名称: " c
      docker port "$c" 2>/dev/null
      docker inspect "$c" --format '{{json .HostConfig.PortBindings}}' 2>/dev/null
      ;;
  esac
  pause
}

# ---- Docker IPv6 网络配置 ----
panels_docker_ipv6() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "Docker IPv6 网络配置"
  msg ""

  msg "  1) 启用 Docker IPv6"
  msg "  2) 禁用 Docker IPv6"
  msg "  3) 创建 IPv6 网络"
  msg "  0) 返回"
  read -p "请选择: " ipv6_choice

  case "$ipv6_choice" in
    1)
      mkdir -p /etc/docker
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['ipv6'] = True
cfg['fixed-cidr-v6'] = 'fd00::/80'
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
      else
        echo '{"ipv6": true, "fixed-cidr-v6": "fd00::/80"}' > "$daemon_json"
      fi
      systemctl restart docker 2>/dev/null
      msg_ok "Docker IPv6 已启用"
      _log_write "Docker IPv6 已启用"
      ;;
    2)
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg.pop('ipv6', None)
cfg.pop('fixed-cidr-v6', None)
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
        systemctl restart docker 2>/dev/null
        msg_ok "Docker IPv6 已禁用"
      fi
      ;;
    3)
      read -p "网络名称: " net_name
      read -p "IPv6 子网 (如 fd00:1::/64): " ipv6_subnet
      if [[ -n "$net_name" && -n "$ipv6_subnet" ]]; then
        docker network create --ipv6 --subnet "$ipv6_subnet" "$net_name" 2>/dev/null && \
          msg_ok "IPv6 网络 '$net_name' 已创建" || msg_err "创建失败"
      fi
      ;;
  esac
  pause
}

# ---- Docker daemon.json 编辑 ----
panels_docker_daemon() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "Docker daemon.json 配置"
  msg ""

  if [[ -f "$daemon_json" ]]; then
    msg "  ${F_BOLD}当前配置:${F_RESET}"
    cat "$daemon_json" 2>/dev/null
  else
    msg "  当前使用默认配置"
  fi

  msg ""
  msg "  1) 配置镜像加速"
  msg "  2) 配置日志限制"
  msg "  3) 配置 DNS"
  msg "  4) 手动编辑 daemon.json"
  msg "  5) 重置为默认"
  msg "  0) 返回"
  read -p "请选择: " dm_choice

  case "$dm_choice" in
    1)
      read -p "请输入镜像加速地址: " mirror_url
      if [[ -n "$mirror_url" ]]; then
        mkdir -p /etc/docker
        if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
          python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['registry-mirrors'] = ['$mirror_url']
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
        else
          echo "{\"registry-mirrors\": [\"$mirror_url\"]}" > "$daemon_json"
        fi
        systemctl restart docker 2>/dev/null
        msg_ok "镜像加速已配置"
      fi
      ;;
    2)
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['log-driver'] = 'json-file'
cfg['log-opts'] = {'max-size': '10m', 'max-file': '3'}
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
      else
        echo '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}' > "$daemon_json"
      fi
      systemctl restart docker 2>/dev/null
      msg_ok "日志限制已配置 (10MB x 3)"
      ;;
    3)
      read -p "DNS 服务器 (如 8.8.8.8): " dns_server
      if [[ -n "$dns_server" ]]; then
        if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
          python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['dns'] = ['$dns_server']
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
        fi
        systemctl restart docker 2>/dev/null
        msg_ok "DNS 已设为 $dns_server"
      fi
      ;;
    4)
      ${EDITOR:-vi} "$daemon_json"
      systemctl restart docker 2>/dev/null
      ;;
    5)
      if confirm "确认重置 daemon.json？"; then
        rm -f "$daemon_json"
        systemctl restart docker 2>/dev/null
        msg_ok "已重置为默认配置"
      fi
      ;;
  esac
  pause
}

# ---- Docker 备份/迁移/恢复 ----
panels_docker_backup() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 备份/迁移/恢复"
  msg ""
  msg "  1) 备份所有容器"
  msg "  2) 备份指定容器"
  msg "  3) 备份所有镜像"
  msg "  4) 备份 Compose 项目"
  msg "  5) 恢复容器/镜像"
  msg "  6) 容器迁移到远程服务器"
  msg "  0) 返回"
  read -p "请选择: " dbk_choice

  local backup_dir="/root/docker_backups"
  mkdir -p "$backup_dir"
  local date_str=$(date '+%Y%m%d_%H%M%S')

  case "$dbk_choice" in
    1)
      msg_info "正在备份所有容器..."
      for container in $(docker ps -a --format '{{.Names}}' 2>/dev/null); do
        docker export "$container" > "$backup_dir/${container}_${date_str}.tar" 2>/dev/null && \
          msg "  已导出: $container"
      done
      msg_ok "所有容器已备份到 $backup_dir"
      _log_write "Docker 容器已全部备份"
      ;;
    2)
      read -p "容器名称: " c
      if [[ -n "$c" ]]; then
        docker export "$c" > "$backup_dir/${c}_${date_str}.tar" 2>/dev/null
        msg_ok "容器 '$c' 已备份"
      fi
      ;;
    3)
      local img_file="$backup_dir/all_images_${date_str}.tar"
      msg_info "正在备份所有镜像..."
      docker save $(docker images -q 2>/dev/null) -o "$img_file" 2>/dev/null
      msg_ok "所有镜像已备份: $img_file ($(du -h "$img_file" | cut -f1))"
      ;;
    4)
      local compose_backup="$backup_dir/compose_${date_str}.tar.gz"
      tar czf "$compose_backup" /opt/docker/ 2>/dev/null
      msg_ok "Compose 项目已备份: $compose_backup"
      ;;
    5)
      ls -lh "$backup_dir"/*.tar "$backup_dir"/*.tar.gz 2>/dev/null
      read -p "输入备份文件名: " backup_file
      if [[ -f "$backup_dir/$backup_file" ]]; then
        if [[ "$backup_file" == *images*.tar ]]; then
          docker load -i "$backup_dir/$backup_file" 2>/dev/null && msg_ok "镜像已恢复"
        elif [[ "$backup_file" == *.tar.gz ]]; then
          tar xzf "$backup_dir/$backup_file" -C / && msg_ok "Compose 项目已恢复"
        else
          read -p "新容器名称: " new_name
          docker import "$backup_dir/$backup_file" "$new_name" 2>/dev/null && msg_ok "已导入: $new_name"
        fi
      fi
      ;;
    6)
      read -p "容器名称: " c
      read -p "远程主机 (user@host): " remote_host
      if [[ -n "$c" && -n "$remote_host" ]]; then
        local img_file="$backup_dir/${c}_${date_str}.tar"
        docker export "$c" > "$img_file" 2>/dev/null
        scp "$img_file" "${remote_host}:/tmp/" 2>/dev/null && \
          msg_ok "已传输到 $remote_host:/tmp/$(basename "$img_file")" || msg_err "传输失败"
        msg "在远程运行: docker import /tmp/$(basename "$img_file") $c"
      fi
      ;;
  esac
  pause
}

# ---- Docker 容器管理 ----
panels_docker_container_mgmt() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "容器管理"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 启动容器"
  msg "  2) 停止容器"
  msg "  3) 重启容器"
  msg "  4) 删除容器"
  msg "  5) 查看容器日志"
  msg "  6) 进入容器终端"
  msg "  7) 查看资源占用"
  msg "  8) 设置自动重启"
  msg "  0) 返回"
  read -p "请选择: " cm_choice

  case "$cm_choice" in
    1) read -p "容器名称: " c; docker start "$c" 2>/dev/null && msg_ok "已启动: $c" ;;
    2) read -p "容器名称: " c; docker stop "$c" 2>/dev/null && msg_ok "已停止: $c" ;;
    3) read -p "容器名称: " c; docker restart "$c" 2>/dev/null && msg_ok "已重启: $c" ;;
    4)
      read -p "容器名称: " c
      if confirm "确认删除容器 $c？"; then
        docker stop "$c" 2>/dev/null; docker rm "$c" 2>/dev/null && msg_ok "已删除: $c"
      fi
      ;;
    5) read -p "容器名称: " c; read -p "行数 (默认50): " n; docker logs --tail "${n:-50}" "$c" 2>/dev/null ;;
    6) read -p "容器名称: " c; docker exec -it "$c" /bin/bash 2>/dev/null || docker exec -it "$c" /bin/sh 2>/dev/null ;;
    7) docker stats --no-stream 2>/dev/null ;;
    8)
      read -p "容器名称: " c
      msg "  1) 设置自动重启  2) 取消自动重启"
      read -p "请选择: " r
      [[ "$r" == "1" ]] && docker update --restart=always "$c" 2>/dev/null && msg_ok "已设置" || \
        docker update --restart=no "$c" 2>/dev/null && msg_ok "已取消"
      ;;
  esac
  pause
}

# ---- Docker 网络管理 ----
panels_docker_network() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 网络管理"
  msg ""
  docker network ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 创建网络"
  msg "  2) 查看网络详情"
  msg "  3) 连接容器到网络"
  msg "  4) 删除网络"
  msg "  0) 返回"
  read -p "请选择: " net_choice

  case "$net_choice" in
    1)
      read -p "网络名称: " net_name
      read -p "子网 (如 172.20.0.0/16，可留空): " subnet
      if [[ -n "$net_name" ]]; then
        if [[ -n "$subnet" ]]; then
          docker network create --subnet "$subnet" "$net_name" 2>/dev/null
        else
          docker network create "$net_name" 2>/dev/null
        fi
        msg_ok "网络 '$net_name' 已创建"
      fi
      ;;
    2) read -p "网络名称: " n; docker network inspect "$n" 2>/dev/null ;;
    3)
      read -p "网络名称: " n; read -p "容器名称: " c
      docker network connect "$n" "$c" 2>/dev/null && msg_ok "已连接"
      ;;
    4) read -p "网络名称: " n; confirm "确认删除？" && docker network rm "$n" 2>/dev/null && msg_ok "已删除" ;;
  esac
  pause
}

# ---- Docker 卷管理 ----
panels_docker_volumes() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 卷管理"
  msg ""
  docker volume ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 创建卷"
  msg "  2) 查看卷详情"
  msg "  3) 删除卷"
  msg "  4) 清理未使用卷"
  msg "  0) 返回"
  read -p "请选择: " vol_choice

  case "$vol_choice" in
    1) read -p "卷名称: " v; docker volume create "$v" 2>/dev/null && msg_ok "卷 '$v' 已创建" ;;
    2) read -p "卷名称: " v; docker volume inspect "$v" 2>/dev/null ;;
    3) read -p "卷名称: " v; confirm "确认删除？" && docker volume rm "$v" 2>/dev/null && msg_ok "已删除" ;;
    4) confirm "清理所有未使用的卷？" && docker volume prune -f 2>/dev/null && msg_ok "已清理" ;;
  esac
  pause
}

panels_docker_menu() {
  while true; do
    clear
    msg_title "Docker 管理"
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
    msg "  ${F_GREEN} 1${F_RESET}) 安装 Docker"
    msg "  ${F_GREEN} 2${F_RESET}) 列出容器"
    msg "  ${F_GREEN} 3${F_RESET}) 列出镜像"
    msg "  ${F_GREEN} 4${F_RESET}) Docker Compose / 项目"
    msg "  ${F_GREEN} 5${F_RESET}) 清理 (prune)"
    msg "  ${F_GREEN} 6${F_RESET}) 容器端口访问控制"
    msg "  ${F_GREEN} 7${F_RESET}) Docker IPv6 网络配置"
    msg "  ${F_GREEN} 8${F_RESET}) 编辑 daemon.json"
    msg "  ${F_GREEN} 9${F_RESET}) Docker 备份/迁移/恢复"
    msg "  ${F_GREEN}10${F_RESET}) 容器管理 (启动/停止/重启/删除)"
    msg "  ${F_GREEN}11${F_RESET}) 网络管理"
    msg "  ${F_GREEN}12${F_RESET}) 卷管理"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-12]: " dk_choice
    case "$dk_choice" in
      1) panels_docker_install; pause ;;
      2) panels_docker_ps ;;
      3) panels_docker_images ;;
      4) panels_docker_compose ;;
      5) panels_docker_prune ;;
      6) panels_docker_port_control ;;
      7) panels_docker_ipv6 ;;
      8) panels_docker_daemon ;;
      9) panels_docker_backup ;;
      10) panels_docker_container_mgmt ;;
      11) panels_docker_network ;;
      12) panels_docker_volumes ;;
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
    _log_write "X-UI 已安装"
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
    _log_write "哪吒监控 Agent 已配置"
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
