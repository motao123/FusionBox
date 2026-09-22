# FusionBox WARP 管理模块
# Cloudflare WARP 安装、配置、管理

warp_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    install|in)       warp_install "$@" ;;
    uninstall|rm)     warp_uninstall "$@" ;;
    status|st)        warp_status "$@" ;;
    on)               warp_on "$@" ;;
    off)              warp_off "$@" ;;
    mode)             warp_mode "$@" ;;
    ip)               warp_ip "$@" ;;
    proxy)            warp_proxy "$@" ;;
    menu|main)        warp_menu ;;
    help|h)           warp_help ;;
    *)                _module_unknown_cmd "warp" "$cmd" ;;
  esac
}

# ---- 安装 WARP ----
warp_install() {
  _require_root
  msg_title "$(L MSG_WARP_0001)"
  msg ""

  if systemctl is-active warp-svc &>/dev/null; then
    msg_ok "$(L MSG_WARP_0002)"
    warp_status
    pause; return
  fi

  msg_info "$(L MSG_WARP_0003)"

  # Detect package manager and add repo
  case "$F_PKG_MGR" in
    apt)
      _install_pkg gnupg2
      curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg 2>/dev/null | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null
      echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflare-client.list
      apt-get update -y
      _install_pkg cloudflare-warp
      ;;
    yum)
      rpm -ivh https://pkg.cloudflareclient.com/cloudflare-release-el8.rpm 2>/dev/null || \
      curl -fsSL https://pkg.cloudflareclient.com/cloudflare-ascii.repo -o /etc/yum.repos.d/cloudflare.repo
      _install_pkg cloudflare-warp
      ;;
    *)
      msg_err "$(L MSG_WARP_0004)"
      msg_info "$(L MSG_WARP_0005)"
      pause; return
      ;;
  esac

  if command -v warp-cli &>/dev/null || systemctl is-active warp-svc &>/dev/null; then
    msg_ok "$(L MSG_WARP_0006)"

    msg_info "$(L MSG_WARP_0007)"
    if ! warp-cli --accept-tos registration new 2>/dev/null; then
      # warp-cli 注册失败不再静默（旧版误报"安装完成"）
      msg_warn "$(L MSG_WARP_0008)"
    fi

    # Set default mode to proxy
    warp-cli --accept-tos mode proxy 2>/dev/null

    # 禁止自动连接（防止远程服务器SSH断开）
    if [[ -f /var/lib/cloudflare-warp/settings.json ]]; then
      python3 -c "import json; d=json.load(open('/var/lib/cloudflare-warp/settings.json')); d['always_on']=False; json.dump(d,open('/var/lib/cloudflare-warp/settings.json','w'),indent=2)" 2>/dev/null
    fi

    # 禁止开机自启
    systemctl disable warp-svc 2>/dev/null

    msg_ok "$(L MSG_WARP_0009)"
    msg ""
    msg "$(L MSG_WARP_0010 "${F_BOLD}" "${F_RESET}")"
    msg "$(L MSG_WARP_0011 "${F_BOLD}" "${F_RESET}")"
    _log_write "$(L MSG_WARP_0012)"
  else
    msg_err "$(L MSG_WARP_0013)"
  fi
  pause
}

# ---- 卸载 WARP ----
warp_uninstall() {
  _require_root
  if ! command -v warp-cli &>/dev/null && ! systemctl is-active warp-svc &>/dev/null; then
    msg_warn "$(L MSG_WARP_0014)"
    pause; return
  fi

  if confirm "$(L MSG_WARP_0015)"; then
    warp-cli --accept-tos disconnect 2>/dev/null
    warp-cli --accept-tos registration delete 2>/dev/null
    case "$F_PKG_MGR" in
      apt) apt-get remove -y cloudflare-warp 2>/dev/null ;;
      yum) yum remove -y cloudflare-warp 2>/dev/null ;;
    esac
    msg_ok "$(L MSG_WARP_0016)"
    _log_write "$(L MSG_WARP_0016)"
  fi
  pause
}

# ---- WARP 状态 ----
warp_status() {
  msg ""
  if command -v warp-cli &>/dev/null; then
    msg "$(L MSG_WARP_0017 "${F_BOLD}" "${F_RESET}" "$(warp-cli --accept-tos --version 2>/dev/null)")"
    local reg_status=$(warp-cli --accept-tos registration show 2>/dev/null | head -1)
    msg "$(L MSG_WARP_0018 "${F_BOLD}" "${F_RESET}" "${reg_status:-未注册}")"
    local conn_status=$(warp-cli --accept-tos status 2>/dev/null | head -1)
    msg "$(L MSG_WARP_0019 "${F_BOLD}" "${F_RESET}" "${conn_status:-未连接}")"
    local warp_mode=$(warp-cli --accept-tos settings 2>/dev/null | grep -i mode | awk '{print $NF}')
    msg "$(L MSG_WARP_0020 "${F_BOLD}" "${F_RESET}" "${warp_mode:-未知}")"
  else
    msg "$(L MSG_WARP_0021)"
  fi
}

# ---- 开启 WARP ----
warp_on() {
  _require_root
  if ! command -v warp-cli &>/dev/null; then
    msg_err "$(L MSG_WARP_0022)"
    pause; return
  fi

  # 确保 always_on 为 false（防止自动连接导致SSH断开）
  if [[ -f /var/lib/cloudflare-warp/settings.json ]]; then
    python3 -c "import json; d=json.load(open('/var/lib/cloudflare-warp/settings.json')); d['always_on']=False; json.dump(d,open('/var/lib/cloudflare-warp/settings.json','w'),indent=2)" 2>/dev/null
  fi

  # 启动 WARP 服务（如果未运行）
  if ! systemctl is-active warp-svc &>/dev/null; then
    systemctl start warp-svc 2>/dev/null
    sleep 2
  fi

  # 强制使用 Proxy 模式（防止全局模式断开SSH）
  warp-cli --accept-tos mode proxy 2>/dev/null
  sleep 1

  warp-cli --accept-tos connect 2>/dev/null
  sleep 3
  local status=$(warp-cli --accept-tos status 2>/dev/null | head -1)
  if echo "$status" | grep -qi "connected"; then
    msg_ok "$(L MSG_WARP_0023)"
    msg "$(L MSG_WARP_0010 "${F_BOLD}" "${F_RESET}")"

    # Test IP
    warp_ip
  else
    msg_warn "$(L MSG_WARP_0024 "$status")"
  fi
  _log_write "$(L MSG_WARP_0025)"
  pause
}

# ---- 关闭 WARP ----
warp_off() {
  _require_root
  warp-cli --accept-tos disconnect 2>/dev/null
  msg_ok "$(L MSG_WARP_0026)"
  _log_write "$(L MSG_WARP_0026)"
  pause
}

# ---- 切换模式 ----
warp_mode() {
  _require_root
  if ! command -v warp-cli &>/dev/null; then
    msg_err "$(L MSG_WARP_0014)"
    pause; return
  fi

  msg_title "$(L MSG_WARP_0027)"
  msg ""
  local current_mode=$(warp-cli --accept-tos settings 2>/dev/null | grep -i mode | awk '{print $NF}')
  msg "$(L MSG_WARP_0020 "${F_BOLD}" "${F_RESET}" "${current_mode:-未知}")"
  msg ""
  msg "$(L MSG_WARP_0028 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WARP_0029 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WARP_0030 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WARP_0031 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_WARP_0032)" mode_choice

  case "$mode_choice" in
    1)
      msg_warn "$(L MSG_WARP_0033)"
      if confirm "$(L MSG_WARP_0034)"; then
        warp-cli --accept-tos mode warp 2>/dev/null
        msg_ok "$(L MSG_WARP_0035)"
        _log_write "$(L MSG_WARP_0036)"
      else
        msg_info "$(L MSG_WARP_0037)"
      fi
      ;;
    2)
      warp-cli --accept-tos mode proxy 2>/dev/null
      msg_ok "$(L MSG_WARP_0038)"
      msg "$(L MSG_WARP_0039)"
      ;;
    3)
      warp-cli --accept-tos mode doh 2>/dev/null
      msg_ok "$(L MSG_WARP_0040)"
      ;;
    0) return ;;
  esac
  _log_write "$(L MSG_WARP_0041 "$mode_choice")"
  pause
}

# ---- 查看 IP ----
warp_ip() {
  msg ""
  msg_info "$(L MSG_WARP_0042)"
  local real_ip=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
  local warp_ip_check=""

  if warp-cli --accept-tos status 2>/dev/null | grep -qi "connected"; then
    # Test through WARP proxy
    local warp_mode=$(warp-cli --accept-tos settings 2>/dev/null | grep -i mode | awk '{print $NF}')
    if [[ "$warp_mode" == "warp_proxy" ]]; then
      warp_ip_check=$(curl -s4 --connect-timeout 5 --socks5-hostname 127.0.0.1:40000 https://api.ipify.org 2>/dev/null)
    else
      warp_ip_check=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null)
    fi
  fi

  msg "$(L MSG_WARP_0043 "${F_BOLD}" "${F_RESET}" "${real_ip:-未知}")"
  if [[ -n "$warp_ip_check" ]]; then
    msg "$(L MSG_WARP_0044 "${F_BOLD}" "${F_RESET}" "${warp_ip_check:-未知}")"
    if [[ "$real_ip" != "$warp_ip_check" && -n "$warp_ip_check" ]]; then
      msg "$(L MSG_WARP_0045 "${F_GREEN}" "${F_RESET}")"
    fi
  fi

  # Check streaming unlock
  msg ""
  msg_info "$(L MSG_WARP_0046)"
  local cf_trace=$(curl -s4 --connect-timeout 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
  local warp_status=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
  msg "$(L MSG_WARP_0047 "${warp_status:-N/A}")"
}

# ---- WARP 代理配置 ----
warp_proxy() {
  _require_root
  msg_title "$(L MSG_WARP_0048)"
  msg ""

  if ! warp-cli --accept-tos status 2>/dev/null | grep -qi "connected"; then
    msg_warn "$(L MSG_WARP_0049)"
    if confirm "$(L MSG_WARP_0050)"; then
      warp-cli --accept-tos connect 2>/dev/null
      sleep 2
    fi
  fi

  msg "$(L MSG_WARP_0051 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WARP_0052)"
  msg "$(L MSG_WARP_0053)"
  msg ""
  msg "$(L MSG_WARP_0054 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WARP_0055)"
  msg "$(L MSG_WARP_0056)"
  msg "  3. curl --socks5 127.0.0.1:40000 https://example.com"
  msg ""
  msg "$(L MSG_WARP_0057 "${F_BOLD}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WARP_0058 "${F_CYAN}" "${F_RESET}")"
  msg '  {'
  msg '    "protocol": "socks",'
  msg '    "settings": {"servers": [{"address": "127.0.0.1", "port": 40000}]}'
  msg '  }'
  msg ""
  msg "$(L MSG_WARP_0059 "${F_CYAN}" "${F_RESET}")"
  msg '  {'
  msg '    "type": "socks",'
  msg '    "server": "127.0.0.1",'
  msg '    "server_port": 40000'
  msg '  }'
  msg ""
  pause
}

# ---- Help ----
warp_help() {
  msg_title "$(L MSG_WARP_0060)"
  msg ""
  msg "$(L MSG_WARP_0061)"
  msg "$(L MSG_WARP_0062)"
  msg "$(L MSG_WARP_0063)"
  msg "$(L MSG_WARP_0064)"
  msg "$(L MSG_WARP_0065)"
  msg "$(L MSG_WARP_0066)"
  msg "$(L MSG_WARP_0067)"
  msg "$(L MSG_WARP_0068)"
  msg ""
  msg "$(L MSG_WARP_0069 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WARP_0070)"
  msg "$(L MSG_WARP_0071)"
  msg "$(L MSG_WARP_0072)"
  msg ""
}

# ---- Interactive Menu ----
warp_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_WARP_0073)"
    msg ""
    warp_status
    msg ""
    msg "$(L MSG_WARP_0074 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0075 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0076 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0077 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0078 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0079 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0080 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WARP_0081 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_WARP_0082)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) warp_install ;;
      2) warp_uninstall ;;
      3) warp_on ;;
      4) warp_off ;;
      5) warp_mode ;;
      6) warp_ip; pause ;;
      7) warp_proxy ;;
      0) break ;;
    esac
  done
}
