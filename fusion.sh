#!/bin/bash
# FusionBox - Ultimate Linux Management Script
# Repository: https://github.com/fusionbox/fusionbox

[[ $EUID -ne 0 ]] && echo "Root required" && exit 1

export FUSION_BASE="$(cd "$(dirname "$0")" && pwd)"
export FUSION_SRC="$FUSION_BASE/src"

. "$FUSION_SRC/init.sh"

# ---- Command Router ----
# Routes user commands to the appropriate module

route() {
  local cmd="$1"; shift || true

  case "$cmd" in
    # Proxy module (sing-box management)
    proxy|p|sb|sing-box)
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
      msg "$(tr MSG_VERSION "Version"): $FUSION_VER"
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
      msg_err "$(tr MSG_ERROR "Unknown command"): $cmd"
      msg_info "$(tr MSG_INFO "Use"): fusionbox help"
      return 1
      ;;
  esac
}

# ---- Status Overview ----
show_status() {
  _print_banner
  msg_title "$(tr SYS_INFO "System Status Overview")"
  msg ""
  msg "  ${F_BOLD}CPU:${F_RESET} $(nproc --all) cores | $(free -h | awk '/Mem/{print $2}') RAM"
  msg "  ${F_BOLD}Disk:${F_RESET} $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
  msg "  ${F_BOLD}Kernel:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}OS:${F_RESET} $F_OS_NAME $F_OS_VER"
  msg ""

  # Check proxy status
  local proxy_status="$PROXY_STOPPED"
  if command -v sing-box &>/dev/null; then
    if pgrep -x "sing-box" &>/dev/null; then
      proxy_status="$PROXY_RUNNING"
    else
      proxy_status="$PROXY_STOPPED"
    fi
  else
    proxy_status="$PROXY_NOT_INSTALLED"
  fi
  _module_status "$(tr MOD_PROXY "Proxy")" "$proxy_status"

  # Check BBR
  local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  _module_status "$(tr SYS_BBR "BBR")" "$bbr_status"

  # Check Docker
  if command -v docker &>/dev/null; then
    _module_status "$(tr PANEL_DOCKER "Docker")" "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "not running")"
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
  msg_info "$(tr MSG_INFO "Checking for updates...")"
  _download "https://raw.githubusercontent.com/fusionbox/fusionbox/main/version.txt" /tmp/fusionbox_ver
  if [[ -f /tmp/fusionbox_ver ]]; then
    local remote_ver=$(cat /tmp/fusionbox_ver | tr -d ' \n')
    if [[ "$remote_ver" != "$FUSION_VER" && -n "$remote_ver" ]]; then
      msg_info "New version $remote_ver available. Updating..."
      local tmpdir=$(mktemp -d)
      _download "https://github.com/fusionbox/fusionbox/archive/main.tar.gz" "$tmpdir/fusionbox.tar.gz"
      if [[ -f "$tmpdir/fusionbox.tar.gz" ]]; then
        tar xzf "$tmpdir/fusionbox.tar.gz" -C "$tmpdir"
        cp -rf "$tmpdir/fusionbox-main/"* "$FUSION_BASE/"
        msg_ok "$(tr MSG_DONE "Update completed")"
      else
        msg_err "$(tr MSG_ERROR "Download failed")"
      fi
      rm -rf "$tmpdir"
    else
      msg_ok "$(tr MSG_OK "Already up to date")"
    fi
  else
    msg_warn "$(tr MSG_WARN "Cannot check for updates (offline)")"
  fi
}

# ---- Help ----
show_help() {
  _print_banner
  msg_title "FusionBox Help"
  msg ""
  msg "  ${F_BOLD}Usage:${F_RESET} fusionbox <command> [options]"
  msg ""
  msg "  ${F_BOLD}Modules:${F_RESET}"
  msg "  ${F_GREEN}proxy, p${F_RESET}        $(tr MOD_PROXY "Proxy Management") - sing-box proxy manager"
  msg "  ${F_GREEN}system, sys${F_RESET}      $(tr MOD_SYSTEM "System Management") - BBR, benchmark, backup"
  msg "  ${F_GREEN}network, net${F_RESET}     $(tr MOD_NETWORK "Network Tools") - IP, streaming, speedtest"
  msg "  ${F_GREEN}web${F_RESET}              $(tr MOD_WEB "Web/LNMP Deployment") - LNMP, websites, SSL"
  msg "  ${F_GREEN}panels, tools${F_RESET}    $(tr MOD_PANELS "Panel & Tools") - Docker, panels, utilities"
  msg "  ${F_GREEN}market${F_RESET}           $(tr MOD_MARKET "App Market") - one-click app installation"
  msg ""
  msg "  ${F_BOLD}Commands:${F_RESET}"
  msg "  ${F_GREEN}status${F_RESET}            System status overview"
  msg "  ${F_GREEN}update${F_RESET}            Update FusionBox itself"
  msg "  ${F_GREEN}version${F_RESET}           Show version"
  msg "  ${F_GREEN}help${F_RESET}              Show this help"
  msg ""
  msg "  ${F_BOLD}Examples:${F_RESET}"
  msg "  fusionbox proxy add reality    # Add VLESS-REALITY proxy"
  msg "  fusionbox system bbr           # Enable BBR"
  msg "  fusionbox network speedtest    # Run speedtest"
  msg "  fusionbox web lnmp             # Install LNMP"
  msg "  fusionbox panels docker        # Docker management"
  msg ""

  # Quick reference per module
  local mod="${1:-all}"
  if [[ "$mod" == "all" ]]; then
    msg "  ${F_BOLD}Tip:${F_RESET} fusionbox help <module> for detailed module help"
  fi
  pause
}

# ---- Main Menu ----
main_menu() {
  _print_banner

  msg_title "$(tr MSG_SELECT "Main Menu")"
  msg ""
  msg "  ${F_GREEN}1${F_RESET}) $(tr MOD_PROXY "Proxy Management")"
  msg "  ${F_GREEN}2${F_RESET}) $(tr MOD_SYSTEM "System Management")"
  msg "  ${F_GREEN}3${F_RESET}) $(tr MOD_NETWORK "Network Tools")"
  msg "  ${F_GREEN}4${F_RESET}) $(tr MOD_WEB "Web/LNMP Deployment")"
  msg "  ${F_GREEN}5${F_RESET}) $(tr MOD_PANELS "Panel & Tools")"
  msg "  ${F_GREEN}6${F_RESET}) $(tr MOD_MARKET "App Market")"
  msg "  ${F_GREEN}7${F_RESET}) $(tr SYS_INFO "System Status")"
  msg "  ${F_GREEN}8${F_RESET}) $(tr MSG_INFO "Help")"
  msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Exit")"
  msg ""

  read -p "$(tr MSG_SELECT "Please select") [0-8]: " main_choice

  case "$main_choice" in
    1) route proxy ;;
    2) route system ;;
    3) route network ;;
    4) route web ;;
    5) route panels ;;
    6) route market ;;
    7) show_status ;;
    8) show_help ;;
    0) msg "$(tr MSG_EXIT "Goodbye")"; _log_write "FusionBox session ended"; exit 0 ;;
    *) main_menu ;;
  esac
}

# ---- Entry ----
_log_write "FusionBox v$FUSION_VER started with args: $*"

# Route the command
route "$@"

# If route returns without looping, show main menu
[[ $# -eq 0 ]] && main_menu
