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
    install) _install_pkg screen; msg_ok "screen 已安装" ;;
    list)
      msg_title "Screen 会话"
      screen -ls 2>/dev/null || msg "  暂无 screen 会话"
      ;;
    create)
      local session_name; session_name=$(read_input "会话名称" "fusionbox_$(date +%s)")
      screen -dmS "$session_name" 2>/dev/null && \
        msg_ok "Screen 会话 '$session_name' 已创建" || \
        msg_err "创建失败 (screen 未安装？)"
      msg "  进入会话: screen -r $session_name"
      ;;
    attach)
      screen -ls 2>/dev/null
      read -p "会话名称: " session_name
      if [[ -n "$session_name" ]]; then
        screen -r "$session_name" 2>/dev/null || msg_err "会话不存在"
      fi
      ;;
    kill)
      screen -ls 2>/dev/null
      read -p "会话名称: " session_name
      if [[ -n "$session_name" ]]; then
        if confirm "确认终止会话 '$session_name'？其中的进程将全部退出"; then
          screen -S "$session_name" -X quit 2>/dev/null && msg_ok "已终止: $session_name" || msg_err "终止失败"
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
    msg_title "Screen 管理"
    msg ""
    if command -v screen &>/dev/null; then
      msg "  Screen: $(screen -v 2>&1 | head -1)"
      msg ""
      screen -ls 2>/dev/null | while read -r line; do
        [[ "$line" == *"No Sockets"* ]] && msg "  暂无会话" || msg "  $line"
      done
    else
      msg "  Screen 未安装"
    fi
    msg ""
    msg "  1) 安装 Screen"
    msg "  2) 创建新会话"
    msg "  3) 列出会话"
    msg "  4) 进入会话"
    msg "  5) 终止会话"
    msg "  0) 返回"
    read -p "请选择: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
    install) _install_pkg tmux; msg_ok "tmux 已安装" ;;
    list)
      msg_title "Tmux 会话"
      tmux ls 2>/dev/null || msg "  暂无 tmux 会话"
      ;;
    create)
      local session_name; session_name=$(read_input "会话名称" "fusionbox_$(date +%s)")
      tmux new-session -d -s "$session_name" 2>/dev/null && \
        msg_ok "Tmux 会话 '$session_name' 已创建" || \
        msg_err "创建失败 (tmux 未安装？)"
      msg "  进入会话: tmux attach -t $session_name"
      ;;
    attach)
      tmux ls 2>/dev/null
      read -p "会话名称: " session_name
      if [[ -n "$session_name" ]]; then
        tmux attach -t "$session_name" 2>/dev/null || msg_err "会话不存在"
      fi
      ;;
    kill)
      tmux ls 2>/dev/null
      read -p "会话名称: " session_name
      if [[ -n "$session_name" ]]; then
        if confirm "确认终止会话 '$session_name'？其中的进程将全部退出"; then
          tmux kill-session -t "$session_name" 2>/dev/null && msg_ok "已终止: $session_name" || msg_err "终止失败"
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
    msg_title "Tmux 管理"
    msg ""
    if command -v tmux &>/dev/null; then
      msg "  Tmux: $(tmux -V 2>&1)"
      tmux ls 2>/dev/null | while read -r line; do
        msg "  $line"
      done || msg "  暂无会话"
    else
      msg "  Tmux 未安装"
    fi
    msg ""
    msg "  1) 安装 Tmux"
    msg "  2) 创建新会话"
    msg "  3) 列出会话"
    msg "  4) 进入会话"
    msg "  5) 终止会话"
    msg "  0) 返回"
    read -p "请选择: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
    msg_err "编号必须是 1-10（或 w1-w10）: $1"
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
  msg_err "编号工作区需要 tmux 或 screen，二者均未安装"
  msg_info "安装方式: $(_pkg_install_hint tmux)  或  $(_pkg_install_hint screen)"
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
      msg_info "$dir_name 不存在，正在创建…"
      _ws_slot_create "$dir_name" || { msg_err "$dir_name 创建失败"; return 1; }
    fi
    _ws_slot_attach "$dir_name"
    return $?
  fi

  case "$action" in
    list)
      local i name state
      msg "  ${F_BOLD}编号工作区 ($tool):${F_RESET}"
      for i in 1 2 3 4 5 6 7 8 9 10; do
        name="w$i"
        if _ws_slot_exists "$name"; then
          state="${F_GREEN}运行中${F_RESET}"
        else
          state="空闲"
        fi
        msg "    $name: $state"
      done
      msg "  进入: fusionbox ws w3   （固定槽位，无需查找 PID）"
      ;;
    new)
      local n="${2:-}" cmd="${3:-}" name
      name=$(_ws_work_name "$n") || return 1
      if _ws_slot_exists "$name"; then
        msg_err "$name 已存在（attach 进入或 kill 后重建）"
        return 1
      fi
      if _ws_slot_create "$name" "$cmd"; then
        if [[ -n "$cmd" ]]; then
          msg_ok "$name 已创建并执行: $cmd"
        else
          msg_ok "$name 已创建"
        fi
      else
        msg_err "$name 创建失败"
        return 1
      fi
      ;;
    attach)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if ! _ws_slot_exists "$name"; then
        msg_err "$name 不存在（workspace work new $n 创建）"
        return 1
      fi
      _ws_slot_attach "$name"
      ;;
    send|say)
      local n="${2:-}" cmd="${3:-}" name
      name=$(_ws_work_name "$n") || return 1
      [[ -n "$cmd" ]] || { msg_err "用法: fusionbox ws w<编号> send <命令>"; return 2; }
      if ! _ws_slot_exists "$name"; then
        msg_err "$name 不存在"
        return 1
      fi
      _ws_slot_send "$name" "$cmd" && msg_ok "已注入 $name: $cmd"
      ;;
    capture|peek|log)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if ! _ws_slot_exists "$name"; then
        msg_err "$name 不存在"
        return 1
      fi
      if command -v tmux &>/dev/null; then
        tmux capture-pane -p -t "$name" | tail -n 40
      else
        msg_warn "screen 后端无法读取回显；请直接进入: fusionbox ws $name"
      fi
      ;;
    kill)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      if confirm "确认终止 $name（其中进程全部退出）？"; then
        _ws_slot_kill "$name" && msg_ok "$name 已终止" || msg_err "$name 不存在"
      fi
      ;;
    ensure|resume)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      _ws_slot_ensure "$name" 1 || { msg_err "$name 创建失败"; return 1; }
      msg_ok "$name 已就绪，进入后断线重连只需再次执行 fusionbox ws $name"
      _ws_slot_attach "$name"
      ;;
    ssh)
      local n="${2:-}" name
      name=$(_ws_work_name "$n") || return 1
      _ws_slot_ensure "$name" 1 || { msg_err "$name 创建失败"; return 1; }
      msg_title "$name 常驻会话"
      msg "  从任意 SSH 终端重连进入该槽位："
      msg "    fusionbox ws $name"
      msg "  或直接使用 tmux/screen 原生命令："
      if command -v tmux &>/dev/null; then
        msg "    tmux attach -t $name"
      else
        msg "    screen -r $name"
      fi
      msg "  会话在 SSH 断开后继续运行；重新登录后按上面命令即可回到原状态。"
      ;;
    menu|"")
      workspace_work_menu
      ;;
    *)
      msg_err "未知子命令: $action（可用: list/new/attach/ensure/ssh/send/capture/kill，或直接写 w1-w10）"; return 2 ;;
  esac
}

workspace_work_menu() {
  while true; do
    clear
    _print_banner
    msg_title "编号工作区"
    msg ""
    workspace_work list
    msg ""
    msg "  1) 新建编号槽位 (可附带首条命令)"
    msg "  2) 进入编号槽位 (也可直接 fusionbox ws w3；不存在会自动创建)"
    msg "  3) 向槽位注入命令"
    msg "  4) 查看槽位回显 (tmux，末尾 40 行)"
    msg "  5) 终止槽位"
    msg "  6) 常驻会话/SSH 重连说明"
    msg "  0) 返回"
    read -p "请选择: " w_choice || { msg ""; return; }
    case "$w_choice" in
      1) read -p "编号 (1-10): " w_n; read -p "首条命令（留空为空 shell）: " w_c
         if [[ -n "$w_c" ]]; then workspace_work new "$w_n" "$w_c" || true; else workspace_work new "$w_n" || true; fi ;;
      2) read -p "编号 (1-10): " w_n; workspace_work attach "$w_n" ;;
      3) read -p "编号 (1-10 或 w1-w10): " w_n; read -p "要注入的命令: " w_c; workspace_work send "$w_n" "$w_c" ;;
      4) read -p "编号 (1-10 或 w1-w10): " w_n; workspace_work capture "$w_n"; pause ;;
      5) read -p "编号 (1-10 或 w1-w10): " w_n; workspace_work kill "$w_n" ;;
      6) read -p "编号 (1-10 或 w1-w10): " w_n; workspace_work ssh "$w_n"; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ---- 列出所有后台会话 ----
workspace_list() {
  msg_title "后台工作区"
  msg ""
  if command -v screen &>/dev/null; then
    msg "  ${F_BOLD}Screen 会话:${F_RESET}"
    screen -ls 2>/dev/null | while read -r line; do
      [[ "$line" == *"No Sockets"* ]] && msg "    暂无" || msg "    $line"
    done || msg "    暂无"
  fi
  msg ""
  if command -v tmux &>/dev/null; then
    msg "  ${F_BOLD}Tmux 会话:${F_RESET}"
    tmux ls 2>/dev/null | while read -r line; do
      msg "    $line"
    done || msg "    暂无"
  fi
  pause
}

# ---- Help ----
workspace_help() {
  msg_title "后台工作区 帮助"
  msg ""
  msg "  fusionbox workspace work        编号工作区 w1-w10（tmux/screen 自动选择）"
  msg "  fusionbox ws w3                  直接进入 3 号槽位（固定槽位，不用记 PID）"
  msg "  fusionbox ws w3 ensure           确保 3 号槽位存在并进入（断线重连）"
  msg "  fusionbox ws w3 ssh              打印 3 号槽位在 SSH 重连时的进入方法"
  msg "  fusionbox ws w3 send 'make'      向 3 号槽位注入命令"
  msg "  fusionbox ws w3 capture          查看 3 号槽位最近回显（tmux）"
  msg "  fusionbox workspace screen       Screen 会话管理"
  msg "  fusionbox workspace tmux         Tmux 会话管理"
  msg "  fusionbox workspace list         列出所有后台会话"
  msg ""
  msg "  ${F_BOLD}快捷命令:${F_RESET}"
  msg "  screen -S <name>                 创建 screen 会话"
  msg "  screen -r <name>                 恢复 screen 会话"
  msg "  tmux new -s <name>               创建 tmux 会话"
  msg "  tmux attach -t <name>            恢复 tmux 会话"
  msg ""
}

# ---- Interactive Menu ----
workspace_menu() {
  while true; do
    clear
    _print_banner
    msg_title "后台工作区"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) Screen 管理"
    msg "  ${F_GREEN}2${F_RESET}) Tmux 管理"
    msg "  ${F_GREEN}3${F_RESET}) 列出所有后台会话"
    msg "  ${F_GREEN}4${F_RESET}) 编号工作区 w1-w10（重连用 fusionbox ws w3）"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-4]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) workspace_screen_menu ;;
      2) workspace_tmux_menu ;;
      3) workspace_list ;;
      4) workspace_work_menu ;;
      0) break ;;
    esac
  done
}
