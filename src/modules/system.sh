# FusionBox System Management Module
# System administration, BBR, benchmark, backup

system_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    info|i)           system_info "$@" ;;
    bbr)              system_bbr "$@" ;;
    benchmark|bench)  system_benchmark "$@" ;;
    monitor|top)      system_monitor "$@" ;;
    backup)           system_backup "$@" ;;
    restore)          system_restore "$@" ;;
    update|up)        system_update "$@" ;;
    clean|cleanup)    system_clean "$@" ;;
    swap)             system_swap "$@" ;;
    users)            system_users "$@" ;;
    security|sec)     system_security "$@" ;;
    menu|main)        system_menu ;;
    help|h)           system_help ;;
    *)                system_menu ;;
  esac
}

# ---- System Info ----
system_info() {
  _require_root
  msg_title "系统信息"
  msg ""

  # CPU
  local cpu_model; cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs)
  local cpu_cores; cpu_cores=$(nproc --all)
  msg "  ${F_BOLD}CPU:${F_RESET} ${cpu_model:-未知} (${cpu_cores} 核)"

  # Load
  local load; load=$(uptime | awk -F'average:' '{print $2}' | xargs)
  msg "  ${F_BOLD}负载:${F_RESET} $load"

  # Memory
  msg "  ${F_BOLD}内存:${F_RESET}"
  free -h | awk 'NR==1{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'
  free -h | awk 'NR==2{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'

  # Disk
  msg "  ${F_BOLD}磁盘:${F_RESET}"
  df -h / /boot /home 2>/dev/null | awk 'NR>0{print "            " $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}'

  # Network
  msg "  ${F_BOLD}网络:${F_RESET}"
  ip addr show | grep -E "inet " | grep -v "127.0.0.1" | awk '{print "            " $NF ": " $2}'

  # OS
  msg "  ${F_BOLD}系统:${F_RESET} $F_OS_NAME $F_OS_VER ($F_ARCH)"
  msg "  ${F_BOLD}内核:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}运行时间:${F_RESET} $(uptime -p 2>/dev/null | sed 's/up //')"
  msg "  ${F_BOLD}虚拟化:${F_RESET} $F_VIRT"

  # BBR status
  local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
  msg "  ${F_BOLD}拥塞控制:${F_RESET} $cc"
  local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
  msg "  ${F_BOLD}队列算法:${F_RESET} $qdisc"

  # Security
  if command -v ufw &>/dev/null; then
    msg "  ${F_BOLD}UFW:${F_RESET} $(ufw status 2>/dev/null | head -1)"
  fi
  if command -v fail2ban-client &>/dev/null; then
    msg "  ${F_BOLD}Fail2Ban:${F_RESET} $(fail2ban-client status 2>/dev/null | head -1 || echo "运行中")"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    msg "  ${F_BOLD}Docker:${F_RESET} $(docker --version 2>/dev/null)"
  fi

  # Proxy status
  if [[ -f /etc/fusionbox/proxy/current_backend ]]; then
    local proxy_be=$(cat /etc/fusionbox/proxy/current_backend)
    local proxy_st="已停止"
    systemctl is-active fusionbox-proxy &>/dev/null && proxy_st="运行中"
    msg "  ${F_BOLD}代理:${F_RESET} $proxy_be ($proxy_st)"
  fi

  msg ""
  pause
}

# ---- BBR Management ----
system_bbr() {
  _require_root
  msg_title "BBR 管理"
  msg ""

  # Detect current status
  local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
  local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
  local kmaj; kmaj=$(uname -r | cut -d. -f1)
  local kmin; kmin=$(uname -r | cut -d. -f2)
  local kpatch; kpatch=$(uname -r | cut -d. -f3)

  msg "  ${F_BOLD}当前拥塞控制:${F_RESET} $cc"
  msg "  ${F_BOLD}当前队列算法:${F_RESET} $qdisc"
  msg "  ${F_BOLD}内核版本:${F_RESET} $(uname -r)"
  msg ""

  # Detect BBR version
  local bbr_ver="未启用"
  if [[ "$cc" == "bbr" ]]; then
    if modinfo tcp_bbr2 &>/dev/null && lsmod | grep -q tcp_bbr2; then
      bbr_ver="BBRv2"
    elif echo "$kpatch" | grep -qi "bbrplus\|bbr2\|bbr_new"; then
      bbr_ver="BBRplus/BBRv3"
    else
      bbr_ver="BBR v1"
    fi
    msg "  ${F_BOLD}BBR 版本:${F_RESET} ${F_GREEN}$bbr_ver${F_RESET}"
  else
    msg "  ${F_BOLD}BBR 版本:${F_RESET} ${F_YELLOW}未启用${F_RESET}"
  fi

  # Check available BBR modules
  msg ""
  msg "  ${F_BOLD}[可用 BBR 模块]${F_RESET}"
  if modinfo tcp_bbr &>/dev/null; then
    msg "    ${F_GREEN}[可用]${F_RESET} tcp_bbr (BBR v1)"
  else
    msg "    ${F_RED}[不可用]${F_RESET} tcp_bbr (BBR v1)"
  fi
  if modinfo tcp_bbr2 &>/dev/null; then
    msg "    ${F_GREEN}[可用]${F_RESET} tcp_bbr2 (BBR v2)"
  else
    msg "    ${F_YELLOW}[不可用]${F_RESET} tcp_bbr2 (BBR v2) - 需要内核 5.18+ 或补丁"
  fi

  msg ""
  msg "  ${F_BOLD}[操作]${F_RESET}"
  if [[ "$cc" == "bbr" ]]; then
    msg "  ${F_GREEN}1${F_RESET}) 切换为 BBR v1"
    if modinfo tcp_bbr2 &>/dev/null; then
      msg "  ${F_GREEN}2${F_RESET}) 切换为 BBR v2"
    fi
    msg "  ${F_GREEN}3${F_RESET}) 禁用 BBR (恢复为 cubic)"
    msg "  ${F_GREEN}4${F_RESET}) 更新内核以获取 BBRv2/BBRplus 支持"
    msg "  ${F_GREEN}5${F_RESET}) 代理程序 BBR 配置说明"
  else
    msg "  ${F_GREEN}1${F_RESET}) 启用 BBR v1"
    if modinfo tcp_bbr2 &>/dev/null; then
      msg "  ${F_GREEN}2${F_RESET}) 启用 BBR v2"
    fi
    msg "  ${F_GREEN}3${F_RESET}) 更新内核以获取 BBRv2/BBRplus 支持"
    msg "  ${F_GREEN}4${F_RESET}) 代理程序 BBR 配置说明"
  fi
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择: " bbr_choice

  case "$bbr_choice" in
    1)
      _system_enable_bbr "bbr" "fq"
      ;;
    2)
      if modinfo tcp_bbr2 &>/dev/null; then
        modprobe tcp_bbr2 2>/dev/null
        _system_enable_bbr "bbr2" "fq"
      else
        msg_err "tcp_bbr2 模块不可用，请先更新内核"
      fi
      ;;
    3)
      if [[ "$cc" == "bbr" ]]; then
        _system_disable_bbr
      else
        _system_install_kernel_for_bbr
      fi
      ;;
    4)
      if [[ "$cc" == "bbr" ]]; then
        _system_install_kernel_for_bbr
      else
        _system_proxy_bbr_info
      fi
      ;;
    5)
      if [[ "$cc" == "bbr" ]]; then
        _system_proxy_bbr_info
      fi
      ;;
  esac
  pause
}

_system_enable_bbr() {
  local algo="$1" qdisc="$2"
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  cat >> /etc/sysctl.conf << SEOF

# FusionBox BBR 设置
net.ipv4.tcp_congestion_control = $algo
net.core.default_qdisc = $qdisc
SEOF
  sysctl -p 2>/dev/null
  modprobe tcp_${algo} 2>/dev/null
  local new_cc; new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  if [[ "$new_cc" == "$algo" ]]; then
    msg_ok "已启用 $algo (队列: $qdisc)"
  else
    msg_warn "设置已写入，但当前仍为 $new_cc，可能需要重启"
  fi
  _log_write "BBR 已启用: $algo"
}

_system_disable_bbr() {
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  cat >> /etc/sysctl.conf << 'SEOF'

# FusionBox BBR 设置
net.ipv4.tcp_congestion_control = cubic
net.core.default_qdisc = fq
SEOF
  sysctl -p 2>/dev/null
  msg_info "已恢复为 cubic"
  _log_write "BBR 已禁用，恢复为 cubic"
}

_system_install_kernel_for_bbr() {
  msg_title "更新内核以支持 BBRv2/BBRplus"
  msg ""
  local kmaj; kmaj=$(uname -r | cut -d. -f1)
  local kmin; kmin=$(uname -r | cut -d. -f2)

  msg_info "当前内核: $(uname -r)"
  msg ""
  msg "  BBR 各版本内核要求："
  msg "    BBR v1:    内核 4.9+（当前$( [[ $kmaj -ge 5 || ($kmaj -eq 4 && $kmin -ge 9) ]] && echo "满足" || echo "不满足" )）"
  msg "    BBR v2:    内核 5.18+（当前$( [[ $kmaj -ge 6 || ($kmaj -eq 5 && $kmin -ge 18) ]] && echo "满足" || echo "不满足" )）"
  msg "    BBRplus:   需要打补丁内核（cx9208/Linux-NetSpeed 或 ylx2016/Linux-NetSpeed）"
  msg ""

  if [[ $kmaj -ge 6 ]] || [[ $kmaj -eq 5 && $kmin -ge 18 ]]; then
    msg_ok "当前内核已支持 BBRv2，尝试加载模块..."
    if modprobe tcp_bbr2 2>/dev/null; then
      msg_ok "tcp_bbr2 模块加载成功"
      if confirm "是否启用 BBRv2？"; then
        _system_enable_bbr "bbr2" "fq"
      fi
    else
      msg_warn "模块加载失败，可能需要重新编译内核"
    fi
    return
  fi

  msg "  更新内核选项："
  msg "  ${F_GREEN}1${F_RESET}) 安装发行版最新内核（推荐）"
  msg "  ${F_GREEN}2${F_RESET}) 安装 BBRplus 补丁内核（适用于 4.9-5.17 内核）"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  read -p "请选择: " kc_choice

  case "$kc_choice" in
    1)
      _system_install_kernel
      ;;
    2)
      _system_install_bbrplus_kernel
      ;;
  esac
}

_system_install_bbrplus_kernel() {
  msg_info "正在安装 BBRplus 补丁内核..."
  msg ""

  case "$F_PKG_MGR" in
    apt)
      local tmpdir=$(mktemp -d)
      # Use cx9208/Linux-NetSpeed scripts
      msg_info "正在下载内核安装脚本..."
      _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
      _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
        msg_err "下载失败，请检查网络"
        rm -rf "$tmpdir"
        return 1
      }
      msg_info "已下载安装脚本"
      msg_warn "即将运行内核安装脚本，请按提示操作"
      msg ""
      if confirm "运行 BBRplus 内核安装脚本？"; then
        bash "$tmpdir/tcp.sh"
      fi
      rm -rf "$tmpdir"
      ;;
    yum)
      msg_info "CentOS/RHEL 系统请手动编译内核"
      msg_info "参考: https://github.com/cx9208/Linux-NetSpeed"
      ;;
    *)
      msg_err "当前包管理器不支持自动安装补丁内核"
      msg_info "请参考: https://github.com/cx9208/Linux-NetSpeed"
      ;;
  esac
}

_system_proxy_bbr_info() {
  msg_title "代理程序 BBR 配置说明"
  msg ""
  msg "  ${F_BOLD}BBR 与代理程序的关系：${F_RESET}"
  msg "  BBR 是内核级别的 TCP 拥塞控制算法，对所有 TCP 连接生效，"
  msg "  包括代理程序的 TCP 传输（VLESS-TCP、VMess-TCP、Trojan 等）。"
  msg ""
  msg "  ${F_BOLD}各代理后端 BBR 相关配置：${F_RESET}"
  msg ""
  msg "  ${F_CYAN}Xray-core${F_RESET} (推荐):"
  msg "    - TCP 传输自动使用系统 BBR"
  msg "    - QUIC/HTTPUpgrade 有内置拥塞控制配置"
  msg "    - streamSettings 可配置 tcpSettings.congestionControl"
  msg ""
  msg "  ${F_CYAN}v2ray-core${F_RESET}:"
  msg "    - TCP 传输自动使用系统 BBR"
  msg "    - QUIC 传输有拥塞控制选项"
  msg "    - 建议配合 mKCP 使用 utcpCongestion: bbr"
  msg ""
  msg "  ${F_CYAN}sing-box${F_RESET}:"
  msg "    - TCP 传输自动使用系统 BBR"
  msg "    - QUIC/HTTPUpgrade 支持 congestion_control 配置"
  msg "    - hysteria2/tuic 协议自带拥塞控制"
  msg ""
  msg "  ${F_CYAN}Clash.Meta${F_RESET}:"
  msg "    - TCP 传输自动使用系统 BBR"
  msg "    - hysteria/tuic 节点有独立拥塞控制"
  msg ""
  msg "  ${F_BOLD}建议：${F_RESET}"
  msg "  1. 先在系统层面启用 BBR（选项 1）"
  msg "  2. TCP 类型协议自动受益于系统 BBR"
  msg "  3. UDP/QUIC 类型协议使用各自内置拥塞控制"
  msg "  4. BBRv2/BBRplus 在高丢包网络下表现更好"
  msg ""
}

_system_install_kernel() {
  case "$F_PKG_MGR" in
    apt)
      msg_info "正在更新软件包列表..."
      apt-get update -y
      msg_info "正在安装新内核..."
      apt-get install -y linux-image-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null || \
      apt-get install -y --install-recommends linux-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null
      msg_info "内核安装完成，需要重启。"
      if confirm "是否立即重启？"; then
        reboot
      fi
      ;;
    yum)
      # Install ELrepo and kernel-lt
      rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || true
      yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm 2>/dev/null || true
      yum --enablerepo=elrepo-kernel install -y kernel-lt 2>/dev/null || true
      if grub2-set-default 0 2>/dev/null; then
        msg_info "内核安装完成，需要重启。"
        confirm "是否立即重启？" && reboot
      fi
      ;;
  esac
}

# ---- Benchmark (SuperBench style) ----
system_benchmark() {
  _require_root
  msg_title "系统基准测试"
  msg ""
  msg_info "正在运行基准测试..."

  # CPU - simple sieve
  msg "  ${F_BOLD}CPU 核心:${F_RESET} $(nproc --all)"
  local cpu_start; cpu_start=$(date +%s)
  local prime_count=0
  for ((i=2; i<=50000; i++)); do
    local is_prime=1
    for ((j=2; j*j<=i; j++)); do
      if ((i % j == 0)); then is_prime=0; break; fi
    done
    ((is_prime)) && ((prime_count++))
  done
  local cpu_end; cpu_end=$(date +%s)
  local cpu_time=$((cpu_end - cpu_start))
  msg "  ${F_BOLD}CPU 测试:${F_RESET} ${cpu_time}秒内计算 $prime_count 个素数 (5万筛法)"

  # Memory speed test
  msg "  ${F_BOLD}内存:${F_RESET}"
  free -h | awk '/Mem:/{printf "    Total: %s  Used: %s  Free: %s\n", $2, $3, $4}'
  free -h | awk '/Swap:/{printf "    Swap: %s  Used: %s  Free: %s\n", $2, $3, $4}'

  # Disk I/O test
  msg "  ${F_BOLD}磁盘 I/O (dd 测试):${F_RESET}"
  local io_write; io_write=$(dd if=/dev/zero of=/tmp/fusionbench bs=1M count=1024 conv=fdatasync 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "    写入: ${io_write:-测试失败}"
  sync
  local io_read; io_read=$(dd if=/tmp/fusionbench of=/dev/null bs=1M count=1024 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "    读取: ${io_read:-测试失败}"
  rm -f /tmp/fusionbench

  # Network speed test
  msg "  ${F_BOLD}网络:${F_RESET}"
  _get_ip
  msg "    IPv4: ${F_IP:-未知}"
  msg "    IPv6: ${F_IPV6:-未知}"

  # Optional: download speedtest
  if confirm "是否运行网络测速？（会下载测试文件）"; then
    msg_info "正在测试下载速度..."
    local dl_start; dl_start=$(date +%s)
    _download "https://speed.cloudflare.com/__down?bytes=104857600" /tmp/speedtest 2>/dev/null &
    local dl_pid=$!
    local dl_size=0
    while kill -0 "$dl_pid" 2>/dev/null; do
      sleep 1
      local new_size; new_size=$(stat -c%s /tmp/speedtest 2>/dev/null || echo 0)
      local elapsed=$(( $(date +%s) - dl_start ))
      if [[ $elapsed -ge 15 ]]; then
        kill "$dl_pid" 2>/dev/null
        break
      fi
      dl_size=$new_size
    done
    kill "$dl_pid" 2>/dev/null || true
    local elapsed=$(( $(date +%s) - dl_start ))
    [[ $elapsed -lt 1 ]] && elapsed=1
    local speed_mbps=$(( dl_size * 8 / elapsed / 1048576 ))
    msg "    下载速度: ~${speed_mbps} Mbps"
    rm -f /tmp/speedtest
  fi

  msg ""
  _log_write "基准测试完成"
  pause
}

# ---- System Monitor (top-like) ----
system_monitor() {
  msg_title "系统监控"
  msg "按 Ctrl+C 退出"
  msg ""

  local interval="${1:-5}"
  while true; do
    clear
    msg "${F_BOLD}${F_CYAN}FusionBox 系统监控 (每 ${interval} 秒刷新)${F_RESET}"
    msg "${F_BOLD}时间:${F_RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    msg ""

    # CPU & Load
    msg "${F_BOLD}[CPU 与负载]${F_RESET}"
    local load; load=$(cat /proc/loadavg 2>/dev/null)
    msg "  负载均衡: $load"
    msg "  进程数: $(ps aux | wc -l)"

    # CPU usage
    local cpu_idle; cpu_idle=$(top -bn1 2>/dev/null | grep "%Cpu" | awk '{print $8}' | cut -d. -f1)
    if [[ -n "$cpu_idle" && "$cpu_idle" -le 100 ]]; then
      msg "  CPU 使用率: $((100 - cpu_idle))%"
    fi

    # Top processes
    msg ""
    msg "${F_BOLD}[CPU 占用 Top 进程]${F_RESET}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | awk 'NR>1{printf "  %-12s %-6s %-5s %s\n", $1, $2, $3"%", $11}'

    # Memory
    msg ""
    msg "${F_BOLD}[内存]${F_RESET}"
    free -h | awk 'NR==1{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'
    free -h | awk 'NR==2{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'

    # Disk
    msg ""
    msg "${F_BOLD}[磁盘]${F_RESET}"
    df -h / 2>/dev/null | awk 'NR==2{printf "  %-15s %-10s %-10s %s\n", $1, $2, $3, $5}'

    # Network connections
    msg ""
    msg "${F_BOLD}[网络]${F_RESET}"
    if command -v ss &>/dev/null; then
      msg "  连接数: $(ss -tlnp 2>/dev/null | wc -l) 监听中, $(ss -tan 2>/dev/null | wc -l) 总计"
    fi
    msg "  IP: ${F_IP:-$(curl -s ip.sb 2>/dev/null || echo "N/A")}"

    # Proxy
    if systemctl is-active fusionbox-proxy &>/dev/null; then
      local pbe=$(cat /etc/fusionbox/proxy/current_backend 2>/dev/null || echo "proxy")
      msg "  代理: ${F_GREEN}$pbe 运行中${F_RESET}"
    fi

    sleep "$interval"
  done
}

# ---- System Backup ----
system_backup() {
  _require_root
  local backup_dir="${1:-/root/backups}"
  mkdir -p "$backup_dir"

  local date_str; date_str=$(date '+%Y%m%d_%H%M%S')
  local backup_file="$backup_dir/fusionbox_backup_$date_str.tar.gz"

  msg_title "系统备份"
  msg ""

  local dirs_to_backup=(
    "/etc/fusionbox/proxy" "/etc/nginx" "/etc/caddy"
    "/etc/fusionbox" "/var/www"
    "/opt/docker"
  )

  msg_info "正在备份到: $backup_file"
  local tar_cmd="tar czf"
  local exists=0
  for d in "${dirs_to_backup[@]}"; do
    if [[ -d "$d" ]]; then
      tar_cmd+=" $d"
      exists=1
    fi
  done

  if [[ $exists -eq 1 ]]; then
    tar czf "$backup_file" "${dirs_to_backup[@]}" 2>/dev/null
    if [[ -f "$backup_file" ]]; then
      local size; size=$(du -h "$backup_file" | cut -f1)
      msg_ok "备份已创建: $backup_file ($size)"
      _log_write "系统备份已创建: $backup_file"
    else
      msg_err "备份失败"
    fi
  else
    msg_warn "没有可备份的目录"
  fi
  pause
}

system_restore() {
  _require_root
  local backup_dir="${1:-/root/backups}"

  msg_title "系统恢复"
  msg ""

  local backups=()
  for f in "$backup_dir"/fusionbox_backup_*.tar.gz; do
    [[ -f "$f" ]] && backups+=("$f")
  done

  if [[ ${#backups[@]} -eq 0 ]]; then
    msg_warn "在 $backup_dir 中未找到备份文件"
    pause
    return
  fi

  msg_info "可用备份:"
  local i=1
  for f in "${backups[@]}"; do
    local size; size=$(du -h "$f" | cut -f1)
    local date_str; date_str=$(basename "$f" .tar.gz | sed 's/fusionbox_backup_//')
    msg "  $i) $date_str ($size)"
    i=$((i+1))
  done
  msg ""

  read -p "请选择要恢复的备份: " choice
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
    if confirm "这将覆盖现有文件，确认继续？"; then
      tar xzf "${backups[$idx]}" -C /
      msg_ok "恢复完成"
      _log_write "系统已从备份恢复: ${backups[$idx]}"
    fi
  fi
  pause
}

# ---- System Update ----
system_update() {
  _require_root
  msg_title "系统更新"
  msg ""

  case "$F_PKG_MGR" in
    apt)
      apt-get update -y
      apt-get upgrade -y
      apt-get autoremove -y
      ;;
    yum)
      yum update -y
      yum autoremove -y
      ;;
    apk)
      apk update
      apk upgrade
      ;;
    zypper)
      zypper update -y
      ;;
  esac

  msg_ok "系统更新完成"
  _log_write "系统已更新"

  if [[ -f /var/run/reboot-required ]]; then
    msg_warn "需要重启以应用更新"
    if confirm "是否立即重启？"; then
      reboot
    fi
  fi
  pause
}

# ---- System Cleanup ----
system_clean() {
  _require_root
  msg_title "系统清理"
  msg ""

  msg_info "正在清理软件包缓存..."
  case "$F_PKG_MGR" in
    apt)
      apt-get autoremove -y
      apt-get autoclean -y
      ;;
    yum)
      yum autoremove -y
      yum clean all
      ;;
    apk)
      apk cache clean
      ;;
  esac

  msg_info "正在清理系统日志..."
  journalctl --vacuum-time=7d 2>/dev/null || true

  msg_info "正在清理临时文件..."
  rm -rf /tmp/*.tmp 2>/dev/null || true
  rm -rf /tmp/fusion* 2>/dev/null || true

  msg_info "正在清理 Docker（如已安装）..."
  if command -v docker &>/dev/null; then
    docker system prune -f --volumes 2>/dev/null || true
  fi

  msg_ok "系统清理完成"
  _log_write "系统清理完成"
  pause
}

# ---- Swap Management ----
system_swap() {
  _require_root
  msg_title "Swap 管理"
  msg ""

  msg "  当前 Swap:"
  swapon --show 2>/dev/null || msg "    暂无 Swap"
  free -h | awk '/Swap:/{printf "    %s %s %s\n", $2, $3, $4}'

  msg ""
  msg "  1) 创建 Swap 文件 (2GB)"
  msg "  2) 删除所有 Swap"
  msg "  0) 返回"
  read -p "请选择: " sw_choice

  case "$sw_choice" in
    1)
      if confirm "确认创建 2GB Swap 文件？"; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
        msg_ok "Swap 已创建 (2GB)"
        free -h | grep Swap
        _log_write "2GB Swap 已创建"
      fi
      ;;
    2)
      if confirm "警告：将删除所有 Swap，确认继续？"; then
        swapoff -a 2>/dev/null || true
        rm -f /swapfile 2>/dev/null || true
        sed -i '/swapfile/d' /etc/fstab
        msg_ok "Swap 已删除"
        _log_write "Swap 已删除"
      fi
      ;;
  esac
  pause
}

# ---- User Management ----
system_users() {
  _require_root
  msg_title "用户管理"
  msg ""
  msg "  ${F_BOLD}系统用户:${F_RESET}"
  awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s, shell=%s)\n", $1, $3, $7}' /etc/passwd
  msg ""
  msg "  ${F_BOLD}最近登录:${F_RESET}"
  last -n 10 2>/dev/null | head -10
  msg ""
  pause
}

# ---- Security Audit ----
system_security() {
  _require_root
  msg_title "安全审计"
  msg ""

  msg "${F_BOLD}[SSH 配置]${F_RESET}"
  local ssh_port; ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  msg "  SSH 端口: ${ssh_port:-22 (默认)}"
  if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "  ${F_YELLOW}Root 登录: 已启用（建议禁用）${F_RESET}"
  else
    msg "  ${F_GREEN}Root 登录: 已禁用或仅密钥${F_RESET}"
  fi
  if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "  ${F_YELLOW}密码认证: 已启用（建议仅密钥）${F_RESET}"
  fi

  msg ""
  msg "${F_BOLD}[防火墙]${F_RESET}"
  if command -v ufw &>/dev/null; then
    ufw status 2>/dev/null | head -5
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all 2>/dev/null | head -5
  else
    msg "  未检测到防火墙（推荐: ufw）"
  fi

  msg ""
  msg "${F_BOLD}[Fail2Ban]${F_RESET}"
  if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status 2>/dev/null || msg "  Fail2Ban 未运行"
  else
    msg "  未安装（推荐安装）"
  fi

  msg ""
  msg "${F_BOLD}[开放端口]${F_RESET}"
  ss -tlnp 2>/dev/null | awk 'NR>1{printf "  %s %s\n", $4, $NF}'

  msg ""
  msg "  1) 安装并启用 UFW 防火墙"
  msg "  2) 安装 Fail2Ban"
  msg "  3) 修改 SSH 端口"
  msg "  0) 返回"
  read -p "请选择: " sec_choice

  case "$sec_choice" in
    1)
      _install_pkg ufw
      ufw allow ssh
      ufw --force enable
      msg_ok "UFW 已启用（SSH 已放行）"
      ;;
    2)
      _install_pkg fail2ban
      systemctl enable --now fail2ban 2>/dev/null || true
      msg_ok "Fail2Ban 已安装并启动"
      ;;
    3)
      read -p "请输入新的 SSH 端口: " new_port
      if [[ -n "$new_port" && "$new_port" =~ ^[0-9]+$ ]]; then
        sed -i "s/^#\?Port .*/Port $new_port/" /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        msg_ok "SSH 端口已修改为 $new_port"
        if command -v ufw &>/dev/null; then
          ufw allow "$new_port"/tcp
        fi
        _log_write "SSH 端口已更改为 $new_port"
      fi
      ;;
  esac
  pause
}

# ---- Help ----
system_help() {
  msg_title "系统管理 帮助"
  msg ""
  msg "  fusionbox system info           查看系统信息"
  msg "  fusionbox system bbr            BBR 管理"
  msg "  fusionbox system benchmark      运行基准测试"
  msg "  fusionbox system monitor        实时系统监控"
  msg "  fusionbox system backup         备份系统配置"
  msg "  fusionbox system restore        从备份恢复"
  msg "  fusionbox system update         更新系统软件包"
  msg "  fusionbox system clean          系统清理"
  msg "  fusionbox system swap           Swap 管理"
  msg "  fusionbox system security       安全审计与加固"
  msg ""
}

# ---- Interactive Menu ----
system_menu() {
  while true; do
    clear
    _print_banner
    msg_title "系统管理"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 系统信息"
    msg "  ${F_GREEN}2${F_RESET}) BBR 管理"
    msg "  ${F_GREEN}3${F_RESET}) 运行基准测试"
    msg "  ${F_GREEN}4${F_RESET}) 系统监控"
    msg "  ${F_GREEN}5${F_RESET}) 备份系统"
    msg "  ${F_GREEN}6${F_RESET}) 恢复系统"
    msg "  ${F_GREEN}7${F_RESET}) 更新系统"
    msg "  ${F_GREEN}8${F_RESET}) 系统清理"
    msg "  ${F_GREEN}9${F_RESET}) Swap 与安全"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-9]: " choice
    case "$choice" in
      1) system_info ;;
      2) system_bbr ;;
      3) system_benchmark ;;
      4) system_monitor ;;
      5) system_backup ;;
      6) system_restore ;;
      7) system_update ;;
      8) system_clean ;;
      9) system_swap; system_security ;;
      0) break ;;
    esac
  done
}
