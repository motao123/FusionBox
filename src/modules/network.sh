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
  msg "  ${F_BOLD}[Detailed IP Info]${F_RESET}"
  local ip_info; ip_info=$(curl -s --connect-timeout 5 http://ip-api.com/json/ 2>/dev/null)
  if [[ -n "$ip_info" ]]; then
    local country;  country=$(echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
    local region;   region=$(echo "$ip_info" | grep -o '"regionName":"[^"]*"' | cut -d'"' -f4)
    local city;     city=$(echo "$ip_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
    local isp;      isp=$(echo "$ip_info" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4)
    local org;      org=$(echo "$ip_info" | grep -o '"org":"[^"]*"' | cut -d'"' -f4)
    local as;       as=$(echo "$ip_info" | grep -o '"as":"[^"]*"' | cut -d'"' -f4)

    msg "    Country: ${country:-N/A}"
    msg "    Region:  ${region:-N/A}"
    msg "    City:    ${city:-N/A}"
    msg "    ISP:     ${isp:-N/A}"
    msg "    ORG:     ${org:-N/A}"
    msg "    AS:      ${as:-N/A}"
  fi

  msg ""
  # Additional IP info
  if command -v curl &>/dev/null; then
    msg "  ${F_BOLD}[CDN / Network Info]${F_RESET}"
    curl -s --connect-timeout 5 https://speed.cloudflare.com/meta 2>/dev/null | \
      grep -o '"colo":"[^"]*"' | cut -d'"' -f4 | xargs -I{} msg "    Cloudflare Colo: {}"
  fi

  pause
}

# ---- Streaming Test ----
network_streaming() {
  msg_title "$(tr NET_STREAMING "Streaming Test")"
  msg ""
  msg_info "Testing streaming service accessibility..."
  msg ""

  # Netflix
  msg "  ${F_BOLD}Netflix:${F_RESET}"
  local netflix; netflix=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.netflix.com/title/80018499" 2>/dev/null)
  case "$netflix" in
    200|301|302) msg "    ${F_GREEN}Available${F_RESET}" ;;
    403)         msg "    ${F_YELLOW}Proxy Detected${F_RESET}" ;;
    *)           msg "    ${F_RED}Unavailable${F_RESET} (HTTP $netflix)" ;;
  esac

  # YouTube
  msg "  ${F_BOLD}YouTube:${F_RESET}"
  local yt; yt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.youtube.com" 2>/dev/null)
  [[ "$yt" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_YELLOW}Restricted${F_RESET}"

  # ChatGPT
  msg "  ${F_BOLD}ChatGPT:${F_RESET}"
  local cgpt; cgpt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://chat.openai.com" 2>/dev/null)
  [[ "$cgpt" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_RED}Unavailable${F_RESET}"

  # TikTok
  msg "  ${F_BOLD}TikTok:${F_RESET}"
  local tiktok; tiktok=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.tiktok.com" 2>/dev/null)
  [[ "$tiktok" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_YELLOW}Maybe Restricted${F_RESET}"

  # Disney+
  msg "  ${F_BOLD}Disney+:${F_RESET}"
  local disney; disney=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.disneyplus.com" 2>/dev/null)
  [[ "$disney" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_RED}Unavailable${F_RESET}"

  # Bilibili
  msg "  ${F_BOLD}Bilibili (HK/TW):${F_RESET}"
  local bili; bili=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.bilibili.com" 2>/dev/null)
  [[ "$bili" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_RED}Unavailable${F_RESET}"

  # iQIYI
  msg "  ${F_BOLD}iQIYI:${F_RESET}"
  local iqiyi; iqiyi=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.iqiyi.com" 2>/dev/null)
  [[ "$iqiyi" =~ 200|301|302 ]] && msg "    ${F_GREEN}Available${F_RESET}" || msg "    ${F_RED}Unavailable${F_RESET}"

  msg ""
  _log_write "Streaming test completed"
  pause
}

# ---- Speedtest ----
network_speedtest() {
  msg_title "$(tr NET_SPEED "Speedtest")"
  msg ""
  msg_info "Testing network speed..."
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
    msg_info "Installing speedtest-cli..."
    _install_pkg speedtest-cli 2>/dev/null || \
      pip3 install speedtest-cli 2>/dev/null || true

    if command -v speedtest-cli &>/dev/null; then
      speedtest-cli --simple 2>/dev/null
    else
      msg_info "Running fallback speed test (Cloudflare)..."
      msg "  Download test..."

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

      msg "    Download: ~${avg_speed} Mbps (${final_size} bytes in ${total_elapsed}s)"

      # Latency
      msg "  Latency test..."
      local ping_start; ping_start=$(date +%s%N)
      _download "https://speed.cloudflare.com/__down?bytes=100" /dev/null 2>/dev/null || true
      local ping_end; ping_end=$(date +%s%N)
      local ping_ms=$(( (ping_end - ping_start) / 1000000 ))
      msg "    Latency: ~${ping_ms}ms"

      rm -f /tmp/fusion_speedtest
    fi
  fi

  msg ""
  _log_write "Speed test completed"
  pause
}

# ---- DNS Test ----
network_dns() {
  local domain="${1:-google.com}"
  msg_title "$(tr NET_DNS "DNS Test")"
  msg ""

  msg "  Testing DNS resolution for: $domain"
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
  msg "  ${F_BOLD}System DNS:${F_RESET}"
  cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | while read -r line; do
    msg "    $line"
  done

  pause
}

# ---- Trace Route ----
network_trace() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(tr MSG_INPUT "Target host or IP"): " target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "$(tr NET_TRACE "Trace Route")"
  msg ""

  if command -v mtr &>/dev/null; then
    msg_info "Running MTR (5 pings)..."
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
    msg_err "Install traceroute or mtr: fusionbox market install traceroute"
  fi

  pause
}

# ---- Ping ----
network_ping() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(tr MSG_INPUT "Target host or IP"): " target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "Ping Test"
  msg ""

  if command -v ping &>/dev/null; then
    ping -c 5 "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  else
    msg_err "ping not found"
  fi
  pause
}

# ---- MTR ----
network_mtr() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    read -p "$(tr MSG_INPUT "Target host or IP for MTR"): " target
    [[ -z "$target" ]] && target="google.com"
  fi

  _check_pkg mtr mtr
  msg_title "MTR Report: $target"
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
    read -p "$(tr MSG_INPUT "Host"): " host
    read -p "$(tr MSG_INPUT "Port"): " port
    [[ -z "$host" ]] && host="localhost"
    [[ -z "$port" ]] && port="80"
  fi

  msg_title "Port Check: $host:$port"
  msg ""
  timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && \
    msg_ok "Port $port is ${F_GREEN}OPEN${F_RESET} on $host" || \
    msg_err "Port $port is ${F_RED}CLOSED${F_RESET} or filtered on $host"
  pause
}

# ---- Help ----
network_help() {
  msg_title "$(tr MOD_NETWORK "Network Tools") Help"
  msg ""
  msg "  fusionbox network ip           $(tr NET_IP "IP address query")"
  msg "  fusionbox network streaming    $(tr NET_STREAMING "Streaming test")"
  msg "  fusionbox network speedtest    $(tr NET_SPEED "Speed test")"
  msg "  fusionbox network dns          $(tr NET_DNS "DNS resolution test")"
  msg "  fusionbox network trace        $(tr NET_TRACE "Trace route to host")"
  msg "  fusionbox network ping <host>  Ping a host"
  msg "  fusionbox network mtr <host>   MTR report to host"
  msg "  fusionbox network port <host> <port>  Check if port is open"
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
    msg "  ${F_GREEN}6${F_RESET}) Ping"
    msg "  ${F_GREEN}7${F_RESET}) MTR Report"
    msg "  ${F_GREEN}8${F_RESET}) Port Check"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "$(tr MSG_SELECT "Select") [0-8]: " choice
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
