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
  read -r -p "$(L MSG_CL_0269)" node_name || return 1
  read -r -p "$(L MSG_CL_0270)" ssh_addr || return 1
  read -r -p "$(L MSG_CL_0271)" ssh_port || return 1
  [[ "$ssh_addr" == *@* ]] || { msg_err "$(L MSG_CL_0272)"; return 1; }
  _cluster_nodes add "$node_name" "${ssh_addr%%@*}" "${ssh_addr#*@}" "${ssh_port:-22}" || return 1
  msg_ok "$(L MSG_CL_0273)"
  pause
}

cluster_remove() {
  _require_root
  local node_name
  _cluster_nodes list || return 1
  read -r -p "$(L MSG_CL_0274)" node_name || return 1
  confirm "$(L MSG_CL_0275 "$node_name")" || return 1
  _cluster_nodes remove "$node_name" || return 1
  msg_ok "$(L MSG_CL_0276)"
  pause
}

cluster_list() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0277)"
  msg ""
  if [[ -n "$CLUSTER_SNAPSHOT" ]]; then
    local i=1
    while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
      local status="$(L MSG_CL_0278 "${F_RED}" "${F_RESET}")"
      if ssh -n -F /dev/null -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=3 -p "$port" "$addr" "echo ok" &>/dev/null; then
        status="$(L MSG_CL_0279 "${F_GREEN}" "${F_RESET}")"
      fi
      msg "  $i) $name ($addr:$port) - $status"
      i=$((i+1))
    done <<< "$CLUSTER_SNAPSHOT"
  else
    msg "$(L MSG_CL_0280)"
  fi
  pause
}

cluster_exec() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0281)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0282)"
    pause; return
  fi

  msg "$(L MSG_CL_0283)"
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg "    $name ($addr:$port)"
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  read -p "$(L MSG_CL_0284)" cmd_to_run
  if [[ -z "$cmd_to_run" ]]; then
    pause; return
  fi

  confirm "$(L MSG_CL_0285)" || { pause; return; }

  msg ""
  msg_info "$(L MSG_CL_0286 "$cmd_to_run")"
  msg "$(L MSG_CL_0287)"
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
      msg "$(L MSG_CL_0288 "${F_RED}" "${F_RESET}")"
    fi
  done <<< "$CLUSTER_SNAPSHOT"
  msg "$(L MSG_CL_0287)"
  _log_write "$(L MSG_CL_0289 "$cmd_to_run")"
  pause
}

cluster_sync() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0290)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0291)"
    pause; return
  fi

  read -p "$(L MSG_CL_0292)" local_path
  read -p "$(L MSG_CL_0293)" remote_path
  if [[ ! -e "$local_path" ]]; then
    msg_err "$(L MSG_CL_0294)"
    pause; return
  fi

  msg ""
  while IFS='|' read -r name addr port; do
    [[ -n "$name" ]] || continue
    msg_info "$(L MSG_CL_0295 "$name")"
    local destination="$addr"
    if [[ "${addr#*@}" == *:* ]]; then destination="${addr%%@*}@[${addr#*@}]"; fi
    scp -F /dev/null -r -P "$port" -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$CLUSTER_DIR/known_hosts" -o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10 -- "$local_path" "$destination:$remote_path" 2>/dev/null && \
      msg_ok "$(L MSG_CL_0296 "$name")" || \
      msg_err "$(L MSG_CL_0297 "$name")"
  done <<< "$CLUSTER_SNAPSHOT"
  _log_write "$(L MSG_CL_0298 "$local_path" "$remote_path")"
  pause
}

# ---- 预置批量任务 ----
# 数据表: 名称|说明|远端命令
# 命令内不包含 $ 与反引号，故可安全存放在双引号数组中；远端由目标机 shell 解析
CLUSTER_TASKS=(
  "$(L MSG_CL_0299)"
  "$(L MSG_CL_0300)"
  "$(L MSG_CL_0301)"
  "$(L MSG_CL_0302)"
  "$(L MSG_CL_0303)"
  "$(L MSG_CL_0304)"
  "$(L MSG_CL_0305)"
  "$(L MSG_CL_0306)"
  "$(L MSG_CL_0307)"
)

cluster_task() {
  _require_root
  _cluster_init || return 1
  msg_title "$(L MSG_CL_0308)"
  msg ""

  if [[ -z "$CLUSTER_SNAPSHOT" ]]; then
    msg_warn "$(L MSG_CL_0309)"
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
  msg "$(L MSG_CL_0310 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0311)" task_choice
  [[ -z "$task_choice" ]] && { pause; return; }

  # 解析选择（任务序号 / 多选 / c 自定义）
  local -a run_cmds=() run_names=()
  for token in $task_choice; do
    if [[ "$token" =~ ^[Cc]$ ]]; then
      read -p "$(L MSG_CL_0312)" tcmd
      if [[ -n "$tcmd" ]]; then
        run_cmds+=("$tcmd")
        run_names+=("$(L MSG_CL_0313)")
      fi
    elif [[ "$token" =~ ^[0-9]+$ ]] && [[ "$token" -ge 1 && "$token" -le "${#CLUSTER_TASKS[@]}" ]]; then
      entry="${CLUSTER_TASKS[$((token-1))]}"
      name="${entry%%|*}"
      tcmd="${entry#*|}"; tcmd="${tcmd#*|}"
      run_cmds+=("$tcmd")
      run_names+=("$name")
    else
      msg_warn "$(L MSG_CL_0314 "$token")"
    fi
  done

  if [[ ${#run_cmds[@]} -eq 0 ]]; then
    msg_err "$(L MSG_CL_0315)"
    pause; return
  fi

  # 显示目标节点清单
  msg ""
  msg "$(L MSG_CL_0316 "${F_BOLD}" "${F_RESET}")"
  local node_total=0 n a p
  while IFS='|' read -r n a p; do
    [[ -z "$n" ]] && continue
    msg "    $n ($a:$p)"
    node_total=$((node_total+1))
  done <<< "$CLUSTER_SNAPSHOT"

  msg ""
  msg "$(L MSG_CL_0317 "${run_names[*]}")"
  confirm "$(L MSG_CL_0318 "$node_total")" || { pause; return; }

  # reboot 属破坏性操作：额外二次确认（输入大写 YES）
  local j need_reboot=0
  for j in "${!run_names[@]}"; do
    [[ "${run_names[$j]}" == "reboot" ]] && need_reboot=1
  done
  if [[ $need_reboot -eq 1 ]]; then
    msg_warn "$(L MSG_CL_0319)"
    read -p "$(L MSG_CL_0320)" reboot_yes
    [[ "$reboot_yes" == "YES" ]] || { msg_info "$(L MSG_CL_0321)"; pause; return; }
    msg_info "$(L MSG_CL_0322)"
  fi

  # 逐节点执行：单个节点内依次跑完所选任务
  local ok=0 fail=0 result rc line node_fail=0
  msg ""
  msg "$(L MSG_CL_0287)"
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
          msg "$(L MSG_CL_0323 "${F_GREEN}" "${F_RESET}")"
        fi
      else
        msg "$(L MSG_CL_0324 "${F_RED}" "${F_RESET}")"
        [[ -n "$result" ]] && msg "      $result"
        node_fail=1
      fi
    done
    if [[ $node_fail -eq 0 ]]; then
      msg "$(L MSG_CL_0325 "${F_GREEN}" "$n" "${F_RESET}")"
      ok=$((ok+1))
    else
      msg "$(L MSG_CL_0326 "${F_RED}" "$n" "${F_RESET}")"
      fail=$((fail+1))
    fi
  done <<< "$CLUSTER_SNAPSHOT"

  msg "$(L MSG_CL_0287)"
  msg "$(L MSG_CL_0327 "${F_GREEN}" "$ok" "${F_RESET}" "${F_RED}" "$fail" "${F_RESET}" "$node_total")"
  _log_write "$(L MSG_CL_0328 "${run_names[*]}" "$ok" "$fail")"
  pause
  [[ $fail -eq 0 ]]
}

# ---- 游戏服务端 ----
cluster_game() {
  _require_root
  msg_title "$(L MSG_CL_0329)"
  msg ""
  msg "$(L MSG_CL_0330 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0331 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0332 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0333 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0334 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0335 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0336)" game_choice

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

  msg_info "$(L MSG_CL_0337)"
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
    msg_ok "$(L MSG_CL_0338)"
    msg "$(L MSG_CL_0339)"
    msg "$(L MSG_CL_0340 "$rcon_pass")"
    msg "$(L MSG_CL_0341 "$app_dir")"
    _log_write "$(L MSG_CL_0338)"
  else
    msg_err "$(L MSG_CL_0342 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0343)"
    msg "$(L MSG_CL_0344)"
    _log_write "$(L MSG_CL_0343)"
  else
    msg_err "$(L MSG_CL_0342 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0345)"
    msg "$(L MSG_CL_0346)"
    _log_write "$(L MSG_CL_0345)"
  else
    msg_err "$(L MSG_CL_0342 "$app_dir")"
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
    msg_ok "$(L MSG_CL_0347)"
    msg "$(L MSG_CL_0348)"
    _log_write "$(L MSG_CL_0349)"
  else
    msg_err "$(L MSG_CL_0342 "$app_dir")"
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
  "$(L MSG_CL_0350)"
)
CLUSTER_GAME_BACKUP_DIR="/root/game-backups"

cluster_game_manage() {
  _require_root
  msg_title "$(L MSG_CL_0351)"
  msg ""

  if ! command -v docker >/dev/null 2>&1; then
    msg_err "$(L MSG_CL_0352)"
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
    msg_warn "$(L MSG_CL_0353)"
    msg "$(L MSG_CL_0354)"
    pause; return
  fi

  local st gsel
  msg "$(L MSG_CL_0355)"
  for j in "${!d_keys[@]}"; do
    st="$(L MSG_CL_0356 "${F_RED}" "${F_RESET}")"
    if [[ -n "$(docker ps --filter "name=${d_conts[$j]}" --format '{{.Names}}' 2>/dev/null)" ]]; then
      st="$(L MSG_CL_0357 "${F_GREEN}" "${F_RESET}")"
    fi
    msg "  ${F_GREEN}$((j+1))${F_RESET}) ${d_names[$j]} - $st  ${F_CYAN}(${d_keys[$j]})${F_RESET}"
  done
  msg "$(L MSG_CL_0335 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0358)" gsel || { msg ""; return; }
  [[ "$gsel" == "0" || -z "$gsel" ]] && return
  if ! [[ "$gsel" =~ ^[0-9]+$ ]] || [[ "$gsel" -lt 1 || "$gsel" -gt ${#d_keys[@]} ]]; then
    msg_err "$(L MSG_CL_0359)"
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
    msg_title "$(L MSG_CL_0360 "$gname")"
    msg "$(L MSG_CL_0361)"
    msg "$(L MSG_CL_0362)"
    msg "$(L MSG_CL_0363)"
    msg "$(L MSG_CL_0364)"
    msg "$(L MSG_CL_0365)"
    msg "$(L MSG_CL_0366)"
    msg "$(L MSG_CL_0367)"
    msg "$(L MSG_CL_0368)"
    msg "$(L MSG_CL_0369)"
    msg "$(L MSG_CL_0335 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_CL_0370)" op || { msg ""; return; }

    case "$op" in
      1)
        msg ""
        out=$(cd "$app_dir" && docker compose ps 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "$(L MSG_CL_0371 "${F_YELLOW}" "${F_RESET}")"
        fi
        ;;
      2)
        if (cd "$app_dir" && docker compose up -d); then
          msg_ok "$(L MSG_CL_0372 "$gname")"
          _log_write "$(L MSG_CL_0373 "$key")"
        else
          msg_err "$(L MSG_CL_0374 "$app_dir")"
        fi
        ;;
      3)
        confirm "$(L MSG_CL_0375 "$gname")" || { msg_info "$(L MSG_CL_0376)"; continue; }
        if (cd "$app_dir" && docker compose stop); then
          msg_ok "$(L MSG_CL_0377 "$gname")"
          _log_write "$(L MSG_CL_0378 "$key")"
        else
          msg_err "$(L MSG_CL_0379)"
        fi
        ;;
      4)
        confirm "$(L MSG_CL_0380 "$gname")" || { msg_info "$(L MSG_CL_0376)"; continue; }
        if (cd "$app_dir" && docker compose restart); then
          msg_ok "$(L MSG_CL_0381 "$gname")"
        else
          msg_err "$(L MSG_CL_0382)"
        fi
        ;;
      5)
        msg ""
        out=$(cd "$app_dir" && docker compose logs --tail 50 2>&1)
        if [[ -n "$out" ]]; then
          while IFS= read -r line; do msg "    $line"; done <<< "$out"
        else
          msg "$(L MSG_CL_0383)"
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
  msg_info "$(L MSG_CL_0384)"
  if docker pull alpine >/dev/null 2>&1; then
    msg_ok "$(L MSG_CL_0385)"
    return 0
  fi
  msg_err "$(L MSG_CL_0386)"
  return 1
}

# Resolve the actual Compose volume name, including project prefixes and explicit names.
_game_resolve_volume() {
  local key="$1" logical="$2" actual config
  [[ "$key" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
  command -v python3 >/dev/null || { msg_err "$(L MSG_CL_0387)" >&2; return 1; }
  config=$(cd "/opt/games/$key" && docker compose config --format json) || return 1
  actual=$(printf '%s' "$config" | python3 -c 'import json,sys; c=json.load(sys.stdin); print(c.get("volumes",{}).get(sys.argv[1],{}).get("name", ""))' "$logical") || return 1
  [[ -n "$actual" ]] || { msg_err "$(L MSG_CL_0388)" >&2; return 1; }
  docker volume inspect "$actual" >/dev/null 2>&1 || return 1
  printf '%s\n' "$actual"
}

_game_backup() {
  local key="$1" gvol="$2"
  local backup_dir="$CLUSTER_GAME_BACKUP_DIR"
  local ts file size

  if ! mkdir -p "$backup_dir"; then
    msg_err "$(L MSG_CL_0389 "$backup_dir")"
    return 1
  fi
  gvol=$(_game_resolve_volume "$key" "$gvol") || return 1
  _game_ensure_alpine || return 1

  # 先声明再赋值，避免 local 吞掉退出码（SC2155）
  ts=$(date +%Y%m%d-%H%M%S)
  file="$key-$ts.tar.gz"
  msg_info "$(L MSG_CL_0390 "$gvol" "$backup_dir" "$file")"
  if docker run --rm -v "$gvol":/data -v "$backup_dir":/backup alpine tar czf "/backup/$file" -C /data .; then
    size=$(du -h "$backup_dir/$file" 2>/dev/null | cut -f1)
    msg_ok "$(L MSG_CL_0391 "$backup_dir" "$file" "${size:-大小未知}")"
    _log_write "$(L MSG_CL_0392 "$key" "$file")"
  else
    msg_err "$(L MSG_CL_0393)"
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
    msg_warn "$(L MSG_CL_0394 "$backup_dir" "$key")"
    return 0
  fi

  msg ""
  msg "$(L MSG_CL_0395)"
  for j in "${!files[@]}"; do
    msg "  ${F_GREEN}$((j+1))${F_RESET}) $(basename "${files[$j]}")  ${F_CYAN}($(du -h "${files[$j]}" 2>/dev/null | cut -f1))${F_RESET}"
  done
  msg "$(L MSG_CL_0335 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_CL_0396)" rsel
  [[ "$rsel" == "0" || -z "$rsel" ]] && return 0
  if ! [[ "$rsel" =~ ^[0-9]+$ ]] || [[ "$rsel" -lt 1 || "$rsel" -gt ${#files[@]} ]]; then
    msg_err "$(L MSG_CL_0397)"
    return 0
  fi

  f="${files[$((rsel-1))]}"
  base=$(basename "$f")
  msg_warn "$(L MSG_CL_0398 "$gvol" "$base")"
  confirm "$(L MSG_CL_0399)" || { msg_info "$(L MSG_CL_0376)"; return 0; }
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
  [[ $? -eq 0 ]] || { msg_err "$(L MSG_CL_0400)"; return 1; }
  local app_dir="/opt/games/$key" running safety rc=0
  running=$(cd "$app_dir" && docker compose ps --status running -q) || return 1
  (cd "$app_dir" && docker compose stop) || return 1
  safety="$key-before-restore-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data,readonly" -v "$backup_dir":/backup alpine tar czf "/backup/$safety" -C /data .; then
    msg_err "$(L MSG_CL_0401)"
    [[ -z "$running" ]] || docker start $running >/dev/null
    return 1
  fi
  if ! docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$base"; then
    rc=1
    msg_err "$(L MSG_CL_0402 "$safety")"
    docker run --rm --mount "type=volume,src=$gvol,dst=/data" -v "$backup_dir":/backup:ro alpine sh -c 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + && tar xzf "/backup/$1" -C /data' sh "$safety" || {
      msg_err "$(L MSG_CL_0403 "$safety")"; return 1;
    }
  fi
  if [[ -n "$running" ]]; then docker start $running >/dev/null || return 1; fi
  [[ "$rc" -eq 0 ]] && msg_ok "$(L MSG_CL_0404 "$safety")"
  return "$rc"
}

_game_config() {
  local key="$1"
  local app_dir="/opt/games/$key"
  local compose="$app_dir/docker-compose.yml"

  if [[ ! -f "$compose" ]]; then
    msg_err "$(L MSG_CL_0405 "$compose")"
    return 1
  fi

  # 改前留副本便于回滚
  cp -f "$compose" "$compose.bak" 2>/dev/null || true

  local line new_mem new_pl changed=0
  case "$key" in
    minecraft-java)
      msg_info "$(L MSG_CL_0406)"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*(MEMORY|MAX_PLAYERS):' "$compose" 2>/dev/null)
      read -p "$(L MSG_CL_0407)" new_mem
      read -p "$(L MSG_CL_0408)" new_pl
      if [[ -n "$new_mem" ]]; then
        if [[ "$new_mem" =~ ^[0-9]+[GgMm]$ ]]; then
          sed -i -E "s|^([[:space:]]*MEMORY:[[:space:]]*).*|\1\"$new_mem\"|" "$compose"
          msg_ok "$(L MSG_CL_0409 "$new_mem")"
          changed=1
        else
          msg_err "$(L MSG_CL_0410)"
        fi
      fi
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*MAX_PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "$(L MSG_CL_0411 "$new_pl")"
          changed=1
        else
          msg_err "$(L MSG_CL_0412)"
        fi
      fi
      ;;
    palworld)
      msg_info "$(L MSG_CL_0406)"
      while IFS= read -r line; do msg "    $line"; done < <(grep -E '^[[:space:]]*PLAYERS:' "$compose" 2>/dev/null)
      read -p "$(L MSG_CL_0413)" new_pl
      if [[ -n "$new_pl" ]]; then
        if [[ "$new_pl" =~ ^[0-9]+$ ]]; then
          sed -i -E "s|^([[:space:]]*PLAYERS:[[:space:]]*).*|\1\"$new_pl\"|" "$compose"
          msg_ok "$(L MSG_CL_0414 "$new_pl")"
          changed=1
        else
          msg_err "$(L MSG_CL_0412)"
        fi
      fi
      ;;
    *)
      msg_info "$(L MSG_CL_0415 "$compose")"
      msg "$(L MSG_CL_0416 "$app_dir")"
      return 0
      ;;
  esac

  if [[ $changed -eq 1 ]]; then
    msg_info "$(L MSG_CL_0417 "$app_dir")"
    _log_write "$(L MSG_CL_0418 "$key")"
  else
    msg "$(L MSG_CL_0419)"
  fi
}

_game_uninstall() {
  local key="$1" gname="$2" app_dir="$3" gvol="$4"

  # 目录必须位于 /opt/games 下，避免误删
  if [[ "$app_dir" != /opt/games/* ]]; then
    msg_err "$(L MSG_CL_0420 "$app_dir")"
    return 1
  fi

  msg_warn "$(L MSG_CL_0421 "$gname" "$app_dir")"
  msg_warn "$(L MSG_CL_0422 "$gvol")"
  confirm "$(L MSG_CL_0423 "$gname")" || { msg_info "$(L MSG_CL_0376)"; return 1; }
  read -p "$(L MSG_CL_0424)" uninstall_yes
  [[ "$uninstall_yes" == "YES" ]] || { msg_info "$(L MSG_CL_0425)"; return 1; }

  msg_info "$(L MSG_CL_0426)"
  if (cd "$app_dir" && docker compose down); then
    msg_ok "$(L MSG_CL_0427)"
  else
    msg_err "$(L MSG_CL_0428)"
    return 1
  fi
  rm -rf "$app_dir"
  msg_ok "$(L MSG_CL_0429 "$gname")"
  msg_info "$(L MSG_CL_0430 "$gvol" "$gvol")"
  _log_write "$(L MSG_CL_0431 "$key" "$gvol")"
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
        msg_err "$(L MSG_CL_0432)"
        return 2
        ;;
      *)
        msg_err "$(L MSG_CL_0433 "$1")"
        msg "$(L MSG_CL_0434)"
        return 2
        ;;
    esac
  fi

  _require_root
  msg_title "$(L MSG_CL_0435)"
  msg ""
  msg_warn "$(L MSG_CL_0436)"
  msg ""
  msg "$(L MSG_CL_0437)"
  msg "$(L MSG_CL_0438)"
  msg "$(L MSG_CL_0439)"
  msg "$(L MSG_CL_0440)"
  read -r -p "$(L MSG_CL_0336)" oc_choice || return
  case "$oc_choice" in
    1) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect ;;
    2) python3 -B "$FUSION_SRC/lib/oracle_tools.py" detect --metadata ;;
    3) python3 -B "$FUSION_SRC/lib/oracle_tools.py" status ;;
    0) return 0 ;;
    *) msg_err "$(L MSG_CL_0359)"; return 2 ;;
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
      [[ -s "$file" ]] || { msg "$(L MSG_CL_0441)"; return 0; }
      msg "$(L MSG_CL_0442 "${F_BOLD}" "${F_RESET}")"
      awk -F'|' '{printf "    %s -> %s:%s\n", $1, $2, $3}' "$file"
      ;;
    add)
      local name="${1:-}" target="${2:-}" port="${3:-22}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0443 "$name")"; return 1; }
      [[ "$target" =~ ^[a-zA-Z0-9._@-]+$ ]] || { msg_err "$(L MSG_CL_0444 "$target")"; return 1; }
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "$(L MSG_CL_0445 "$port")"; return 1; }
      grep -q "^$name|" "$file" 2>/dev/null && { msg_err "$(L MSG_CL_0446 "$name")"; return 1; }
      mkdir -p "$(dirname "$file")" && touch "$file" && chmod 600 "$file"
      printf '%s|%s|%s
' "$name" "$target" "$port" >> "$file"
      msg_ok "$(L MSG_CL_0447 "$name" "$target" "$port")"
      ;;
    rm)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0448)"; return 1; }
      [[ -f "$file" ]] && grep -q "^$name|" "$file" || { msg_err "$(L MSG_CL_0449 "$name")"; return 1; }
      sed -i "/^$name|/d" "$file"
      msg_ok "$(L MSG_CL_0450 "$name")"
      ;;
    connect)
      local name="${1:-}"
      [[ "$name" =~ ^[a-zA-Z0-9._-]{1,32}$ ]] || { msg_err "$(L MSG_CL_0448)"; return 1; }
      local row; row=$(grep "^$name|" "$file" 2>/dev/null | tail -1)
      [[ -n "$row" ]] || { msg_err "$(L MSG_CL_0449 "$name")"; return 1; }
      local target="${row#*|}"; target="${target%%|*}"
      local port="${row##*|}"
      msg_info "$(L MSG_CL_0451 "$name" "$target" "$port")"
      ssh -t -p "$port" "$target"
      ;;
    *)
      msg_err "$(L MSG_CL_0452 "$action")"; return 2 ;;
  esac
}

# ---- k 风格中文速查表 (A 档) ----
# A single page that pairs each common command with a one-line human explanation,
# so users do not have to memorise the CLI surface or read the source.
cluster_k_alias() {
  _require_root
  msg_title "$(L MSG_CL_0453)"
  msg ""
  msg "$(L MSG_CL_0454 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0455 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0456 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0457 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0458 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0459 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0460 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0461 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0462 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0463 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0464 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0465 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0466 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0467 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0468 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0469 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0470 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0471 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0472 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0473 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0474 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0475 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0476 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_CL_0477 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0478 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0479 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_CL_0480 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg_info "$(L MSG_CL_0481)"
  msg ""
}

cluster_kcmd() {
  _require_root
  local kcmd_dir="/etc/fusionbox/kcmd"
  mkdir -p "$kcmd_dir"
  local kcmd_file="$kcmd_dir/aliases.sh"

  msg_title "$(L MSG_CL_0482)"
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

  msg "$(L MSG_CL_0483 "${F_BOLD}" "${F_RESET}")"
  msg ""
  while IFS= read -r line; do
    [[ "$line" == alias* ]] || continue
    local alias_name alias_cmd
    alias_name=$(echo "$line" | sed "s/alias \([^=]*\)=.*/\1/")
    alias_cmd=$(echo "$line" | sed "s/alias [^=]*='\(.*\)'/\1/")
    msg "  ${F_GREEN}$alias_name${F_RESET} → $alias_cmd"
  done < "$kcmd_file"

  msg ""
  msg "$(L MSG_CL_0484)"
  msg "$(L MSG_CL_0485)"
  msg "$(L MSG_CL_0486)"
  msg "$(L MSG_CL_0487)"
  msg "$(L MSG_CL_0440)"
  read -p "$(L MSG_CL_0336)" k_choice

  case "$k_choice" in
    1)
      read -p "$(L MSG_CL_0488)" alias_name
      read -p "$(L MSG_CL_0489)" alias_cmd
      if [[ -n "$alias_name" && -n "$alias_cmd" ]]; then
        # 别名会写入被 source 的 shell 文件，必须校验命名合法性
        if [[ ! "$alias_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
          msg_err "$(L MSG_CL_0490)"
        else
          echo "alias $alias_name='$alias_cmd'" >> "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "$(L MSG_CL_0491 "$alias_name" "$alias_cmd")"
        fi
      fi
      ;;
    2)
      nl -ba "$kcmd_file" | grep "alias"
      read -p "$(L MSG_CL_0492)" del_line
      if [[ -n "$del_line" ]]; then
        if ! [[ "$del_line" =~ ^[0-9]+$ ]] || [[ "$del_line" -lt 1 || "$del_line" -gt $(wc -l < "$kcmd_file") ]]; then
          msg_err "$(L MSG_CL_0493 "$(wc -l < "$kcmd_file")")"
        elif confirm "$(L MSG_CL_0494 "$del_line")"; then
          sed -i "${del_line}d" "$kcmd_file"
          source "$kcmd_file" 2>/dev/null
          msg_ok "$(L MSG_CL_0495)"
        fi
      fi
      ;;
    3)
      rm -f "$kcmd_file"
      cluster_kcmd
      ;;
    4)
      source "$kcmd_file" 2>/dev/null
      msg_ok "$(L MSG_CL_0496)"
      ;;
  esac
  pause
}

# ---- Help ----
cluster_help() {
  msg_title "$(L MSG_CL_0497)"
  msg ""
  msg "$(L MSG_CL_0498 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0499)"
  msg "$(L MSG_CL_0500)"
  msg "$(L MSG_CL_0501)"
  msg "$(L MSG_CL_0502)"
  msg "$(L MSG_CL_0503)"
  msg "$(L MSG_CL_0504)"
  msg "$(L MSG_CL_0505)"
  msg "$(L MSG_CL_0506)"
  msg "$(L MSG_CL_0507)"
  msg "$(L MSG_CL_0508)"
  msg "$(L MSG_CL_0509)"
  msg "$(L MSG_CL_0510)"
  msg "$(L MSG_CL_0511)"
  msg "$(L MSG_CL_0512)"
  msg ""
  msg "$(L MSG_CL_0513 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0514)"
  msg "    - Minecraft Java/Bedrock"
  msg "    - Terraria"
  msg "$(L MSG_CL_0515)"
  msg "$(L MSG_CL_0516)"
  msg ""
  msg "  ${F_BOLD}[Oracle Cloud]${F_RESET}"
  msg "$(L MSG_CL_0517)"
  msg "$(L MSG_CL_0518)"
  msg ""
  msg "$(L MSG_CL_0519 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_CL_0520)"
  msg "    k=fusionbox  ks=system  kb=bbr  kn=network"
  msg "    kw=web  kp=proxy  kd=docker  km=market"
  msg ""
}

# ---- Interactive Menu ----
cluster_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_CL_0521)"
    msg ""
    msg "$(L MSG_CL_0522 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0523 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0524 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0525 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0526 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0527 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0528 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0529 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0530 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_CL_0531 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_CL_0370)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1)
        msg "$(L MSG_CL_0532)"
        read -p "$(L MSG_CL_0336)" node_choice || { msg ""; break; }
        case "$node_choice" in
          1) cluster_add ;;
          2) cluster_remove ;;
          3) cluster_list ;;
          4) read -r -p "$(L MSG_CL_0533)" transfer_file || return 1
             cluster_transfer export "$transfer_file"; pause ;;
          5) read -r -p "$(L MSG_CL_0534)" transfer_file || return 1
             if cluster_transfer import "$transfer_file" --dry-run; then
               if confirm "$(L MSG_CL_0535)"; then
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
