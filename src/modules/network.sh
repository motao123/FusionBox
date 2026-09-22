# FusionBox Network Tools Module
# Network testing utilities

# ---- VPS 评测矩阵 数据表 ----
# 字段: 名称|分类|说明|来源URL|模式
# 模式: intensive = 吃资源/耗时长, normal = 轻量
# 表中 URL 均已逐个验证可访问（200/302），失效项已剔除
NETWORK_BENCH_ITEMS=(
  # ---- 综合评测 ----
  "$(L MSG_NET_0144)"
  "$(L MSG_NET_0145)"
  "$(L MSG_NET_0146)"
  "$(L MSG_NET_0147)"
  "$(L MSG_NET_0148)"
  # ---- 网络测试 ----
  "$(L MSG_NET_0149)"
  "$(L MSG_NET_0150)"
  "$(L MSG_NET_0151)"
  "$(L MSG_NET_0152)"
  "$(L MSG_NET_0153)"
  # ---- 解锁检测 ----
  "$(L MSG_NET_0154)"
  "$(L MSG_NET_0155)"
  # ---- IP 质量 ----
  "$(L MSG_NET_0156)"
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
  msg_title "$(L MSG_NET_0157)"
  msg ""

  msg "  ${F_BOLD}IPv4:${F_RESET} ${F_CYAN}${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "N/A")}${F_RESET}"

  local ipv6; ipv6=$(curl -s6 --connect-timeout 5 ip.sb 2>/dev/null || echo "")
  if [[ -n "$ipv6" ]]; then
    msg "  ${F_BOLD}IPv6:${F_RESET} $ipv6"
  fi

  msg ""
  msg "$(L MSG_NET_0158 "${F_BOLD}" "${F_RESET}")"
  # ip-api.com 免费接口仅 HTTP 明文，改用 HTTPS 的 ipinfo.io
  local ip_info; ip_info=$(curl -s --connect-timeout 5 https://ipinfo.io/json 2>/dev/null)
  if [[ -n "$ip_info" ]]; then
    local country;  country=$(echo "$ip_info" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
    local region;   region=$(echo "$ip_info" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
    local city;     city=$(echo "$ip_info" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
    local org;      org=$(echo "$ip_info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)

    msg "$(L MSG_NET_0159 "${country:-N/A}")"
    msg "$(L MSG_NET_0160 "${region:-N/A}")"
    msg "$(L MSG_NET_0161 "${city:-N/A}")"
    msg "$(L MSG_NET_0162 "${org:-N/A}")"
  fi

  msg ""
  # Additional IP info
  if command -v curl &>/dev/null; then
    msg "$(L MSG_NET_0163 "${F_BOLD}" "${F_RESET}")"
    curl -s --connect-timeout 5 https://speed.cloudflare.com/meta 2>/dev/null | \
      grep -o '"colo":"[^"]*"' | cut -d'"' -f4 | xargs -I{} msg "    Cloudflare Colo: {}"
  fi

  pause
}

# ---- Streaming Test ----
network_streaming() {
  msg_title "$(L MSG_NET_0164)"
  msg ""
  msg_info "$(L MSG_NET_0165)"
  msg ""

  # Netflix
  msg "  ${F_BOLD}Netflix:${F_RESET}"
  local netflix; netflix=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.netflix.com/title/80018499" 2>/dev/null)
  case "$netflix" in
    200|301|302) msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" ;;
    403)         msg "$(L MSG_NET_0167 "${F_YELLOW}" "${F_RESET}")" ;;
    *)           msg "$(L MSG_NET_0168 "${F_RED}" "${F_RESET}" "$netflix")" ;;
  esac

  # YouTube
  msg "  ${F_BOLD}YouTube:${F_RESET}"
  local yt; yt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.youtube.com" 2>/dev/null)
  [[ "$yt" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0169 "${F_YELLOW}" "${F_RESET}")"

  # ChatGPT
  msg "  ${F_BOLD}ChatGPT:${F_RESET}"
  local cgpt; cgpt=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://chat.openai.com" 2>/dev/null)
  [[ "$cgpt" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0170 "${F_RED}" "${F_RESET}")"

  # TikTok
  msg "  ${F_BOLD}TikTok:${F_RESET}"
  local tiktok; tiktok=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.tiktok.com" 2>/dev/null)
  [[ "$tiktok" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0171 "${F_YELLOW}" "${F_RESET}")"

  # Disney+
  msg "  ${F_BOLD}Disney+:${F_RESET}"
  local disney; disney=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.disneyplus.com" 2>/dev/null)
  [[ "$disney" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0170 "${F_RED}" "${F_RESET}")"

  # Bilibili
  msg "  ${F_BOLD}Bilibili (HK/TW):${F_RESET}"
  local bili; bili=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.bilibili.com" 2>/dev/null)
  [[ "$bili" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0170 "${F_RED}" "${F_RESET}")"

  # iQIYI
  msg "  ${F_BOLD}iQIYI:${F_RESET}"
  local iqiyi; iqiyi=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0" \
    "https://www.iqiyi.com" 2>/dev/null)
  [[ "$iqiyi" =~ 200|301|302 ]] && msg "$(L MSG_NET_0166 "${F_GREEN}" "${F_RESET}")" || msg "$(L MSG_NET_0170 "${F_RED}" "${F_RESET}")"

  msg ""
  _log_write "$(L MSG_NET_0172)"
  pause
}

# ---- Speedtest ----
network_speedtest() {
  msg_title "$(L MSG_NET_0173)"
  msg ""

  # network.speedtest_server：auto（自动就近）或 speedtest 的数值节点 ID。
  # 非法值不静默忽略，明确告警后回退 auto，避免“配了但没生效”的错觉。
  local server_id="${CONFIG_network_speedtest_server:-auto}"
  local -a st_args=()
  if [[ "$server_id" != "auto" ]]; then
    if [[ "$server_id" =~ ^[0-9]+$ ]]; then
      st_args=(--server "$server_id")
      msg_info "$(L MSG_NET_0174 "$server_id")"
    else
      msg_warn "$(L MSG_NET_0175 "$server_id")"
      server_id="auto"
    fi
  fi

  msg_info "$(L MSG_NET_0176)"
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
    msg_info "$(L MSG_NET_0177)"
    _install_pkg speedtest-cli 2>/dev/null || \
      pip3 install speedtest-cli 2>/dev/null || true

    if command -v speedtest-cli &>/dev/null; then
      speedtest-cli --simple 2>/dev/null
    else
      msg_info "$(L MSG_NET_0178)"
      msg "$(L MSG_NET_0179)"

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

      msg "$(L MSG_NET_0180 "${avg_speed}" "${final_size}" "${total_elapsed}")"

      # Latency
      msg "$(L MSG_NET_0181)"
      local ping_start; ping_start=$(date +%s%N)
      _download "https://speed.cloudflare.com/__down?bytes=100" /dev/null 2>/dev/null || true
      local ping_end; ping_end=$(date +%s%N)
      local ping_ms=$(( (ping_end - ping_start) / 1000000 ))
      msg "$(L MSG_NET_0182 "${ping_ms}")"

      rm -f /tmp/fusion_speedtest
    fi
  fi

  msg ""
  _log_write "$(L MSG_NET_0183)"
  pause
}

# ---- DNS Test ----
network_dns() {
  local domain="${1:-google.com}"
  msg_title "$(L MSG_NET_0184)"
  msg ""

  msg "$(L MSG_NET_0185 "$domain")"
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
  msg "$(L MSG_NET_0186 "${F_BOLD}" "${F_RESET}")"
  cat /etc/resolv.conf 2>/dev/null | grep -v '^#' | grep -v '^$' | while read -r line; do
    msg "    $line"
  done

  pause
}

# ---- Trace Route ----
network_trace() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(L MSG_NET_0187)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "$(L MSG_NET_0188)"
  msg ""

  if command -v mtr &>/dev/null; then
    msg_info "$(L MSG_NET_0189)"
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
    msg_err "$(L MSG_NET_0190)"
  fi

  pause
}

# ---- Ping ----
network_ping() {
  local target="${1:-google.com}"
  if [[ -z "$1" ]]; then
    read -p "$(L MSG_NET_0187)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  msg_title "$(L MSG_NET_0191)"
  msg ""

  if _require_optional_cmd ping iputils-ping "$(L MSG_NET_0191)"; then
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
    read -p "$(L MSG_NET_0192)" target
    [[ -z "$target" ]] && target="google.com"
  fi

  _check_pkg mtr mtr
  msg_title "$(L MSG_NET_0193 "$target")"
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
    read -p "$(L MSG_NET_0194)" host
    read -p "$(L MSG_NET_0195)" port
    [[ -z "$host" ]] && host="localhost"
    [[ -z "$port" ]] && port="80"
  fi

  # 输入校验：主机/端口直接拼入 /dev/tcp，必须先过滤
  [[ "$host" =~ ^[a-zA-Z0-9._-]+$ ]] || { msg_err "$(L MSG_NET_0196)"; pause; return 1; }
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || { msg_err "$(L MSG_NET_0197)"; pause; return 1; }

  msg_title "$(L MSG_NET_0198 "$host" "$port")"
  msg ""
  timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && \
    msg_ok "$(L MSG_NET_0199 "$port" "$host" "${F_GREEN}" "${F_RESET}")" || \
    msg_err "$(L MSG_NET_0200 "$port" "$host" "${F_RED}" "${F_RESET}")"
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
    echo "$(L MSG_NET_0201 "${F_YELLOW}" "${F_RESET}")"
  else
    echo "$(L MSG_NET_0202 "${F_GREEN}" "${F_RESET}")"
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
  msg "$(L MSG_NET_0203 "${F_BOLD}" "${F_RESET}" "${#NETWORK_BENCH_ITEMS[@]}")"
  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    idx=$((idx + 1))
    if [[ "$cat" != "$cur_cat" ]]; then
      cur_cat="$cat"
      msg ""
      msg "  ${F_CYAN}${F_BOLD}[$cat]${F_RESET}"
    fi
    printf -v num '%2d' "$idx"
    msg "$(L MSG_NET_0204 "${F_GREEN}" "${num}" "${F_RESET}" "${F_BOLD}" "${name}" "${F_RESET}" "$(_network_bench_mode_label "$mode")")"
    msg "      ${desc}"
    msg "$(L MSG_NET_0205 "$(_network_bench_domain "$url")")"
  done
  msg ""
}

# 执行单个评测项: $1=名称 $2=说明 $3=URL $4=模式 $5=auto 表示批量模式（不再逐项确认）
_network_bench_execute() {
  local name="$1" desc="$2" url="$3" mode="$4" auto="${5:-}"

  msg_title "$(L MSG_NET_0206 "$name")"
  msg ""
  msg "$(L MSG_NET_0207 "$desc")"
  msg "$(L MSG_NET_0208 "$(_network_bench_mode_label "$mode")")"

  # 重型项目：内存不足且无 swap 时仅提示，不自动创建
  if [[ "$mode" == "intensive" ]]; then
    local mem_mb swap_mb
    mem_mb=$(_network_bench_mem_mb)
    swap_mb=$(_network_bench_swap_mb)
    if [[ -n "$mem_mb" && "$mem_mb" -lt 1024 && "$swap_mb" -eq 0 ]]; then
      msg_warn "$(L MSG_NET_0209 "${mem_mb}")"
      msg_warn "$(L MSG_NET_0210)"
    fi
  fi

  [[ "$F_IS_ROOT" == "1" ]] || msg_warn "$(L MSG_NET_0211)"

  msg ""
  msg "$(L MSG_NET_0212 "${F_ULINE}" "${url}" "${F_RESET}")"
  msg ""
  if [[ "$auto" != "auto" ]]; then
    confirm "$(L MSG_NET_0213)" || { msg_info "$(L MSG_NET_0214)"; return 0; }
  fi

  local tmp; tmp=$(mktemp)
  if ! _download "$url" "$tmp"; then
    msg_err "$(L MSG_NET_0215 "$url")"
    msg_err "$(L MSG_NET_0216)"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    msg_err "$(L MSG_NET_0217 "$url")"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi

  _log_write "$(L MSG_NET_0218 "$name" "$url")"
  bash "$tmp"
  local rc=$?
  rm -f "$tmp"

  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_NET_0219 "$name")"
  else
    msg_warn "$(L MSG_NET_0220 "$rc")"
  fi
  _log_write "$(L MSG_NET_0221 "$name" "$rc")"
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
  msg_err "$(L MSG_NET_0222 "$want")"
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

  msg_info "$(L MSG_NET_0223 "${count}")"
  confirm "$(L MSG_NET_0224)" || { msg_info "$(L MSG_NET_0214)"; return 0; }

  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    [[ "$mode" == "normal" ]] || continue
    _network_bench_execute "$name" "$desc" "$url" "$mode" auto || failed=1
  done
  msg_ok "$(L MSG_NET_0225)"
  _log_write "$(L MSG_NET_0226)"
  return "$failed"
}

# 自定义 URL 运行
network_bench_custom() {
  local url; url=$(read_input "$(L MSG_NET_0227)")
  if [[ -z "$url" ]]; then
    msg_info "$(L MSG_NET_0228)"
    return 0
  fi
  if [[ "$url" != https://* ]]; then
    msg_err "$(L MSG_NET_0229 "$url")"
    pause
    return 1
  fi
  _network_bench_execute "$(L MSG_NET_0230)" "$(L MSG_NET_0231)" "$url" "normal"
}

# 交互式矩阵菜单
network_bench_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0232)"
    msg ""
    network_bench_list
    msg "$(L MSG_NET_0233 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_NET_0234)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
  [[ "$1" =~ ^[a-zA-Z0-9._-]{1,15}$ ]] || { msg_err "$(L MSG_NET_0235 "$1")"; return 1; }
  ip link show dev "$1" &>/dev/null || { msg_err "$(L MSG_NET_0236 "$1")"; return 1; }
}

_nic_default_iface() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

_nic_list() {
  msg "$(L MSG_NET_0237 "${F_BOLD}" "${F_RESET}")"
  ip -br addr 2>/dev/null || ip addr show
  msg ""
  msg "$(L MSG_NET_0238 "${F_BOLD}" "${F_RESET}" "$(_nic_default_iface)")"
  msg "$(L MSG_NET_0239)"
}

_nic_info() {
  local dev="${1:-}"
  _nic_check_name "$dev" || return 1
  msg "$(L MSG_NET_0240 "${F_BOLD}" "${dev}" "${F_RESET}")"
  ip addr show dev "$dev"
  msg ""
  msg "$(L MSG_NET_0241 "${F_BOLD}" "${dev}" "${F_RESET}")"
  ip -s link show dev "$dev"
  if command -v ethtool &>/dev/null; then
    msg ""
    msg "$(L MSG_NET_0242 "${F_BOLD}" "${dev}" "${F_RESET}")"
    ethtool "$dev" 2>/dev/null | grep -E "Speed|Duplex|Link detected" | sed 's/^/  /'
    ethtool -i "$dev" 2>/dev/null | grep -E "^(driver|version|bus-info)" | sed 's/^/  /'
  else
    msg ""
    msg_info "$(L MSG_NET_0243)"
  fi
}

_nic_toggle() {
  local action="$1" dev="${2:-}"
  _nic_check_name "$dev" || return 1
  local def_if; def_if=$(_nic_default_iface)
  if [[ "$action" == "down" && "$dev" == "$def_if" ]]; then
    msg_warn "$(L MSG_NET_0244 "$dev")"
    confirm "$(L MSG_NET_0245 "$dev")" || { msg_info "$(L MSG_NET_0214)"; return 1; }
  fi
  if ! ip link set dev "$dev" "$action"; then
    msg_err "$(L MSG_NET_0246 "$dev" "$action")"
    return 1
  fi
  local st; st=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null || echo unknown)
  msg_ok "$(L MSG_NET_0247 "$dev" "$action" "$st")"
  _log_write "$(L MSG_NET_0248 "$dev" "$action")"
}

_nic_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0249)"
    msg ""
    _nic_list
    msg ""
    msg "$(L MSG_NET_0250)"
    msg "$(L MSG_NET_0251)"
    msg "$(L MSG_NET_0252)"
    msg "$(L MSG_NET_0253)"
    read -p "$(L MSG_NET_0234)" nic_choice || { msg ""; return; }
    case "$nic_choice" in
      1) nic_d=$(read_input "$(L MSG_NET_0254)") && _nic_info "$nic_d" && pause ;;
      2) nic_d=$(read_input "$(L MSG_NET_0255)") && _nic_toggle up "$nic_d" && pause ;;
      3) nic_d=$(read_input "$(L MSG_NET_0256)") && _nic_toggle down "$nic_d" && pause ;;
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
    *)     msg_err "$(L MSG_NET_0257 "$cmd")"; return 1 ;;
  esac
}

# ---- Help ----
network_help() {
  msg_title "$(L MSG_NET_0258)"
  msg ""
  msg "$(L MSG_NET_0259)"
  msg "$(L MSG_NET_0260)"
  msg "$(L MSG_NET_0261)"
  msg "$(L MSG_NET_0262)"
  msg "$(L MSG_NET_0263)"
  msg "$(L MSG_NET_0264)"
  msg "$(L MSG_NET_0265)"
  msg "$(L MSG_NET_0266)"
  msg ""
  msg "$(L MSG_NET_0267)"
  msg "$(L MSG_NET_0268)"
  msg "$(L MSG_NET_0269)"
  msg "$(L MSG_NET_0270)"
  msg ""
  msg "$(L MSG_NET_0271)"
  msg ""
  msg "$(L MSG_NET_0272)"
  msg "$(L MSG_NET_0273)"
  msg ""
}

# ---- Interactive Menu ----
network_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_NET_0274)"
    msg ""
    msg "$(L MSG_NET_0275 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0276 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0277 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0278 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0279 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0280 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0281 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0282 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0283 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0284 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_NET_0285 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_NET_0286)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
