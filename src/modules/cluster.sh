# FusionBox 集群控制与实用工具模块
# 多服务器管理、k命令快捷方式、游戏服务端、Oracle Cloud

cluster_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    add)              cluster_add "$@" ;;
    remove|rm)        cluster_remove "$@" ;;
    list|ls)          cluster_list "$@" ;;
    exec|run)         cluster_exec "$@" ;;
    sync)             cluster_sync "$@" ;;
    game|server)      cluster_game "$@" ;;
    oracle|oc)        cluster_oracle "$@" ;;
    kcmd|k)           cluster_kcmd "$@" ;;
    menu|main)        cluster_menu ;;
    help|h)           cluster_help ;;
    *)                cluster_menu ;;
  esac
}

# ---- 集群节点管理 ----
CLUSTER_DIR="/etc/fusionbox/cluster"
CLUSTER_NODES="$CLUSTER_DIR/nodes.conf"

_cluster_init() {
  mkdir -p "$CLUSTER_DIR"
  [[ -f "$CLUSTER_NODES" ]] || touch "$CLUSTER_NODES"
}

cluster_add() {
  _require_root
  _cluster_init
  msg_title "添加集群节点"
  msg ""

  read -p "节点名称: " node_name
  read -p "SSH 地址 (user@host): " ssh_addr
  read -p "SSH 端口 (默认 22): " ssh_port
  ssh_port=${ssh_port:-22}

  if [[ -n "$node_name" && -n "$ssh_addr" ]]; then
    echo "$node_name|$ssh_addr|$ssh_port" >> "$CLUSTER_NODES"
    msg_ok "节点 '$node_name' 已添加"
    _log_write "集群节点已添加: $node_name ($ssh_addr)"

    # Test SSH connection
    msg_info "正在测试 SSH 连接..."
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$ssh_port" "$ssh_addr" "echo ok" &>/dev/null; then
      msg_ok "SSH 连接测试成功"
    else
      msg_warn "SSH 连接测试失败，请检查密钥/密码配置"
    fi
  fi
  pause
}

cluster_remove() {
  _require_root
  _cluster_init
  cluster_list
  read -p "输入要删除的节点名称: " node_name
  if [[ -n "$node_name" ]]; then
    sed -i "/^${node_name}|/d" "$CLUSTER_NODES"
    msg_ok "节点 '$node_name' 已删除"
  fi
  pause
}

cluster_list() {
  _require_root
  _cluster_init
  msg_title "集群节点列表"
  msg ""
  if [[ -s "$CLUSTER_NODES" ]]; then
    local i=1
    while IFS='|' read -r name addr port; do
      local status="${F_RED}离线${F_RESET}"
      if ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -p "$port" "$addr" "echo ok" &>/dev/null; then
        status="${F_GREEN}在线${F_RESET}"
      fi
      msg "  $i) $name ($addr:$port) - $status"
      i=$((i+1))
    done < "$CLUSTER_NODES"
  else
    msg "  暂无节点"
  fi
  pause
}

cluster_exec() {
  _require_root
  _cluster_init
  msg_title "批量执行命令"
  msg ""

  if [[ ! -s "$CLUSTER_NODES" ]]; then
    msg_warn "暂无集群节点，请先添加"
    pause; return
  fi

  msg "  当前节点:"
  while IFS='|' read -r name addr port; do
    msg "    $name ($addr:$port)"
  done < "$CLUSTER_NODES"

  msg ""
  read -p "请输入要执行的命令: " cmd_to_run
  if [[ -z "$cmd_to_run" ]]; then
    pause; return
  fi

  msg ""
  msg_info "正在所有节点执行: $cmd_to_run"
  msg "————————————————————————————————"
  while IFS='|' read -r name addr port; do
    msg "  ${F_CYAN}[$name]${F_RESET}"
    local result=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$port" "$addr" "$cmd_to_run" 2>&1)
    if [[ $? -eq 0 ]]; then
      echo "$result" | while IFS= read -r line; do
        msg "    $line"
      done
    else
      msg "    ${F_RED}执行失败${F_RESET}"
    fi
  done < "$CLUSTER_NODES"
  msg "————————————————————————————————"
  _log_write "集群批量执行: $cmd_to_run"
  pause
}

cluster_sync() {
  _require_root
  _cluster_init
  msg_title "同步文件到集群"
  msg ""

  if [[ ! -s "$CLUSTER_NODES" ]]; then
    msg_warn "暂无集群节点"
    pause; return
  fi

  read -p "本地文件/目录路径: " local_path
  read -p "远程目标路径: " remote_path
  if [[ ! -e "$local_path" ]]; then
    msg_err "本地路径不存在"
    pause; return
  fi

  msg ""
  while IFS='|' read -r name addr port; do
    msg_info "正在同步到 $name..."
    scp -r -P "$port" -o ConnectTimeout=10 "$local_path" "$addr:$remote_path" 2>/dev/null && \
      msg_ok "  $name: 同步成功" || \
      msg_err "  $name: 同步失败"
  done < "$CLUSTER_NODES"
  _log_write "集群文件同步: $local_path → $remote_path"
  pause
}

# ---- 游戏服务端 ----
cluster_game() {
  _require_root
  msg_title "游戏服务端"
  msg ""
  msg "  ${F_GREEN}1${F_RESET}) Minecraft Java 版服务端"
  msg "  ${F_GREEN}2${F_RESET}) Minecraft Bedrock 版服务端"
  msg "  ${F_GREEN}3${F_RESET}) Terraria 服务端"
  msg "  ${F_GREEN}4${F_RESET}) Palworld (幻兽帕鲁) 服务端"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择: " game_choice

  case "$game_choice" in
    1) _deploy_minecraft_java ;;
    2) _deploy_minecraft_bedrock ;;
    3) _deploy_terraria ;;
    4) _deploy_palworld ;;
    0) return ;;
  esac
}

_deploy_minecraft_java() {
  local app_dir="/opt/games/minecraft-java"
  mkdir -p "$app_dir"

  msg_info "正在部署 Minecraft Java 服务端..."
  cat > "$app_dir/docker-compose.yml" << MCEOF
version: '3.8'
services:
  minecraft:
    image: itzg/minecraft-server:latest
    container_name: minecraft-java
    restart: always
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      MEMORY: "2G"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "20"
      ONLINE_MODE: "false"
      ENABLE_RCON: "true"
      RCON_PASSWORD: "fusionbox"
    volumes:
      - mc_data:/data

volumes:
  mc_data:
MCEOF

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Minecraft Java 服务端已部署"
  msg "  端口: 25565"
  msg "  RCON 密码: fusionbox"
  msg "  数据目录: $app_dir"
  _log_write "Minecraft Java 服务端已部署"
  pause
}

_deploy_minecraft_bedrock() {
  local app_dir="/opt/games/minecraft-bedrock"
  mkdir -p "$app_dir"

  cat > "$app_dir/docker-compose.yml" << MBEOF
version: '3.8'
services:
  minecraft:
    image: itzg/minecraft-bedrock-server:latest
    container_name: minecraft-bedrock
    restart: always
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      GAMEMODE: "survival"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "20"
    volumes:
      - mcbe_data:/data

volumes:
  mcbe_data:
MBEOF

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Minecraft Bedrock 服务端已部署"
  msg "  端口: 19132/UDP"
  _log_write "Minecraft Bedrock 服务端已部署"
  pause
}

_deploy_terraria() {
  local app_dir="/opt/games/terraria"
  mkdir -p "$app_dir"

  cat > "$app_dir/docker-compose.yml" << TSEOF
version: '3.8'
services:
  terraria:
    image: ryshe/terraria:latest
    container_name: terraria
    restart: always
    ports:
      - "7777:7777"
    environment:
      WORLD_FILENAME: "fusionbox.wld"
      MAX_PLAYERS: "8"
      DIFFICULTY: "1"
    volumes:
      - terraria_data:/root/.local/share/Terraria/Worlds

volumes:
  terraria_data:
TSEOF

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Terraria 服务端已部署"
  msg "  端口: 7777"
  _log_write "Terraria 服务端已部署"
  pause
}

_deploy_palworld() {
  local app_dir="/opt/games/palworld"
  mkdir -p "$app_dir"

  cat > "$app_dir/docker-compose.yml" << PWEOF
version: '3.8'
services:
  palworld:
    image: thijsvanloef/palworld-server-docker:latest
    container_name: palworld
    restart: always
    ports:
      - "8211:8211/udp"
      - "27015:27015/udp"
    environment:
      PLAYERS: "16"
      MULTITHREADING: "true"
      COMMUNITY_SERVER: "false"
    volumes:
      - palworld_data:/palworld/Pal/Saved

volumes:
  palworld_data:
PWEOF

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Palworld (幻兽帕鲁) 服务端已部署"
  msg "  端口: 8211/UDP, 27015/UDP"
  _log_write "Palworld 服务端已部署"
  pause
}

# ---- Oracle Cloud 脚本 ----
cluster_oracle() {
  _require_root
  msg_title "Oracle Cloud 防回收脚本"
  msg ""
  msg_warn "此功能仅适用于 Oracle Cloud 免费服务器"
  msg ""
  msg "  1) 安装防回收保活脚本"
  msg "  2) 查看保活状态"
  msg "  3) 卸载保活脚本"
  msg "  4) 安装 OCI CLI"
  msg "  0) 返回"
  read -p "请选择: " oc_choice

  case "$oc_choice" in
    1)
      msg_info "正在安装 Oracle Cloud 防回收脚本..."
      # Install keep-alive script
      cat > /usr/local/bin/oracle-keepalive << 'OKEOF'
#!/bin/bash
# Oracle Cloud Keep-Alive Script
# Prevents idle instance from being reclaimed

LOG="/var/log/oracle-keepalive.log"
echo "[$(date)] Keep-alive ping" >> "$LOG"

# CPU stress to prevent idle detection
dd if=/dev/urandom bs=1M count=10 | md5sum > /dev/null 2>&1

# Network activity
curl -s https://www.oracle.com > /dev/null 2>&1

echo "[$(date)] Keep-alive completed" >> "$LOG"
OKEOF
      chmod +x /usr/local/bin/oracle-keepalive

      # Add cron job - every 10 minutes
      (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/oracle-keepalive") | crontab -

      msg_ok "防回收脚本已安装 (每 10 分钟运行)"
      _log_write "Oracle Cloud 防回收脚本已安装"
      ;;
    2)
      msg "  ${F_BOLD}保活日志:${F_RESET}"
      tail -10 /var/log/oracle-keepalive.log 2>/dev/null || msg "  暂无日志"
      msg ""
      msg "  ${F_BOLD}Cron 任务:${F_RESET}"
      crontab -l 2>/dev/null | grep "oracle-keepalive" || msg "  未配置"
      ;;
    3)
      crontab -l 2>/dev/null | grep -v "oracle-keepalive" | crontab -
      rm -f /usr/local/bin/oracle-keepalive
      msg_ok "防回收脚本已卸载"
      ;;
    4)
      msg_info "正在安装 OCI CLI..."
      bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" 2>/dev/null
      msg_ok "OCI CLI 安装完成"
      msg "  运行 'oci setup' 进行配置"
      ;;
  esac
  pause
}

# ---- k 命令快捷方式 ----
cluster_kcmd() {
  _require_root
  local kcmd_dir="/etc/fusionbox/kcmd"
  mkdir -p "$kcmd_dir"
  local kcmd_file="$kcmd_dir/aliases.sh"

  msg_title "k 命令快捷方式"
  msg ""

  # Initialize default aliases if not exists
  if [[ ! -f "$kcmd_file" ]]; then
    cat > "$kcmd_file" << 'KEOF'
# FusionBox k 命令快捷方式
alias k='fusionbox'
alias ks='fusionbox system'
alias kb='fusionbox system bbr'
alias kn='fusionbox network'
alias kw='fusionbox web'
alias kp='fusionbox proxy'
alias kd='fusionbox panels docker'
alias km='fusionbox market'
alias kwarp='fusionbox warp'
alias kstatus='fusionbox status'
alias kupdate='fusionbox update'
alias khelp='fusionbox help'
KEOF
  fi

  # Add to bashrc if not present
  if ! grep -q "fusionbox/kcmd" ~/.bashrc 2>/dev/null; then
    echo "[ -f $kcmd_file ] && source $kcmd_file" >> ~/.bashrc
  fi

  msg "  ${F_BOLD}已配置的快捷命令:${F_RESET}"
  msg ""
  cat "$kcmd_file" | grep "^alias" | while IFS= read -r line; do
    local alias_name=$(echo "$line" | sed "s/alias \([^=]*\)=.*/\1/")
    local alias_cmd=$(echo "$line" | sed "s/alias [^=]*='\(.*\)'/\1/")
    msg "  ${F_GREEN}$alias_name${F_RESET} → $alias_cmd"
  done

  msg ""
  msg "  1) 添加自定义快捷命令"
  msg "  2) 删除快捷命令"
  msg "  3) 重置为默认"
  msg "  4) 立即生效 (source)"
  msg "  0) 返回"
  read -p "请选择: " k_choice

  case "$k_choice" in
    1)
      read -p "快捷名称 (如 klog): " alias_name
      read -p "对应命令 (如 'fusionbox system monitor'): " alias_cmd
      if [[ -n "$alias_name" && -n "$alias_cmd" ]]; then
        echo "alias $alias_name='$alias_cmd'" >> "$kcmd_file"
        source "$kcmd_file" 2>/dev/null
        msg_ok "已添加: $alias_name → $alias_cmd"
      fi
      ;;
    2)
      nl -ba "$kcmd_file" | grep "alias"
      read -p "输入要删除的行号: " del_line
      if [[ -n "$del_line" ]]; then
        sed -i "${del_line}d" "$kcmd_file"
        source "$kcmd_file" 2>/dev/null
        msg_ok "已删除"
      fi
      ;;
    3)
      rm -f "$kcmd_file"
      cluster_kcmd
      ;;
    4)
      source "$kcmd_file" 2>/dev/null
      msg_ok "快捷命令已生效"
      ;;
  esac
  pause
}

# ---- Help ----
cluster_help() {
  msg_title "集群控制 帮助"
  msg ""
  msg "  ${F_BOLD}[集群管理]${F_RESET}"
  msg "  fusionbox cluster add            添加集群节点"
  msg "  fusionbox cluster remove         删除集群节点"
  msg "  fusionbox cluster list           列出集群节点"
  msg "  fusionbox cluster exec <cmd>     批量执行命令"
  msg "  fusionbox cluster sync           同步文件到集群"
  msg ""
  msg "  ${F_BOLD}[游戏服务端]${F_RESET}"
  msg "  fusionbox cluster game           游戏服务端部署"
  msg "    - Minecraft Java/Bedrock"
  msg "    - Terraria"
  msg "    - Palworld (幻兽帕鲁)"
  msg ""
  msg "  ${F_BOLD}[Oracle Cloud]${F_RESET}"
  msg "  fusionbox cluster oracle         Oracle Cloud 防回收"
  msg ""
  msg "  ${F_BOLD}[k 命令快捷方式]${F_RESET}"
  msg "  fusionbox cluster kcmd           配置快捷命令"
  msg "    k=fusionbox  ks=system  kb=bbr  kn=network"
  msg "    kw=web  kp=proxy  kd=docker  km=market"
  msg ""
}

# ---- Interactive Menu ----
cluster_menu() {
  while true; do
    clear
    _print_banner
    msg_title "集群控制与工具"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 集群节点管理"
    msg "  ${F_GREEN}2${F_RESET}) 批量执行命令"
    msg "  ${F_GREEN}3${F_RESET}) 同步文件到集群"
    msg "  ${F_GREEN}4${F_RESET}) 游戏服务端"
    msg "  ${F_GREEN}5${F_RESET}) Oracle Cloud 防回收"
    msg "  ${F_GREEN}6${F_RESET}) k 命令快捷方式"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-6]: " choice
    case "$choice" in
      1)
        msg "  1) 添加节点  2) 删除节点  3) 列出节点"
        read -p "请选择: " node_choice
        case "$node_choice" in
          1) cluster_add ;;
          2) cluster_remove ;;
          3) cluster_list ;;
        esac
        ;;
      2) cluster_exec ;;
      3) cluster_sync ;;
      4) cluster_game ;;
      5) cluster_oracle ;;
      6) cluster_kcmd ;;
      0) break ;;
    esac
  done
}
