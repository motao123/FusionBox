# FusionBox Network Tools Module
# Network testing utilities

# ---- VPS 评测矩阵 数据表 ----
# 字段: 名称|分类|说明|来源URL|模式
# 模式: intensive = 吃资源/耗时长, normal = 轻量
# 表中 URL 均已逐个验证可访问（200/302），失效项已剔除
NETWORK_BENCH_ITEMS=(
  # ---- 综合评测 ----
  "$(L MSG_NET_0001)"
  "$(L MSG_NET_0002)"
  "$(L MSG_NET_0003)"
  "$(L MSG_NET_0004)"
  "$(L MSG_NET_0005)"
  # ---- 网络测试 ----
  "$(L MSG_NET_0006)"
  "$(L MSG_NET_0007)"
  "$(L MSG_NET_0008)"
  "$(L MSG_NET_0009)"
  "$(L MSG_NET_0010)"
  # ---- 解锁检测 ----
  "$(L MSG_NET_0011)"
  "$(L MSG_NET_0012)"
  # ---- IP 质量 ----
  "$(L MSG_NET_0013)"
)

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
    bench|benchmark)  network_bench "$@" ;;
    nic|iface)        network_nic "$@" ;;
    menu|main)        network_menu ;;
    help|h)           network_help ;;
    *)                _module_unknown_cmd "network" "$cmd" ;;
  esac
}

# ---- IP Query ----
network_ip() {
  msg_title "$(L MSG_NET_0014)"
  msg ""

  msg "  ${F_BOLD}IPv4:${F_RESET} ${F_CYAN}${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "N/A")}${F_RESET}"

  local ipv6; ipv6=$(curl -s6 --connect-timeout 5 ip.sb 2>/dev/null || echo "")
  if [[ -n "$ipv6" ]]; then
    msg "  ${F_BOLD}IPv6:${F_RESET} $ipv6"
  fi

  msg ""
  msg "$(L MSG_NET_0015 "${F_BOLD}" "${F_RESET}")"
  # ip-api.com 免费接口仅 HTTP 明文，改用 HTTPS 的 ipinfo.io
  local ip_info; ip_info=$(curl -s --connect-timeout 5 https://ipinfo.io/json 2>/dev/null)
  if [[ -n "$ip_info" ]]; then
    local country;  country=$(echo "$ip_info" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
    local region;   region=$(echo "$ip_info" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
    local city;     city=$(echo "$ip_info" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
    local org;      org=$(echo "$ip_info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)

    msg "$(L MSG_NET_0016 "${country:-N/A}")"
    msg "$(L MSG_NET_0017 "${region:-N/A}")"
    msg "$(L MSG_NET_0018 "${city:-N/A}")"
    msg "$(L MSG_NET_0019 "${org:-N/A}")"
  fi

  msg ""
  # Additional IP info
  if command -v curl &>/dev/null; then
    msg "$(L MSG_NET_0020 "${F_BOLD}" "${F_RESET}")"
    curl -s --connect-timeout 5 https://speed.cloudflare.com/meta 2>/dev/null | \
      grep -o '"colo":"[^"]*"' | cut -d'"' -f4 | xargs -I{} msg "    Cloudflare Colo: {}"
  fi

  pause
}

# ---- Streaming Test ----
network_streaming() {
  msg_title "$(L MSG_NET_0021)"
  msg ""
  msg_info "$(L MSG_NET_0022)"
  msg ""

  # Netflix
  msg "  ${F_BOLD}Netflix:${F_RESET}"
  local netflix; netflix=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.netflix.com/title/80018499" 2>/dev/null)
  case "$netflix" in
    200|301|302) msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" ;;
    403)         msg "$(L MSG_NET_0024 "${F_YELLOW}" "${F_RESET}")" ;;
    *)           msg "$(L MSG_NET_0025 "${F_RED}" "${F_RESET}" "$netflix")" ;;
  esac

  # YouTube
  msg "  ${F_BOLD}YouTube:${F_RESET}"
  local yt; yt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.youtube.com" 2>/dev/null)
  [[ "$yt" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0026 "${F_YELLOW}" "${F_RESET}")"

  # ChatGPT
  msg "  ${F_BOLD}ChatGPT:${F_RESET}"
  local cgpt; cgpt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://chat.openai.com" 2>/dev/null)
  [[ "$cgpt" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0027 "${F_RED}" "${F_RESET}")"

  # TikTok
  msg "  ${F_BOLD}TikTok:${F_RESET}"
  local tiktok; tiktok=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.tiktok.com" 2>/dev/null)
  [[ "$tiktok" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0028 "${F_YELLOW}" "${F_RESET}")"

  # Disney+
  msg "  ${F_BOLD}Disney+:${F_RESET}"
  local disney; disney=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.disneyplus.com" 2>/dev/null)
  [[ "$disney" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0027 "${F_RED}" "${F_RESET}")"

  # Bilibili
  msg "  ${F_BOLD}Bilibili (HK/TW):${F_RESET}"
  local bili; bili=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.bilibili.com" 2>/dev/null)
  [[ "$bili" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0027 "${F_RED}" "${F_RESET}")"

  # iQIYI
  msg "  ${F_BOLD}iQIYI:${F_RESET}"
  local iqiyi; iqiyi=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.iqiyi.com" 2>/dev/null)
  [[ "$iqiyi" =~ 200|301|302 ]] && msg "$(L MSG_NET_0023 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0027 "${F_RED}" "${F_RESET}")"

  msg ""
  _log_write "$(L MSG_NET_0029)"
  pause
}

# ---- Speedtest ----
network_speedtest() {
  msg_title "$(L MSG_NET_0030)"
  msg ""

  # network.speedtest_server：auto（自动就近）或 speedtest 的数值节点 ID。
  # 非法值不静默忽略，明确告警后回退 auto，避免“配了但没生效”的错觉。
  local server_id="${CONFIG_network_speedtest_server:-auto}"
  local -a st_args=()
  if [[ "$server_id" != "auto" ]]; then
    if [[ "$server_id" =~ ^[0-9]+$ ]]; then
      st_args=(--server "$server_id")
      msg_info "$(L MSG_NET_0031 "$server_id")"
    else
      msg_warn "$(L MSG_NET_0032 "$server_id")"
      server_id="auto"
    fi
  fi

  msg_info "$(L MSG_NET_0033)"
  msg ""

  # Try speedtest-cli first
  if command -v speedtest-cli &>/dev/null; then
    speedtest-cli ${st_args[@]+"${st_args[@]}"} --simple 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  elif command -v speedtest &>/dev/null; then
    local -a okla_args=()
    [[ ${#st_args[@]} -gt 0 ]] && okla_args=(--server-id "$server_id")
    speedtest ${okla_args[@]+"${okla_args[@]}"} --progress no --format human 2>/dev/null || speedtest --simple 2>/dev/null
  else
    # Fallback: download test from Cloudflare
    msg_info "$(L MSG_NET_0034)"
    _install_pkg speedtest-cli 2>/dev/null || \
      pip3 install speedtest-cli 2>/dev/null || true

    if command -v speedtest-cli &>/dev/null; then
      speedtest-cli --simple 2>/dev/null
    else
      msg_info "$(L MSG_NET_0035)"
      msg "$(L MSG_NET_0036)"

      local dl_start; dl_start=$(date +%s)
      _download "https://speed.cloudflare.com/__down?bytes=104857600" /tmp/fusion_speedtest &
      local pid=$!
      local last_size=0

      while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        local elapsed=$(( $(date +%s) - dl_start ))
        if [[ $elapsed -ge 15 ]]; then
          kill "$pid" 2>/dev/null; break
        fi
        last_size=$(stat -c%s /tmp/fusion_speedtest 2>/dev/null || echo 0)
      done

      local total_elapsed=$(( $(date +%s) - dl_start ))
      [[ $total_elapsed -lt 1 ]] && total_elapsed=1
      local final_size; final_size=$(stat -c%s /tmp/fusion_speedtest 2>/dev/null || echo 0)
      local avg_speed=$(( final_size * 8 / total_elapsed / 1048576 ))

      msg "$(L MSG_NET_0037 "${avg_speed}" "${final_size}" "${total_elapsed}")"

      # Latency
      msg "$(L MSG_NET_0038)"
      local ping_start; ping_start=$(date +%s%N)
      _download "https://speed.cloudflare.com/__down?bytes=100" /dev/null 2>/dev/null || true
      local ping_end; ping_end=$(date +%s%N)
      local ping_ms=$(( (ping_end - ping_start) / 1000000 ))
      msg "$(L MSG_NET_0039 "${ping_ms}")"

      rm -f /tmp/fusion_speedtest
    fi
  fi

  msg ""
  _log_write "$(L MSG_NET_0040)"
  pause
}

# ---- DNS Test ----
network_dns() {
  local domain="${1:-google.com}"
  msg_title "$(L MSG_NET_0041)"
  msg ""

  msg "$(L MSG_NET_0042 "$domain")"
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
  msg "$(L MSG_NET_0043 "${F_BOLD}" "${F_RESET}")"
  cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | while read -r line; do
    msg "    $line"
  done

  pause
}

# ---- Trace Route ----
network_trace() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(L MSG_NET_0044)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "$(L MSG_NET_0045)"
  msg ""

  if command -v mtr &>/dev/null; then
    msg_info "$(L MSG_NET_0046)"
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
    msg_err "$(L MSG_NET_0047)"
  fi

  pause
}

# ---- Ping ----
network_ping() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(L MSG_NET_0044)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "$(L MSG_NET_0048)"
  msg ""

  if _require_optional_cmd ping iputils-ping "$(L MSG_NET_0048)"; then
    ping -c 5 "$target" 2>/dev/null | while read -r line; do
      msg "  $line"
    done
  fi
  pause
}

# ---- MTR ----
network_mtr() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    read -p "$(L MSG_NET_0049)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  _check_pkg mtr mtr
  msg_title "$(L MSG_NET_0050 "$target")"
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
    read -p "$(L MSG_NET_0051)" host
    read -p "$(L MSG_NET_0052)" port
    [[ -z "$host" ]] && host="localhost"
    [[ -z "$port" ]] && port="80"
  fi

  # 输入校验：主机/端口直接拼入 /dev/tcp，必须先过滤
  [[ "$host" =~ ^[a-zA-Z0-9._-]+$ ]] || { msg_err "$(L MSG_NET_0053)"; pause; return 1; }
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || { msg_err "$(L MSG_NET_0054)"; pause; return 1; }

  msg_title "$(L MSG_NET_0055 "$host" "$port")"
  msg ""
  timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && \
    msg_ok "$(L MSG_NET_0056 "$port" "$host" "${F_GREEN}" "${F_RESET}")" || \
    msg_err "$(L MSG_NET_0057 "$port" "$host" "${F_RED}" "${F_RESET}")"
  pause
}

# ---- VPS 评测矩阵 ----

# 取 URL 的域名，菜单中展示来源
_network_bench_domain() {
  local url="${1#*://}"
  echo "${url%%/*}"
}

# 模式标签
_network_bench_mode_label() {
  if [[ "$1" == "intensive" ]]; then
    echo "$(L MSG_NET_0058 "${F_YELLOW}" "${F_RESET}")"
  else
    echo "$(L MSG_NET_0059 "${F_GREEN}" "${F_RESET}")"
  fi
}

# 当前内存 (MB)
_network_bench_mem_mb() {
  command -v free &>/dev/null || return 0
  free -m 2>/dev/null | awk '/^Mem:/{print $2}'
}

# 当前 swap (MB)，取不到按 0
_network_bench_swap_mb() {
  local s=""
  command -v free &>/dev/null && s=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}')
  echo "${s:-0}"
}

# 列出全部评测项（按分类分组，含模式与来源域名）
network_bench_list() {
  local item name cat desc url mode idx=0 cur_cat=""
  msg "$(L MSG_NET_0060 "${F_BOLD}" "${F_RESET}" "${#NETWORK_BENCH_ITEMS[@]}")"
  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    idx=$((idx + 1))
    if [[ "$cat" != "$cur_cat" ]]; then
      cur_cat="$cat"
      msg ""
      msg "  ${F_CYAN}${F_BOLD}[$cat]${F_RESET}"
    fi
    printf -v num '%2d' "$idx"
    msg "$(L MSG_NET_0061 "${F_GREEN}" "${num}" "${F_RESET}" "${F_BOLD}" "${name}" "${F_RESET}" "$(_network_bench_mode_label "$mode")")"
    msg "      ${desc}"
    msg "$(L MSG_NET_0062 "$(_network_bench_domain "$url")")"
  done
  msg ""
}

# 执行单个评测项: $1=名称 $2=说明 $3=URL $4=模式 $5=auto 表示批量模式（不再逐项确认）
_network_bench_execute() {
  local name="$1" desc="$2" url="$3" mode="$4" auto="${5:-}"

  msg_title "$(L MSG_NET_0063 "$name")"
  msg ""
  msg "$(L MSG_NET_0064 "$desc")"
  msg "$(L MSG_NET_0065 "$(_network_bench_mode_label "$mode")")"

  # 重型项目：内存不足且无 swap 时仅提示，不自动创建
  if [[ "$mode" == "intensive" ]]; then
    local mem_mb swap_mb
    mem_mb=$(_network_bench_mem_mb)
    swap_mb=$(_network_bench_swap_mb)
    if [[ -n "$mem_mb" && "$mem_mb" -lt 1024 && "$swap_mb" -eq 0 ]]; then
      msg_warn "$(L MSG_NET_0066 "${mem_mb}")"
      msg_warn "$(L MSG_NET_0067)"
    fi
  fi

  [[ "$F_IS_ROOT" == "1" ]] || msg_warn "$(L MSG_NET_0068)"

  msg ""
  msg "$(L MSG_NET_0069 "${F_ULINE}" "${url}" "${F_RESET}")"
  msg ""
  if [[ "$auto" != "auto" ]]; then
    confirm "$(L MSG_NET_0070)" || { msg_info "$(L MSG_NET_0071)"; return 0; }
  fi

  local tmp; tmp=$(mktemp)
  if ! _download "$url" "$tmp"; then
    msg_err "$(L MSG_NET_0072 "$url")"
    msg_err "$(L MSG_NET_0073)"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    msg_err "$(L MSG_NET_0074 "$url")"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi

  _log_write "$(L MSG_NET_0075 "$name" "$url")"
  bash "$tmp"
  local rc=$?
  rm -f "$tmp"

  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_NET_0076 "$name")"
  else
    msg_warn "$(L MSG_NET_0077 "$rc")"
  fi
  _log_write "$(L MSG_NET_0078 "$name" "$rc")"
  [[ "$auto" != "auto" ]] && pause
  return "$rc"
}

# 按序号或名称运行单项
network_bench_run() {
  local want="$1" item name cat desc url mode idx=0
  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    idx=$((idx + 1))
    if [[ "$want" == "$idx" || "${want,,}" == "${name,,}" ]]; then
      _network_bench_execute "$name" "$desc" "$url" "$mode"
      return $?
    fi
  done
  msg_err "$(L MSG_NET_0079 "$want")"
  pause
  return 1
}

# 依次运行全部轻量项
network_bench_all_light() {
  local item name cat desc url mode count=0 failed=0
  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    [[ "$mode" == "normal" ]] && count=$((count + 1))
  done

  msg_info "$(L MSG_NET_0080 "${count}")"
  confirm "$(L MSG_NET_0081)" || { msg_info "$(L MSG_NET_0071)"; return 0; }

  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    [[ "$mode" == "normal" ]] || continue
    _network_bench_execute "$name" "$desc" "$url" "$mode" auto || failed=1
  done
  msg_ok "$(L MSG_NET_0082)"
  _log_write "$(L MSG_NET_0083)"
  return "$failed"
}

# 自定义 URL 运行
network_bench_custom() {
  local url; url=$(read_input "$(L MSG_NET_0084)")
  if [[ -z "$url" ]]; then
    msg_info "$(L MSG_NET_0085)"
    return 0
  fi
  if [[ "$url" != https://* ]]; then
    msg_err "$(L MSG_NET_0086 "$url")"
    pause
    return 1
  fi
  _network_bench_execute "$(L MSG_NET_0087)" "$(L MSG_NET_0088)" "$url" "normal"
}

# 交互式矩阵菜单
network_bench_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0089)"
    msg ""
    network_bench_list
    msg "$(L MSG_NET_0090 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_NET_0091)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      ""|l|L) continue ;;
      0)      break ;;
      a|A)    network_bench_all_light ;;
      u|U)    network_bench_custom ;;
      *)      network_bench_run "$choice" ;;
    esac
  done
}

network_bench() {
  local arg="${1:-}"
  case "$arg" in
    list|l)  network_bench_list; pause ;;
    all|a)   network_bench_all_light ;;
    "")      network_bench_menu ;;
    *)       network_bench_run "$arg" ;;
  esac
}

# ---- 网卡管理 (G10)：列表/详情/启停 ----

_nic_check_name() {
  [[ "$1" =~ ^[a-zA-Z0-9._-]{1,15}$ ]] || { msg_err "$(L MSG_NET_0092 "$1")"; return 1; }
  ip link show dev "$1" &>/dev/null || { msg_err "$(L MSG_NET_0093 "$1")"; return 1; }
}

_nic_default_iface() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

_nic_list() {
  msg "$(L MSG_NET_0094 "${F_BOLD}" "${F_RESET}")"
  ip -br addr 2>/dev/null || ip addr show
  msg ""
  msg "$(L MSG_NET_0095 "${F_BOLD}" "${F_RESET}" "$(_nic_default_iface)")"
  msg "$(L MSG_NET_0096)"
}

_nic_info() {
  local dev="${1:-}"
  _nic_check_name "$dev" || return 1
  msg "$(L MSG_NET_0097 "${F_BOLD}" "${dev}" "${F_RESET}")"
  ip addr show dev "$dev"
  msg ""
  msg "$(L MSG_NET_0098 "${F_BOLD}" "${dev}" "${F_RESET}")"
  ip -s link show dev "$dev"
  if command -v ethtool &>/dev/null; then
    msg ""
    msg "$(L MSG_NET_0099 "${F_BOLD}" "${dev}" "${F_RESET}")"
    ethtool "$dev" 2>/dev/null | grep -E "Speed|Duplex|Link detected" | sed 's/^/  /'
    ethtool -i "$dev" 2>/dev/null | grep -E "^(driver|version|bus-info)" | sed 's/^/  /'
  else
    msg ""
    msg_info "$(L MSG_NET_0100)"
  fi
}

_nic_toggle() {
  local action="$1" dev="${2:-}"
  _nic_check_name "$dev" || return 1
  local def_if; def_if=$(_nic_default_iface)
  if [[ "$action" == "down" && "$dev" == "$def_if" ]]; then
    msg_warn "$(L MSG_NET_0101 "$dev")"
    confirm "$(L MSG_NET_0102 "$dev")" || { msg_info "$(L MSG_NET_0071)"; return 1; }
  fi
  if ! ip link set dev "$dev" "$action"; then
    msg_err "$(L MSG_NET_0103 "$dev" "$action")"
    return 1
  fi
  local st; st=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null || echo unknown)
  msg_ok "$(L MSG_NET_0104 "$dev" "$action" "$st")"
  _log_write "$(L MSG_NET_0105 "$dev" "$action")"
}

_nic_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0106)"
    msg ""
    _nic_list
    msg ""
    msg "$(L MSG_NET_0107)"
    msg "$(L MSG_NET_0108)"
    msg "$(L MSG_NET_0109)"
    msg "$(L MSG_NET_0110)"
    read -p "$(L MSG_NET_0091)" nic_choice || { msg ""; return; }
    case "$nic_choice" in
      1) nic_d=$(read_input "$(L MSG_NET_0111)") && _nic_info "$nic_d" && pause ;;
      2) nic_d=$(read_input "$(L MSG_NET_0112)") && _nic_toggle up "$nic_d" && pause ;;
      3) nic_d=$(read_input "$(L MSG_NET_0113)") && _nic_toggle down "$nic_d" && pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

network_nic() {
  _require_root
  local cmd="${1:-menu}"
  case "$cmd" in
    list)  _nic_list ;;
    info)  shift; _nic_info "$@" ;;
    up)    shift; _nic_toggle up "$@" ;;
    down)  shift; _nic_toggle down "$@" ;;
    menu|"") _nic_menu ;;
    *)     msg_err "$(L MSG_NET_0114 "$cmd")"; return 1 ;;
  esac
}

# ---- Help ----
network_help() {
  msg_title "$(L MSG_NET_0115)"
  msg ""
  msg "$(L MSG_NET_0116)"
  msg "$(L MSG_NET_0117)"
  msg "$(L MSG_NET_0118)"
  msg "$(L MSG_NET_0119)"
  msg "$(L MSG_NET_0120)"
  msg "$(L MSG_NET_0121)"
  msg "$(L MSG_NET_0122)"
  msg "$(L MSG_NET_0123)"
  msg ""
  msg "$(L MSG_NET_0124)"
  msg "$(L MSG_NET_0125)"
  msg "$(L MSG_NET_0126)"
  msg "$(L MSG_NET_0127)"
  msg ""
  msg "$(L MSG_NET_0128)"
  msg ""
  msg "$(L MSG_NET_0129)"
  msg "$(L MSG_NET_0130)"
  msg ""
}

# ---- Interactive Menu ----
network_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0131)"
    msg ""
    msg "$(L MSG_NET_0132 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0133 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0134 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0135 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0136 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0137 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0138 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0139 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0140 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0141 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0142 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_NET_0143)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) network_ip ;;
      2) network_streaming ;;
      3) network_speedtest ;;
      4) network_dns ;;
      5) network_trace ;;
      6) network_ping ;;
      7) network_mtr ;;
      8) network_port_check ;;
      9) network_bench ;;
      10) network_nic ;;
      0) break ;;
    esac
  done
}
