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
    alias|cheatsheet|ref) cluster_k_alias ;;
    sshout|out)       cluster_sshout "$@" ;;
    menu|main)        cluster_menu ;;
    help|h)           cluster_help ;;
    *)                _module_unknown_cmd "cluster" "$cmd" ;;
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
  read -r -p "$(L MSG_CL_0001)" node_name || return 1
  read -r -p "$(L MSG_CL_0002)" ssh_addr || return 1
  read -r -p "$(L MSG_CL_0003)" ssh_port || return 1
  [[ "$ssh_addr" == *@* ]] || { msg_err "$(L MSG_CL_0004)"; return 1; }
  _cluster_nodes add "$node_name" "${ssh_addr%%@*}" "${ssh_addr#*@}" "${ssh_port:-22}" || return 1
  msg_ok "$(L MSG_CL_0005)"
  pause
}

cluster_remove() {
  _require_root
  local node_name
  _cluster_nodes list || return 1
  read -r -p "$(L MSG_CL_0006)" node_name || return 1
  confirm "$(L MSG_CL_0007 "$node_name")" || return 1
  _cluster_nodes remove "$node_name" || return 1
  msg_ok "$(L MSG_CL_0008)"
  pause
}

cluster_list() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0009)"
  msg ""
  if [[ -n "$CLUSTER_SNAPSHOT" ]]; then
    local i=1
    while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
      local status="$(L MSG_CL_0010 "${F_RED}" "${F_RESET}")"
      if ssh -n -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=3 -p "$port" "$addr" "echo ok" &>/dev/null; then
        status="$(L MSG_CL_0011 "${F_GREEN}" "${F_RESET}")"
      fi
      msg "  $i) $name ($addr:$port) - $status"
      i=$((i+1))
    done <<< "$CLUSTER_SNAPSHOT"
  else
    msg "$(L MSG_CL_0012)"
  fi
  pause
}

cluster_exec() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0013)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0014)"
    pause; return
  fi

  msg "$(L MSG_CL_0015)"
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg "    $name ($addr:$port)"
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  read -p "$(L MSG_CL_0016)" cmd_to_run
  if [[ -z "$cmd_to_run" ]]; then
    pause; return
  fi

  confirm "$(L MSG_CL_0017)" || { pause; return; }

  msg ""
  msg_info "$(L MSG_CL_0018 "$cmd_to_run")"
  msg "$(L MSG_CL_0019)"
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
      msg "$(L MSG_CL_0020 "${F_RED}" "${F_RESET}")"
    fi
  done <<< "$CLUSTER_SNAPSHOT"
  msg "$(L MSG_CL_0019)"
  _log_write "$(L MSG_CL_0021 "$cmd_to_run")"
  pause
}

cluster_sync() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0022)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0023)"
    pause; return
  fi

  read -p "$(L MSG_CL_0024)" local_path
  read -p "$(L MSG_CL_0025)" remote_path
  if [[ ! -e "$local_path" ]]; then
    msg_err "$(L MSG_CL_0026)"
    pause; return
  fi

  msg ""
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg_info "$(L MSG_CL_0027 "$name")"
    local destination="$addr"
    if [[ "${addr#*@}" == *:* ]]; then destination="${addr%%@*}@[${addr#*@}]"; fi
    scp -F /dev/null -r -P "$port" -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10 -- "$local_path" "$destination:$remote_path" 2>/dev/null && \
      msg_ok "$(L MSG_CL_0028 "$name")" || \
      msg_err "$(L MSG_CL_0029 "$name")"
  done <<< "$CLUSTER_SNAPSHOT"
  _log_write "$(L MSG_CL_0030 "$local_path" "$remote_path")"
  pause
}

# ---- 预置批量任务 ----
# 数据表: 名称|说明|远端命令
# 命令内不包含 $ 与反引号，故可安全存放在双引号数组中；远端由目标机 shell 解析
CLUSTER_TASKS=(
  "$(L MSG_CL_0031)"
  "$(L MSG_CL_0032)"
  "$(L MSG_CL_0033)"
  "$(L MSG_CL_0034)"
  "$(L MSG_CL_0035)"
  "$(L MSG_CL_0036)"
  "$(L MSG_CL_0037)"
  "$(L MSG_CL_0039)"$(L MSG_CL_0038)"; else test ! -e /swapfile && test ! -L /swapfile && fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && (grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab); fi"
  "$(L MSG_CL_0040)"
)

cluster_task() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0041)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0042)"
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
  msg "$(L MSG_CL_0043 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0044)" task_choice
  [[ -z "$task_choice" ]] && { pause; return; }

  # 解析选择（任务序号 / 多选 / c 自定义）
  local -a run_cmds=() run_names=()
  for token in $task_choice; do
    if [[ "$token" =~ ^[Cc]$ ]]; then
      read -p "$(L MSG_CL_0045)" tcmd
      if [[ -n "$tcmd" ]]; then
        run_cmds+=("$tcmd")
        run_names+=("$(L MSG_CL_0046)")
      fi
    elif [[ "$token" =~ ^[0-9]+$ ]] && [[ "$token" -ge 1 && "$token" -le "${#CLUSTER_TASKS[@]}" ]]; then
      entry="${CLUSTER_TASKS[$((token-1))]}"
      name="${entry%%|*}"
      tcmd="${entry#*|}"; tcmd="${tcmd#*|}"
      run_cmds+=("$tcmd")
      run_names+=("$name")
    else
      msg_warn "$(L MSG_CL_0047 "$token")"
    fi
  done

  if [[ ${#run_cmds[@]} -eq 0 ]]; then
    msg_err "$(L MSG_CL_0048)"
    pause; return
  fi

  # 显示目标节点清单
  msg ""
  msg "$(L MSG_CL_0049 "${F_BOLD}" "${F_RESET}")"
  local node_total=0 n a p
  while IFS='|' read -r n a p; do
    [[ -z "$n" ]] && continue
    msg "    $n ($a:$p)"
    node_total=$((node_total+1))
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  msg "$(L MSG_CL_0050 "${run_names[*]}")"
  confirm "$(L MSG_CL_0051 "$node_total")" || { pause; return; }

  # reboot 属破坏性操作：额外二次确认（输入大写 YES）
  local j need_reboot=0
  for j in "${!run_names[@]}"; do
    [[ "${run_names[$j]}" == "reboot" ]] && need_reboot=1
  done
  if [[ $need_reboot -eq 1 ]]; then
    msg_warn "$(L MSG_CL_0052)"
    read -p "$(L MSG_CL_0053)" reboot_yes
    [[ "$reboot_yes" == "YES" ]] || { msg_info "$(L MSG_CL_0054)"; pause; return; }
    msg_info "$(L MSG_CL_0055)"
  fi

  # 逐节点执行：单个节点内依次跑完所选任务
  local ok=0 fail=0 result rc line node_fail=0
  msg ""
  msg "$(L MSG_CL_0019)"
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
          msg "$(L MSG_CL_0056 "${F_GREEN}" "${F_RESET}")"
        fi
      else
        msg "$(L MSG_CL_0057 "${F_RED}" "${F_RESET}")"
        [[ -n "$result" ]] && msg "      $result"
        node_fail=1
      fi
    done
    if [[ $node_fail -eq 0 ]]; then
      msg "$(L MSG_CL_0058 "${F_GREEN}" "$n" "${F_RESET}")"
      ok=$((ok+1))
    else
      msg "$(L MSG_CL_0059 "${F_RED}" "$n" "${F_RESET}")"
      fail=$((fail+1))
    fi
  done <<< "$CLUSTER_SNAPSHOT"

  msg "$(L MSG_CL_0019)"
  msg "$(L MSG_CL_0060 "${F_GREEN}" "$ok" "${F_RESET}" "${F_RED}" "$fail" "${F_RESET}" "$node_total")"
  _log_write "$(L MSG_CL_0061 "${run_names[*]}" "$ok" "$fail")"
  pause
  [[ $fail -eq 0 ]]
}

# ---- 游戏服务端 ----
cluster_game() {
  _require_root
  msg_title "$(L MSG_CL_0062)"
  msg ""
  msg "$(L MSG_CL_0063 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0064 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0065 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0066 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0067 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0068 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0069)" game_choice

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

  msg_info "$(L MSG_CL_0070)"
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
    msg_ok "$(L MSG_CL_0071)"
    msg "$(L MSG_CL_0072)"
    msg "$(L MSG_CL_0073 "$rcon_pass")"
    msg "$(L MSG_CL_0074 "$app_dir")"
    _log_write "$(L MSG_CL_0071)"
  else
    msg_err "$(L MSG_CL_0075 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0076)"
    msg "$(L MSG_CL_0077)"
    _log_write "$(L MSG_CL_0076)"
  else
    msg_err "$(L MSG_CL_0075 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0078)"
    msg "$(L MSG_CL_0079)"
    _log_write "$(L MSG_CL_0078)"
  else
    msg_err "$(L MSG_CL_0075 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0080)"
    msg "$(L MSG_CL_0081)"
    _log_write "$(L MSG_CL_0082)"
  else
    msg_err "$(L MSG_CL_0075 "$app_dir")"
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
  "$(L MSG_CL_0083)"
)
CLUSTER_GAME_BACKUP_DIR="/root/game-backups"

cluster_game_manage() {
  _require_root
  msg_title "$(L MSG_CL_0084)"
  msg ""

  if ! command -v docker >/dev/null 2>&1; then
    msg_err "$(L MSG_CL_0085)"
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
    msg_warn "$(L MSG_CL_0086)"
    msg "$(L MSG_CL_0087)"
    pause; return
  fi

  local st gsel
  msg "$(L MSG_CL_0088)"
  for j in "${!d_keys[@]}"; do
    st="$(L MSG_CL_0089 "${F_RED}" "${F_RESET}")"
    if [[ -n "$(docker ps --filter "name=${d_conts[$j]}" --format '{{.Names}}' 2>/dev/null)" ]]; then
      st="$(L MSG_CL_0090 "${F_GREEN}" "${F_RESET}")"
    fi
    msg "  ${F_GREEN}$((j+1))${F_RESET}) ${d_names[$j]} - $st  ${F_CYAN}(${d_keys[$j]})${F_RESET}"
  done
  msg "$(L MSG_CL_0068 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0091)" gsel || { msg ""; return; }
  [[ "$gsel" == "0" || -z "$gsel" ]] && return
  if ! [[ "$gsel" =~ ^[0-9]+$ ]] || [[ "$gsel" -lt 1 || "$gsel" -gt ${#d_keys[@]} ]]; then
    msg_err "$(L MSG_CL_0092)"
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
    msg_title "$(L MSG_CL_0093 "$gname")"
    msg "$(L MSG_CL_0094)"
    msg "$(L MSG_CL_0095)"
    msg "$(L MSG_CL_0096)"
    msg "$(L MSG_CL_0097)"
    msg "$(L MSG_CL_0098)"
    msg "$(L MSG_CL_0099)"
    msg "$(L MSG_CL_0100)"
    msg "$(L MSG_CL_0101)"
    msg "$(L MSG_CL_0102)"
    msg "$(L MSG_CL_0068 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_CL_0103)" op || { msg ""; return; }

    case "$op" in
      1)
        msg ""
        out=$(cd "$app_dir" && docker compose ps 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "$(L MSG_CL_0104 "${F_YELLOW}" "${F_RESET}")"
        fi
        ;;
      2)
        if (cd "$app_dir" && docker compose up -d); then
          msg_ok "$(L MSG_CL_0105 "$gname")"
          _log_write "$(L MSG_CL_0106 "$key")"
        else
          msg_err "$(L MSG_CL_0107 "$app_dir")"
        fi
        ;;
      3)
        confirm "$(L MSG_CL_0108 "$gname")" || { msg_info "$(L MSG_CL_0109)"; continue; }
        if (cd "$app_dir" && docker compose stop); then
          msg_ok "$(L MSG_CL_0110 "$gname")"
          _log_write "$(L MSG_CL_0111 "$key")"
        else
          msg_err "$(L MSG_CL_0112)"
        fi
        ;;
      4)
        confirm "$(L MSG_CL_0113 "$gname")" || { msg_info "$(L MSG_CL_0109)"; continue; }
        if (cd "$app_dir" && docker compose restart); then
          msg_ok "$(L MSG_CL_0114 "$gname")"
        else
          msg_err "$(L MSG_CL_0115)"
        fi
        ;;
      5)
        msg ""
        out=$(cd "$app_dir" && docker compose logs --tail 50 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "$(L MSG_CL_0116)"
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
  msg_info "$(L MSG_CL_0117)"
  if docker pull alpine >/dev/null 2>&1; then
    msg_ok "$(L MSG_CL_0118)"
    return 0
  fi
  msg_err "$(L MSG_CL_0119)"
  return 1
}

# Resolve the actual Compose volume name, including project prefixes and explicit names.
_game_resolve_volume() {
  local key="$1" logical="$2" actual config
  [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  command -v python3 >/dev/null || { msg_err "$(L MSG_CL_0120)" >&2; return 1; }
  config=$(cd "/opt/games/$key" && docker compose config --format json) || return 1
  actual=$(printf '%s' "$config" | python3 -c 'import json,sys; c=json.load(sys.stdin); print(c.get("volumes",{}).get(sys.argv[1],{}).get("name", ""))' "$logical") || return 1
  [[ -n "$actual" ]] || { msg_err "$(L MSG_CL_0121)" >&2; return 1; }
  docker volume inspect "$actual" >/dev/null 2>&1 || return 1
  printf '%s\n' "$actual"
}

_game_backup() {
  local key="$1" gvol="$2"
  local backup_dir="$CLUSTER_GAME_BACKUP_DIR"
  local ts file size

  if ! mkdir -p "$backup_dir"; then
    msg_err "$(L MSG_CL_0122 "$backup_dir")"
    return 1
  fi
  gvol=$(_game_resolve_volume "$key" "$gvol") || return 1
  _game_ensure_alpine || return 1

  # 先声明再赋值，避免 local 吞掉退出码（SC2155）
  ts=$(date +%Y%m%d-%H%M%S)
  file="$key-$ts.tar.gz"
  msg_info "$(L MSG_CL_0123 "$gvol" "$backup_dir" "$file")"
  if docker run --rm -v "$gvol":/data -v "$backup_dir":/backup alpine tar czf "/backup/$file" -C /data .; then
    size=$(du -h "$backup_dir/$file" 2>/dev/null | cut -f1)
    msg_ok "$(L MSG_CL_0124 "$backup_dir" "$file" "${size:-大小未知}")"
    _log_write "$(L MSG_CL_0125 "$key" "$file")"
  else
    msg_err "$(L MSG_CL_0126)"
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
    msg_warn "$(L MSG_CL_0127 "$backup_dir" "$key")"
    return 0
  fi

  msg ""
  msg "$(L MSG_CL_0128)"
  for j in "${!files[@]}"; do
    msg "  ${F_GREEN}$((j+1))${F_RESET}) $(basename "${files[$j]}")  ${F_CYAN}($(du -h "${files[$j]}" 2>/dev/null | cut -f1))${F_RESET}"
  done
  msg "$(L MSG_CL_0068 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0129)" rsel
  [[ "$rsel" == "0" || -z "$rsel" ]] && return 0
  if ! [[ "$rsel" =~ ^[0-9]+$ ]] || [[ "$rsel" -lt 1 || "$rsel" -gt ${#files[@]} ]]; then
    msg_err "$(L MSG_CL_0130)"
    return 0
  fi

  f="${files[$((rsel-1))]}"
  base=$(basename "$f")
  msg_warn "$(L MSG_CL_0131 "$gvol" "$base")"
  confirm "$(L MSG_CL_0132)" || { msg_info "$(L MSG_CL_0109)"; return 0; }
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
  [[ $? -eq 0 ]] || { msg_err "$(L MSG_CL_0133)"; return 1; }
  local app_dir="/opt/games/$key" running safety rc=0
  running=$(cd "$app_dir" && docker compose ps --status running -q) || return 1
  (cd "$app_dir" && docker compose stop) || return 1
  safety="$key-before-restore-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data,readonly" -v "$backup_dir":/backup alpine tar czf "/backup/$safety" -C /data .; then
    msg_err "$(L MSG_CL_0134)"
    [[ -z "$running" ]] || docker start $running >/dev/null
    return 1
  fi
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$base"; then
    rc=1
    msg_err "$(L MSG_CL_0135 "$safety")"
    docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$safety" || {
      msg_err "$(L MSG_CL_0136 "$safety")"; return 1;
    }
  fi
  if [[ -n "$running" ]]; then docker start $running >/dev/null || return 1; fi
  [[ "$rc" -eq 0 ]] && msg_ok "$(L MSG_CL_0137 "$safety")"
  return "$rc"
}

_game_config() {
  local key="$1"
  local app_dir="/opt/games/$key"
  local compose="$app_dir/docker-compose.yml"

  if [[ ! -f "$compose" ]]; then
    msg_err "$(L MSG_CL_0138 "$compose")"
    return 1
  fi

  # 改前留副本便于回滚
  cp -f "$compose" "$compose.bak" 2>/dev/null || true

  local line new_mem new_pl changed=0
  case "$key" in
    minecraft-java)
      msg_info "$(L MSG_CL_0139)"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*(MEMORY|MAX_PLAYERS):' "$compose" 2>/dev/null)
      read -p "$(L MSG_CL_0140)" new_mem
      read -p "$(L MSG_CL_0141)" new_pl
      if [[ -n "$new_mem" ]]; then
        if [[ "$new_mem" =~ ^[0-9]+[GgMm]$ ]]; then
          sed -i -E "s|^([[:space:]]*MEMORY:[[:space:]]*).*|\1\"$new_mem\"|" "$compose"
          msg_ok "$(L MSG_CL_0142 "$new_mem")"
          changed=1
        else
          msg_err "$(L MSG_CL_0143)"
        fi
      fi
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*MAX_PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "$(L MSG_CL_0144 "$new_pl")"
          changed=1
        else
          msg_err "$(L MSG_CL_0145)"
        fi
      fi
      ;;
    palworld)
      msg_info "$(L MSG_CL_0139)"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*PLAYERS:' "$compose" 2>/dev/null)
      read -p "$(L MSG_CL_0146)" new_pl
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "$(L MSG_CL_0147 "$new_pl")"
          changed=1
        else
          msg_err "$(L MSG_CL_0145)"
        fi
      fi
      ;;
    *)
      msg_info "$(L MSG_CL_0148 "$compose")"
      msg "$(L MSG_CL_0149 "$app_dir")"
      return 0
      ;;
  esac

  if [[ $changed -eq 1 ]]; then
    msg_info "$(L MSG_CL_0150 "$app_dir")"
    _log_write "$(L MSG_CL_0151 "$key")"
  else
    msg "$(L MSG_CL_0152)"
  fi
}

_game_uninstall() {
  local key="$1" gname="$2" app_dir="$3" gvol="$4"

  # 目录必须位于 /opt/games 下，避免误删
  if [[ "$app_dir" != /opt/games/* ]]; then
    msg_err "$(L MSG_CL_0153 "$app_dir")"
    return 1
  fi

  msg_warn "$(L MSG_CL_0154 "$gname" "$app_dir")"
  msg_warn "$(L MSG_CL_0155 "$gvol")"
  confirm "$(L MSG_CL_0156 "$gname")" || { msg_info "$(L MSG_CL_0109)"; return 1; }
  read -p "$(L MSG_CL_0157)" uninstall_yes
  [[ "$uninstall_yes" == "YES" ]] || { msg_info "$(L MSG_CL_0158)"; return 1; }

  msg_info "$(L MSG_CL_0159)"
  if (cd "$app_dir" && docker compose down); then
    msg_ok "$(L MSG_CL_0160)"
  else
    msg_err "$(L MSG_CL_0161)"
    return 1
  fi
  rm -rf "$app_dir"
  msg_ok "$(L MSG_CL_0162 "$gname")"
  msg_info "$(L MSG_CL_0163 "$gvol" "$gvol")"
  _log_write "$(L MSG_CL_0164 "$key" "$gvol")"
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
        msg_err "$(L MSG_CL_0165)"
        return 2
        ;;
      *)
        msg_err "$(L MSG_CL_0166 "$1")"
        msg "$(L MSG_CL_0167)"
        return 2
        ;;
    esac
  fi

  _require_root
  msg_title "$(L MSG_CL_0168)"
  msg ""
  msg_warn "$(L MSG_CL_0169)"
  msg ""
  msg "$(L MSG_CL_0170)"
  msg "$(L MSG_CL_0171)"
  msg "$(L MSG_CL_0172)"
  msg "$(L MSG_CL_0173)"
  read -r -p "$(L MSG_CL_0069)" oc_choice || return
  case "$oc_choice" in
    1) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect ;;
    2) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect --metadata ;;
    3) python3 -B "$FUSION_SRC/lib/oracle_tools.py" status ;;
    0) return 0 ;;
    *) msg_err "$(L MSG_CL_0092)"; return 2 ;;
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
      [[ -s "$file" ]] || { msg "$(L MSG_CL_0174)"; return 0; }
      msg "$(L MSG_CL_0175 "${F_BOLD}" "${F_RESET}")"
      awk -F'|' '{printf "    %s -> %s:%s\n", $1, $2, $3}' "$file"
      ;;
    add)
      local name="${1:-}" target="${2:-}" port="${3:-22}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0176 "$name")"; return 1; }
      [[ "$target" =~ ^[a-zA-Z0-9._@-]+$ ]] || { msg_err "$(L MSG_CL_0177 "$target")"; return 1; }
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "$(L MSG_CL_0178 "$port")"; return 1; }
      grep -q "^$name|" "$file" 2>/dev/null && { msg_err "$(L MSG_CL_0179 "$name")"; return 1; }
      mkdir -p "$(dirname "$file")" && touch "$file" && chmod 600 "$file"
      printf '%s|%s|%s
' "$name" "$target" "$port" >> "$file"
      msg_ok "$(L MSG_CL_0180 "$name" "$target" "$port")"
      ;;
    rm)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0181)"; return 1; }
      [[ -f "$file" ]] && grep -q "^$name|" "$file" || { msg_err "$(L MSG_CL_0182 "$name")"; return 1; }
      sed -i "/^$name|/d" "$file"
      msg_ok "$(L MSG_CL_0183 "$name")"
      ;;
    connect)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0181)"; return 1; }
      local row; row=$(grep "^$name|" "$file" 2>/dev/null | tail -1)
      [[ -n "$row" ]] || { msg_err "$(L MSG_CL_0182 "$name")"; return 1; }
      local target="${row#*|}"; target="${target%%|*}"
      local port="${row##*|}"
      msg_info "$(L MSG_CL_0184 "$name" "$target" "$port")"
      ssh -t -p "$port" "$target"
      ;;
    *)
      msg_err "$(L MSG_CL_0185 "$action")"; return 2 ;;
  esac
}

# ---- k 风格中文速查表 (A 档) ----
# A single page that pairs each common command with a one-line human explanation,
# so users do not have to memorise the CLI surface or read the source.
cluster_k_alias() {
  _require_root
  msg_title "$(L MSG_CL_0186)"
  msg ""
  msg "$(L MSG_CL_0187 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0188 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0189 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0190 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0191 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0192 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0193 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0194 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0195 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0196 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0197 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0198 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0199 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0200 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0201 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0202 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0203 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0204 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0205 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0206 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0207 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0208 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0209 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0210 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0211 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0212 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0213 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg_info "$(L MSG_CL_0214)"
  msg ""
}

cluster_kcmd() {
  _require_root
  local kcmd_dir="/etc/fusionbox/kcmd"
  mkdir -p "$kcmd_dir"
  local kcmd_file="$kcmd_dir/aliases.sh"

  msg_title "$(L MSG_CL_0215)"
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

  msg "$(L MSG_CL_0216 "${F_BOLD}" "${F_RESET}")"
  msg ""
  while IFS= read -r line; do
    [[ "$line" == alias* ]] || continue
    local alias_name alias_cmd
    alias_name=$(echo "$line" | sed "s/alias \([^=]*\)=.*/\1/")
    alias_cmd=$(echo "$line" | sed "s/alias [^=]*='\(.*\)'/\1/")
    msg "  ${F_GREEN}$alias_name${F_RESET} → $alias_cmd"
  done < "$kcmd_file"

  msg ""
  msg "$(L MSG_CL_0217)"
  msg "$(L MSG_CL_0218)"
  msg "$(L MSG_CL_0219)"
  msg "$(L MSG_CL_0220)"
  msg "$(L MSG_CL_0173)"
  read -p "$(L MSG_CL_0069)" k_choice

  case "$k_choice" in
    1)
      read -p "$(L MSG_CL_0221)" alias_name
      read -p "$(L MSG_CL_0222)" alias_cmd
      if [[ -n "$alias_name" && -n "$alias_cmd" ]]; then
        # 别名会写入被 source 的 shell 文件，必须校验命名合法性
        if [[ ! "$alias_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
          msg_err "$(L MSG_CL_0223)"
        else
          echo "alias $alias_name='$alias_cmd'" >> "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "$(L MSG_CL_0224 "$alias_name" "$alias_cmd")"
        fi
      fi
      ;;
    2)
      nl -ba "$kcmd_file" | grep "alias"
      read -p "$(L MSG_CL_0225)" del_line
      if [[ -n "$del_line" ]]; then
        if ! [[ "$del_line" =~ ^[0-9]+$ ]] || [[ "$del_line" -lt 1 || "$del_line" -gt $(wc -l < "$kcmd_file") ]]; then
          msg_err "$(L MSG_CL_0226 "$(wc -l < "$kcmd_file")")"
        elif confirm "$(L MSG_CL_0227 "$del_line")"; then
          sed -i "${del_line}d" "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "$(L MSG_CL_0228)"
        fi
      fi
      ;;
    3)
      rm -f "$kcmd_file"
      cluster_kcmd
      ;;
    4)
      source "$kcmd_file" 2>/dev/null
      msg_ok "$(L MSG_CL_0229)"
      ;;
  esac
  pause
}

# ---- Help ----
cluster_help() {
  msg_title "$(L MSG_CL_0230)"
  msg ""
  msg "$(L MSG_CL_0231 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0232)"
  msg "$(L MSG_CL_0233)"
  msg "$(L MSG_CL_0234)"
  msg "$(L MSG_CL_0235)"
  msg "$(L MSG_CL_0236)"
  msg "$(L MSG_CL_0237)"
  msg "$(L MSG_CL_0238)"
  msg "$(L MSG_CL_0239)"
  msg "$(L MSG_CL_0240)"
  msg "$(L MSG_CL_0241)"
  msg "$(L MSG_CL_0242)"
  msg "$(L MSG_CL_0243)"
  msg "$(L MSG_CL_0244)"
  msg "$(L MSG_CL_0245)"
  msg ""
  msg "$(L MSG_CL_0246 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0247)"
  msg "    - Minecraft Java/Bedrock"
  msg "    - Terraria"
  msg "$(L MSG_CL_0248)"
  msg "$(L MSG_CL_0249)"
  msg ""
  msg "  ${F_BOLD}[Oracle Cloud]${F_RESET}"
  msg "$(L MSG_CL_0250)"
  msg "$(L MSG_CL_0251)"
  msg ""
  msg "$(L MSG_CL_0252 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0253)"
  msg "    k=fusionbox  ks=system  kb=bbr  kn=network"
  msg "    kw=web  kp=proxy  kd=docker  km=market"
  msg ""
}

# ---- Interactive Menu ----
cluster_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_CL_0254)"
    msg ""
    msg "$(L MSG_CL_0255 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0256 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0257 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0258 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0259 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0260 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0261 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0262 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0263 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0264 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_CL_0103)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1)
        msg "$(L MSG_CL_0265)"
        read -p "$(L MSG_CL_0069)" node_choice || { msg ""; break; }
        case "$node_choice" in
          1) cluster_add ;;
          2) cluster_remove ;;
          3) cluster_list ;;
          4) read -r -p "$(L MSG_CL_0266)" transfer_file || return 1
             cluster_transfer export "$transfer_file"; pause ;;
          5) read -r -p "$(L MSG_CL_0267)" transfer_file || return 1
             if cluster_transfer import "$transfer_file" --dry-run; then
               if confirm "$(L MSG_CL_0268)"; then
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
