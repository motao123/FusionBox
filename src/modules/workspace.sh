# FusionBox 后台工作区管理模块
# Screen/Tmux 会话管理

workspace_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    screen|sc)       workspace_screen "$@" ;;
    tmux|tm)         workspace_tmux "$@" ;;
    list|ls)         workspace_list "$@" ;;
    work)            workspace_work "$@" ;;
    menu|main)       workspace_menu ;;
    help|h)          workspace_help ;;
    *)               _module_unknown_cmd "workspace" "$cmd" ;;
  esac
}

# ---- Screen 管理 ----
workspace_screen() {
  local action="${1:-menu}"

  case "$action" in
    install) _install_pkg screen; msg_ok "$(L MSG_WS_0093)" ;;
    list)
      msg_title "$(L MSG_WS_0094)"
      screen -ls 2>/dev/null || msg "$(L MSG_WS_0095)"
      ;;
    create)
      local session_name; session_name=$(read_input "$(L MSG_WS_0096)" "fusionbox_$(date +%s)")
      screen -dmS "$session_name" 2>/dev/null && \
        msg_ok "$(L MSG_WS_0097 "$session_name")" || \
        msg_err "$(L MSG_WS_0098)"
      msg "$(L MSG_WS_0099 "$session_name")"
      ;;
    attach)
      screen -ls 2>/dev/null
      read -p "$(L MSG_WS_0100)" session_name
      if [[ -n "$session_name" ]]; then
        screen -r "$session_name" 2>/dev/null || msg_err "$(L MSG_WS_0101)"
      fi
      ;;
    kill)
      screen -ls 2>/dev/null
      read -p "$(L MSG_WS_0100)" session_name
      if [[ -n "$session_name" ]]; then
        if confirm "$(L MSG_WS_0102 "$session_name")"; then
          screen -S "$session_name" -X quit 2>/dev/null && msg_ok "$(L MSG_WS_0103 "$session_name")" || msg_err "$(L MSG_WS_0104)"
        fi
      fi
      ;;
    *)
      workspace_screen_menu
      ;;
  esac
}

workspace_screen_menu() {
  while true; do
    clear
    msg_title "$(L MSG_WS_0105)"
    msg ""
    if command -v screen &>/dev/null; then
      msg "  Screen: $(screen -v 2>&1 | head -1)"
      msg ""
      screen -ls 2>/dev/null | while read -r line; do
        [[ "$line" == *"No Sockets"* ]] && msg "$(L MSG_WS_0106)" || msg "  $line"
      done
    else
      msg "$(L MSG_WS_0107)"
    fi
    msg ""
    msg "$(L MSG_WS_0108)"
    msg "$(L MSG_WS_0109)"
    msg "$(L MSG_WS_0110)"
    msg "$(L MSG_WS_0111)"
    msg "$(L MSG_WS_0112)"
    msg "$(L MSG_WS_0113)"
    read -p "$(L MSG_WS_0114)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) _install_pkg screen; pause ;;
      2) workspace_screen create; pause ;;
      3) workspace_screen list; pause ;;
      4) workspace_screen attach ;;
      5) workspace_screen kill; pause ;;
      0) break ;;
    esac
  done
}

# ---- Tmux 管理 ----
workspace_tmux() {
  local action="${1:-menu}"

  case "$action" in
    install) _install_pkg tmux; msg_ok "$(L MSG_WS_0115)" ;;
    list)
      msg_title "$(L MSG_WS_0116)"
      tmux ls 2>/dev/null || msg "$(L MSG_WS_0117)"
      ;;
    create)
      local session_name; session_name=$(read_input "$(L MSG_WS_0096)" "fusionbox_$(date +%s)")
      tmux new-session -d -s "$session_name" 2>/dev/null && \
        msg_ok "$(L MSG_WS_0118 "$session_name")" || \
        msg_err "$(L MSG_WS_0119)"
      msg "$(L MSG_WS_0120 "$session_name")"
      ;;
    attach)
      tmux ls 2>/dev/null
      read -p "$(L MSG_WS_0100)" session_name
      if [[ -n "$session_name" ]]; then
        tmux attach -t "$session_name" 2>/dev/null || msg_err "$(L MSG_WS_0101)"
      fi
      ;;
    kill)
      tmux ls 2>/dev/null
      read -p "$(L MSG_WS_0100)" session_name
      if [[ -n "$session_name" ]]; then
        if confirm "$(L MSG_WS_0102 "$session_name")"; then
          tmux kill-session -t "$session_name" 2>/dev/null && msg_ok "$(L MSG_WS_0103 "$session_name")" || msg_err "$(L MSG_WS_0104)"
        fi
      fi
      ;;
    *)
      workspace_tmux_menu
      ;;
  esac
}

workspace_tmux_menu() {
  while true; do
    clear
    msg_title "$(L MSG_WS_0121)"
    msg ""
    if command -v tmux &>/dev/null; then
      msg "  Tmux: $(tmux -V 2>&1)"
      tmux ls 2>/dev/null | while read -r line; do
        msg "  $line"
      done || msg "$(L MSG_WS_0106)"
    else
      msg "$(L MSG_WS_0122)"
    fi
    msg ""
    msg "$(L MSG_WS_0123)"
    msg "$(L MSG_WS_0109)"
    msg "$(L MSG_WS_0110)"
    msg "$(L MSG_WS_0111)"
    msg "$(L MSG_WS_0112)"
    msg "$(L MSG_WS_0113)"
    read -p "$(L MSG_WS_0114)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) _install_pkg tmux; pause ;;
      2) workspace_tmux create; pause ;;
      3) workspace_tmux list; pause ;;
      4) workspace_tmux attach ;;
      5) workspace_tmux kill; pause ;;
      0) break ;;
    esac
  done
}

# ---- 编号工作区 (G62)：w1-w10 固定槽位，支持命令注入与重连 ----
# Slots are stable names (w1..w10) so a user reconnects with `fusionbox ws w3`
# instead of hunting for PIDs in `screen -ls` / `tmux ls`.
# Normalize "3" / "w3" / "work3" -> "3" (must strip "work" before the "w" prefix
# check, otherwise "work7" would be mangled into "ork7").
_ws_work_strip() {
  local n="$1"
  n="${n#work}"
  n="${n#w}"
  printf '%s' "$n"
}

_ws_work_check_n() {
  local n; n=$(_ws_work_strip "$1")
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le 10 ] || {
    msg_err "$(L MSG_WS_0124 "$1")"
    return 1
  }
}

# Normalize "3", "w3", "work3" -> "w3"
_ws_work_name() {
  local n; n=$(_ws_work_strip "$1")
  _ws_work_check_n "$n" || return 1
  printf 'w%s' "$n"
}

# tmux is preferred; screen is accepted as a fallback so the slots still work
# on hosts where only screen is available. Prints the chosen tool.
_ws_work_tool() {
  if command -v tmux &>/dev/null; then
    printf tmux
    return 0
  fi
  if command -v screen &>/dev/null; then
    printf screen
    return 0
  fi
  msg_err "$(L MSG_WS_0125)"
  msg_info "$(L MSG_WS_0126 "$(_pkg_install_hint tmux)" "$(_pkg_install_hint screen)")"
  return 1
}

# ---- Backend-agnostic slot operations (tmux or screen) ----
_ws_slot_exists() {
  local name="$1"
  if type -t tmux &>/dev/null && command -v tmux &>/dev/null; then
    tmux has-session -t "$name" 2>/dev/null && return 0
  fi
  if command -v screen &>/dev/null; then
    screen -ls 2>/dev/null | grep -qE "[.]${name}[[:space:]]" && return 0
  fi
  return 1
}

_ws_slot_create() {
  local name="$1" cmd="${2:-}"
  if command -v tmux &>/dev/null; then
    if [[ -n "$cmd" ]]; then
      tmux new-session -d -s "$name" "$cmd"
    else
      tmux new-session -d -s "$name"
    fi
    return $?
  fi
  if [[ -n "$cmd" ]]; then
    screen -dmS "$name" sh -c "$cmd; exec \${SHELL:-/bin/sh}"
  else
    screen -dmS "$name"
  fi
}

_ws_slot_attach() {
  local name="$1"
  if command -v tmux &>/dev/null; then
    tmux attach -t "$name"
  else
    screen -r "$name"
  fi
}

# Attach if the slot exists, otherwise create it first. Used by the SSH-resident
# flow: reconnecting only needs `fusionbox ws w3`, and a missing slot is rebuilt
# instead of erroring out.
_ws_slot_ensure() {
  local name="$1" create="${2:-1}"
  if _ws_slot_exists "$name"; then
    return 0
  fi
  [[ "$create" == 1 ]] || return 1
  _ws_slot_create "$name"
}

_ws_slot_send() {
  local name="$1" cmd="$2"
  if command -v tmux &>/dev/null; then
    tmux send-keys -t "$name" "$cmd" C-m
  else
    # screen has no non-interactive send-keys; paste via a temporary buffer file
    screen -S "$name" -X stuff "$(printf '%s\r' "$cmd")"
  fi
}

_ws_slot_kill() {
  local name="$1"
  if command -v tmux &>/dev/null && tmux has-session -t "$name" 2>/dev/null; then
    tmux kill-session -t "$name"
    return $?
  fi
  screen -S "$name" -X quit 2>/dev/null
}

workspace_work() {
  _require_root
  local action="${1:-menu}"
  local tool; tool=$(_ws_work_tool) || return 1
  # 直接 `fusionbox ws w3`：省略动作时进入该槽位；不存在则自动创建，
  # 这样断线重连时永远能回到（或重建）同一个编号工作区。
  if [[ "$action" =~ ^(w?[0-9]+)$ ]]; then
    local dir_name; dir_name=$(_ws_work_name "$action") || return 1
    if ! _ws_slot_exists "$dir_name"; then
      msg_info "$(L MSG_WS_0127 "$dir_name")"
      _ws_slot_create "$dir_name" || { msg_err "$(L MSG_WS_0128 "$dir_name")"; return 1; }
    fi
    _ws_slot_attach "$dir_name"
    return $?
  fi

  case "$action" in
    list)
      local i name state
      msg "$(L MSG_WS_0129 "${F_BOLD}" "$tool" "${F_RESET}")"
      for i in 1 2 3 4 5 6 7 8 9 10; do
        name="w$i"
        if _ws_slot_exists "$name"; then
          state="$(L MSG_WS_0130 "${F_GREEN}" "${F_RESET}")"
        else
          state="$(L MSG_WS_0131)"
        fi
        msg "    $name: $state"
      done
      msg "$(L MSG_WS_0132)"
      ;;
    new)
      local n="${2:-}" cmd="${3:-}" name
      name=$(_ws_work_name "$n") || return 1
      if _ws_slot_exists "$name"; then
        msg_err "$(L MSG_WS_0133 "$name")"
        return 1
      fi
      if _ws_slot_create "$name" "$cmd"; then
        if [[ -n "$cmd" ]]; then
          msg_ok "$(L MSG_WS_0134 "$name" "$cmd")"
        else
          msg_ok "$(L MSG_WS_0135 "$name")"
        fi
      else
        msg_err "$(L MSG_WS_0128 "$name")"
        return 1
      fi
      ;;
    attach)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if ! _ws_slot_exists "$name"; then
        msg_err "$(L MSG_WS_0136 "$name" "$n")"
        return 1
      fi
      _ws_slot_attach "$name"
      ;;
    send|say)
      local n="${2:-}" cmd="${3:-}" name
      name=$(_ws_work_name "$n") || return 1
      [[ -n "$cmd" ]] || { msg_err "$(L MSG_WS_0137)"; return 2; }
      if ! _ws_slot_exists "$name"; then
        msg_err "$(L MSG_WS_0138 "$name")"
        return 1
      fi
      _ws_slot_send "$name" "$cmd" && msg_ok "$(L MSG_WS_0139 "$name" "$cmd")"
      ;;
    capture|peek|log)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if ! _ws_slot_exists "$name"; then
        msg_err "$(L MSG_WS_0138 "$name")"
        return 1
      fi
      if command -v tmux &>/dev/null; then
        tmux capture-pane -p -t "$name" | tail -n 40
      else
        msg_warn "$(L MSG_WS_0140 "$name")"
      fi
      ;;
    kill)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if confirm "$(L MSG_WS_0141 "$name")"; then
        _ws_slot_kill "$name" && msg_ok "$(L MSG_WS_0142 "$name")" || msg_err "$(L MSG_WS_0138 "$name")"
      fi
      ;;
    ensure|resume)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      _ws_slot_ensure "$name" 1 || { msg_err "$(L MSG_WS_0128 "$name")"; return 1; }
      msg_ok "$(L MSG_WS_0143 "$name" "$name")"
      _ws_slot_attach "$name"
      ;;
    ssh)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      _ws_slot_ensure "$name" 1 || { msg_err "$(L MSG_WS_0128 "$name")"; return 1; }
      msg_title "$(L MSG_WS_0144 "$name")"
      msg "$(L MSG_WS_0145)"
      msg "    fusionbox ws $name"
      msg "$(L MSG_WS_0146)"
      if command -v tmux &>/dev/null; then
        msg "    tmux attach -t $name"
      else
        msg "    screen -r $name"
      fi
      msg "$(L MSG_WS_0147)"
      ;;
    menu|"")
      workspace_work_menu
      ;;
    *)
      msg_err "$(L MSG_WS_0148 "$action")"; return 2 ;;
  esac
}

workspace_work_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_WS_0149)"
    msg ""
    workspace_work list
    msg ""
    msg "$(L MSG_WS_0150)"
    msg "$(L MSG_WS_0151)"
    msg "$(L MSG_WS_0152)"
    msg "$(L MSG_WS_0153)"
    msg "$(L MSG_WS_0154)"
    msg "$(L MSG_WS_0155)"
    msg "$(L MSG_WS_0113)"
    read -p "$(L MSG_WS_0114)" w_choice || { msg ""; return; }
    case "$w_choice" in
      1) read -p "$(L MSG_WS_0156)" w_n; read -p "$(L MSG_WS_0157)" w_c
         if [[ -n "$w_c" ]]; then workspace_work new "$w_n" "$w_c" || true; else workspace_work new "$w_n" || true; fi ;;
      2) read -p "$(L MSG_WS_0156)" w_n; workspace_work attach "$w_n" ;;
      3) read -p "$(L MSG_WS_0158)" w_n; read -p "$(L MSG_WS_0159)" w_c; workspace_work send "$w_n" "$w_c" ;;
      4) read -p "$(L MSG_WS_0158)" w_n; workspace_work capture "$w_n"; pause ;;
      5) read -p "$(L MSG_WS_0158)" w_n; workspace_work kill "$w_n" ;;
      6) read -p "$(L MSG_WS_0158)" w_n; workspace_work ssh "$w_n"; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ---- 列出所有后台会话 ----
workspace_list() {
  msg_title "$(L MSG_WS_0160)"
  msg ""
  if command -v screen &>/dev/null; then
    msg "$(L MSG_WS_0161 "${F_BOLD}" "${F_RESET}")"
    screen -ls 2>/dev/null | while read -r line; do
      [[ "$line" == *"No Sockets"* ]] && msg "$(L MSG_WS_0162)" || msg "    $line"
    done || msg "$(L MSG_WS_0162)"
  fi
  msg ""
  if command -v tmux &>/dev/null; then
    msg "$(L MSG_WS_0163 "${F_BOLD}" "${F_RESET}")"
    tmux ls 2>/dev/null | while read -r line; do
      msg "    $line"
    done || msg "$(L MSG_WS_0162)"
  fi
  pause
}

# ---- Help ----
workspace_help() {
  msg_title "$(L MSG_WS_0164)"
  msg ""
  msg "$(L MSG_WS_0165)"
  msg "$(L MSG_WS_0166)"
  msg "$(L MSG_WS_0167)"
  msg "$(L MSG_WS_0168)"
  msg "$(L MSG_WS_0169)"
  msg "$(L MSG_WS_0170)"
  msg "$(L MSG_WS_0171)"
  msg "$(L MSG_WS_0172)"
  msg "$(L MSG_WS_0173)"
  msg ""
  msg "$(L MSG_WS_0174 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WS_0175)"
  msg "$(L MSG_WS_0176)"
  msg "$(L MSG_WS_0177)"
  msg "$(L MSG_WS_0178)"
  msg ""
}

# ---- Interactive Menu ----
workspace_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_WS_0160)"
    msg ""
    msg "$(L MSG_WS_0179 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WS_0180 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WS_0181 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WS_0182 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WS_0183 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_WS_0184)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) workspace_screen_menu ;;
      2) workspace_tmux_menu ;;
      3) workspace_list ;;
      4) workspace_work_menu ;;
      0) break ;;
    esac
  done
}
