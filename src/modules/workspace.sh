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
    *)               workspace_menu ;;
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

# ---- 编号工作区 (G62)：work1-10 常驻 tmux 会话，支持命令注入与重连 ----
_ws_work_check_n() {
  [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 10 ] || {
    msg_err "编号必须是 1-10: $1"
    return 1
  }
}

_ws_work_tool() {
  if command -v tmux &>/dev/null; then
    printf tmux
    return 0
  fi
  msg_err "tmux 未安装（workspace work 需要 tmux）"
  return 1
}

workspace_work() {
  _require_root
  local action="${1:-menu}"
  local tool; tool=$(_ws_work_tool) || return 1

  case "$action" in
    list)
      local i state
      msg "  ${F_BOLD}编号工作区 (tmux):${F_RESET}"
      for i in 1 2 3 4 5 6 7 8 9 10; do
        if tmux has-session -t "work$i" 2>/dev/null; then
          state="${F_GREEN}运行中${F_RESET}"
        else
          state="空闲"
        fi
        msg "    work$i: $state"
      done
      ;;
    new)
      local n="${2:-}" cmd="${3:-}"
      _ws_work_check_n "$n" || return 1
      if tmux has-session -t "work$n" 2>/dev/null; then
        msg_err "work$n 已存在（attach 进入或 kill 后重建）"
        return 1
      fi
      if [[ -n "$cmd" ]]; then
        tmux new-session -d -s "work$n" "$cmd" && msg_ok "work$n 已创建并执行: $cmd"
      else
        tmux new-session -d -s "work$n" && msg_ok "work$n 已创建"
      fi
      ;;
    attach)
      local n="${2:-}"
      _ws_work_check_n "$n" || return 1
      if ! tmux has-session -t "work$n" 2>/dev/null; then
        msg_err "work$n 不存在（workspace work new $n 创建）"
        return 1
      fi
      tmux attach -t "work$n"
      ;;
    send)
      local n="${2:-}" cmd="${3:-}"
      _ws_work_check_n "$n" || return 1
      [[ -n "$cmd" ]] || { msg_err "用法: workspace work send <编号> <命令>"; return 2; }
      if ! tmux has-session -t "work$n" 2>/dev/null; then
        msg_err "work$n 不存在"
        return 1
      fi
      tmux send-keys -t "work$n" "$cmd" C-m && msg_ok "已注入 work$n: $cmd"
      ;;
    kill)
      local n="${2:-}"
      _ws_work_check_n "$n" || return 1
      if confirm "确认终止 work$n（其中进程全部退出）？"; then
        tmux kill-session -t "work$n" 2>/dev/null && msg_ok "work$n 已终止" || msg_err "work$n 不存在"
      fi
      ;;
    menu|"")
      workspace_work_menu
      ;;
    *)
      msg_err "未知子命令: $action（可用: list/new/attach/send/kill）"; return 2 ;;
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
    msg "  1) 新建编号会话 (可附带首条命令)"
    msg "  2) 进入编号会话"
    msg "  3) 向会话注入命令"
    msg "  4) 终止会话"
    msg "  0) 返回"
    read -p "请选择: " w_choice || { msg ""; return; }
    case "$w_choice" in
      1) read -p "编号 (1-10): " w_n; read -p "首条命令（留空为空 shell）: " w_c
         if [[ -n "$w_c" ]]; then workspace_work new "$w_n" "$w_c" || true; else workspace_work new "$w_n" || true; fi ;;
      2) read -p "编号 (1-10): " w_n; workspace_work attach "$w_n" ;;
      3) read -p "编号 (1-10): " w_n; read -p "要注入的命令: " w_c; workspace_work send "$w_n" "$w_c" ;;
      4) read -p "编号 (1-10): " w_n; workspace_work kill "$w_n" ;;
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
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-3]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) workspace_screen_menu ;;
      2) workspace_tmux_menu ;;
      3) workspace_list ;;
      0) break ;;
    esac
  done
}
