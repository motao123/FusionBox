# FusionBox 集群控制与实用工具模块
# 多服务器管理、k命令快捷方式、游戏服务端、Oracle Cloud

cluster_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    add)              cluster_add "$@" ;;
    remove|rm)        cluster_remove "$@" ;;
    import|export)    cluster_transfer "$cmd" "$@" ;;
    archive)          cluster_archive "$@" ;;
    trust|connect)    cluster_session "$cmd" "$@" ;;
    node-exec)        cluster_session exec "$@" ;;
    migrate-key)      cluster_session migrate-key "$@" ;;
    list|ls)          cluster_list "$@" ;;
    exec|run)         cluster_exec "$@" ;;
    task|tasks)       cluster_task "$@" ;;
    sync)             cluster_sync "$@" ;;
    game|server)      cluster_game "$@" ;;
    game-manage|gm)   cluster_game_manage "$@" ;;
    oracle|oc)        cluster_oracle "$@" ;;
    kcmd|k)           cluster_kcmd "$@" ;;
    sshout|out)       cluster_sshout "$@" ;;
    menu|main)        cluster_menu ;;
    help|h)           cluster_help ;;
    *)                cluster_menu ;;
  esac
}

# ---- 集群节点管理 ----
CLUSTER_DIR="/etc/fusionbox/cluster"
CLUSTER_NODES="$CLUSTER_DIR/nodes.conf"

_cluster_nodes() {
  python3 "$FUSION_SRC/lib/cluster_nodes.py" --directory "$CLUSTER_DIR" "$@"
}

_cluster_init() {
  # Capture a validated, locked snapshot. Never consume unvalidated disk rows.
  CLUSTER_SNAPSHOT=$(_cluster_nodes list) || return 1
}

cluster_transfer() {
  _require_root
  _cluster_nodes "$@"
}

cluster_archive() {
  _require_root
  python3 "$FUSION_SRC/lib/archive_transfer.py" "$@" --directory "$CLUSTER_DIR"
}

cluster_session() {
  _require_root
  python3 "$FUSION_SRC/lib/cluster_session.py" --directory "$CLUSTER_DIR" "$@"
}

cluster_add() {
  _require_root
  local node_name ssh_addr ssh_port
  read -r -p "节点名称: " node_name || return 1
  read -r -p "SSH 地址 (user@host，IPv6 不加方括号): " ssh_addr || return 1
  read -r -p "SSH 端口 (默认 22): " ssh_port || return 1
  [[ "$ssh_addr" == *@* ]] || { msg_err "需要 user@host"; return 1; }
  _cluster_nodes add "$node_name" "${ssh_addr%%@*}" "${ssh_addr#*@}" "${ssh_port:-22}" || return 1
  msg_ok "节点已添加；未建立 SSH 连接"
  pause
}

cluster_remove() {
  _require_root
  local node_name
  _cluster_nodes list || return 1
  read -r -p "输入要删除的节点名称: " node_name || return 1
  confirm "确认删除节点 '$node_name'？" || return 1
  _cluster_nodes remove "$node_name" || return 1
  msg_ok "节点已删除"
  pause
}

cluster_list() {
  _require_root
  _cluster_init || return 1
  msg_title "集群节点列表"
  msg ""
  if [[ -n "$CLUSTER_SNAPSHOT" ]]; then
    local i=1
    while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
      local status="${F_RED}离线${F_RESET}"
      if ssh -n -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=3 -p "$port" "$addr" "echo ok" &>/dev/null; then
        status="${F_GREEN}在线${F_RESET}"
      fi
      msg "  $i) $name ($addr:$port) - $status"
      i=$((i+1))
    done <<< "$CLUSTER_SNAPSHOT"
  else
    msg "  暂无节点"
  fi
  pause
}

cluster_exec() {
  _require_root
  _cluster_init || return 1
  msg_title "批量执行命令"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "暂无集群节点，请先添加"
    pause; return
  fi

  msg "  当前节点:"
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg "    $name ($addr:$port)"
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  read -p "请输入要执行的命令: " cmd_to_run
  if [[ -z "$cmd_to_run" ]]; then
    pause; return
  fi

  confirm "将在以上所有节点执行该命令，确认？" || { pause; return; }

  msg ""
  msg_info "正在所有节点执行: $cmd_to_run"
  msg "————————————————————————————————"
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg "  ${F_CYAN}[$name]${F_RESET}"
    # 先声明再赋值，避免 local 吞掉 ssh 的退出码（SC2155）
    local result
    result=$(ssh -n -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10 -p "$port" "$addr" "$cmd_to_run" 2>&1)
    if [[ $? -eq 0 ]]; then
      echo "$result" | while IFS= read -r line; do
        msg "    $line"
      done
    else
      msg "    ${F_RED}执行失败${F_RESET}"
    fi
  done <<< "$CLUSTER_SNAPSHOT"
  msg "————————————————————————————————"
  _log_write "集群批量执行: $cmd_to_run"
  pause
}

cluster_sync() {
  _require_root
  _cluster_init || return 1
  msg_title "同步文件到集群"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
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
    [[ -n "$name" ]] || continue
    msg_info "正在同步到 $name..."
    local destination="$addr"
    if [[ "${addr#*@}" == *:* ]]; then destination="${addr%%@*}@[${addr#*@}]"; fi
    scp -F /dev/null -r -P "$port" -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10 -- "$local_path" "$destination:$remote_path" 2>/dev/null && \
      msg_ok "  $name: 同步成功" || \
      msg_err "  $name: 同步失败"
  done <<< "$CLUSTER_SNAPSHOT"
  _log_write "集群文件同步: $local_path → $remote_path"
  pause
}

# ---- 预置批量任务 ----
# 数据表: 名称|说明|远端命令
# 命令内不包含 $ 与反引号，故可安全存放在双引号数组中；远端由目标机 shell 解析
CLUSTER_TASKS=(
  "status|系统状态概览|uptime; free -h | head -2; df -h / | tail -1"
  "update|系统更新|if command -v apt-get >/dev/null; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade; elif command -v dnf >/dev/null; then dnf -y upgrade; elif command -v yum >/dev/null; then yum -y update; fi"
  "clean|系统清理|if command -v apt-get >/dev/null; then apt-get -y autoremove && apt-get clean; elif command -v dnf >/dev/null; then dnf -y autoremove; fi"
  "bbr|启用 BBR|sysctl -w net.ipv4.tcp_congestion_control=bbr && sysctl -w net.core.default_qdisc=fq && sysctl -n net.ipv4.tcp_congestion_control"
  "timezone|设置时区为 Asia/Shanghai|(timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime) && date"
  "docker-ps|Docker 容器状态|docker ps --format 'table {{.Names}}\t{{.Status}}'"
  "fail2ban|安装 fail2ban|(if command -v apt-get >/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban; elif command -v dnf >/dev/null; then dnf -y install fail2ban; else exit 1; fi) && systemctl enable --now fail2ban && echo done"
  "swap1g|创建 1G Swap|if swapon --show=NAME --noheadings | grep -Fxq /swapfile; then echo '已有 swap'; else test ! -e /swapfile && test ! -L /swapfile && fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && (grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab); fi"
  "reboot|重启节点|reboot"
)

cluster_task() {
  _require_root
  _cluster_init || return 1
  msg_title "预置批量任务"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "暂无集群节点，请先添加节点"
    pause; return
  fi

  # 列出任务表
  local i=1 entry name desc tcmd token
  for entry in "${CLUSTER_TASKS[@]}"; do
    name="${entry%%|*}"
    desc="${entry#*|}"; desc="${desc%%|*}"
    msg "  ${F_GREEN}${i}${F_RESET}) ${F_BOLD}${name}${F_RESET} - ${desc}"
    i=$((i+1))
  done
  msg "  ${F_GREEN}c${F_RESET}) 自定义命令"
  msg ""
  read -p "请选择任务（可多选，空格分隔，如 1 3 5；c=自定义）: " task_choice
  [[ -z "$task_choice" ]] && { pause; return; }

  # 解析选择（任务序号 / 多选 / c 自定义）
  local -a run_cmds=() run_names=()
  for token in $task_choice; do
    if [[ "$token" =~ ^[Cc]$ ]]; then
      read -p "请输入自定义命令: " tcmd
      if [[ -n "$tcmd" ]]; then
        run_cmds+=("$tcmd")
        run_names+=("自定义")
      fi
    elif [[ "$token" =~ ^[0-9]+$ ]] && [[ "$token" -ge 1 && "$token" -le "${#CLUSTER_TASKS[@]}" ]]; then
      entry="${CLUSTER_TASKS[$((token-1))]}"
      name="${entry%%|*}"
      tcmd="${entry#*|}"; tcmd="${tcmd#*|}"
      run_cmds+=("$tcmd")
      run_names+=("$name")
    else
      msg_warn "忽略无效选项: $token"
    fi
  done

  if [[ ${#run_cmds[@]} -eq 0 ]]; then
    msg_err "未选择任何有效任务"
    pause; return
  fi

  # 显示目标节点清单
  msg ""
  msg "  ${F_BOLD}目标节点:${F_RESET}"
  local node_total=0 n a p
  while IFS='|' read -r n a p; do
    [[ -z "$n" ]] && continue
    msg "    $n ($a:$p)"
    node_total=$((node_total+1))
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  msg "  已选任务: ${run_names[*]}"
  confirm "确认在以上 $node_total 个节点执行所选任务？" || { pause; return; }

  # reboot 属破坏性操作：额外二次确认（输入大写 YES）
  local j need_reboot=0
  for j in "${!run_names[@]}"; do
    [[ "${run_names[$j]}" == "reboot" ]] && need_reboot=1
  done
  if [[ $need_reboot -eq 1 ]]; then
    msg_warn "所选任务包含「重启节点」，目标节点将立即断开连接并重启"
    read -p "请输入大写 YES 二次确认: " reboot_yes
    [[ "$reboot_yes" == "YES" ]] || { msg_info "已取消执行"; pause; return; }
    msg_info "提示: 节点重启会立即断开 SSH，该节点可能显示执行失败，属正常现象"
  fi

  # 逐节点执行：单个节点内依次跑完所选任务
  local ok=0 fail=0 result rc line node_fail=0
  msg ""
  msg "————————————————————————————————"
  while IFS='|' read -r n a p; do
    [[ -z "$n" ]] && continue
    msg "  ${F_CYAN}[$n]${F_RESET} ($a:$p)"
    node_fail=0
    for j in "${!run_cmds[@]}"; do
      msg "    ${F_BOLD}>${F_RESET} ${run_names[$j]}"
      # 先声明再赋值，避免 local 吞掉 ssh 的退出码（SC2155）
      result=$(ssh -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10 -p "$p" "$a" "${run_cmds[$j]}" < /dev/null 2>&1)
      rc=$?
      if [[ $rc -eq 0 ]]; then
        if [[ -n "$result" ]]; then
          while IFS= read -r line; do msg "      $line"; done <<< "$result"
        else
          msg "      ${F_GREEN}完成${F_RESET}"
        fi
      else
        msg "      ${F_RED}执行失败${F_RESET}"
        [[ -n "$result" ]] && msg "      $result"
        node_fail=1
      fi
    done
    if [[ $node_fail -eq 0 ]]; then
      msg "    ${F_GREEN}$n: 全部完成${F_RESET}"
      ok=$((ok+1))
    else
      msg "    ${F_RED}$n: 存在失败任务${F_RESET}"
      fail=$((fail+1))
    fi
  done <<< "$CLUSTER_SNAPSHOT"

  msg "————————————————————————————————"
  msg "  汇总: ${F_GREEN}成功 $ok${F_RESET} / ${F_RED}失败 $fail${F_RESET} （共 $node_total 个节点）"
  _log_write "集群预置任务 [${run_names[*]}] 执行完成: 成功 $ok / 失败 $fail"
  pause
  [[ $fail -eq 0 ]]
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
  msg "  ${F_GREEN}5${F_RESET}) 管理已部署服务端"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择: " game_choice

  case "$game_choice" in
    1) _deploy_minecraft_java ;;
    2) _deploy_minecraft_bedrock ;;
    3) _deploy_terraria ;;
    4) _deploy_palworld ;;
    5) cluster_game_manage ;;
    0) return ;;
  esac
}

_deploy_minecraft_java() {
  local app_dir="/opt/games/minecraft-java"
  mkdir -p "$app_dir"

  # RCON 密码随机生成（旧版硬编码 "fusionbox"）
  local rcon_pass
  rcon_pass="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

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
      RCON_PASSWORD: "$rcon_pass"
    volumes:
      - mc_data:/data

volumes:
  mc_data:
MCEOF
  chmod 600 "$app_dir/docker-compose.yml"   # compose 文件含 RCON 密码

  if (cd "$app_dir" && docker compose up -d); then
    msg_ok "Minecraft Java 服务端已部署"
    msg "  端口: 25565"
    msg "  RCON 密码: $rcon_pass （请妥善保存，仅此显示一次）"
    msg "  数据目录: $app_dir"
    _log_write "Minecraft Java 服务端已部署"
  else
    msg_err "部署失败，请执行: cd $app_dir && docker compose logs"
    pause; return 1
  fi
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

  if (cd "$app_dir" && docker compose up -d); then
    msg_ok "Minecraft Bedrock 服务端已部署"
    msg "  端口: 19132/UDP"
    _log_write "Minecraft Bedrock 服务端已部署"
  else
    msg_err "部署失败，请执行: cd $app_dir && docker compose logs"
    pause; return 1
  fi
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

  if (cd "$app_dir" && docker compose up -d); then
    msg_ok "Terraria 服务端已部署"
    msg "  端口: 7777"
    _log_write "Terraria 服务端已部署"
  else
    msg_err "部署失败，请执行: cd $app_dir && docker compose logs"
    pause; return 1
  fi
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

  if (cd "$app_dir" && docker compose up -d); then
    msg_ok "Palworld (幻兽帕鲁) 服务端已部署"
    msg "  端口: 8211/UDP, 27015/UDP"
    _log_write "Palworld 服务端已部署"
  else
    msg_err "部署失败，请执行: cd $app_dir && docker compose logs"
    pause; return 1
  fi
  pause
}

# ---- 游戏服务端管理（针对已部署实例） ----
# 目录名|显示名|数据卷名|容器名  （与上方 _deploy_* 保持一一对应）
CLUSTER_GAMES=(
  "minecraft-java|Minecraft Java|mc_data|minecraft-java"
  "minecraft-bedrock|Minecraft Bedrock|mcbe_data|minecraft-bedrock"
  "terraria|Terraria|terraria_data|terraria"
  "palworld|Palworld (幻兽帕鲁)|palworld_data|palworld"
)
CLUSTER_GAME_BACKUP_DIR="/root/game-backups"

cluster_game_manage() {
  _require_root
  msg_title "已部署游戏服务端管理"
  msg ""

  if ! command -v docker >/dev/null 2>&1; then
    msg_err "未检测到 Docker，无法管理游戏服务端"
    pause; return
  fi

  # 自动探测已部署服务端
  local entry key rest gname gvol gcont app_dir j
  local -a d_keys=() d_names=() d_vols=() d_conts=()
  for entry in "${CLUSTER_GAMES[@]}"; do
    key="${entry%%|*}"; rest="${entry#*|}"
    gname="${rest%%|*}"; rest="${rest#*|}"
    gvol="${rest%%|*}"; gcont="${rest##*|}"
    app_dir="/opt/games/$key"
    if [[ -f "$app_dir/docker-compose.yml" ]]; then
      d_keys+=("$key"); d_names+=("$gname"); d_vols+=("$gvol"); d_conts+=("$gcont")
    fi
  done

  if [[ ${#d_keys[@]} -eq 0 ]]; then
    msg_warn "未检测到已部署的服务端（未找到 /opt/games/<游戏>/docker-compose.yml）"
    msg "  请先在「游戏服务端」菜单中完成部署"
    pause; return
  fi

  local st gsel
  msg "  检测到以下已部署服务端:"
  for j in "${!d_keys[@]}"; do
    st="${F_RED}已停止${F_RESET}"
    if [[ -n "$(docker ps --filter "name=${d_conts[$j]}" --format '{{.Names}}' 2>/dev/null)" ]]; then
      st="${F_GREEN}运行中${F_RESET}"
    fi
    msg "  ${F_GREEN}$((j+1))${F_RESET}) ${d_names[$j]} - $st  ${F_CYAN}(${d_keys[$j]})${F_RESET}"
  done
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择要管理的服务端: " gsel || { msg ""; return; }
  [[ "$gsel" == "0" || -z "$gsel" ]] && return
  if ! [[ "$gsel" =~ ^[0-9]+$ ]] || [[ "$gsel" -lt 1 || "$gsel" -gt ${#d_keys[@]} ]]; then
    msg_err "无效选择"
    pause; return
  fi

  j=$((gsel-1))
  _game_manage_menu "${d_keys[$j]}" "${d_names[$j]}" "${d_vols[$j]}"
  pause
}

_game_manage_menu() {
  local key="$1" gname="$2" gvol="$3"
  local app_dir="/opt/games/$key"
  local op out line

  while true; do
    msg ""
    msg_title "$gname 服务端管理"
    msg "  1) 查看运行状态"
    msg "  2) 启动服务端"
    msg "  3) 停止服务端"
    msg "  4) 重启服务端"
    msg "  5) 查看最近日志 (50 行)"
    msg "  6) 备份存档"
    msg "  7) 恢复存档"
    msg "  8) 修改常用配置"
    msg "  9) 卸载服务端"
    msg "  ${F_GREEN}0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-9]: " op || { msg ""; return; }

    case "$op" in
      1)
        msg ""
        out=$(cd "$app_dir" && docker compose ps 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "    ${F_YELLOW}无输出（容器可能尚未创建）${F_RESET}"
        fi
        ;;
      2)
        if (cd "$app_dir" && docker compose up -d); then
          msg_ok "$gname 已启动"
          _log_write "游戏服务端已启动: $key"
        else
          msg_err "启动失败，请执行: cd $app_dir && docker compose logs"
        fi
        ;;
      3)
        confirm "停止 $gname 将断开所有在线玩家，确认？" || { msg_info "已取消"; continue; }
        if (cd "$app_dir" && docker compose stop); then
          msg_ok "$gname 已停止"
          _log_write "游戏服务端已停止: $key"
        else
          msg_err "停止失败"
        fi
        ;;
      4)
        confirm "重启 $gname 将断开所有在线玩家，确认？" || { msg_info "已取消"; continue; }
        if (cd "$app_dir" && docker compose restart); then
          msg_ok "$gname 已重启"
        else
          msg_err "重启失败"
        fi
        ;;
      5)
        msg ""
        out=$(cd "$app_dir" && docker compose logs --tail 50 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "    暂无日志"
        fi
        ;;
      6) _game_backup "$key" "$gvol" ;;
      7) _game_restore "$key" "$gvol" ;;
      8) _game_config "$key" ;;
      9) _game_uninstall "$key" "$gname" "$app_dir" "$gvol" && return ;;
      0) return ;;
    esac
  done
}

_game_ensure_alpine() {
  docker image inspect alpine >/dev/null 2>&1 && return 0
  msg_info "本地未找到 alpine 镜像，正在拉取..."
  if docker pull alpine >/dev/null 2>&1; then
    msg_ok "alpine 镜像已就绪"
    return 0
  fi
  msg_err "alpine 镜像拉取失败，无法执行备份/恢复"
  return 1
}

# Resolve the actual Compose volume name, including project prefixes and explicit names.
_game_resolve_volume() {
  local key="$1" logical="$2" actual config
  [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  command -v python3 >/dev/null || { msg_err "需要 python3 解析 Compose 配置" >&2; return 1; }
  config=$(cd "/opt/games/$key" && docker compose config --format json) || return 1
  actual=$(printf '%s' "$config" | python3 -c 'import json,sys; c=json.load(sys.stdin); print(c.get("volumes",{}).get(sys.argv[1],{}).get("name", ""))' "$logical") || return 1
  [[ -n "$actual" ]] || { msg_err "无法确定真实数据卷，拒绝创建新卷" >&2; return 1; }
  docker volume inspect "$actual" >/dev/null 2>&1 || return 1
  printf '%s\n' "$actual"
}

_game_backup() {
  local key="$1" gvol="$2"
  local backup_dir="$CLUSTER_GAME_BACKUP_DIR"
  local ts file size

  if ! mkdir -p "$backup_dir"; then
    msg_err "无法创建备份目录 $backup_dir"
    return 1
  fi
  gvol=$(_game_resolve_volume "$key" "$gvol") || return 1
  _game_ensure_alpine || return 1

  # 先声明再赋值，避免 local 吞掉退出码（SC2155）
  ts=$(date +%Y%m%d-%H%M%S)
  file="$key-$ts.tar.gz"
  msg_info "正在备份数据卷 $gvol → $backup_dir/$file ..."
  if docker run --rm -v "$gvol":/data -v "$backup_dir":/backup alpine tar czf "/backup/$file" -C /data .; then
    size=$(du -h "$backup_dir/$file" 2>/dev/null | cut -f1)
    msg_ok "备份完成: $backup_dir/$file (${size:-大小未知})"
    _log_write "游戏服务端存档备份: $key → $file"
  else
    msg_err "备份失败"
    rm -f "$backup_dir/$file"   # 清理可能残留的半个包
    return 1
  fi
}

_game_restore() {
  local key="$1" gvol="$2"
  local backup_dir="$CLUSTER_GAME_BACKUP_DIR"
  local -a files=()
  local f base rsel j

  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(ls -1t "$backup_dir/$key"-*.tar.gz 2>/dev/null)

  if [[ ${#files[@]} -eq 0 ]]; then
    msg_warn "未找到备份文件（$backup_dir/$key-*.tar.gz），请先执行备份"
    return 0
  fi

  msg ""
  msg "  可用备份（新→旧）:"
  for j in "${!files[@]}"; do
    msg "  ${F_GREEN}$((j+1))${F_RESET}) $(basename "${files[$j]}")  ${F_CYAN}($(du -h "${files[$j]}" 2>/dev/null | cut -f1))${F_RESET}"
  done
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择要恢复的备份: " rsel
  [[ "$rsel" == "0" || -z "$rsel" ]] && return 0
  if ! [[ "$rsel" =~ ^[0-9]+$ ]] || [[ "$rsel" -lt 1 || "$rsel" -gt ${#files[@]} ]]; then
    msg_err "无效序号"
    return 0
  fi

  f="${files[$((rsel-1))]}"
  base=$(basename "$f")
  msg_warn "恢复将清空数据卷 $gvol 的现有内容，再解压 $base"
  confirm "确认恢复存档？" || { msg_info "已取消"; return 0; }
  _game_ensure_alpine || return 1

  gvol=$(_game_resolve_volume "$key" "$gvol") || return 1
  # Validate all members and decompress fully before stopping services or touching data.
  python3 - "$f" << 'PY'
import pathlib, sys, tarfile
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsafe archive member: ' + member.name)
        if member.isfile():
            with archive.extractfile(member) as stream:
                while stream.read(1024 * 1024): pass
PY
  [[ $? -eq 0 ]] || { msg_err "归档校验失败，未修改数据"; return 1; }
  local app_dir="/opt/games/$key" running safety rc=0
  running=$(cd "$app_dir" && docker compose ps --status running -q) || return 1
  (cd "$app_dir" && docker compose stop) || return 1
  safety="$key-before-restore-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data,readonly" -v "$backup_dir":/backup alpine tar czf "/backup/$safety" -C /data .; then
    msg_err "现状备份失败，取消恢复"
    [[ -z "$running" ]] || docker start $running >/dev/null
    return 1
  fi
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$base"; then
    rc=1
    msg_err "恢复失败，正在还原现状备份: $safety"
    docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$safety" || {
      msg_err "回滚失败，服务保持停止，请使用 $safety 手动恢复"; return 1;
    }
  fi
  if [[ -n "$running" ]]; then docker start $running >/dev/null || return 1; fi
  [[ "$rc" -eq 0 ]] && msg_ok "存档已恢复，现状备份保留: $safety"
  return "$rc"
}

_game_config() {
  local key="$1"
  local app_dir="/opt/games/$key"
  local compose="$app_dir/docker-compose.yml"

  if [[ ! -f "$compose" ]]; then
    msg_err "未找到配置文件: $compose"
    return 1
  fi

  # 改前留副本便于回滚
  cp -f "$compose" "$compose.bak" 2>/dev/null || true

  local line new_mem new_pl changed=0
  case "$key" in
    minecraft-java)
      msg_info "当前配置（原文件已备份为 docker-compose.yml.bak）:"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*(MEMORY|MAX_PLAYERS):' "$compose" 2>/dev/null)
      read -p "内存 MEMORY（如 2G / 4G / 512M，回车跳过）: " new_mem
      read -p "最大玩家数 MAX_PLAYERS（数字，回车跳过）: " new_pl
      if [[ -n "$new_mem" ]]; then
        if [[ "$new_mem" =~ ^[0-9]+[GgMm]$ ]]; then
          sed -i -E "s|^([[:space:]]*MEMORY:[[:space:]]*).*|\1\"$new_mem\"|" "$compose"
          msg_ok "MEMORY 已更新为 $new_mem"
          changed=1
        else
          msg_err "内存格式无效（示例: 2G / 512M）"
        fi
      fi
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*MAX_PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "MAX_PLAYERS 已更新为 $new_pl"
          changed=1
        else
          msg_err "玩家数必须为数字"
        fi
      fi
      ;;
    palworld)
      msg_info "当前配置（原文件已备份为 docker-compose.yml.bak）:"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*PLAYERS:' "$compose" 2>/dev/null)
      read -p "最大玩家数 PLAYERS（数字，回车跳过）: " new_pl
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "PLAYERS 已更新为 $new_pl"
          changed=1
        else
          msg_err "玩家数必须为数字"
        fi
      fi
      ;;
    *)
      msg_info "该游戏暂不支持自动修改配置，请手动编辑: $compose"
      msg "  修改后执行: cd $app_dir && docker compose up -d"
      return 0
      ;;
  esac

  if [[ $changed -eq 1 ]]; then
    msg_info "配置修改需重启服务端生效: cd $app_dir && docker compose up -d"
    _log_write "游戏服务端配置已修改: $key"
  else
    msg "  未做任何修改"
  fi
}

_game_uninstall() {
  local key="$1" gname="$2" app_dir="$3" gvol="$4"

  # 目录必须位于 /opt/games 下，避免误删
  if [[ "$app_dir" != /opt/games/* ]]; then
    msg_err "安装目录异常，拒绝卸载: $app_dir"
    return 1
  fi

  msg_warn "即将停止并删除 $gname 服务端，并删除目录 $app_dir"
  msg_warn "数据卷 $gvol 会保留，存档不会被删除"
  confirm "确认卸载 $gname 服务端？" || { msg_info "已取消"; return 1; }
  read -p "危险操作，请输入大写 YES 二次确认: " uninstall_yes
  [[ "$uninstall_yes" == "YES" ]] || { msg_info "已取消卸载"; return 1; }

  msg_info "正在停止并移除服务端..."
  if (cd "$app_dir" && docker compose down); then
    msg_ok "容器已停止并移除"
  else
    msg_err "docker compose down 失败，保留安装目录"
    return 1
  fi
  rm -rf "$app_dir"
  msg_ok "$gname 服务端已卸载"
  msg_info "数据卷 $gvol 已保留，如需彻底清理存档请执行: docker volume rm $gvol"
  _log_write "游戏服务端已卸载: $key（数据卷 $gvol 保留）"
  return 0
}

# ---- Oracle Cloud scripts ----
cluster_oracle() {
  if [[ $# -gt 0 ]]; then
    case "${1:-}" in
      detect|status|help)
        python3 -B "$FUSION_SRC/lib/oracle_tools.py" "$@"
        return $?
        ;;
      install|enable|disable|uninstall)
        msg_err "受管 lookbusy 保活尚未启用：固定镜像 digest 和 Linux 隔离验收完成前拒绝创建负载"
        return 2
        ;;
      *)
        msg_err "未知 Oracle 操作: $1"
        msg "用法: fusionbox cluster oracle detect [--metadata] | status | help"
        return 2
        ;;
    esac
  fi

  _require_root
  msg_title "Oracle Cloud 只读识别与保活状态"
  msg ""
  msg_warn "受管 lookbusy 负载尚未启用；旧 oracle-keepalive 只报告，不自动接管或删除"
  msg ""
  msg "  1) 本机 OCI 证据识别"
  msg "  2) OCI 识别（一次有界 metadata 只读探测）"
  msg "  3) 查看受管/旧实现状态"
  msg "  0) 返回"
  read -r -p "请选择: " oc_choice || return
  case "$oc_choice" in
    1) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect ;;
    2) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect --metadata ;;
    3) python3 -B "$FUSION_SRC/lib/oracle_tools.py" status ;;
    0) return 0 ;;
    *) msg_err "无效选择"; return 2 ;;
  esac
  pause

}

# ---- k 命令快捷方式 ----# ---- SSH 出站收藏 (G15)：常用 ssh 目标保存与直连 ----
_CLUSTER_SSHOUT_FILE="/etc/fusionbox/ssh_out.conf"

cluster_sshout() {
  _require_root
  local action="${1:-list}"; shift || true
  local file="$_CLUSTER_SSHOUT_FILE"

  case "$action" in
    list)
      [[ -s "$file" ]] || { msg "  无 SSH 收藏（cluster sshout add 添加）"; return 0; }
      msg "  ${F_BOLD}SSH 收藏:${F_RESET}"
      awk -F'|' '{printf "    %s -> %s:%s\n", $1, $2, $3}' "$file"
      ;;
    add)
      local name="${1:-}" target="${2:-}" port="${3:-22}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "名称无效（字母/数字/._-，≤32）: $name"; return 1; }
      [[ "$target" =~ ^[a-zA-Z0-9._@-]+$ ]] || { msg_err "目标格式无效（应为 user@host，不含空格/特殊字符）: $target"; return 1; }
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "端口无效: $port"; return 1; }
      grep -q "^$name|" "$file" 2>/dev/null && { msg_err "名称已存在: $name"; return 1; }
      mkdir -p "$(dirname "$file")" && touch "$file" && chmod 600 "$file"
      printf '%s|%s|%s
' "$name" "$target" "$port" >> "$file"
      msg_ok "已收藏: $name -> $target:$port"
      ;;
    rm)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "名称无效"; return 1; }
      [[ -f "$file" ]] && grep -q "^$name|" "$file" || { msg_err "收藏不存在: $name"; return 1; }
      sed -i "/^$name|/d" "$file"
      msg_ok "已删除收藏: $name"
      ;;
    connect)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "名称无效"; return 1; }
      local row; row=$(grep "^$name|" "$file" 2>/dev/null | tail -1)
      [[ -n "$row" ]] || { msg_err "收藏不存在: $name"; return 1; }
      local target="${row#*|}"; target="${target%%|*}"
      local port="${row##*|}"
      msg_info "连接 $name ($target:$port)..."
      ssh -t -p "$port" "$target"
      ;;
    *)
      msg_err "未知子命令: $action（可用: list/add/rm/connect）"; return 2 ;;
  esac
}

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
        # 别名会写入被 source 的 shell 文件，必须校验命名合法性
        if [[ ! "$alias_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
          msg_err "快捷名称仅允许字母/数字/下划线，且以字母开头"
        else
          echo "alias $alias_name='$alias_cmd'" >> "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "已添加: $alias_name → $alias_cmd"
        fi
      fi
      ;;
    2)
      nl -ba "$kcmd_file" | grep "alias"
      read -p "输入要删除的行号: " del_line
      if [[ -n "$del_line" ]]; then
        if ! [[ "$del_line" =~ ^[0-9]+$ ]] || [[ "$del_line" -lt 1 || "$del_line" -gt $(wc -l < "$kcmd_file") ]]; then
          msg_err "无效行号（范围 1-$(wc -l < "$kcmd_file")）"
        elif confirm "确认删除第 $del_line 行？"; then
          sed -i "${del_line}d" "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "已删除"
        fi
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
  msg "  fusionbox cluster export /absolute/nodes.json  私有 JSON；拒绝覆盖"
  msg "  fusionbox cluster import /absolute/nodes.json --dry-run  预览（默认）"
  msg "  fusionbox cluster import /absolute/nodes.json --confirm  合并；冲突拒绝"
  msg "  fusionbox cluster add            添加集群节点"
  msg "  fusionbox cluster remove         删除集群节点"
  msg "  fusionbox cluster list           列出集群节点"
  msg "  fusionbox cluster trust <节点>   核对指纹后固定 known_hosts"
  msg "  fusionbox cluster connect <节点> [--password|--password-fd N]"
  msg "  fusionbox cluster node-exec <节点> [密码选项] -- <命令> [参数...]"
  msg "  fusionbox cluster migrate-key <节点> [密码选项] [--public-key 路径]"
  msg "  fusionbox cluster exec <cmd>     批量执行命令（仅密钥）"
  msg "  fusionbox cluster task           预置批量任务（状态/更新/清理/BBR 等）"
  msg "  fusionbox cluster archive --help  校验归档 push/pull/status（密钥、严格 known_hosts）"
  msg "  fusionbox cluster sync           同步文件到集群"
  msg ""
  msg "  ${F_BOLD}[游戏服务端]${F_RESET}"
  msg "  fusionbox cluster game           游戏服务端部署"
  msg "    - Minecraft Java/Bedrock"
  msg "    - Terraria"
  msg "    - Palworld (幻兽帕鲁)"
  msg "  fusionbox cluster game-manage    管理已部署服务端（启停/日志/备份/恢复/卸载）"
  msg ""
  msg "  ${F_BOLD}[Oracle Cloud]${F_RESET}"
  msg "  fusionbox cluster oracle detect [--metadata]  OCI 只读识别"
  msg "  fusionbox cluster oracle status               受管/旧保活状态"
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
    msg "  ${F_GREEN}5${F_RESET}) Oracle Cloud 只读识别/状态"
    msg "  ${F_GREEN}6${F_RESET}) k 命令快捷方式"
    msg "  ${F_GREEN}7${F_RESET}) 预置批量任务"
    msg "  ${F_GREEN}8${F_RESET}) 管理已部署游戏服务端"
    msg "  ${F_GREEN}9${F_RESET}) 校验归档传输命令帮助（push/pull/status）"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-9]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1)
        msg "  1) 添加节点  2) 删除节点  3) 列出节点  4) 导出  5) 导入"
        read -p "请选择: " node_choice || { msg ""; break; }
        case "$node_choice" in
          1) cluster_add ;;
          2) cluster_remove ;;
          3) cluster_list ;;
          4) read -r -p "导出文件路径（必须不存在）: " transfer_file || return 1
             cluster_transfer export "$transfer_file"; pause ;;
          5) read -r -p "导入 JSON 路径（0600）: " transfer_file || return 1
             if cluster_transfer import "$transfer_file" --dry-run; then
               if confirm "确认合并？同名节点拒绝，原节点保留"; then
                 cluster_transfer import "$transfer_file" --confirm
               fi
             fi
             pause ;;
        esac
        ;;
      2) cluster_exec ;;
      3) cluster_sync ;;
      4) cluster_game ;;
      5) cluster_oracle ;;
      6) cluster_kcmd ;;
      7) cluster_task ;;
      8) cluster_game_manage ;;
      9) cluster_archive --help; pause ;;
      0) break ;;
    esac
  done
}
