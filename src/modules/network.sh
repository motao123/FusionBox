# FusionBox Network Tools Module
# Network testing utilities

network_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    ip|myip)          network_ip ;;
    streaming|media)  network_streaming ;;
    speed|speedtest)  network_speedtest ;;
    dns)              network_dns "$@" ;;
    trace|traceroute) network_trace "$@" ;;
    ping)             network_ping "$@" ;;
    mtr)              network_mtr "$@" ;;
    port|portcheck)   network_port_check "$@" ;;
    menu|main)        network_menu ;;
    help|h)           network_help ;;
    *)                network_menu ;;
  esac
}

# ---- IP Query ----
network_ip() {
  msg_title "$(tr NET_IP "IP Address Query")"
  msg ""

  msg "  ${F_BOLD}IPv4:${F_RESET} ${F_CYAN}${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "N/A")}${F_RESET}"

  local ipv6; ipv6=$(curl -s6 --connect-timeout 5 ip.sb 2>/dev/null || echo "")
  if [[ -n "$ipv6" ]]; then
    msg "  ${F_BOLD}IPv6:${F_RESET} $ipv6"
  fi

  msg ""
  msg "  ${F_BOLD}[详细 IP 信息]${F_RESET}"
  local ip_info; ip_info=$(curl -s --connect-timeout 5 http://ip-api.com/json/ 2>/dev/null)
  if [[ -n "$ip_info" ]]; then
    local country;  country=$(echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    local region;   region=$(echo "$ip_info" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
    local city;     city=$(echo "$ip_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
    local isp;      isp=$(echo "$ip_info" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
    local org;      org=$(echo "$ip_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
    local as;       as=$(echo "$ip_info" | grep -o '"as":"[^"]*"' | cut -d'"' -f4)

    msg "    国家: ${country:-N/A}"
    msg "    地区: ${region:-N/A}"
    msg "    城市: ${city:-N/A}"
    msg "    ISP:  ${isp:-N/A}"
    msg "    组织: ${org:-N/A}"
    msg "    AS:   ${as:-N/A}"
  fi

  msg ""
  # Additional IP info
  if command -v curl &>/dev/null; then
    msg "  ${F_BOLD}[CDN / 网络信息]${F_RESET}"
    curl -s --connect-timeout 5 https://speed.cloudflare.com/meta 2>/dev/null | \
      grep -o '"colo":"[^"]*"' | cut -d'"' -f4 | xargs -I{} msg "    Cloudflare Colo: {}"
  fi

  pause
}

# ---- Streaming Test ----
network_streaming() {
  msg_title "$(tr NET_STREAMING "Streaming Test")"
  msg ""
  msg_info "正在测试流媒体服务可访问性..."
  msg ""

  # Netflix
  msg "  ${F_BOLD}Netflix:${F_RESET}"
  local netflix; netflix=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.netflix.com/title/80018499" 2>/dev/null)
  case "$netflix" in
    200|301|302) msg "    ${F_GREEN}可用${F_RESET}" ;;
    403)         msg "    ${F_YELLOW}检测到代理${F_RESET}" ;;
    *)           msg "    ${F_RED}不可用${F_RESET} (HTTP $netflix)" ;;
  esac

  # YouTube
  msg "  ${F_BOLD}YouTube:${F_RESET}"
  local yt; yt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.youtube.com" 2>/dev/null)
  [[ "$yt" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_YELLOW}受限${F_RESET}"

  # ChatGPT
  msg "  ${F_BOLD}ChatGPT:${F_RESET}"
  local cgpt; cgpt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://chat.openai.com" 2>/dev/null)
  [[ "$cgpt" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_RED}不可用${F_RESET}"

  # TikTok
  msg "  ${F_BOLD}TikTok:${F_RESET}"
  local tiktok; tiktok=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.tiktok.com" 2>/dev/null)
  [[ "$tiktok" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_YELLOW}可能受限${F_RESET}"

  # Disney+
  msg "  ${F_BOLD}Disney+:${F_RESET}"
  local disney; disney=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.disneyplus.com" 2>/dev/null)
  [[ "$disney" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_RED}不可用${F_RESET}"

  # Bilibili
  msg "  ${F_BOLD}Bilibili (HK/TW):${F_RESET}"
  local bili; bili=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.bilibili.com" 2>/dev/null)
  [[ "$bili" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_RED}不可用${F_RESET}"

  # iQIYI
  msg "  ${F_BOLD}iQIYI:${F_RESET}"
  local iqiyi; iqiyi=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.iqiyi.com" 2>/dev/null)
  [[ "$iqiyi" =~ 200|301|302 ]] && msg "    ${F_GREEN}可用${F_RESET}" || msg "    ${F_RED}不可用${F_RESET}"

  msg ""
  _log_write "流媒体测试完成"
  pause
}

# ---- Speedtest ----
network_speedtest() {
  msg_title "$(tr NET_SPEED "Speedtest")"
  msg ""
  msg_info "正在测试网络速度..."
  msg ""

  # Try speedtest-cli first
  if command -v speedtest-cli &>/dev/null; then
    speedtest-cli --simple 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  elif command -v speedtest &>/dev/null; then
    speedtest --progress no --format human 2>/dev/null || speedtest --simple 2>/dev/null
  else
    # Fallback: download test from Cloudflare
    msg_info "正在安装 speedtest-cli..."
    _install_pkg speedtest-cli 2>/dev/null || \
      pip3 install speedtest-cli 2>/dev/null || true

    if command -v speedtest-cli &>/dev/null; then
      speedtest-cli --simple 2>/dev/null
    else
      msg_info "正在运行备用测速 (Cloudflare)..."
      msg "  下载测试..."

      local dl_start; dl_start=$(date +%s)
      _download "https://speed.cloudflare.com/__down?bytes=104857600" /tmp/fusion_speedtest &
      local pid=$!
      local last_size=0
      local speed_samples=()
      local sample_count=0

      while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        local elapsed=$(( $(date +%s) - dl_start ))
        if [[ $elapsed -ge 15 ]]; then
          kill "$pid" 2>/dev/null; break
        fi
        local cur_size; cur_size=$(stat -c%s /tmp/fusion_speedtest 2>/dev/null || echo 0)
        if [[ $cur_size -gt $last_size && $sample_count -gt 0 ]]; then
          local speed_mbps=$(( (cur_size - last_size) * 8 / 1048576 ))
          speed_samples+=("$speed_mbps")
        fi
        last_size=$cur_size
        sample_count=$((sample_count + 1))
      done

      local total_elapsed=$(( $(date +%s) - dl_start ))
      [[ $total_elapsed -lt 1 ]] && total_elapsed=1
      local final_size; final_size=$(stat -c%s /tmp/fusion_speedtest 2>/dev/null || echo 0)
      local avg_speed=$(( final_size * 8 / total_elapsed / 1048576 ))

      msg "    下载速度: ~${avg_speed} Mbps (${final_size} 字节, ${total_elapsed}秒)"

      # Latency
      msg "  延迟测试..."
      local ping_start; ping_start=$(date +%s%N)
      _download "https://speed.cloudflare.com/__down?bytes=100" /dev/null 2>/dev/null || true
      local ping_end; ping_end=$(date +%s%N)
      local ping_ms=$(( (ping_end - ping_start) / 1000000 ))
      msg "    延迟: ~${ping_ms}ms"

      rm -f /tmp/fusion_speedtest
    fi
  fi

  msg ""
  _log_write "网速测试完成"
  pause
}

# ---- DNS Test ----
network_dns() {
  local domain="${1:-google.com}"
  msg_title "$(tr NET_DNS "DNS Test")"
  msg ""

  msg "  正在测试 DNS 解析: $domain"
  msg ""

  local dns_servers=(
    "1.1.1.1 (Cloudflare)"
    "8.8.8.8 (Google)"
    "208.67.222.222 (OpenDNS)"
    "114.114.114.114 (114DNS)"
  )

  for server_info in "${dns_servers[@]}"; do
    local server="${server_info%% *}"
    local name="${server_info#* }"
    local start; start=$(date +%s%N)
    local result; result=$(nslookup "$domain" "$server" 2>/dev/null | grep -A1 "Name:" | tail -1)
    local end; end=$(date +%s%N)
    local ms=$(( (end - start) / 1000000 ))
    if [[ -n "$result" ]]; then
      msg "  ${F_GREEN}$name${F_RESET} ($server): ${ms}ms -> $(echo "$result" | awk '{print $2}')"
    else
      msg "  ${F_RED}$name${F_RESET} ($server): timeout"
    fi
  done

  # Current system DNS
  msg ""
  msg "  ${F_BOLD}系统 DNS:${F_RESET}"
  cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | while read -r line; do
    msg "    $line"
  done

  pause
}

# ---- Trace Route ----
network_trace() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "请输入目标主机或 IP: " target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "路由追踪"
  msg ""

  if command -v mtr &>/dev/null; then
    msg_info "正在运行 MTR (5 次 ping)..."
    mtr -r -c 5 "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  elif command -v traceroute &>/dev/null; then
    traceroute -n "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  elif command -v tracepath &>/dev/null; then
    tracepath -n "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  else
    msg_err "请安装 traceroute 或 mtr: fusionbox market install traceroute"
  fi

  pause
}

# ---- Ping ----
network_ping() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "请输入目标主机或 IP: " target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "Ping 测试"
  msg ""

  if command -v ping &>/dev/null; then
    ping -c 5 "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  else
    msg_err "ping 未找到"
  fi
  pause
}

# ---- MTR ----
network_mtr() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    read -p "请输入 MTR 目标主机或 IP: " target
    [[ -z "$target" ]] && target="google.com"
  fi

  _check_pkg mtr mtr
  msg_title "MTR 报告: $target"
  mtr -r -c 10 "$target" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

# ---- Port Check ----
network_port_check() {
  local host="${1:-localhost}"
  local port="${2:-80}"
  if [[ -z "$1" || -z "$2" ]]; then
    read -p "请输入主机: " host
    read -p "请输入端口: " port
    [[ -z "$host" ]] && host="localhost"
    [[ -z "$port" ]] && port="80"
  fi

  msg_title "端口检测: $host:$port"
  msg ""
  timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && \
    msg_ok "端口 $port 在 $host 上${F_GREEN}开放${F_RESET}" || \
    msg_err "端口 $port 在 $host 上${F_RED}关闭${F_RESET}或被过滤"
  pause
}

# ---- Help ----
network_help() {
  msg_title "网络工具 帮助"
  msg ""
  msg "  fusionbox network ip           IP 地址查询"
  msg "  fusionbox network streaming    流媒体测试"
  msg "  fusionbox network speedtest    网速测试"
  msg "  fusionbox network dns          DNS 解析测试"
  msg "  fusionbox network trace        路由追踪"
  msg "  fusionbox network ping <host>  Ping 测试"
  msg "  fusionbox network mtr <host>   MTR 报告"
  msg "  fusionbox network port <host> <port>  端口检测"
  msg ""
}

# ---- Interactive Menu ----
network_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(tr MOD_NETWORK "Network Tools")"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) $(tr NET_IP "IP Address Query")"
    msg "  ${F_GREEN}2${F_RESET}) $(tr NET_STREAMING "Streaming Test")"
    msg "  ${F_GREEN}3${F_RESET}) $(tr NET_SPEED "Speedtest")"
    msg "  ${F_GREEN}4${F_RESET}) $(tr NET_DNS "DNS Test")"
    msg "  ${F_GREEN}5${F_RESET}) $(tr NET_TRACE "Trace Route")"
    msg "  ${F_GREEN}6${F_RESET}) Ping 测试"
    msg "  ${F_GREEN}7${F_RESET}) MTR 报告"
    msg "  ${F_GREEN}8${F_RESET}) 端口检测"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "请选择 [0-8]: " choice
    case "$choice" in
      1) network_ip ;;
      2) network_streaming ;;
      3) network_speedtest ;;
      4) network_dns ;;
      5) network_trace ;;
      6) network_ping ;;
      7) network_mtr ;;
      8) network_port_check ;;
      0) break ;;
    esac
  done
}
