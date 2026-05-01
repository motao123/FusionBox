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
    *)                warp_menu ;;
  esac
}

# ---- 安装 WARP ----
warp_install() {
  _require_root
  msg_title "安装 WARP"
  msg ""

  if systemctl is-active warp-svc &>/dev/null; then
    msg_ok "WARP 已安装并运行中"
    warp_status
    pause; return
  fi

  msg_info "正在安装 Cloudflare WARP..."

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
      msg_err "当前系统不支持自动安装 WARP"
      msg_info "请参考: https://pkg.cloudflareclient.com/"
      pause; return
      ;;
  esac

  if command -v warp-cli &>/dev/null || systemctl is-active warp-svc &>/dev/null; then
    msg_ok "WARP 安装完成"

    # Register
    msg_info "正在注册 WARP..."
    warp-cli --accept-tos registration new 2>/dev/null

    # Set default mode to proxy
    warp-cli --accept-tos mode proxy 2>/dev/null

    # 禁止自动连接（防止远程服务器SSH断开）
    if [[ -f /var/lib/cloudflare-warp/settings.json ]]; then
      python3 -c "import json; d=json.load(open('/var/lib/cloudflare-warp/settings.json')); d['always_on']=False; json.dump(d,open('/var/lib/cloudflare-warp/settings.json','w'),indent=2)" 2>/dev/null
    fi

    # 禁止开机自启
    systemctl disable warp-svc 2>/dev/null

    msg_ok "WARP 已注册，默认模式: Proxy (SOCKS5)"
    msg ""
    msg "  ${F_BOLD}SOCKS5 代理:${F_RESET} 127.0.0.1:40000"
    msg "  ${F_BOLD}提示:${F_RESET} 使用 'fusionbox warp on' 开启"
    _log_write "WARP 已安装"
  else
    msg_err "WARP 安装失败"
  fi
  pause
}

# ---- 卸载 WARP ----
warp_uninstall() {
  _require_root
  if ! command -v warp-cli &>/dev/null && ! systemctl is-active warp-svc &>/dev/null; then
    msg_warn "WARP 未安装"
    pause; return
  fi

  if confirm "确认卸载 WARP？"; then
    warp-cli --accept-tos disconnect 2>/dev/null
    warp-cli --accept-tos registration delete 2>/dev/null
    case "$F_PKG_MGR" in
      apt) apt-get remove -y cloudflare-warp 2>/dev/null ;;
      yum) yum remove -y cloudflare-warp 2>/dev/null ;;
    esac
    msg_ok "WARP 已卸载"
    _log_write "WARP 已卸载"
  fi
  pause
}

# ---- WARP 状态 ----
warp_status() {
  msg ""
  if command -v warp-cli &>/dev/null; then
    msg "  ${F_BOLD}WARP 版本:${F_RESET} $(warp-cli --accept-tos --version 2>/dev/null)"
    local reg_status=$(warp-cli --accept-tos registration show 2>/dev/null | head -1)
    msg "  ${F_BOLD}注册状态:${F_RESET} ${reg_status:-未注册}"
    local conn_status=$(warp-cli --accept-tos status 2>/dev/null | head -1)
    msg "  ${F_BOLD}连接状态:${F_RESET} ${conn_status:-未连接}"
    local warp_mode=$(warp-cli --accept-tos settings 2>/dev/null | grep -i mode | awk '{print $NF}')
    msg "  ${F_BOLD}当前模式:${F_RESET} ${warp_mode:-未知}"
  else
    msg "  WARP 未安装"
  fi
}

# ---- 开启 WARP ----
warp_on() {
  _require_root
  if ! command -v warp-cli &>/dev/null; then
    msg_err "WARP 未安装，请先安装"
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
    msg_ok "WARP 已开启 (Proxy 模式)"
    msg "  ${F_BOLD}SOCKS5 代理:${F_RESET} 127.0.0.1:40000"

    # Test IP
    warp_ip
  else
    msg_warn "WARP 状态: $status"
  fi
  _log_write "WARP 已开启"
  pause
}

# ---- 关闭 WARP ----
warp_off() {
  _require_root
  warp-cli --accept-tos disconnect 2>/dev/null
  msg_ok "WARP 已关闭"
  _log_write "WARP 已关闭"
  pause
}

# ---- 切换模式 ----
warp_mode() {
  _require_root
  if ! command -v warp-cli &>/dev/null; then
    msg_err "WARP 未安装"
    pause; return
  fi

  msg_title "WARP 模式切换"
  msg ""
  local current_mode=$(warp-cli --accept-tos settings 2>/dev/null | grep -i mode | awk '{print $NF}')
  msg "  ${F_BOLD}当前模式:${F_RESET} ${current_mode:-未知}"
  msg ""
  msg "  ${F_GREEN}1${F_RESET}) WARP 模式 (全局代理，所有流量经过 WARP)"
  msg "  ${F_GREEN}2${F_RESET}) Proxy 模式 (SOCKS5 代理，手动配置)"
  msg "  ${F_GREEN}3${F_RESET}) DoH 模式 (仅 DNS over HTTPS)"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择: " mode_choice

  case "$mode_choice" in
    1)
      warp-cli --accept-tos mode warp 2>/dev/null
      msg_ok "已切换到 WARP 模式（全局代理）"
      msg_warn "所有流量将经过 Cloudflare WARP"
      ;;
    2)
      warp-cli --accept-tos mode proxy 2>/dev/null
      msg_ok "已切换到 Proxy 模式"
      msg "  SOCKS5 代理地址: 127.0.0.1:40000"
      ;;
    3)
      warp-cli --accept-tos mode doh 2>/dev/null
      msg_ok "已切换到 DoH 模式"
      ;;
    0) return ;;
  esac
  _log_write "WARP 模式已切换为 $mode_choice"
  pause
}

# ---- 查看 IP ----
warp_ip() {
  msg ""
  msg_info "正在检测 IP..."
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

  msg "  ${F_BOLD}原始 IP:${F_RESET} ${real_ip:-未知}"
  if [[ -n "$warp_ip_check" ]]; then
    msg "  ${F_BOLD}WARP IP:${F_RESET} ${warp_ip_check:-未知}"
    if [[ "$real_ip" != "$warp_ip_check" && -n "$warp_ip_check" ]]; then
      msg "  ${F_GREEN}IP 已通过 WARP 隐藏${F_RESET}"
    fi
  fi

  # Check streaming unlock
  msg ""
  msg_info "正在检测流媒体解锁..."
  local cf_trace=$(curl -s4 --connect-timeout 5 "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null)
  local warp_status=$(echo "$cf_trace" | grep "warp=" | cut -d= -f2)
  msg "  Cloudflare WARP 状态: ${warp_status:-N/A}"
}

# ---- WARP 代理配置 ----
warp_proxy() {
  _require_root
  msg_title "WARP 代理配置"
  msg ""

  if ! warp-cli --accept-tos status 2>/dev/null | grep -qi "connected"; then
    msg_warn "WARP 未连接"
    if confirm "是否开启 WARP？"; then
      warp-cli --accept-tos connect 2>/dev/null
      sleep 2
    fi
  fi

  msg "  ${F_BOLD}WARP Proxy 信息:${F_RESET}"
  msg "  类型: SOCKS5"
  msg "  地址: 127.0.0.1:40000"
  msg ""
  msg "  ${F_BOLD}使用场景:${F_RESET}"
  msg "  1. 代理程序的出站流量通过 WARP 解锁"
  msg "  2. 浏览器配置 SOCKS5 代理: 127.0.0.1:40000"
  msg "  3. curl --socks5 127.0.0.1:40000 https://example.com"
  msg ""
  msg "  ${F_BOLD}代理程序配置示例:${F_RESET}"
  msg ""
  msg "  ${F_CYAN}Xray-core 出站配置:${F_RESET}"
  msg '  {'
  msg '    "protocol": "socks",'
  msg '    "settings": {"servers": [{"address": "127.0.0.1", "port": 40000}]}'
  msg '  }'
  msg ""
  msg "  ${F_CYAN}sing-box 出站配置:${F_RESET}"
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
  msg_title "WARP 管理 帮助"
  msg ""
  msg "  fusionbox warp install          安装 WARP"
  msg "  fusionbox warp uninstall        卸载 WARP"
  msg "  fusionbox warp status           查看 WARP 状态"
  msg "  fusionbox warp on               开启 WARP"
  msg "  fusionbox warp off              关闭 WARP"
  msg "  fusionbox warp mode             切换模式 (WARP/Proxy/DoH)"
  msg "  fusionbox warp ip               查看 WARP IP 和流媒体解锁"
  msg "  fusionbox warp proxy            查看代理配置信息"
  msg ""
  msg "  ${F_BOLD}模式说明:${F_RESET}"
  msg "  WARP    - 全局代理，所有流量经过 Cloudflare"
  msg "  Proxy   - SOCKS5 代理 (127.0.0.1:40000)，手动配置使用"
  msg "  DoH     - 仅 DNS over HTTPS"
  msg ""
}

# ---- Interactive Menu ----
warp_menu() {
  while true; do
    clear
    _print_banner
    msg_title "WARP 管理"
    msg ""
    warp_status
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 安装 WARP"
    msg "  ${F_GREEN}2${F_RESET}) 卸载 WARP"
    msg "  ${F_GREEN}3${F_RESET}) 开启 WARP"
    msg "  ${F_GREEN}4${F_RESET}) 关闭 WARP"
    msg "  ${F_GREEN}5${F_RESET}) 切换模式"
    msg "  ${F_GREEN}6${F_RESET}) 查看 IP / 流媒体解锁"
    msg "  ${F_GREEN}7${F_RESET}) 代理配置说明"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-7]: " choice
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
