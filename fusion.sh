#!/bin/bash
# FusionBox - Ultimate Linux Management Script
# Repository: https://github.com/fusionbox/fusionbox

[[ $EUID -ne 0 ]] && echo "需要 root 权限" && exit 1

export FUSION_BASE="$(cd "$(dirname "$0")" && pwd)"
export FUSION_SRC="$FUSION_BASE/src"

. "$FUSION_SRC/init.sh"

# ---- Command Router ----
# Routes user commands to the appropriate module

route() {
  local cmd="$1"; shift || true

  case "$cmd" in
    # Proxy module
    proxy|p)
      _load_module "proxy"
      proxy_main "$@"
      ;;
    # System management
    system|sys|s)
      _load_module "system"
      system_main "$@"
      ;;
    # Network tools
    network|net|n)
      _load_module "network"
      network_main "$@"
      ;;
    # Web/LNMP
    web|w|lnmp)
      _load_module "web"
      web_main "$@"
      ;;
    # Panels & Docker
    panels|panel|tools|t)
      _load_module "panels"
      panels_main "$@"
      ;;
    # App market
    market|m|apps)
      _load_module "market"
      market_main "$@"
      ;;
    # System commands
    status)
      show_status
      ;;
    version|v)
      msg "$FUSION_CODENAME v$FUSION_VER"
      msg "版本: $FUSION_VER"
      ;;
    update|up)
      self_update
      ;;
    help|h)
      show_help
      ;;
    # Interactive main menu (no args)
    menu|main)
      main_menu
      ;;
    "")
      main_menu
      ;;
    *)
      msg_err "未知命令: $cmd"
      msg_info "用法: fusionbox help"
      return 1
      ;;
  esac
}

# ---- Status Overview ----
show_status() {
  _print_banner
  msg_title "系统状态概览"
  msg ""
  msg "  ${F_BOLD}CPU:${F_RESET} $(nproc --all) cores | $(free -h | awk '/Mem/{print $2}') RAM"
  msg "  ${F_BOLD}Disk:${F_RESET} $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
  msg "  ${F_BOLD}Kernel:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}OS:${F_RESET} $F_OS_NAME $F_OS_VER"
  msg ""

  # Check proxy status
  local proxy_status="未安装"
  if [[ -f /etc/fusionbox/proxy/current_backend ]]; then
    if systemctl is-active fusionbox-proxy &>/dev/null; then
      proxy_status="运行中"
    else
      proxy_status="已停止"
    fi
  fi
  _module_status "代理管理" "$proxy_status"

  # Check BBR
  local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  _module_status "BBR" "$bbr_status"

  # Check Docker
  if command -v docker &>/dev/null; then
    _module_status "Docker" "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "未运行")"
  fi

  # Check Nginx
  if command -v nginx &>/dev/null; then
    _module_status "Nginx" "$(nginx -v 2>&1 | awk -F/ '{print $2}')"
  fi

  msg ""
  pause
}

# ---- Self Update ----
self_update() {
  msg_info "正在检查更新..."
  _download "https://raw.githubusercontent.com/fusionbox/fusionbox/main/version.txt" /tmp/fusionbox_ver
  if [[ -f /tmp/fusionbox_ver ]]; then
    local remote_ver=$(cat /tmp/fusionbox_ver | tr -d ' \n')
    if [[ "$remote_ver" != "$FUSION_VER" && -n "$remote_ver" ]]; then
      msg_info "发现新版本 $remote_ver，正在更新..."
      local tmpdir=$(mktemp -d)
      _download "https://github.com/fusionbox/fusionbox/archive/main.tar.gz" "$tmpdir/fusionbox.tar.gz"
      if [[ -f "$tmpdir/fusionbox.tar.gz" ]]; then
        tar xzf "$tmpdir/fusionbox.tar.gz" -C "$tmpdir"
        cp -rf "$tmpdir/fusionbox-main/"* "$FUSION_BASE/"
        msg_ok "更新完成"
      else
        msg_err "下载失败"
      fi
      rm -rf "$tmpdir"
    else
      msg_ok "已是最新版本"
    fi
  else
    msg_warn "无法检查更新（离线）"
  fi
}

# ---- Help ----
show_help() {
  _print_banner
  msg_title "FusionBox 帮助"
  msg ""
  msg "  ${F_BOLD}用法:${F_RESET} fusionbox <命令> [选项]"
  msg ""
  msg "  ${F_BOLD}模块:${F_RESET}"
  msg "  ${F_GREEN}proxy, p${F_RESET}        代理管理 - 多后端代理管理"
  msg "  ${F_GREEN}system, sys${F_RESET}      系统管理 - BBR、基准测试、备份"
  msg "  ${F_GREEN}network, net${F_RESET}     网络工具 - IP、流媒体、测速"
  msg "  ${F_GREEN}web${F_RESET}              网站部署 - LNMP、网站、SSL"
  msg "  ${F_GREEN}panels, tools${F_RESET}    面板与工具 - Docker、面板、实用工具"
  msg "  ${F_GREEN}market${F_RESET}           应用市场 - 一键安装应用"
  msg ""
  msg "  ${F_BOLD}命令:${F_RESET}"
  msg "  ${F_GREEN}status${F_RESET}            系统状态概览"
  msg "  ${F_GREEN}update${F_RESET}            更新 FusionBox"
  msg "  ${F_GREEN}version${F_RESET}           显示版本"
  msg "  ${F_GREEN}help${F_RESET}              显示帮助"
  msg ""
  msg "  ${F_BOLD}示例:${F_RESET}"
  msg "  fusionbox proxy add              # 添加代理配置"
  msg "  fusionbox system bbr             # 启用 BBR"
  msg "  fusionbox network speedtest      # 网速测试"
  msg "  fusionbox web lnmp               # 安装 LNMP"
  msg "  fusionbox panels docker          # Docker 管理"
  msg ""

  # Quick reference per module
  local mod="${1:-all}"
  if [[ "$mod" == "all" ]]; then
    msg "  ${F_BOLD}提示:${F_RESET} fusionbox help <模块> 查看模块详细帮助"
  fi
  pause
}

# ---- Main Menu ----
main_menu() {
  _print_banner

  msg_title "主菜单"
  msg ""
  msg "  ${F_GREEN}1${F_RESET}) 代理管理"
  msg "  ${F_GREEN}2${F_RESET}) 系统管理"
  msg "  ${F_GREEN}3${F_RESET}) 网络工具"
  msg "  ${F_GREEN}4${F_RESET}) 网站部署"
  msg "  ${F_GREEN}5${F_RESET}) 面板与工具"
  msg "  ${F_GREEN}6${F_RESET}) 应用市场"
  msg "  ${F_GREEN}7${F_RESET}) 系统状态"
  msg "  ${F_GREEN}8${F_RESET}) 帮助"
  msg "  ${F_GREEN}0${F_RESET}) 退出"
  msg ""

  read -p "请选择 [0-8]: " main_choice

  case "$main_choice" in
    1) route proxy ;;
    2) route system ;;
    3) route network ;;
    4) route web ;;
    5) route panels ;;
    6) route market ;;
    7) show_status ;;
    8) show_help ;;
    0) msg "再见！"; _log_write "FusionBox 会话已结束"; break ;;
    *) main_menu ;;
  esac
}

# ---- Entry ----
_log_write "FusionBox v$FUSION_VER started with args: $*"

# Route the command
route "$@"
