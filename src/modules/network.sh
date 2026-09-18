# FusionBox Network Tools Module
# Network testing utilities

# ---- VPS 评测矩阵 数据表 ----
# 字段: 名称|分类|说明|来源URL|模式
# 模式: intensive = 吃资源/耗时长, normal = 轻量
# 表中 URL 均已逐个验证可访问（200/302），失效项已剔除
NETWORK_BENCH_ITEMS=(
  # ---- 综合评测 ----
  "YABS|综合评测|磁盘 IO、网络带宽与计算性能一条龙测试，含 fio 与 iperf3 数据|https://yabs.sh|intensive"
  "Bench|综合评测|经典轻量跑分脚本，输出 CPU、内存、磁盘与三网测速结果|https://bench.sh|intensive"
  "Geekbench 5|综合评测|调用 Geekbench 5 做 CPU 单核/多核基准，便于与公开成绩对比|https://raw.githubusercontent.com/i-abc/GB5/main/gb5-test.sh|intensive"
  "融合怪|综合评测|覆盖系统信息、硬件参数、线路质量与解锁情况的全能体检|https://github.com/spiritLHLS/ecs/raw/main/ecs.sh|intensive"
  "NodeQuality|综合评测|生成可在线分享的节点质量报告，含基础性能与网络概览|https://run.NodeQuality.com|normal"
  # ---- 网络测试 ----
  "NextTrace 快速回程|网络测试|列出到国内三网的回程线路走向，快速判断是否绕路|https://nxtrace.org/nt|normal"
  "多节点测速|网络测试|从多个国内节点并发测速，反映真实下载带宽|https://github.com/i-abc/Speedtest/raw/main/speedtest.sh|normal"
  "网络质量体检|网络测试|对 IPv4/IPv6 做连通性、延迟、丢包与路由的综合诊断|https://Net.Check.Place|intensive"
  "TCP 重传|网络测试|统计 TCP 重传率，用于定位链路抖动与拥塞|https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh|normal"
  "三网路由追踪|网络测试|分别经电信、联通、移动节点回程追踪，输出完整跳数路径|https://github.com/zhucaidan/mtr_trace/raw/main/mtr_trace.sh|normal"
  # ---- 解锁检测 ----
  "ChatGPT 解锁|解锁检测|检测当前 IP 能否正常访问 ChatGPT 及所属区域|https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh|normal"
  "流媒体可用性|解锁检测|批量探测 Netflix、YouTube、Disney+ 等平台的可用情况|https://github.com/yeahwu/check/raw/main/check.sh|normal"
  # ---- IP 质量 ----
  "IP 质量体检|IP 质量|评估 IP 纯净度、风险评分、流媒体与 AI 服务解锁状态|https://IP.Check.Place|normal"
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
    menu|main)        network_menu ;;
    help|h)           network_help ;;
    *)                network_menu ;;
  esac
}

# ---- IP Query ----
network_ip() {
  msg_title "IP 地址查询"
  msg ""

  msg "  ${F_BOLD}IPv4:${F_RESET} ${F_CYAN}${F_IP:-$(curl -s4 --connect-timeout 5 ip.sb 2>/dev/null || echo "N/A")}${F_RESET}"

  local ipv6; ipv6=$(curl -s6 --connect-timeout 5 ip.sb 2>/dev/null || echo "")
  if [[ -n "$ipv6" ]]; then
    msg "  ${F_BOLD}IPv6:${F_RESET} $ipv6"
  fi

  msg ""
  msg "  ${F_BOLD}[详细 IP 信息]${F_RESET}"
  # ip-api.com 免费接口仅 HTTP 明文，改用 HTTPS 的 ipinfo.io
  local ip_info; ip_info=$(curl -s --connect-timeout 5 https://ipinfo.io/json 2>/dev/null)
  if [[ -n "$ip_info" ]]; then
    local country;  country=$(echo "$ip_info" | grep -o '"country": *"[^"]*"' | cut -d'"' -f4)
    local region;   region=$(echo "$ip_info" | grep -o '"region": *"[^"]*"' | cut -d'"' -f4)
    local city;     city=$(echo "$ip_info" | grep -o '"city": *"[^"]*"' | cut -d'"' -f4)
    local org;      org=$(echo "$ip_info" | grep -o '"org": *"[^"]*"' | cut -d'"' -f4)

    msg "    国家: ${country:-N/A}"
    msg "    地区: ${region:-N/A}"
    msg "    城市: ${city:-N/A}"
    msg "    ISP/组织: ${org:-N/A}"
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
  msg_title "流媒体测试"
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
  msg_title "网速测试"
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
  msg_title "DNS 测试"
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

  # 输入校验：主机/端口直接拼入 /dev/tcp，必须先过滤
  [[ "$host" =~ ^[a-zA-Z0-9._-]+$ ]] || { msg_err "无效的主机名（仅允许字母数字与 . _ -）"; pause; return 1; }
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || { msg_err "无效端口（1-65535）"; pause; return 1; }

  msg_title "端口检测: $host:$port"
  msg ""
  timeout 5 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null && \
    msg_ok "端口 $port 在 $host 上${F_GREEN}开放${F_RESET}" || \
    msg_err "端口 $port 在 $host 上${F_RED}关闭${F_RESET}或被过滤"
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
    echo "${F_YELLOW}重型${F_RESET}"
  else
    echo "${F_GREEN}轻量${F_RESET}"
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
  msg "${F_BOLD}VPS 评测矩阵${F_RESET}（共 ${#NETWORK_BENCH_ITEMS[@]} 项）"
  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    idx=$((idx + 1))
    if [[ "$cat" != "$cur_cat" ]]; then
      cur_cat="$cat"
      msg ""
      msg "  ${F_CYAN}${F_BOLD}[$cat]${F_RESET}"
    fi
    printf -v num '%2d' "$idx"
    msg "  ${F_GREEN}${num}${F_RESET}) ${F_BOLD}${name}${F_RESET}  模式: $(_network_bench_mode_label "$mode")"
    msg "      ${desc}"
    msg "      来源: $(_network_bench_domain "$url")"
  done
  msg ""
}

# 执行单个评测项: $1=名称 $2=说明 $3=URL $4=模式 $5=auto 表示批量模式（不再逐项确认）
_network_bench_execute() {
  local name="$1" desc="$2" url="$3" mode="$4" auto="${5:-}"

  msg_title "VPS 评测: $name"
  msg ""
  msg "  说明: $desc"
  msg "  模式: $(_network_bench_mode_label "$mode")"

  # 重型项目：内存不足且无 swap 时仅提示，不自动创建
  if [[ "$mode" == "intensive" ]]; then
    local mem_mb swap_mb
    mem_mb=$(_network_bench_mem_mb)
    swap_mb=$(_network_bench_swap_mb)
    if [[ -n "$mem_mb" && "$mem_mb" -lt 1024 && "$swap_mb" -eq 0 ]]; then
      msg_warn "当前内存 ${mem_mb}MB 且未启用 swap，重型评测可能因内存不足而中断"
      msg_warn "建议先执行: fusionbox system swap（本操作不会自动创建 swap）"
    fi
  fi

  [[ "$F_IS_ROOT" == "1" ]] || msg_warn "当前非 root，部分评测项可能无法采集完整数据"

  msg ""
  msg "  来源: ${F_ULINE}${url}${F_RESET}"
  msg ""
  if [[ "$auto" != "auto" ]]; then
    confirm "确认下载并运行该评测脚本？" || { msg_info "已取消"; return 0; }
  fi

  local tmp; tmp=$(mktemp)
  if ! _download "$url" "$tmp"; then
    msg_err "脚本下载失败: $url"
    msg_err "可能是本机网络不通或上游脚本已失效，请稍后重试"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi
  if [[ ! -s "$tmp" ]]; then
    msg_err "下载内容为空: $url"
    rm -f "$tmp"
    [[ "$auto" != "auto" ]] && pause
    return 1
  fi

  _log_write "VPS 评测开始: $name ($url)"
  bash "$tmp"
  local rc=$?
  rm -f "$tmp"

  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "评测脚本执行完成: $name"
  else
    msg_warn "评测脚本退出码: $rc（部分脚本以非零码结束属正常）"
  fi
  _log_write "VPS 评测结束: $name (退出码 $rc)"
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
  msg_err "未找到评测项: $want（可用序号或名称）"
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

  msg_info "将依次运行 ${count} 个轻量评测项（重型项目请单独运行）"
  confirm "确认继续？" || { msg_info "已取消"; return 0; }

  for item in "${NETWORK_BENCH_ITEMS[@]}"; do
    IFS='|' read -r name cat desc url mode <<< "$item"
    [[ "$mode" == "normal" ]] || continue
    _network_bench_execute "$name" "$desc" "$url" "$mode" auto || failed=1
  done
  msg_ok "轻量评测项已全部执行完毕"
  _log_write "VPS 轻量评测批量执行完成"
  return "$failed"
}

# 自定义 URL 运行
network_bench_custom() {
  local url; url=$(read_input "请输入评测脚本 URL (https:// 开头)")
  if [[ -z "$url" ]]; then
    msg_info "未输入 URL，已取消"
    return 0
  fi
  if [[ "$url" != https://* ]]; then
    msg_err "仅支持 https:// 开头的地址: $url"
    pause
    return 1
  fi
  _network_bench_execute "自定义脚本" "用户提供的自定义评测脚本" "$url" "normal"
}

# 交互式矩阵菜单
network_bench_menu() {
  while true; do
    clear
    _print_banner
    msg_title "VPS 评测矩阵"
    msg ""
    network_bench_list
    msg "  输入 ${F_GREEN}序号${F_RESET} 或 ${F_GREEN}名称${F_RESET} 运行；${F_GREEN}l${F_RESET}) 仅列表  ${F_GREEN}a${F_RESET}) 运行全部轻量项  ${F_GREEN}u${F_RESET}) 自定义 URL  ${F_GREEN}0${F_RESET}) 返回"
    msg ""
    read -p "请选择: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
  [[ "$1" =~ ^[a-zA-Z0-9._-]{1,15}$ ]] || { msg_err "网卡名无效: $1"; return 1; }
  ip link show dev "$1" &>/dev/null || { msg_err "网卡不存在: $1"; return 1; }
}

_nic_default_iface() {
  ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

_nic_list() {
  msg "  ${F_BOLD}网卡与地址 (ip -br addr):${F_RESET}"
  ip -br addr 2>/dev/null || ip addr show
  msg ""
  msg "  ${F_BOLD}默认路由网卡:${F_RESET} $(_nic_default_iface)"
  msg "  启停网卡前请注意：停用承载 SSH 连接的网卡会立即断开你的会话"
}

_nic_info() {
  local dev="${1:-}"
  _nic_check_name "$dev" || return 1
  msg "  ${F_BOLD}地址 (${dev}):${F_RESET}"
  ip addr show dev "$dev"
  msg ""
  msg "  ${F_BOLD}计数器 (${dev}):${F_RESET}"
  ip -s link show dev "$dev"
  if command -v ethtool &>/dev/null; then
    msg ""
    msg "  ${F_BOLD}链路与驱动 (${dev}):${F_RESET}"
    ethtool "$dev" 2>/dev/null | grep -E "Speed|Duplex|Link detected" | sed 's/^/  /'
    ethtool -i "$dev" 2>/dev/null | grep -E "^(driver|version|bus-info)" | sed 's/^/  /'
  else
    msg ""
    msg_info "未安装 ethtool，跳过链路/驱动详情"
  fi
}

_nic_toggle() {
  local action="$1" dev="${2:-}"
  _nic_check_name "$dev" || return 1
  local def_if; def_if=$(_nic_default_iface)
  if [[ "$action" == "down" && "$dev" == "$def_if" ]]; then
    msg_warn "$dev 承载默认路由。停用它很可能立即切断你的 SSH 会话与本机外网连接"
    confirm "我了解风险，确认停用 $dev？" || { msg_info "已取消"; return 1; }
  fi
  if ! ip link set dev "$dev" "$action"; then
    msg_err "ip link set dev $dev $action 失败"
    return 1
  fi
  local st; st=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null || echo unknown)
  msg_ok "$dev 已 $action (operstate: $st)"
  _log_write "网卡 $dev 已 $action"
}

_nic_menu() {
  while true; do
    clear
    _print_banner
    msg_title "网卡管理"
    msg ""
    _nic_list
    msg ""
    msg "  1) 网卡详情（地址/计数器/ethtool）"
    msg "  2) 启用网卡 (up)"
    msg "  3) 停用网卡 (down)"
    msg "  0) 返回"
    read -p "请选择: " nic_choice || { msg ""; return; }
    case "$nic_choice" in
      1) nic_d=$(read_input "网卡名（如 eth0/ens3）") && _nic_info "$nic_d" && pause ;;
      2) nic_d=$(read_input "要启用的网卡名") && _nic_toggle up "$nic_d" && pause ;;
      3) nic_d=$(read_input "要停用的网卡名") && _nic_toggle down "$nic_d" && pause ;;
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
    *)     msg_err "未知子命令: $cmd（可用: list/info/up/down）"; return 1 ;;
  esac
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
  msg "  fusionbox network bench            VPS 评测矩阵 (交互式)"
  msg "  fusionbox network bench list       列出全部评测项"
  msg "  fusionbox network bench <序号|名称>  运行指定评测项"
  msg "  fusionbox network bench all        依次运行全部轻量评测项"
  msg ""
  msg "  fusionbox network nic          网卡管理 (list/info/up/down)"
  msg ""
  msg "  评测项分综合评测 / 网络测试 / 解锁检测 / IP 质量四类，"
  msg "  运行前会显示来源 URL 并二次确认，脚本仅在临时文件中执行。"
  msg ""
}

# ---- Interactive Menu ----
network_menu() {
  while true; do
    clear
    _print_banner
    msg_title "网络工具"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) IP 地址查询"
    msg "  ${F_GREEN}2${F_RESET}) 流媒体测试"
    msg "  ${F_GREEN}3${F_RESET}) 网速测试"
    msg "  ${F_GREEN}4${F_RESET}) DNS 测试"
    msg "  ${F_GREEN}5${F_RESET}) 路由追踪"
    msg "  ${F_GREEN}6${F_RESET}) Ping 测试"
    msg "  ${F_GREEN}7${F_RESET}) MTR 报告"
    msg "  ${F_GREEN}8${F_RESET}) 端口检测"
    msg "  ${F_GREEN}9${F_RESET}) VPS 评测矩阵"
    msg "  ${F_GREEN}10${F_RESET}) 网卡管理"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-10]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
