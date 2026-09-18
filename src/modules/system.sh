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
    hardening)        system_hardening ;;
    security|sec)     system_security "$@" ;;
    sshkey|ssh)       system_sshkey "$@" ;;
    firewall|fw)      system_firewall "$@" ;;
    cron|crontab)     system_cron "$@" ;;
    disk)             system_disk "$@" ;;
    timezone|tz)      system_timezone "$@" ;;
    trash)            system_trash "$@" ;;
    dns)              system_dns "$@" ;;
    hostname)         system_hostname "$@" ;;
    hosts)            system_hosts "$@" ;;
    mirror)           system_mirror "$@" ;;
    log)              system_log "$@" ;;
    traffic-guard)    system_traffic_guard "$@" ;;
    notify)           system_notify "$@" ;;
    netopt)           system_netopt "$@" ;;
    settings)         system_settings_menu ;;
    tools)            system_tools_menu ;;
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
    local proxy_be
    proxy_be=$(cat /etc/fusionbox/proxy/current_backend 2>/dev/null) || true
    proxy_be=${proxy_be:-未知}
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
  while true; do
    clear
    _print_banner

    # Detect current status
    local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")
    local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")
    local kver; kver=$(uname -r)
    local kernel_status; kernel_status=$(_bbr_detect_kernel_type)
    local run_status; run_status=$(_bbr_detect_run_status "$cc" "$kernel_status")

    msg_title "TCP 加速管理"
    msg ""
    msg "  ${F_BOLD}系统信息:${F_RESET} $F_OS_NAME $F_OS_VER ($F_ARCH)"
    msg "  ${F_BOLD}内核版本:${F_RESET} $kver"
    msg "  ${F_BOLD}内核类型:${F_RESET} $kernel_status"
    msg "  ${F_BOLD}运行状态:${F_RESET} $run_status"
    msg "  ${F_BOLD}拥塞控制:${F_RESET} $cc  ${F_BOLD}队列算法:${F_RESET} $qdisc"
    msg ""
    msg "————————————————————————————————————————————————————————"
    msg "  ${F_BOLD}[安装内核]${F_RESET}"
    msg "  ${F_GREEN} 1${F_RESET}) 安装 BBR 原版内核"
    msg "  ${F_GREEN} 2${F_RESET}) 安装 BBRplus 内核"
    msg "  ${F_GREEN} 3${F_RESET}) 安装 BBRplus 新版内核"
    msg "  ${F_GREEN} 4${F_RESET}) 安装 xanmod 内核 (BBRv3)"
    msg "  ${F_GREEN} 5${F_RESET}) 安装 cloud 内核 (精简版)"
    msg "  ${F_GREEN} 6${F_RESET}) 编译 BBR 魔改版 (tcp_tsunami)"
    msg "  ${F_GREEN} 7${F_RESET}) 编译 暴力BBR魔改版 (tcp_nanqinlang)"
    msg ""
    msg "  ${F_BOLD}[切换加速]${F_RESET}"
    msg "  ${F_GREEN}11${F_RESET}) BBR + FQ          ${F_GREEN}12${F_RESET}) BBR + FQ_PIE"
    msg "  ${F_GREEN}13${F_RESET}) BBR + CAKE         ${F_GREEN}14${F_RESET}) BBR2 + FQ"
    msg "  ${F_GREEN}15${F_RESET}) BBR2 + FQ_PIE      ${F_GREEN}16${F_RESET}) BBR2 + CAKE"
    msg "  ${F_GREEN}17${F_RESET}) BBRplus + FQ       ${F_GREEN}18${F_RESET}) Lotserver(锐速)"
    msg "  ${F_GREEN}19${F_RESET}) BBR魔改版 + FQ     ${F_GREEN}20${F_RESET}) 暴力BBR魔改 + FQ"
    msg ""
    msg "  ${F_BOLD}[系统优化]${F_RESET}"
    msg "  ${F_GREEN}21${F_RESET}) 系统网络优化 (标准)    ${F_GREEN}22${F_RESET}) 系统网络优化 (激进)"
    msg "  ${F_GREEN}23${F_RESET}) 开启 ECN              ${F_GREEN}24${F_RESET}) 关闭 ECN"
    msg "  ${F_GREEN}25${F_RESET}) 禁用 IPv6             ${F_GREEN}26${F_RESET}) 开启 IPv6"
    msg ""
    msg "  ${F_BOLD}[管理]${F_RESET}"
    msg "  ${F_GREEN}31${F_RESET}) 卸载全部加速"
    msg "  ${F_GREEN}32${F_RESET}) 删除多余内核"
    msg "  ${F_GREEN}33${F_RESET}) 代理程序 BBR 配置说明"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg "————————————————————————————————————————————————————————"
    msg ""
    read -p "请输入数字: " num || { msg ""; break; }   # stdin 关闭时退出，防死循环

    case "$num" in
      1)  _bbr_install_bbr ;;
      2)  _bbr_install_bbrplus ;;
      3)  _bbr_install_bbrplus_new ;;
      4)  _bbr_install_xanmod ;;
      5)  _bbr_install_cloud ;;
      6)  _bbr_compile_tsunami ;;
      7)  _bbr_compile_nanqinlang ;;
      11) _bbr_apply "bbr" "fq" ;;
      12) _bbr_apply "bbr" "fq_pie" ;;
      13) _bbr_apply "bbr" "cake" ;;
      14) _bbr_apply "bbr2" "fq" ;;
      15) _bbr_apply "bbr2" "fq_pie" ;;
      16) _bbr_apply "bbr2" "cake" ;;
      17) _bbr_apply "bbrplus" "fq" ;;
      18) _bbr_enable_lotserver ;;
      19) _bbr_apply "tsunami" "fq" ;;
      20) _bbr_apply "nanqinlang" "fq" ;;
      21) _bbr_optimize_standard ;;
      22) _bbr_optimize_radical ;;
      23) _bbr_set_ecn 1 ;;
      24) _bbr_set_ecn 0 ;;
      25) _bbr_set_ipv6 0 ;;
      26) _bbr_set_ipv6 1 ;;
      31) _bbr_remove_all ;;
      32) _bbr_delete_old_kernels ;;
      33) _bbr_proxy_info ;;
      0)  break ;;
      *)  ;;
    esac
  done
}

# ---- 状态检测 ----
_bbr_detect_kernel_type() {
  local kver; kver=$(uname -r)
  if [[ "$kver" == *bbrplus* ]]; then
    echo "BBRplus"
  elif [[ "$kver" == *xanmod* ]]; then
    echo "xanmod"
  elif [[ "$kver" =~ (4\.9|4\.15|4\.8|3\.16|3\.2|2\.6\.32|4\.4|4\.11) ]]; then
    echo "Lotserver"
  else
    local kmaj; kmaj=$(echo "$kver" | cut -d. -f1)
    local kmin; kmin=$(echo "$kver" | cut -d. -f2)
    if [[ $kmaj -ge 5 ]] || [[ $kmaj -eq 4 && $kmin -ge 9 ]]; then
      echo "BBR"
    else
      echo "不支持加速"
    fi
  fi
}

_bbr_detect_run_status() {
  local cc="$1" ktype="$2"
  case "$cc" in
    bbr)        echo "BBR 运行中" ;;
    bbr2)       echo "BBR2 运行中" ;;
    bbrplus)    echo "BBRplus 运行中" ;;
    tsunami)    echo "BBR魔改版 运行中" ;;
    nanqinlang) echo "暴力BBR魔改版 运行中" ;;
    cubic)   echo "未启用加速 (cubic)" ;;
    *)       echo "$cc" ;;
  esac
}

# ---- 启用加速 ----
_bbr_apply() {
  local algo="$1" qdisc="$2"
  _bbr_remove_accel
  cat >> /etc/sysctl.conf << SEOF

# FusionBox TCP 加速
net.core.default_qdisc = $qdisc
net.ipv4.tcp_congestion_control = $algo
SEOF
  modprobe "tcp_${algo}" 2>/dev/null
  if ! sysctl -p 2>/dev/null; then
    msg_err "sysctl 配置应用失败，请检查 /etc/sysctl.conf 中的错误项"
  fi
  local new_cc; new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  if [[ "$new_cc" == "$algo" ]]; then
    msg_ok "已启用 ${algo^^} + ${qdisc^^}"
  else
    msg_warn "设置已写入，当前为 $new_cc，可能需要重启生效"
  fi
  _log_write "TCP 加速已启用: $algo + $qdisc"
  pause
}

# ---- Lotserver(锐速) ----
_bbr_enable_lotserver() {
  _bbr_remove_accel
  _install_pkg ethtool 2>/dev/null
  msg_info "正在安装 Lotserver(锐速)..."
  local lot_tmp; lot_tmp=$(mktemp)
  _download "https://raw.githubusercontent.com/fei5seven/lotServer/master/lotServerInstall.sh" "$lot_tmp" || {
    rm -f "$lot_tmp"
    msg_err "Lotserver 安装脚本下载失败"
    pause; return
  }
  msg_warn "即将执行第三方脚本（来源: https://raw.githubusercontent.com/fei5seven/lotServer/master/lotServerInstall.sh）"
  if ! confirm "确认执行该第三方脚本？"; then
    rm -f "$lot_tmp"
    pause; return
  fi
  bash "$lot_tmp" install 2>/dev/null || {
    rm -f "$lot_tmp"
    msg_err "Lotserver 安装失败"
    pause; return
  }
  rm -f "$lot_tmp"
  sed -i '/advinacc/d' /appex/etc/config 2>/dev/null
  sed -i '/maxmode/d' /appex/etc/config 2>/dev/null
  echo -e 'advinacc="1"\nmaxmode="1"' >> /appex/etc/config 2>/dev/null
  /appex/bin/lotServer.sh restart 2>/dev/null
  msg_ok "Lotserver(锐速) 已启用"
  _log_write "Lotserver 已启用"
  pause
}

# ---- 卸载加速 ----
_bbr_remove_accel() {
  sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  sed -i '/FusionBox TCP/d' /etc/sysctl.conf
  sysctl -p 2>/dev/null
}

_bbr_remove_all() {
  if confirm "确认卸载全部加速配置？"; then
    _bbr_remove_accel
    if [[ -e /appex/bin/lotServer.sh ]]; then
      bash /appex/bin/lotServer.sh stop 2>/dev/null
      msg_info "Lotserver 已停止"
    fi
    msg_ok "全部加速已卸载"
    _log_write "全部加速已卸载"
  fi
  pause
}

# ---- 内核安装 ----
_bbr_install_bbr() {
  msg_info "正在安装 BBR 原版内核..."
  _system_install_kernel
}

_bbr_install_bbrplus() {
  msg_info "正在安装 BBRplus 内核 (4.14.129)..."
  local tmpdir=$(mktemp -d)
  case "$F_PKG_MGR" in
    apt)
      local arch="amd64"; [[ "$F_ARCH" == "arm64" ]] && arch="arm64"
      _download "https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/debian-bbrplus/linux-headers-4.14.129-bbrplus.deb" "$tmpdir/headers.deb" || \
      _download "https://github.com/ylx2016/Linux-NetSpeed/raw/master/bbrplus/debian-bbrplus/linux-headers-4.14.129-bbrplus.deb" "$tmpdir/headers.deb"
      _download "https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/debian-bbrplus/linux-image-4.14.129-bbrplus.deb" "$tmpdir/image.deb" || \
      _download "https://github.com/ylx2016/Linux-NetSpeed/raw/master/bbrplus/debian-bbrplus/linux-image-4.14.129-bbrplus.deb" "$tmpdir/image.deb"
      if [[ -f "$tmpdir/headers.deb" && -f "$tmpdir/image.deb" ]]; then
        dpkg -i "$tmpdir/headers.deb" "$tmpdir/image.deb"
        _bbr_grub_update
        msg_ok "BBRplus 内核安装完成，需要重启"
        confirm "是否立即重启？" && reboot
      else
        msg_err "下载失败，请检查网络"
      fi
      ;;
    yum)
      _download "https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/centos-bbrplus/kernel-4.14.129-bbrplus.rpm" "$tmpdir/kernel.rpm" || \
      _download "https://github.com/ylx2016/Linux-NetSpeed/raw/master/bbrplus/centos-bbrplus/kernel-4.14.129-bbrplus.rpm" "$tmpdir/kernel.rpm"
      if [[ -f "$tmpdir/kernel.rpm" ]]; then
        rpm -ivh "$tmpdir/kernel.rpm"
        _bbr_grub_update
        msg_ok "BBRplus 内核安装完成，需要重启"
        confirm "是否立即重启？" && reboot
      else
        msg_err "下载失败，请检查网络"
      fi
      ;;
    *)
      msg_err "当前系统不支持自动安装，请手动编译内核"
      ;;
  esac
  rm -rf "$tmpdir"
  pause
}

_bbr_install_bbrplus_new() {
  msg_info "正在安装 BBRplus 新版内核..."
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "下载失败"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "即将执行第三方脚本（来源: https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh）"
  msg_warn "即将运行内核安装脚本，选择选项 5 安装 BBRplus 新版内核"
  if ! confirm "确认执行该第三方脚本？"; then
    rm -rf "$tmpdir"
    pause; return
  fi
  bash "$tmpdir/tcp.sh"
  rm -rf "$tmpdir"
  pause
}

_bbr_install_xanmod() {
  msg_info "正在安装 xanmod 内核 (BBRv3)..."
  if [[ "$F_PKG_MGR" != "apt" ]]; then
    msg_err "xanmod 内核仅支持 Debian/Ubuntu 系统"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "下载失败"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "即将执行第三方脚本（来源: https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh）"
  msg_warn "即将运行内核安装脚本，选择选项 4 安装 xanmod 内核"
  if ! confirm "确认执行该第三方脚本？"; then
    rm -rf "$tmpdir"
    pause; return
  fi
  bash "$tmpdir/tcp.sh"
  rm -rf "$tmpdir"
  pause
}

_bbr_install_cloud() {
  msg_info "正在安装 cloud 内核..."
  if [[ "$F_PKG_MGR" != "apt" ]]; then
    msg_err "cloud 内核仅支持 Debian 系统"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "下载失败"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "即将执行第三方脚本（来源: https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh）"
  msg_warn "即将运行内核安装脚本，选择选项 8 安装 cloud 内核"
  if ! confirm "确认执行该第三方脚本？"; then
    rm -rf "$tmpdir"
    pause; return
  fi
  bash "$tmpdir/tcp.sh"
  rm -rf "$tmpdir"
  pause
}

_bbr_grub_update() {
  if command -v grub2-set-default &>/dev/null; then
    grub2-set-default 0 2>/dev/null
  elif command -v update-grub &>/dev/null; then
    update-grub 2>/dev/null
  fi
}

# ---- 编译 BBR 魔改版 ----
_bbr_compile_tsunami() {
  msg_info "正在编译 BBR 魔改版 (tcp_tsunami)..."
  _check_pkg gcc gcc 2>/dev/null
  _check_pkg make make 2>/dev/null
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    msg_err "gcc 和 make 是编译必需的，请先安装"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/bbr/tcp_tsunami.c" "$tmpdir/tcp_tsunami.c" || \
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/bbr/tcp_tsunami.c" "$tmpdir/tcp_tsunami.c" || {
    msg_err "下载 tcp_tsunami.c 失败"; rm -rf "$tmpdir"; pause; return
  }
  echo "obj-m:=tcp_tsunami.o" > "$tmpdir/Makefile"
  if make -C "/lib/modules/$(uname -r)/build" M="$tmpdir" modules CC=/usr/bin/gcc 2>/dev/null; then
    cp "$tmpdir/tcp_tsunami.ko" "/lib/modules/$(uname -r)/kernel/net/ipv4/" 2>/dev/null
    depmod -a 2>/dev/null
    modprobe tcp_tsunami 2>/dev/null
    msg_ok "tcp_tsunami 编译并加载成功"
    if confirm "是否启用 BBR魔改版 + FQ？"; then
      _bbr_apply "tsunami" "fq"
    fi
  else
    msg_err "编译失败，可能需要安装内核头文件: apt install linux-headers-$(uname -r)"
  fi
  rm -rf "$tmpdir"
  _log_write "BBR魔改版 tcp_tsunami 编译完成"
  pause
}

# ---- 编译 暴力BBR魔改版 ----
_bbr_compile_nanqinlang() {
  msg_info "正在编译 暴力BBR魔改版 (tcp_nanqinlang)..."
  _check_pkg gcc gcc 2>/dev/null
  _check_pkg make make 2>/dev/null
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    msg_err "gcc 和 make 是编译必需的，请先安装"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/bbr/tcp_nanqinlang.c" "$tmpdir/tcp_nanqinlang.c" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/bbr/tcp_nanqinlang.c" "$tmpdir/tcp_nanqinlang.c" || {
    msg_err "下载 tcp_nanqinlang.c 失败"; rm -rf "$tmpdir"; pause; return
  }
  echo "obj-m := tcp_nanqinlang.o" > "$tmpdir/Makefile"
  if make -C "/lib/modules/$(uname -r)/build" M="$tmpdir" modules CC=/usr/bin/gcc 2>/dev/null; then
    cp "$tmpdir/tcp_nanqinlang.ko" "/lib/modules/$(uname -r)/kernel/net/ipv4/" 2>/dev/null
    depmod -a 2>/dev/null
    modprobe tcp_nanqinlang 2>/dev/null
    msg_ok "tcp_nanqinlang 编译并加载成功"
    if confirm "是否启用 暴力BBR魔改版 + FQ？"; then
      _bbr_apply "nanqinlang" "fq"
    fi
  else
    msg_err "编译失败，可能需要安装内核头文件: apt install linux-headers-$(uname -r)"
  fi
  rm -rf "$tmpdir"
  _log_write "暴力BBR魔改版 tcp_nanqinlang 编译完成"
  pause
}

# ---- 系统网络优化 ----
_bbr_optimize_standard() {
  msg_info "正在应用标准网络优化..."
  cat > /etc/sysctl.d/99-fusionbox-optimize.conf << 'SEOF'
# FusionBox 标准网络优化
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_ecn = 0
fs.file-max = 1048576
fs.inotify.max_user_instances = 8192
SEOF
  sysctl --system 2>/dev/null
  msg_ok "标准网络优化已应用"
  _log_write "标准网络优化已应用"
  pause
}

_bbr_optimize_radical() {
  msg_info "正在应用激进网络优化..."
  cat > /etc/sysctl.d/99-fusionbox-optimize.conf << 'SEOF'
# FusionBox 激进网络优化
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 2000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
SEOF
  sysctl --system 2>/dev/null
  msg_ok "激进网络优化已应用"
  _log_write "激进网络优化已应用"
  pause
}

# ---- ECN ----
_bbr_set_ecn() {
  local val="$1"
  sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_ecn/d' /etc/sysctl.d/99-fusionbox-optimize.conf 2>/dev/null
  echo "net.ipv4.tcp_ecn=$val" >> /etc/sysctl.conf
  sysctl -p 2>/dev/null
  if [[ "$val" == "1" ]]; then
    msg_ok "ECN 已开启"
  else
    msg_ok "ECN 已关闭"
  fi
  _log_write "ECN 设置为 $val"
  pause
}

# ---- IPv6 ----
_bbr_set_ipv6() {
  local val="$1"
  sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
  sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
  if [[ "$val" == "0" ]]; then
    cat >> /etc/sysctl.conf << 'SEOF'

# 禁用 IPv6
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
SEOF
    sysctl -p 2>/dev/null
    msg_ok "IPv6 已禁用"
  else
    cat >> /etc/sysctl.conf << 'SEOF'

# 启用 IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
SEOF
    sysctl -p 2>/dev/null
    msg_ok "IPv6 已启用"
  fi
  _log_write "IPv6 设置为 $val"
  pause
}

# ---- 删除多余内核 ----
_bbr_delete_old_kernels() {
  local current_kver; current_kver=$(uname -r)
  msg_info "当前内核: $current_kver"
  msg ""

  case "$F_PKG_MGR" in
    apt)
      local old_kernels=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$current_kver" | grep -v "linux-image-$current_kver")
      if [[ -z "$old_kernels" ]]; then
        msg_ok "没有多余的内核"
        pause; return
      fi
      msg_info "检测到以下旧内核:"
      echo "$old_kernels" | while read -r k; do msg "  $k"; done
      msg ""
      if confirm "确认删除以上旧内核？"; then
        echo "$old_kernels" | while read -r k; do
          apt-get purge -y "$k" 2>/dev/null
        done
        apt-get autoremove -y 2>/dev/null
        msg_ok "旧内核已删除"
      fi
      ;;
    yum)
      local old_kernels=$(rpm -qa | grep kernel | grep -v "$current_kver" | grep -v "noarch")
      if [[ -z "$old_kernels" ]]; then
        msg_ok "没有多余的内核"
        pause; return
      fi
      msg_info "检测到以下旧内核:"
      echo "$old_kernels" | while read -r k; do msg "  $k"; done
      msg ""
      if confirm "确认删除以上旧内核？"; then
        echo "$old_kernels" | while read -r k; do
          rpm --nodeps -e "$k" 2>/dev/null
        done
        msg_ok "旧内核已删除"
      fi
      ;;
    *)
      msg_err "当前系统不支持自动删除内核"
      ;;
  esac
  _log_write "旧内核清理完成"
  pause
}

# ---- 代理程序 BBR 说明 ----
_bbr_proxy_info() {
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
  msg "  ${F_BOLD}队列算法说明：${F_RESET}"
  msg "    fq      - Fair Queue，适合大多数场景"
  msg "    fq_pie  - Fair Queue + PIE，适合低延迟场景"
  msg "    cake    - CAKE，适合高带宽场景"
  msg ""
  msg "  ${F_BOLD}建议：${F_RESET}"
  msg "  1. TCP 类型协议自动受益于系统 BBR"
  msg "  2. UDP/QUIC 类型协议使用各自内置拥塞控制"
  msg "  3. BBRplus 在高丢包网络下表现更好"
  msg "  4. 搭配系统网络优化效果更佳"
  msg ""
  pause
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

  msg_warn "请先停止写入服务；文件备份不是数据库一致性快照。链接与特殊文件将被拒绝。"
  python3 "$FUSION_SRC/lib/archive.py" create system "$backup_file" || return 1
  msg_ok "备份已创建: $backup_file"
  _log_write "系统备份已创建: $backup_file"
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

  read -r -p "请选择要恢复的备份: " choice
  [[ "$choice" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
    local restore_file="${backups[$idx]}"
    msg_info "校验备份与恢复范围:"
    python3 "$FUSION_SRC/lib/archive.py" verify system "$restore_file" || return 1
    msg ""
    if confirm "确认已停止写入服务？将替换清单目录并保留旧目录"; then
      local confirm_input=""
      read -r -p "请输入大写 YES 确认恢复: " confirm_input
      if [[ "$confirm_input" == "YES" ]]; then
        python3 "$FUSION_SRC/lib/archive.py" restore system "$restore_file" || return 1
        msg_ok "恢复完成"
        _log_write "系统已从备份恢复: $restore_file"
      else
        msg_warn "输入不匹配，已取消恢复"
      fi
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
  msg "  1) 创建 Swap 文件 (自定义大小)"
  msg "  2) 仅删除明确确认归属的 /swapfile（保留其他 Swap）"
  msg "  0) 返回"
  read -p "请选择: " sw_choice

  case "$sw_choice" in
    1)
      if [[ -e /swapfile ]] || swapon --show=NAME 2>/dev/null | grep -q "/swapfile"; then
        msg_warn "Swap 文件已存在 (/swapfile)，请先删除后再创建"
        pause
        return
      fi

      read -p "请输入 Swap 大小（默认 2048，支持 2048 / 2G / 512M）: " sw_size
      sw_size="${sw_size// /}"
      sw_size="${sw_size:-2048}"
      if [[ ! "$sw_size" =~ ^[0-9]+[GgMm]?$ ]]; then
        msg_err "大小格式无效: $sw_size（示例: 2048 / 2G / 512M）"
        pause
        return
      fi

      local sw_mb
      case "$sw_size" in
        *[Gg]) sw_mb=$(( ${sw_size%[Gg]} * 1024 )) ;;
        *[Mm]) sw_mb=$(( ${sw_size%[Mm]} )) ;;
        *)     sw_mb=$(( sw_size )) ;;
      esac
      if [[ $sw_mb -lt 16 || $sw_mb -gt 1048576 ]]; then
        msg_err "Swap 大小必须在 16MB - 1TB 之间，当前: ${sw_mb}MB"
        pause
        return
      fi

      local avail_mb; avail_mb=$(df -m / 2>/dev/null | awk 'NR==2{print $4}')
      if [[ "$avail_mb" =~ ^[0-9]+$ ]] && [[ $((avail_mb - sw_mb)) -lt 256 ]]; then
        msg_warn "根分区可用空间仅 ${avail_mb}MB，可能不足以创建 ${sw_mb}MB 的 Swap"
        confirm "仍要继续？" || { pause; return; }
      fi

      if confirm "确认创建 ${sw_mb}MB (${sw_size}) Swap 文件？"; then
        msg_info "正在创建 /swapfile (${sw_mb}MB)..."
        if ! fallocate -l "${sw_mb}M" /swapfile 2>/dev/null; then
          msg_warn "fallocate 不可用，改用 dd 创建（较慢）"
          if ! dd if=/dev/zero of=/swapfile bs=1M count="$sw_mb" status=progress; then
            rm -f /swapfile
            msg_err "Swap 文件创建失败（空间不足？）"
            pause
            return
          fi
        fi
        chmod 600 /swapfile
        if mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile 2>/dev/null; then
          grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
          msg_ok "Swap 已创建 (${sw_mb}MB)"
          free -h | grep -i swap
          _log_write "${sw_mb}MB Swap 已创建"
        else
          msg_err "mkswap 或 swapon 失败，请检查内核是否支持 Swap"
        fi
      fi
      ;;
    2)
      if confirm "确认 /swapfile 为你拥有并允许删除的 Swap 文件？仅停用并删除此文件，保留其他 Swap"; then
        python3 "$FUSION_SRC/lib/system_safety.py" swap || return 1
        msg_ok "仅 /swapfile 已删除"
      fi
      ;;
  esac
  pause
}

# ---- User Management (CRUD/sudo/password, was read-only) ----

_fb_user_check_name() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
    msg_err "用户名无效: 仅小写字母开头，可含小写字母/数字/_/-，最长 32 字符"
    return 1
  }
}

_fb_user_read_password() {
  local label="$1" p1 p2
  read -rsp "$label: " p1 || return 1
  msg ""
  if [[ -z "$p1" ]]; then
    msg_err "密码不能为空"
    return 1
  fi
  if [[ ${#p1} -gt 512 || "$p1" == *:* || "$p1" == *$'\n'* || "$p1" == *$'\r'* ]]; then
    msg_err "密码包含不允许的字符（冒号/换行）或超过 512 字符"
    return 1
  fi
  read -rsp "再次输入密码: " p2 || return 1
  msg ""
  if [[ "$p1" != "$p2" ]]; then
    msg_err "两次输入不一致"
    return 1
  fi
  printf '%s' "$p1"
}

_fb_users_list() {
  msg "  ${F_BOLD}可登录用户 (uid>=1000):${F_RESET}"
  awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s, shell=%s, home=%s)\n", $1, $3, $7, $6}' /etc/passwd
  msg ""
  msg "  ${F_BOLD}FusionBox 受管 sudo 授权 (/etc/sudoers.d/90-fusionbox-*):${F_RESET}"
  local f base found=0
  for f in /etc/sudoers.d/90-fusionbox-*; do
    [[ -f "$f" ]] || continue
    base="${f##*/90-fusionbox-}"
    if head -n1 "$f" 2>/dev/null | grep -q "^# FusionBox managed sudo grant"; then
      msg "  $base (受管)"
    else
      msg "  ${F_YELLOW}$base (归属未知，不自动操作)${F_RESET}"
    fi
    found=1
  done
  [[ $found -eq 0 ]] && msg "  无"
  msg ""
  msg "  ${F_BOLD}最近登录:${F_RESET}"
  last -n 5 2>/dev/null | head -5
}

_fb_user_set_password() {
  local name="$1" pw
  pw=$(_fb_user_read_password "为 $name 设置新密码") || return 1
  printf '%s\n' "$pw" | python3 "$FUSION_SRC/lib/system_safety.py" passwd-set "$name" || return 1
  msg_ok "$name 密码已更新"
  _log_write "用户密码已更新: $name"
}

_fb_users_cmd_add() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  id "$name" &>/dev/null && { msg_err "用户已存在: $name"; return 1; }
  confirm "创建用户 $name（主目录 /home/$name, shell /bin/bash）？" || { msg_info "已取消"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-add "$name" || return 1
  msg_ok "用户 $name 已创建"
  _log_write "用户已创建: $name"
  if confirm "立即为 $name 设置登录密码？"; then
    _fb_user_set_password "$name" || msg_warn "可稍后用 fusionbox system users passwd $name 设置"
  fi
  return 0
}

_fb_users_cmd_del() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  msg_warn "将删除用户 $name 及其主目录（/home/$name）与受管 sudo 授权；系统账号与 root 一律拒绝"
  confirm "确认删除 $name？" || { msg_info "已取消"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-del "$name" || return 1
  msg_ok "用户 $name 已删除"
  _log_write "用户已删除: $name"
}

_fb_users_cmd_sudo() {
  local name="${1:-}" mode="${2:-}"
  _fb_user_check_name "$name" || return 1
  local flag=""
  if [[ -z "$mode" ]]; then
    mode=$(select_option "选择 $name 的 sudo 模式:" "需要密码（推荐）" "免密 NOPASSWD") || return 1
  fi
  [[ "$mode" == "nopasswd" || "$mode" == "2" ]] && flag="nopasswd"
  confirm "授予 $name sudo 权限（${flag:+免密}${flag:-需密码}，写入受管文件 90-fusionbox-$name）？" || { msg_info "已取消"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" sudo-grant "$name" $flag || return 1
  msg_ok "$name 已获得 sudo 权限"
  _log_write "sudo 已授予: $name (${flag:-password})"
}

_fb_users_cmd_unsudo() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  confirm "回收 $name 的 FusionBox 受管 sudo 授权（不影响其他 sudo 配置）？" || { msg_info "已取消"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" sudo-revoke "$name" || return 1
  msg_ok "$name 的受管 sudo 授权已回收"
  _log_write "sudo 已回收: $name"
}

_fb_users_cmd_passwd() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  _fb_user_set_password "$name"
}

_fb_users_menu() {
  while true; do
    clear
    _print_banner
    msg_title "用户管理"
    msg ""
    _fb_users_list
    msg "  1) 创建用户"
    msg "  2) 删除用户"
    msg "  3) 授权 sudo"
    msg "  4) 回收 sudo"
    msg "  5) 修改用户密码"
    msg "  0) 返回"
    read -p "请选择: " u_choice || { msg ""; return; }
    case "$u_choice" in
      1) u_name=$(read_input "请输入新用户名") && _fb_users_cmd_add "$u_name" ;;
      2) u_name=$(read_input "请输入要删除的用户名") && _fb_users_cmd_del "$u_name" ;;
      3) u_name=$(read_input "请输入用户名") && _fb_users_cmd_sudo "$u_name" ;;
      4) u_name=$(read_input "请输入用户名") && _fb_users_cmd_unsudo "$u_name" ;;
      5) u_name=$(read_input "请输入用户名") && _fb_users_cmd_passwd "$u_name" ;;
      0) return ;;
      *) ;;
    esac
  done
}

system_users() {
  _require_root
  local action="${1:-menu}"
  case "$action" in
    list)    _fb_users_list; return 0 ;;
    add)     shift; _fb_users_cmd_add "$@"; return $? ;;
    del)     shift; _fb_users_cmd_del "$@"; return $? ;;
    sudo)    shift; _fb_users_cmd_sudo "$@"; return $? ;;
    unsudo)  shift; _fb_users_cmd_unsudo "$@"; return $? ;;
    passwd)  shift; _fb_users_cmd_passwd "$@"; return $? ;;
    menu)    _fb_users_menu; return 0 ;;
    *)       _fb_users_menu; return 0 ;;
  esac
}

# ---- SSH 加固向导：新建密钥用户并收紧 root 登录 (G05) ----
# 验证未通过时绝不修改 root 登录策略。

_fb_pubkey_valid() {
  local pubkey_re='^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[a-z0-9-]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/=]+( .*)?$'
  [[ "$1" =~ $pubkey_re ]]
}

_fb_hardening_verify_key_login() {
  # $1=用户名 $2=本机私钥路径；返回 0=验证通过 1=验证失败 2=无法本地验证
  local user="$1" keyfile="$2" port
  command -v ssh &>/dev/null || return 2
  systemctl is-active sshd.service &>/dev/null || systemctl is-active ssh.service &>/dev/null || return 2
  port=$(grep -E "^Port[[:space:]]" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1)
  port=${port:-22}
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$keyfile" -p "$port" \
      "${user}@127.0.0.1" "true" &>/dev/null
}

_fb_hardening_root_policy() {
  # $1=用户名 $2=yes(已验证密钥登录)|no(未验证)
  local name="$1" verified="$2" choice
  if [[ "$verified" != "yes" ]]; then
    msg_warn "未能自动验证密钥登录。在收紧 root 策略前，必须先用新用户完成一次真实 SSH 登录"
    confirm "我已在新的连接中用 $name 密钥登录成功，继续修改 root 策略？" || { msg_info "root 策略保持不变"; return 1; }
  fi
  choice=$(select_option "root 登录策略:" "prohibit-password：root 仅允许密钥登录（推荐）" "no：完全禁止 root 登录" "暂不修改，保持现状") || return 1
  case "$choice" in
    1)
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin prohibit-password || return 1
      msg_ok "root 已限制为仅密钥登录"
      _log_write "PermitRootLogin -> prohibit-password (加固向导, 用户 $name)"
      ;;
    2)
      msg_warn "完全禁止 root 登录后只能通过普通用户 + sudo 管理；请确保 $name 可用且已验证"
      confirm "确认完全禁止 root 登录？" || return 1
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin no || return 1
      msg_ok "root 登录已完全禁止"
      _log_write "PermitRootLogin -> no (加固向导, 用户 $name)"
      ;;
    *) msg_info "root 策略保持不变" ;;
  esac
}

system_hardening() {
  _require_root
  msg_title "SSH 加固：新建密钥用户并收紧 root 登录"
  msg ""
  msg "  流程：创建专用用户 → 安装 SSH 公钥 →（可选）sudo → 验证密钥登录 → 收紧 root 策略"
  msg "  ${F_YELLOW}本流程不修改 SSH 端口与防火墙；每步失败即停止并保留当前状态${F_RESET}"
  msg ""

  local name
  name=$(read_input "请输入新用户名（小写字母开头，最长 32 字符）") || return 1
  _fb_user_check_name "$name" || return 1
  id "$name" &>/dev/null && { msg_err "用户已存在: $name，请换一个名字或走单独的用户管理"; return 1; }

  msg ""
  msg "${F_BOLD}[1/5] 创建用户${F_RESET}"
  confirm "创建用户 $name？" || { msg_info "已取消"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-add "$name" || return 1
  if confirm "为 $name 设置登录密码（sudo 授权后需要）？"; then
    _fb_user_set_password "$name" || msg_warn "跳过；可稍后用 fusionbox system users passwd $name 补设"
  fi

  msg ""
  msg "${F_BOLD}[2/5] 安装 SSH 公钥${F_RESET}"
  local key_source key_file=""
  key_source=$(select_option "公钥来源:" "粘贴现有公钥（推荐，私钥留在你手里）" "在本机生成新密钥对") || return 1
  if [[ "$key_source" == "1" ]]; then
    msg "请粘贴公钥内容（以 ssh-rsa/ssh-ed25519 开头）:"
    local pubkey
    read -r pubkey || return 1
    pubkey="${pubkey%$'\r'}"
    _fb_pubkey_valid "$pubkey" || { msg_err "公钥格式无效，已停止（用户已创建，可用 users del 回滚）"; return 1; }
    python3 "$FUSION_SRC/lib/system_safety.py" user-key-install "$name" <<< "$pubkey" || return 1
  else
    local ugroup
    ugroup=$(id -gn "$name" 2>/dev/null) || ugroup="$name"
    key_file="/home/$name/.ssh/id_ed25519"
    install -d -m 700 -o "$name" -g "$ugroup" "/home/$name/.ssh" || return 1
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "fusionbox-$name" || return 1
    chown "$name:$ugroup" "$key_file" "$key_file.pub" && chmod 600 "$key_file" || return 1
    python3 "$FUSION_SRC/lib/system_safety.py" user-key-install "$name" < "${key_file}.pub" || return 1
    msg "  私钥已生成: $key_file （请立即下载到本地并妥善保存）"
  fi

  msg ""
  msg "${F_BOLD}[3/5] sudo 授权（可选）${F_RESET}"
  if confirm "授予 $name sudo 权限？"; then
    _fb_users_cmd_sudo "$name" || msg_warn "sudo 授权未完成，可稍后用 fusionbox system users sudo $name"
  fi

  msg ""
  msg "${F_BOLD}[4/5] 验证密钥登录${F_RESET}"
  local verified="no" rc=0
  if [[ -n "$key_file" ]]; then
    if _fb_hardening_verify_key_login "$name" "$key_file"; then
      msg_ok "本机回环验证：$name 密钥登录成功"
      verified="yes"
    else
      rc=$?
      [[ $rc -eq 2 ]] && msg_warn "本机无法验证（无 ssh 客户端或本机 sshd 未运行）" || msg_warn "本机回环验证失败"
    fi
  else
    msg_info "粘贴的公钥在本机无私钥，需你在新的连接中实测"
  fi

  msg ""
  msg "${F_BOLD}[5/5] 收紧 root 登录策略${F_RESET}"
  _fb_hardening_root_policy "$name" "$verified" || true

  msg ""
  msg_ok "加固流程结束。回滚方式: users del $name / users unsudo $name；root 策略可用 sshkey 菜单调整"
  _log_write "SSH 加固向导完成: $name (verified=$verified)"
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
      if [[ -z "$new_port" || ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        msg_err "端口无效，必须为 1-65535 之间的数字"
      else
        local old_port; old_port=$(grep -E "^Port[[:space:]]" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1)
        old_port=${old_port:-22}
        local fw_ok=0
        if command -v ufw &>/dev/null; then
          if ufw allow "$new_port"/tcp; then
            ufw allow "$old_port"/tcp 2>/dev/null || true
            fw_ok=1
          fi
        elif command -v firewall-cmd &>/dev/null; then
          if firewall-cmd --permanent --add-port="$new_port"/tcp 2>/dev/null && firewall-cmd --reload 2>/dev/null; then
            firewall-cmd --permanent --add-port="$old_port"/tcp 2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
            fw_ok=1
          fi
        fi
        if [[ $fw_ok -eq 0 ]]; then
          msg_warn "未能自动放行端口 $new_port/tcp，请先在防火墙或云安全组中手动放行"
          confirm "已完成手动放行，是否继续修改 SSH 端口？" && fw_ok=1
        fi
        if [[ $fw_ok -eq 1 ]]; then
          python3 "$FUSION_SRC/lib/system_safety.py" ssh Port "$new_port" || return 1
          msg_warn "配置已验证并重载；请先用新端口建立连接，确认后再关闭当前会话。防火墙放行规则保留。"
        else
          msg_err "防火墙未放行端口 $new_port，已取消修改 SSH 端口"
        fi
      fi
      ;;
  esac
  pause
}

# ---- SSH 密钥管理 ----
system_sshkey() {
  _require_root
  msg_title "SSH 密钥管理"
  msg ""

  msg "  ${F_BOLD}当前授权密钥:${F_RESET}"
  if [[ -f ~/.ssh/authorized_keys ]]; then
    python3 "$FUSION_SRC/lib/system_safety.py" keys-list || return 1
  else
    msg "    暂无授权密钥"
  fi

  msg ""
  msg "  1) 添加公钥（粘贴）"
  msg "  2) 生成新密钥对"
  msg "  3) 删除指定密钥"
  msg "  4) 禁用密码登录（仅密钥）"
  msg "  5) 开启 root 密码登录（改 root 密码 + PermitRootLogin yes）"
  msg "  6) 禁止 root 密码登录（PermitRootLogin prohibit-password）"
  msg "  0) 返回"
  read -p "请选择: " ssh_choice

  case "$ssh_choice" in
    1)
      msg "请粘贴公钥内容（以 ssh-rsa/ssh-ed25519 开头）:"
      read -r pubkey
      pubkey="${pubkey%$'\r'}"
      local pubkey_re='^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[a-z0-9-]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/=]+( .*)?$'
      if [[ -n "$pubkey" && ! "$pubkey" =~ $pubkey_re ]]; then
        msg_err "公钥格式无效，已取消添加"
        pause
        return 1
      fi
      if [[ -n "$pubkey" ]]; then
        python3 "$FUSION_SRC/lib/system_safety.py" keys-add <<< "$pubkey" || return 1
        msg_ok "公钥已添加"
        _log_write "SSH 公钥已添加"
      fi
      ;;
    2)
      local key_type; key_type=$(select_option "选择密钥类型:" "ed25519 (推荐)" "RSA 4096")
      local key_file
      if [[ "$key_type" == "1" ]]; then
        key_file="$HOME/.ssh/id_ed25519"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "fusionbox@$(hostname)" 2>/dev/null
      else
        key_file="$HOME/.ssh/id_rsa"
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "fusionbox@$(hostname)" 2>/dev/null
      fi
      if [[ -f "$key_file" ]]; then
        msg_ok "密钥对已生成:"
        msg "  私钥: $key_file"
        msg "  公钥: ${key_file}.pub"
        msg ""
        msg "  公钥内容:"
        cat "${key_file}.pub"
      fi
      ;;
    3)
      if [[ -f ~/.ssh/authorized_keys ]]; then
        read -p "输入要删除的密钥行号: " line_num
        if [[ -n "$line_num" ]]; then
          python3 "$FUSION_SRC/lib/system_safety.py" keys-delete "$line_num" || return 1
          msg_ok "密钥已删除（显示编号对应物理行号）"
        fi
      fi
      ;;
    4)
      python3 "$FUSION_SRC/lib/system_safety.py" keys-check || return 1
      if confirm "确认已在独立连接中验证密钥登录，并禁用 PasswordAuthentication？其他认证策略不变"; then
        python3 "$FUSION_SRC/lib/system_safety.py" ssh PasswordAuthentication no || return 1
        msg_ok "PasswordAuthentication 已设为 no；PAM/交互式认证等策略未更改"
      fi
      ;;
    5)
      msg_warn "将允许 root 使用密码通过 SSH 登录（公网暴露风险上升；建议配合 fail2ban/非标端口/仅密钥用户）"
      confirm "确认继续？" || { msg_info "已取消"; pause; return; }
      local rootpw
      rootpw=$(_fb_user_read_password "设置 root 新密码") || { pause; return 1; }
      printf '%s\n' "$rootpw" | python3 "$FUSION_SRC/lib/system_safety.py" passwd-set root || { pause; return 1; }
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin yes || { pause; return 1; }
      msg_ok "root 密码登录已开启"
      msg_info "若 PasswordAuthentication 为 no，root 仍无法密码登录；如需放开请先执行选项 4 的反向操作"
      _log_write "root 密码登录已开启（PermitRootLogin yes）"
      ;;
    6)
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin prohibit-password || return 1
      msg_ok "root 密码登录已禁止（root 密钥登录不受影响）"
      _log_write "root 密码登录已禁止（PermitRootLogin prohibit-password）"
      ;;
  esac
  pause
}

# ---- 防火墙管理 ----
system_firewall() {
  _require_root
  msg_title "防火墙管理"
  msg ""

  # Detect firewall
  local fw_type="none"
  if command -v ufw &>/dev/null; then
    fw_type="ufw"
    msg "  ${F_BOLD}防火墙:${F_RESET} UFW"
    msg "  $(ufw status 2>/dev/null | head -1)"
  elif command -v firewall-cmd &>/dev/null; then
    fw_type="firewalld"
    msg "  ${F_BOLD}防火墙:${F_RESET} firewalld"
    firewall-cmd --state 2>/dev/null
  elif command -v iptables &>/dev/null; then
    fw_type="iptables"
    msg "  ${F_BOLD}防火墙:${F_RESET} iptables"
    local rule_count
    if rule_count=$(iptables -L -n 2>/dev/null | wc -l); then
      msg "  规则数: $rule_count"
    else
      msg "  规则数: 未知"
    fi
  fi

  msg ""
  msg "  1) 安装并启用 UFW"
  msg "  2) 开放端口"
  msg "  3) 关闭端口"
  msg "  4) 查看当前规则"
  msg "  5) 允许指定 IP"
  msg "  6) 封禁指定 IP"
  msg "  7) 安装 Fail2Ban"
  msg "  8) 配置 Fail2Ban"
  msg "  9) 重置防火墙"
  msg "  0) 返回"
  read -p "请选择: " fw_choice

  case "$fw_choice" in
    1)
      _install_pkg ufw
      ufw default deny incoming 2>/dev/null
      ufw default allow outgoing 2>/dev/null
      ufw allow ssh 2>/dev/null
      ufw --force enable 2>/dev/null
      msg_ok "UFW 已启用（默认拒绝入站，允许出站，SSH 已放行）"
      _log_write "UFW 防火墙已启用"
      ;;
    2)
      read -p "请输入要开放的端口（如 80、443、8000-9000）: " port
      if [[ -n "$port" ]]; then
        local proto; proto=$(select_option "协议:" "TCP+UDP (默认)" "仅 TCP" "仅 UDP")
        case "$proto" in
          2) ufw allow "$port"/tcp 2>/dev/null; iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ;;
          3) ufw allow "$port"/udp 2>/dev/null; iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null ;;
          *) ufw allow "$port" 2>/dev/null; iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null ;;
        esac
        msg_ok "端口 $port 已开放"
        _log_write "端口已开放: $port"
      fi
      ;;
    3)
      read -p "请输入要关闭的端口: " port
      if [[ -n "$port" ]]; then
        ufw deny "$port" 2>/dev/null
        iptables -A INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        msg_ok "端口 $port 已关闭"
      fi
      ;;
    4)
      if [[ "$fw_type" == "ufw" ]]; then
        ufw status verbose 2>/dev/null
      elif [[ "$fw_type" == "firewalld" ]]; then
        firewall-cmd --list-all 2>/dev/null
      else
        iptables -L -n -v 2>/dev/null | head -30
      fi
      ;;
    5)
      read -p "请输入要允许的 IP 地址: " ip_addr
      if [[ -n "$ip_addr" ]]; then
        ufw allow from "$ip_addr" 2>/dev/null
        iptables -A INPUT -s "$ip_addr" -j ACCEPT 2>/dev/null
        msg_ok "已允许 $ip_addr"
      fi
      ;;
    6)
      read -p "请输入要封禁的 IP 地址: " ip_addr
      if [[ -n "$ip_addr" ]]; then
        ufw deny from "$ip_addr" 2>/dev/null
        iptables -A INPUT -s "$ip_addr" -j DROP 2>/dev/null
        msg_ok "已封禁 $ip_addr"
        _log_write "已封禁 IP: $ip_addr"
      fi
      ;;
    7)
      _install_pkg fail2ban
      systemctl enable --now fail2ban 2>/dev/null || true
      msg_ok "Fail2Ban 已安装并启动"
      ;;
    8)
      if ! command -v fail2ban-client &>/dev/null; then
        msg_err "请先安装 Fail2Ban"
      else
        msg "  当前状态:"
        fail2ban-client status 2>/dev/null
        msg ""
        read -p "SSH 最大重试次数 (默认 5): " max_retry
        max_retry=${max_retry:-5}
        read -p "封禁时间（秒，默认 3600）: " ban_time
        ban_time=${ban_time:-3600}
        python3 "$FUSION_SRC/lib/system_safety.py" fail2ban "$max_retry" "$ban_time" || return 1
        msg_ok "Fail2Ban 自有 sshd 参数已保存并重载；启用状态、端口和后端保持原策略，后续配置可能覆盖参数"
      fi
      ;;
    9)
      msg_warn "将清空包括 Docker 在内的全部 iptables 规则，容器网络可能中断"
      local confirm_input=""
      read -r -p "请输入大写 YES 确认重置防火墙: " confirm_input
      if [[ "$confirm_input" == "YES" ]]; then
        local ipt_bak; ipt_bak="/root/iptables-backup-$(date +%Y%m%d%H%M%S).rules"
        if iptables-save > "$ipt_bak" 2>/dev/null; then
          msg_ok "当前规则已备份到 $ipt_bak"
        else
          rm -f "$ipt_bak"
          msg_warn "规则备份失败（iptables-save 不可用）"
        fi
        ufw --force reset 2>/dev/null
        iptables -F 2>/dev/null
        iptables -X 2>/dev/null
        msg_ok "防火墙已重置"
        _log_write "防火墙已重置（规则备份: $ipt_bak）"
      else
        msg_warn "已取消重置防火墙"
      fi
      ;;
  esac
  pause
}

# ---- 定时任务管理 ----
system_cron() {
  _require_root
  msg_title "定时任务管理"
  msg ""

  msg "  ${F_BOLD}当前定时任务:${F_RESET}"
  local cron_list=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$")
  if [[ -n "$cron_list" ]]; then
    echo "$cron_list" | while IFS= read -r line; do
      msg "  $line"
    done
  else
    msg "    暂无定时任务"
  fi

  msg ""
  msg "  1) 添加定时任务"
  msg "  2) 删除定时任务"
  msg "  3) 编辑 crontab"
  msg "  4) 添加系统备份定时任务"
  msg "  5) 添加日志清理定时任务"
  msg "  6) 查看系统 cron 服务"
  msg "  0) 返回"
  read -p "请选择: " cron_choice

  case "$cron_choice" in
    1)
      msg "  常用时间格式:"
      msg "  每天凌晨3点:  0 3 * * *"
      msg "  每小时:       0 * * * *"
      msg "  每周一:       0 0 * * 1"
      msg "  每5分钟:      */5 * * * *"
      msg ""
      read -p "请输入 cron 表达式: " cron_expr
      read -p "请输入要执行的命令: " cron_cmd
      if [[ -n "$cron_expr" && -n "$cron_cmd" ]]; then
        if crontab -l 2>/dev/null | grep -qF "$cron_expr $cron_cmd"; then
          msg_warn "该定时任务已存在，跳过添加"
        else
          (crontab -l 2>/dev/null; echo "$cron_expr $cron_cmd") | crontab -
          msg_ok "定时任务已添加"
          _log_write "定时任务已添加: $cron_expr $cron_cmd"
        fi
      fi
      ;;
    2)
      crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | nl -ba
      read -p "输入要删除的行号: " del_line
      if [[ -n "$del_line" ]]; then
        if [[ "$del_line" =~ ^[0-9]+$ ]]; then
          crontab -l 2>/dev/null | sed "${del_line}d" | crontab -
          msg_ok "已删除"
        else
          msg_err "行号必须为数字"
        fi
      fi
      ;;
    3)
      crontab -e 2>/dev/null || msg_err "请安装编辑器"
      ;;
    4)
      local backup_cron="0 3 * * * /bin/bash -c 'source /etc/fusionbox/src/init.sh && system_backup /root/backups'"
      if crontab -l 2>/dev/null | grep -qF "$backup_cron"; then
        msg_warn "自动备份定时任务已存在，跳过添加"
      else
        (crontab -l 2>/dev/null; echo "$backup_cron") | crontab -
        msg_ok "每天凌晨 3 点自动备份已配置"
        _log_write "自动备份定时任务已配置"
      fi
      ;;
    5)
      local clean_cron="0 4 * * 0 journalctl --vacuum-time=7d && rm -rf /tmp/*.tmp"
      if crontab -l 2>/dev/null | grep -qF "$clean_cron"; then
        msg_warn "日志清理定时任务已存在，跳过添加"
      else
        (crontab -l 2>/dev/null; echo "$clean_cron") | crontab -
        msg_ok "每周日凌晨 4 点自动清理日志已配置"
      fi
      ;;
    6)
      systemctl status cron 2>/dev/null || systemctl status crond 2>/dev/null || service cron status 2>/dev/null
      ;;
  esac
  pause
}

# ---- 磁盘管理 ----
system_disk() {
  _require_root
  msg_title "磁盘管理"
  msg ""

  msg "  ${F_BOLD}磁盘分区:${F_RESET}"
  lsblk -f 2>/dev/null || fdisk -l 2>/dev/null | head -20

  msg ""
  msg "  ${F_BOLD}挂载信息:${F_RESET}"
  df -hT 2>/dev/null | awk 'NR<=10{printf "  %-20s %-8s %-8s %-8s %-5s %s\n", $1, $2, $3, $4, $5, $7}'

  msg ""
  msg "  ${F_BOLD}inode 使用:${F_RESET}"
  df -i / 2>/dev/null | awk 'NR==2{printf "  总计: %s  已用: %s  可用: %s  使用率: %s\n", $2, $3, $4, $5}'

  msg ""
  msg "  1) 磁盘分区（fdisk）"
  msg "  2) 格式化磁盘"
  msg "  3) 挂载磁盘"
  msg "  4) 卸载磁盘"
  msg "  5) 扩展分区（growpart）"
  msg "  6) 查看大文件（Top 20）"
  msg "  7) 查看目录大小"
  msg "  0) 返回"
  read -p "请选择: " disk_choice

  case "$disk_choice" in
    1)
      read -p "请输入磁盘设备（如 /dev/sdb）: " disk_dev
      if [[ -b "$disk_dev" ]]; then
        msg_warn "进入 fdisk 交互模式，输入 m 查看帮助"
        fdisk "$disk_dev"
      else
        msg_err "设备不存在: $disk_dev"
      fi
      ;;
    2)
      read -p "请输入要格式化的分区（如 /dev/sdb1）: " part_dev
      if [[ -b "$part_dev" ]]; then
        local fs_type; fs_type=$(select_option "文件系统:" "ext4 (推荐)" "xfs" "btrfs")
        msg_warn "即将格式化设备: $part_dev，该设备上的所有数据将被清除"
        local confirm_input=""
        read -r -p "请输入大写 YES 确认格式化 $part_dev: " confirm_input
        if [[ "$confirm_input" == "YES" ]]; then
          case "$fs_type" in
            1) mkfs.ext4 "$part_dev" ;;
            2) mkfs.xfs "$part_dev" ;;
            3) mkfs.btrfs "$part_dev" ;;
            *) mkfs.ext4 "$part_dev" ;;
          esac
          msg_ok "格式化完成"
        else
          msg_warn "已取消格式化"
        fi
      fi
      ;;
    3)
      read -p "请输入分区（如 /dev/sdb1）: " part_dev
      read -p "请输入挂载点（如 /data）: " mount_point
      if [[ -b "$part_dev" && -n "$mount_point" ]]; then
        mkdir -p "$mount_point"
        mount "$part_dev" "$mount_point"
        if grep -qE "^[[:space:]]*${part_dev}([[:space:]]|\$)" /etc/fstab 2>/dev/null || \
           grep -qE "^[[:space:]]*[^[:space:]]+[[:space:]]+${mount_point}([[:space:]]|\$)" /etc/fstab 2>/dev/null; then
          msg_warn "/etc/fstab 已存在 $part_dev 或 $mount_point 的挂载条目，跳过写入"
        else
          echo "$part_dev $mount_point auto defaults 0 2" >> /etc/fstab
          msg_ok "已挂载 $part_dev 到 $mount_point"
        fi
      fi
      ;;
    4)
      read -p "请输入挂载点: " mount_point
      if [[ -n "$mount_point" ]]; then
        umount "$mount_point" 2>/dev/null && msg_ok "已卸载 $mount_point" || msg_err "卸载失败"
      fi
      ;;
    5)
      read -p "请输入磁盘设备（如 /dev/sda）: " disk_dev
      read -p "请输入分区号（如 2）: " part_num
      if [[ -b "$disk_dev" && -n "$part_num" ]]; then
        _install_pkg cloud-guest-utils 2>/dev/null || _install_pkg cloud-utils-growpart 2>/dev/null
        growpart "$disk_dev" "$part_num" 2>/dev/null && msg_ok "分区已扩展" || msg_err "扩展失败"
        # Auto resize filesystem
        local part_dev="${disk_dev}${part_num}"
        if [[ -b "$part_dev" ]]; then
          resize2fs "$part_dev" 2>/dev/null || xfs_growfs "$part_dev" 2>/dev/null || true
          msg_ok "文件系统已扩展"
        fi
      fi
      ;;
    6)
      msg_info "正在扫描大文件..."
      find / -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -20
      ;;
    7)
      read -p "目录路径（默认 /）: " dir_path
      dir_path=${dir_path:-/}
      du -h --max-depth=2 "$dir_path" 2>/dev/null | sort -rh | head -20
      ;;
  esac
  pause
}

# ---- 时区管理 ----
system_timezone() {
  _require_root
  msg_title "时区管理"
  msg ""

  msg "  ${F_BOLD}当前时区:${F_RESET} $(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3, $4}' || cat /etc/timezone 2>/dev/null || date +%Z)"
  msg "  ${F_BOLD}当前时间:${F_RESET} $(date '+%Y-%m-%d %H:%M:%S %Z')"

  msg ""
  msg "  1) 设置时区为 亚洲/上海"
  msg "  2) 设置时区为 亚洲/东京"
  msg "  3) 设置时区为 美国/纽约"
  msg "  4) 设置时区为 欧洲/伦敦"
  msg "  5) 自定义时区"
  msg "  6) 同步时间（NTP）"
  msg "  0) 返回"
  read -p "请选择: " tz_choice

  case "$tz_choice" in
    1) timedatectl set-timezone Asia/Shanghai 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; msg_ok "时区已设置为 Asia/Shanghai" ;;
    2) timedatectl set-timezone Asia/Tokyo 2>/dev/null || ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime; msg_ok "时区已设置为 Asia/Tokyo" ;;
    3) timedatectl set-timezone America/New_York 2>/dev/null || ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime; msg_ok "时区已设置为 America/New_York" ;;
    4) timedatectl set-timezone Europe/London 2>/dev/null || ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime; msg_ok "时区已设置为 Europe/London" ;;
    5)
      read -p "请输入时区（如 Asia/Shanghai）: " custom_tz
      if [[ -n "$custom_tz" ]]; then
        timedatectl set-timezone "$custom_tz" 2>/dev/null || ln -sf "/usr/share/zoneinfo/$custom_tz" /etc/localtime
        msg_ok "时区已设置为 $custom_tz"
      fi
      ;;
    6)
      _install_pkg ntp 2>/dev/null || _install_pkg chrony 2>/dev/null || true
      if command -v ntpdate &>/dev/null; then
        ntpdate pool.ntp.org 2>/dev/null && msg_ok "时间已同步"
      elif command -v chronyc &>/dev/null; then
        chronyc makestep 2>/dev/null && msg_ok "时间已同步"
      elif command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true 2>/dev/null && msg_ok "NTP 已启用"
      fi
      msg "  当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
      ;;
  esac
  _log_write "时区设置已更改"
  pause
}

# ---- 回收站管理 ----
system_trash() {
  _require_root
  local trash_dir="/root/.fusionbox_trash"
  mkdir -p "$trash_dir"

  msg_title "回收站管理"
  msg ""

  local trash_count=$(find "$trash_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  msg "  ${F_BOLD}回收站:${F_RESET} $trash_dir"
  msg "  ${F_BOLD}文件数:${F_RESET} $trash_count"

  if [[ $trash_count -gt 0 ]]; then
    msg ""
    msg "  ${F_BOLD}最近删除:${F_RESET}"
    ls -lhrt "$trash_dir" 2>/dev/null | tail -10 | awk '{printf "  %s %s %s %s\n", $6, $7, $5, $9}'
  fi

  msg ""
  msg "  1) 安全删除文件（移入回收站）"
  msg "  2) 恢复文件"
  msg "  3) 清空回收站"
  msg "  4) 查看回收站内容"
  msg "  0) 返回"
  read -p "请选择: " trash_choice

  case "$trash_choice" in
    1)
      read -p "请输入要删除的文件/目录路径: " target_path
      if [[ -e "$target_path" ]]; then
        local trash_name="$(basename "$target_path")_$(date +%s)"
        mv "$target_path" "$trash_dir/$trash_name"
        msg_ok "已移入回收站: $target_path → $trash_dir/$trash_name"
        _log_write "文件已移入回收站: $target_path"
      else
        msg_err "文件不存在: $target_path"
      fi
      ;;
    2)
      if [[ $trash_count -eq 0 ]]; then
        msg "回收站为空"
      else
        ls -lhrt "$trash_dir" | tail -10 | nl -ba
        read -p "输入要恢复的文件名: " restore_name
        if [[ -e "$trash_dir/$restore_name" ]]; then
          read -p "恢复到路径: " restore_path
          mv "$trash_dir/$restore_name" "$restore_path"
          msg_ok "已恢复到: $restore_path"
        fi
      fi
      ;;
    3)
      if confirm "确认清空回收站？此操作不可恢复！"; then
        rm -rf "$trash_dir"/*
        msg_ok "回收站已清空"
        _log_write "回收站已清空"
      fi
      ;;
    4)
      find "$trash_dir" -mindepth 1 -maxdepth 1 -exec ls -lh {} \; 2>/dev/null
      ;;
  esac
  pause
}

# ==== 系统设置（DNS/主机名/hosts/源/日志/流量/告警/网络优化） ====

# ---- 通用：文件备份 ----
# 用法: _fb_backup_file <源文件> <备份路径>
_fb_backup_file() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 1
  mkdir -p "$(dirname "$dst")" 2>/dev/null
  cp -Lp "$src" "$dst" 2>/dev/null || cp -p "$src" "$dst" 2>/dev/null || return 1
  return 0
}

# ---- DNS 优化 ----
_system_dns_lock_status() {
  if command -v lsattr &>/dev/null && lsattr /etc/resolv.conf 2>/dev/null | awk '{print $1}' | grep -q 'i'; then
    echo "已锁定 (chattr +i)"
  else
    echo "未锁定"
  fi
}

# 用法: _system_dns_apply <标签> <DNS1> [DNS2...]
_system_dns_apply() {
  if [[ -L /etc/resolv.conf ]] || systemctl is-active systemd-resolved >/dev/null 2>&1; then
    msg_err "DNS 由链接或 systemd-resolved 管理，请使用 resolvectl 或网络管理器配置"; return 1
  fi
  local label="$1"; shift
  local -a servers=("$@")
  local s

  if [[ ${#servers[@]} -eq 0 ]]; then
    msg_err "未提供 DNS 服务器地址"
    return 1
  fi
  for s in "${servers[@]}"; do
    if [[ ! "$s" =~ ^[0-9a-fA-F:.]+$ ]] || ! python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$s" 2>/dev/null; then
      msg_err "无效的 DNS 地址: $s"
      return 1
    fi
  done

  msg ""
  msg_info "即将写入以下 DNS ($label):"
  for s in "${servers[@]}"; do msg "    nameserver $s"; done

  if systemctl is-active systemd-resolved &>/dev/null; then
    msg_warn "检测到 systemd-resolved 正在运行，/etc/resolv.conf 可能被其自动覆盖"
    msg_warn "如需长期生效，可同时使用菜单中的锁定功能，或改用 resolvectl 配置"
  fi
  if [[ -L /etc/resolv.conf ]]; then
    msg_warn "/etc/resolv.conf 当前是符号链接，写入时会替换为普通文件（原内容已备份）"
  fi

  confirm "确认修改 DNS？" || return 1

  local bak="/etc/resolv.conf.fb-bak-$(date +%s)"
  if [[ -e /etc/resolv.conf ]]; then
    if ! _fb_backup_file /etc/resolv.conf "$bak"; then
      msg_err "备份 /etc/resolv.conf 失败，已取消修改"
      return 1
    fi
    msg_ok "已备份原配置: $bak"
  fi

  local staged
  staged=$(mktemp /etc/.fusionbox-dns.XXXXXXXX) || return 1
  if ! printf 'nameserver %s\n' "${servers[@]}" > "$staged" ||
     ! chmod 644 "$staged"; then
    rm -f "$staged"; return 1
  fi

  if [[ ! -L /etc/resolv.conf ]] && mv -T "$staged" /etc/resolv.conf; then
    msg_ok "DNS 已更新 ($label)"
    msg "  当前配置:"
    grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r s; do msg "    $s"; done
    _log_write "DNS 已更新为 $label"
  else
    msg_err "写入 /etc/resolv.conf 失败"
    rm -f "$staged"
    return 1
  fi
  return 0
}

_system_dns_restore() {
  if [[ -L /etc/resolv.conf ]] || systemctl is-active systemd-resolved >/dev/null 2>&1; then
    msg_err "保留受管理的 DNS 配置，拒绝覆盖"; return 1
  fi
  local -a baks=()
  local f
  while IFS= read -r f; do baks+=("$f"); done < <(ls -1t /etc/resolv.conf.fb-bak-* 2>/dev/null)

  if [[ ${#baks[@]} -eq 0 ]]; then
    msg_warn "没有找到备份文件 (/etc/resolv.conf.fb-bak-*)"
    return 1
  fi

  msg ""
  msg_info "可用备份:"
  local i=1
  for f in "${baks[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) $(basename "$f")"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "选择要恢复的备份编号" "1") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "编号必须为数字"; return 1; }
  local idx=$((sel - 1))
  if [[ $idx -lt 0 || $idx -ge ${#baks[@]} ]]; then
    msg_err "编号超出范围 (1-${#baks[@]})"
    return 1
  fi

  confirm "确认用 $(basename "${baks[$idx]}") 覆盖当前 /etc/resolv.conf？" || return 1
  local staged
  staged=$(mktemp /etc/.fusionbox-dns.XXXXXXXX) || return 1
  if [[ ! -L /etc/resolv.conf ]] &&
     cp -- "${baks[$idx]}" "$staged" && chmod 644 "$staged" &&
     mv -T "$staged" /etc/resolv.conf; then
    msg_ok "已恢复: ${baks[$idx]}"
    grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r f; do msg "    $f"; done
    _log_write "resolv.conf 已从备份恢复"
  else
    msg_err "恢复失败"
    return 1
  fi
}

system_dns() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "DNS 优化"
    msg ""
    msg "  ${F_BOLD}当前 DNS (/etc/resolv.conf):${F_RESET}"
    if [[ -f /etc/resolv.conf ]] && grep -qE "^[[:space:]]*nameserver" /etc/resolv.conf 2>/dev/null; then
      grep -E "^[[:space:]]*nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r line; do msg "    $line"; done
    else
      msg "    (无 nameserver 配置)"
    fi
    msg "  ${F_BOLD}文件状态:${F_RESET} $(_system_dns_lock_status)"
    if systemctl is-active systemd-resolved &>/dev/null; then
      msg "  ${F_YELLOW}提示: systemd-resolved 运行中，修改可能被覆盖${F_RESET}"
    fi
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 国内 DNS 预设 (阿里 / 腾讯 / 114DNS)"
    msg "  ${F_GREEN} 2${F_RESET}) 国际 DNS 预设 (Cloudflare / Google / Quad9)"
    msg "  ${F_GREEN} 3${F_RESET}) 自定义 DNS (每行一个)"
    msg "  ${F_GREEN} 4${F_RESET}) 锁定 /etc/resolv.conf (chattr +i)"
    msg "  ${F_GREEN} 5${F_RESET}) 解锁 /etc/resolv.conf (chattr -i)"
    msg "  ${F_GREEN} 6${F_RESET}) 恢复上次备份"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-6]: " dns_choice || { msg ""; break; }

    case "$dns_choice" in
      1)
        msg ""
        msg "  国内 DNS 预设:"
        msg "    1) 阿里 DNS    223.5.5.5 / 223.6.6.6"
        msg "    2) 腾讯 DNS    119.29.29.29"
        msg "    3) 114DNS      114.114.114.114"
        local cn_sel=""; cn_sel=$(read_input "请选择" "1")
        case "$cn_sel" in
          2) _system_dns_apply "腾讯 DNS" 119.29.29.29 ;;
          3) _system_dns_apply "114DNS" 114.114.114.114 ;;
          *) _system_dns_apply "阿里 DNS" 223.5.5.5 223.6.6.6 ;;
        esac
        pause ;;
      2)
        msg ""
        msg "  国际 DNS 预设:"
        msg "    1) Cloudflare  1.1.1.1 / 1.0.0.1"
        msg "    2) Google      8.8.8.8 / 8.8.4.4"
        msg "    3) Quad9       9.9.9.9"
        local intl_sel=""; intl_sel=$(read_input "请选择" "1")
        case "$intl_sel" in
          2) _system_dns_apply "Google DNS" 8.8.8.8 8.8.4.4 ;;
          3) _system_dns_apply "Quad9" 9.9.9.9 ;;
          *) _system_dns_apply "Cloudflare" 1.1.1.1 1.0.0.1 ;;
        esac
        pause ;;
      3)
        msg ""
        msg_info "请依次输入 DNS 地址，每行一个，直接回车结束（最多 4 个）"
        local -a custom_dns=()
        while [[ ${#custom_dns[@]} -lt 4 ]]; do
          local one_dns=""; one_dns=$(read_input "DNS 服务器 (回车结束)" "") || break
          [[ -z "$one_dns" ]] && break
          if [[ ! "$one_dns" =~ ^[0-9a-fA-F:.]+$ ]]; then
            msg_err "无效地址: $one_dns（仅允许 IP 字符）"
            continue
          fi
          custom_dns+=("$one_dns")
        done
        if [[ ${#custom_dns[@]} -eq 0 ]]; then
          msg_warn "未输入任何地址，已取消"
        else
          _system_dns_apply "自定义" "${custom_dns[@]}"
        fi
        pause ;;
      4)
        if ! command -v chattr &>/dev/null; then
          msg_err "系统未安装 chattr（e2fsprogs），无法锁定"
        elif chattr +i /etc/resolv.conf 2>/dev/null; then
          msg_ok "/etc/resolv.conf 已锁定，修改前需先解锁"
          _log_write "resolv.conf 已锁定 (chattr +i)"
        else
          msg_err "锁定失败（文件系统可能不支持 immutable 属性）"
        fi
        pause ;;
      5)
        if chattr -i /etc/resolv.conf 2>/dev/null; then
          msg_ok "/etc/resolv.conf 已解锁"
          _log_write "resolv.conf 已解锁 (chattr -i)"
        else
          msg_err "解锁失败（可能本就未锁定，或文件系统不支持）"
        fi
        pause ;;
      6)
        _system_dns_restore
        pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 修改主机名 ----
system_hostname() {
  _require_root
  msg_title "修改主机名"
  msg ""

  local cur; cur=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
  msg "  ${F_BOLD}当前主机名:${F_RESET} ${cur:-未知}"
  msg ""

  local newname; newname=$(read_input "请输入新的主机名" "") || { pause; return 1; }
  newname="${newname// /}"
  if [[ -z "$newname" ]]; then
    msg_err "主机名不能为空"
    pause; return 1
  fi
  if [[ ! "$newname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
    msg_err "主机名格式无效：仅允许字母/数字/点/连字符，需以字母或数字开头，最长 63 字符"
    pause; return 1
  fi
  if [[ "$newname" == "$cur" ]]; then
    msg_warn "新主机名与当前相同，无需修改"
    pause; return 0
  fi
  if ! confirm "确认将主机名从 '$cur' 修改为 '$newname'？"; then
    pause; return 1
  fi

  local set_ok=0
  if command -v hostnamectl &>/dev/null && hostnamectl set-hostname "$newname" 2>/dev/null; then
    set_ok=1
    msg_ok "已通过 hostnamectl 设置主机名"
  else
    _fb_backup_file /etc/hostname "/etc/hostname.fb-bak-$(date +%s)" >/dev/null 2>&1
    if echo "$newname" > /etc/hostname 2>/dev/null; then
      set_ok=1
      msg_ok "已写入 /etc/hostname（未检测到可用的 hostnamectl）"
    fi
  fi
  if [[ $set_ok -eq 0 ]]; then
    msg_err "主机名设置失败"
    pause; return 1
  fi

  # 同步 /etc/hosts 中的 127.0.1.1 记录
  if [[ -f /etc/hosts ]]; then
    _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
    if grep -qE "^127\.0\.1\.1([[:space:]]|$)" /etc/hosts 2>/dev/null; then
      sed -i -E "s|^127\.0\.1\.1([[:space:]]).*|127.0.1.1\t$newname|" /etc/hosts
      msg_info "已更新 /etc/hosts 中的 127.0.1.1 记录"
    else
      echo -e "127.0.1.1\t$newname" >> /etc/hosts
      msg_info "已向 /etc/hosts 追加 127.0.1.1 记录"
    fi
  fi

  msg ""
  msg "  ${F_BOLD}当前主机名:${F_RESET} $(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)"
  msg "  ${F_BOLD}/etc/hostname:${F_RESET} $(cat /etc/hostname 2>/dev/null)"
  msg_tip "部分服务需重新登录或重启后才会显示新主机名"
  _log_write "主机名已修改为 $newname"
  pause
}

# ---- hosts 解析管理 ----
# 输出 "行号: 内容"，仅非注释、非空行
_system_hosts_entries() {
  awk 'NF && $1 !~ /^#/ {print NR": "$0}' /etc/hosts 2>/dev/null
}

_system_hosts_show() {
  msg "  ${F_BOLD}当前 hosts 记录:${F_RESET}"
  local -a entries=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done < <(_system_hosts_entries)
  if [[ ${#entries[@]} -eq 0 ]]; then
    msg "    暂无解析记录"
    return 0
  fi
  local i=1
  for line in "${entries[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) ${line#*: }"
    i=$((i + 1))
  done
}

_system_hosts_add() {
  local ip host
  ip=$(read_input "请输入 IP 地址（如 1.2.3.4）" "") || return 1
  if [[ ! "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
    msg_err "IP 地址格式无效: $ip"
    return 1
  fi
  host=$(read_input "请输入主机名（如 example.com）" "") || return 1
  if [[ ! "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
    msg_err "主机名格式无效: $host"
    return 1
  fi
  if [[ -f /etc/hosts ]] && awk -v ip="$ip" -v h="$host" \
      'NF && $1 !~ /^#/ && $1==ip {for(i=2;i<=NF;i++) if($i==h) f=1} END{exit !f}' /etc/hosts; then
    msg_warn "记录已存在: $ip $host，跳过添加"
    return 1
  fi

  confirm "确认添加记录 '$ip $host' 到 /etc/hosts？" || return 1
  _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
  if echo -e "$ip\t$host" >> /etc/hosts 2>/dev/null; then
    msg_ok "已添加: $ip $host"
    _log_write "/etc/hosts 已添加: $ip $host"
  else
    msg_err "写入 /etc/hosts 失败"
    return 1
  fi
  return 0
}

_system_hosts_delete() {
  local -a entries=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done < <(_system_hosts_entries)

  if [[ ${#entries[@]} -eq 0 ]]; then
    msg_warn "没有可删除的解析记录"
    return 1
  fi

  msg "  ${F_BOLD}请选择要删除的记录:${F_RESET}"
  local i=1
  for line in "${entries[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) ${line#*: }"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "输入序号（0 取消）" "0") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "序号必须为数字"; return 1; }
  [[ "$sel" -eq 0 ]] && return 1
  if [[ "$sel" -lt 1 || "$sel" -gt ${#entries[@]} ]]; then
    msg_err "序号超出范围 (1-${#entries[@]})"
    return 1
  fi

  local target="${entries[$((sel - 1))]}"
  local lineno="${target%%:*}"
  local content="${target#*: }"

  confirm "确认删除记录 '$content'？" || return 1
  _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
  if sed -i "${lineno}d" /etc/hosts 2>/dev/null; then
    msg_ok "已删除: $content"
    _log_write "/etc/hosts 已删除记录: $content"
  else
    msg_err "删除失败"
    return 1
  fi
  return 0
}

system_hosts() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "hosts 解析管理"
    msg ""
    _system_hosts_show
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 添加解析记录"
    msg "  ${F_GREEN} 2${F_RESET}) 删除解析记录（按序号）"
    msg "  ${F_GREEN} 3${F_RESET}) 刷新显示"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-3]: " hosts_choice || { msg ""; break; }
    case "$hosts_choice" in
      1) _system_hosts_add; pause ;;
      2) _system_hosts_delete; pause ;;
      3) ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 系统更新源切换 ----
_system_mirror_detect() {
  if command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    echo "yum"
  else
    echo "none"
  fi
}

# 用法: _system_mirror_restore_dir <备份目录>
_system_mirror_restore_dir() {
  local dir="$1"
  if [[ ! -f "$dir/files.manifest" ]]; then
    msg_warn "备份目录缺少 manifest: $dir"
    return 1
  fi
  local flat orig rc=0
  while IFS=$'\t' read -r flat orig; do
    [[ -z "$flat" || -z "$orig" ]] && continue
    [[ -f "$dir/$flat" ]] || continue
    if ! cp -Lp "$dir/$flat" "$orig" 2>/dev/null; then
      msg_err "回滚失败: $orig"
      rc=1
    fi
  done < "$dir/files.manifest"
  return $rc
}

# 用法: _system_mirror_apply_apt <镜像域名> <名称>
_system_mirror_apply_apt() {
  local host="$1" label="$2"
  local -a files=()
  local f

  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")
  if [[ -d /etc/apt/sources.list.d ]]; then
    for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
      [[ -f "$f" ]] && files+=("$f")
    done
  fi
  if [[ ${#files[@]} -eq 0 ]]; then
    msg_warn "未找到 APT 源文件"
    return 1
  fi

  local matched=0
  for f in "${files[@]}"; do
    if grep -qE "archive\.ubuntu\.com|security\.ubuntu\.com|deb\.debian\.org|security\.debian\.org" "$f" 2>/dev/null; then
      matched=1
    fi
  done
  if [[ $matched -eq 0 ]]; then
    msg_warn "源文件中未找到官方域名（archive.ubuntu.com / deb.debian.org 等）"
    msg "  可能已切换过镜像，或使用了第三方源；可先用「显示当前源」确认"
    return 1
  fi

  msg ""
  msg_info "以下文件中的官方域名将被替换为 $host:"
  for f in "${files[@]}"; do msg "    $f"; done
  msg_warn "仅为域名替换，发行版路径保持不变（Ubuntu 24.04 的 .sources 同样处理）"
  confirm "确认切换到 $label？" || return 1

  local bak_dir="/etc/fusionbox/mirror-bak-$(date +%s)"
  mkdir -p "$bak_dir" || { msg_err "无法创建备份目录 $bak_dir"; return 1; }
  : > "$bak_dir/files.manifest"
  for f in "${files[@]}"; do
    local flat="${f//\//_}"
    if ! cp -Lp "$f" "$bak_dir/$flat" 2>/dev/null; then
      msg_err "备份 $f 失败，已取消操作"
      return 1
    fi
    printf '%s\t%s\n' "$flat" "$f" >> "$bak_dir/files.manifest"
  done
  msg_ok "已备份到 $bak_dir"

  for f in "${files[@]}"; do
    sed -i -E "s/archive\.ubuntu\.com/$host/g; s/security\.ubuntu\.com/$host/g; s/deb\.debian\.org/$host/g; s/security\.debian\.org/$host/g" "$f" 2>/dev/null
  done

  msg_info "正在执行 apt-get update 验证..."
  local out
  if out=$(apt-get update -y 2>&1); then
    msg_ok "更新源已切换为 $label ($host)，验证通过"
    _log_write "APT 源已切换为 $label ($host)"
  else
    msg_err "apt-get update 失败，正在从备份回滚..."
    echo "$out" | tail -8 | sed 's/^/    /'
    if _system_mirror_restore_dir "$bak_dir"; then
      msg_warn "已从备份回滚 ($bak_dir)"
      _log_write "APT 源切换失败，已回滚 ($label)"
    else
      msg_err "回滚不完整，请手动检查，备份目录: $bak_dir"
    fi
  fi
  return 0
}

# 用法: _system_mirror_apply_yum <镜像域名> <名称>
_system_mirror_apply_yum() {
  local host="$1" label="$2"
  local -a files=()
  local f

  for f in /etc/yum.repos.d/*.repo /etc/yum.conf; do
    [[ -f "$f" ]] && files+=("$f")
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    msg_warn "未找到 yum/dnf 源文件"
    return 1
  fi

  local matched=0
  for f in "${files[@]}"; do
    if grep -qE "mirror(list)?\.centos\.org|mirrors\.centos\.org" "$f" 2>/dev/null; then
      matched=1
    fi
  done
  if [[ $matched -eq 0 ]]; then
    msg_warn "未找到 mirror.centos.org / mirrorlist.centos.org 等官方域名"
    return 1
  fi

  msg ""
  msg_info "以下文件中的官方域名将被替换为 $host:"
  for f in "${files[@]}"; do msg "    $f"; done
  msg_warn "mirrorlist 形式的条目替换后可能仍需手动调整为 baseurl"
  confirm "确认切换到 $label？" || return 1

  local bak_dir="/etc/fusionbox/mirror-bak-$(date +%s)"
  mkdir -p "$bak_dir" || { msg_err "无法创建备份目录 $bak_dir"; return 1; }
  : > "$bak_dir/files.manifest"
  for f in "${files[@]}"; do
    local flat="${f//\//_}"
    if ! cp -Lp "$f" "$bak_dir/$flat" 2>/dev/null; then
      msg_err "备份 $f 失败，已取消操作"
      return 1
    fi
    printf '%s\t%s\n' "$flat" "$f" >> "$bak_dir/files.manifest"
  done
  msg_ok "已备份到 $bak_dir"

  for f in "${files[@]}"; do
    sed -i -E "s/mirrorlist\.centos\.org/$host/g; s/mirror\.centos\.org/$host/g; s/mirrors\.centos\.org/$host/g" "$f" 2>/dev/null
  done

  msg_info "正在执行 makecache 验证..."
  local out rc=0
  if command -v dnf &>/dev/null; then
    out=$(dnf makecache -y 2>&1) || rc=1
  else
    out=$(yum makecache -y 2>&1) || rc=1
  fi
  if [[ $rc -eq 0 ]]; then
    msg_ok "更新源已切换为 $label ($host)，验证通过"
    _log_write "YUM 源已切换为 $label ($host)"
  else
    msg_err "makecache 失败，正在从备份回滚..."
    echo "$out" | tail -8 | sed 's/^/    /'
    if _system_mirror_restore_dir "$bak_dir"; then
      msg_warn "已从备份回滚 ($bak_dir)"
      _log_write "YUM 源切换失败，已回滚 ($label)"
    else
      msg_err "回滚不完整，请手动检查，备份目录: $bak_dir"
    fi
  fi
  return 0
}

_system_mirror_restore() {
  local -a dirs=()
  local d
  while IFS= read -r d; do dirs+=("$d"); done < <(ls -1dt /etc/fusionbox/mirror-bak-* 2>/dev/null)

  if [[ ${#dirs[@]} -eq 0 ]]; then
    msg_warn "没有找到备份目录 (/etc/fusionbox/mirror-bak-*)"
    return 1
  fi

  msg "  ${F_BOLD}可用备份:${F_RESET}"
  local i=1
  for d in "${dirs[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) $d"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "选择要恢复的备份编号" "1") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "编号必须为数字"; return 1; }
  local idx=$((sel - 1))
  if [[ $idx -lt 0 || $idx -ge ${#dirs[@]} ]]; then
    msg_err "编号超出范围 (1-${#dirs[@]})"
    return 1
  fi

  confirm "确认从 ${dirs[$idx]} 恢复更新源？" || return 1
  if _system_mirror_restore_dir "${dirs[$idx]}"; then
    msg_ok "更新源已恢复，正在刷新源索引..."
    case "$(_system_mirror_detect)" in
      apt)
        if apt-get update -y >/dev/null 2>&1; then
          msg_ok "apt-get update 完成"
        else
          msg_warn "apt-get update 失败，请检查源配置"
        fi
        ;;
      yum)
        if command -v dnf &>/dev/null; then
          dnf makecache -y >/dev/null 2>&1 || msg_warn "makecache 失败，请检查源配置"
        else
          yum makecache -y >/dev/null 2>&1 || msg_warn "makecache 失败，请检查源配置"
        fi
        ;;
    esac
    _log_write "更新源已从备份恢复: ${dirs[$idx]}"
  else
    msg_err "恢复失败，请检查备份目录: ${dirs[$idx]}"
  fi
  return 0
}

_system_mirror_show() {
  local f
  case "$(_system_mirror_detect)" in
    apt)
      for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$f" ]] || continue
        msg "  ${F_BOLD}[$f]${F_RESET}"
        grep -vE "^[[:space:]]*(#|$)" "$f" 2>/dev/null | head -12 | sed 's/^/    /'
      done
      ;;
    yum)
      for f in /etc/yum.repos.d/*.repo /etc/yum.conf; do
        [[ -f "$f" ]] || continue
        msg "  ${F_BOLD}[$f]${F_RESET}"
        grep -iE "^(baseurl|mirrorlist|name)=" "$f" 2>/dev/null | head -12 | sed 's/^/    /'
      done
      ;;
    *)
      msg_warn "当前系统不受支持"
      ;;
  esac
}

system_mirror() {
  _require_root
  local kind; kind=$(_system_mirror_detect)
  if [[ "$kind" == "none" ]]; then
    msg_warn "当前系统不支持自动切换更新源（未检测到 apt/dnf/yum）"
    pause
    return 1
  fi

  while true; do
    clear
    _print_banner
    msg_title "系统更新源切换"
    msg ""
    msg "  ${F_BOLD}包管理器:${F_RESET} $kind"
    msg "  ${F_BOLD}备份目录:${F_RESET} /etc/fusionbox/mirror-bak-<时间戳>/"
    msg ""
    if [[ "$kind" == "apt" ]]; then
      msg "  ${F_GREEN} 1${F_RESET}) 阿里云    mirrors.aliyun.com"
      msg "  ${F_GREEN} 2${F_RESET}) 清华大学  mirrors.tuna.tsinghua.edu.cn"
      msg "  ${F_GREEN} 3${F_RESET}) 中科大    mirrors.ustc.edu.cn"
      msg "  ${F_GREEN} 4${F_RESET}) 华为云    mirrors.huaweicloud.com"
    else
      msg "  ${F_GREEN} 1${F_RESET}) 阿里云    mirrors.aliyun.com"
      msg "  ${F_GREEN} 2${F_RESET}) 清华大学  mirrors.tuna.tsinghua.edu.cn"
      msg "  ${F_YELLOW} 3/4${F_RESET}) 仅 Debian/Ubuntu 可用（yum/dnf 只支持阿里云与清华）"
    fi
    msg "  ${F_GREEN} 5${F_RESET}) 恢复上次备份"
    msg "  ${F_GREEN} 6${F_RESET}) 显示当前源"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-6]: " mirror_choice || { msg ""; break; }

    case "$mirror_choice" in
      1)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.aliyun.com" "阿里云"
        else
          _system_mirror_apply_yum "mirrors.aliyun.com" "阿里云"
        fi
        pause ;;
      2)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.tuna.tsinghua.edu.cn" "清华大学"
        else
          _system_mirror_apply_yum "mirrors.tuna.tsinghua.edu.cn" "清华大学"
        fi
        pause ;;
      3)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.ustc.edu.cn" "中科大"
        else
          msg_warn "yum/dnf 仅支持阿里云与清华源"
        fi
        pause ;;
      4)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.huaweicloud.com" "华为云"
        else
          msg_warn "yum/dnf 仅支持阿里云与清华源"
        fi
        pause ;;
      5) _system_mirror_restore; pause ;;
      6) _system_mirror_show; pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 系统日志管理 ----
_system_log_clean() {
  msg ""
  msg "  ${F_BOLD}当前日志占用:${F_RESET}"
  if command -v journalctl &>/dev/null; then
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /' || msg "    (无法获取)"
  else
    du -sh /var/log 2>/dev/null | awk '{print "    /var/log: " $1}'
  fi
  msg ""
  msg "  1) 清理到 100M"
  msg "  2) 清理到 500M"
  msg "  3) 清理到 1G"
  msg "  4) 只保留最近 7 天"
  msg "  0) 取消"
  local sel; sel=$(read_input "请选择" "0") || return 1

  local arg=""
  case "$sel" in
    1) arg="--vacuum-size=100M" ;;
    2) arg="--vacuum-size=500M" ;;
    3) arg="--vacuum-size=1G" ;;
    4) arg="--vacuum-time=7d" ;;
    *) return 0 ;;
  esac

  if ! command -v journalctl &>/dev/null; then
    msg_warn "当前系统不支持 journalctl，无法自动清理"
    return 1
  fi
  confirm "确认执行日志清理 ($arg)？" || return 1
  if journalctl "$arg" 2>/dev/null; then
    msg_ok "日志清理完成"
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /'
    _log_write "系统日志已清理 ($arg)"
  else
    msg_err "日志清理失败（可能需要 systemd-journald 权限）"
    return 1
  fi
  return 0
}

system_log() {
  _require_root
  local has_journal=0
  command -v journalctl &>/dev/null && has_journal=1

  while true; do
    clear
    _print_banner
    msg_title "系统日志管理"
    msg ""
    if [[ $has_journal -eq 1 ]]; then
      msg "  ${F_BOLD}日志组件:${F_RESET} journalctl 可用"
    else
      msg "  ${F_BOLD}日志组件:${F_RESET} ${F_YELLOW}未检测到 journalctl，将回退到日志文件${F_RESET}"
    fi
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 最近错误 (优先级 3 及以上)"
    msg "  ${F_GREEN} 2${F_RESET}) 查看指定服务日志"
    msg "  ${F_GREEN} 3${F_RESET}) SSH 登录 / 失败记录"
    msg "  ${F_GREEN} 4${F_RESET}) 内核日志 (dmesg)"
    msg "  ${F_GREEN} 5${F_RESET}) 日志占用与清理"
    msg "  ${F_GREEN} 6${F_RESET}) 实时跟踪日志"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-6]: " log_choice || { msg ""; break; }

    case "$log_choice" in
      1)
        msg ""
        msg "  ${F_BOLD}[最近错误]${F_RESET}"
        if [[ $has_journal -eq 1 ]]; then
          journalctl -p 3 -n 50 --no-pager 2>/dev/null || msg_warn "读取 journalctl 失败"
        else
          tail -n 50 /var/log/messages 2>/dev/null || tail -n 50 /var/log/syslog 2>/dev/null || msg_warn "未找到系统日志文件"
        fi
        pause ;;
      2)
        local unit; unit=$(read_input "请输入服务名（如 nginx、sshd）" "") || { pause; continue; }
        if [[ ! "$unit" =~ ^[a-zA-Z0-9@._:-]+$ ]]; then
          msg_err "服务名格式无效: $unit"
        elif [[ $has_journal -eq 1 ]]; then
          msg ""
          journalctl -u "$unit" -n 100 --no-pager 2>/dev/null || msg_warn "未找到 $unit 的日志"
        else
          msg_warn "当前系统不支持 journalctl，请手动查看 /var/log/ 下对应文件"
        fi
        pause ;;
      3)
        msg ""
        msg "  ${F_BOLD}[SSH 登录成功 / 失败]${F_RESET}"
        if [[ $has_journal -eq 1 ]]; then
          journalctl -u ssh -u sshd -n 100 --no-pager 2>/dev/null | grep -E "Accepted|Failed|Invalid user" | tail -20
        fi
        local lf
        for lf in /var/log/auth.log /var/log/secure; do
          if [[ -f "$lf" ]]; then
            msg "  ${F_BOLD}[$lf]${F_RESET}"
            grep -E "Accepted|Failed|Invalid user" "$lf" 2>/dev/null | tail -20 | sed 's/^/    /'
          fi
        done
        msg_tip "如无输出，说明近期没有登录记录或日志已轮转"
        pause ;;
      4)
        msg ""
        msg "  ${F_BOLD}[内核日志 (最近 40 行)]${F_RESET}"
        if command -v dmesg &>/dev/null; then
          dmesg 2>/dev/null | tail -40 || msg_warn "dmesg 读取失败（可能受 kernel.dmesg_restrict 限制）"
        elif [[ -f /var/log/dmesg ]]; then
          tail -40 /var/log/dmesg 2>/dev/null
        else
          msg_warn "系统未提供 dmesg"
        fi
        pause ;;
      5)
        _system_log_clean
        pause ;;
      6)
        if [[ $has_journal -eq 1 ]]; then
          msg_warn "进入实时日志跟踪，按 Ctrl+C 退出"
          msg ""
          journalctl -f
        else
          msg_warn "进入实时日志跟踪，按 Ctrl+C 退出"
          msg ""
          tail -f /var/log/messages 2>/dev/null || tail -f /var/log/syslog 2>/dev/null || msg_warn "无可用日志文件"
        fi
        pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 流量阈值保护 ----
_traffic_guard_conf_get() {
  local key="$1"
  [[ -f /etc/fusionbox/traffic-guard.conf ]] || return 1
  sed -n "s/^[[:space:]]*${key}=//p" /etc/fusionbox/traffic-guard.conf | tail -1 | tr -d '"' | tr -d "'" | tr -d '\r'
}

# 用法: _traffic_guard_conf_write <IFACE> <LIMIT_GB> <ACTION> <CHECK_INTERVAL_MIN>
_traffic_guard_conf_write() {
  local iface="$1" limit="$2" action="$3" interval="$4"
  mkdir -p /etc/fusionbox
  cat > /etc/fusionbox/traffic-guard.conf << TEOF
# FusionBox 流量阈值保护配置（含策略，权限 600）
# IFACE: 监控网卡；auto = 汇总除 lo/docker*/veth*/br-* 以外的全部网卡
IFACE=$iface
# LIMIT_GB: 自然月流量上限（GB），超过后按 ACTION 处理
LIMIT_GB=$limit
# ACTION: warn 仅告警 / shutdown 超限后 5 分钟关机
ACTION=$action
# CHECK_INTERVAL_MIN: 检查间隔（分钟），与 cron 每 5 分钟执行配合节流
CHECK_INTERVAL_MIN=$interval
TEOF
  chmod 600 /etc/fusionbox/traffic-guard.conf
}

_traffic_guard_install_bin() {
  mkdir -p /usr/local/bin /etc/fusionbox /var/lib/fusionbox /var/log

  { printf '#!/bin/bash\nset +x\n'; declare -f _fb_telegram_send _fb_atomic_state; } > /usr/local/bin/fusionbox-traffic-guard || return 1
  cat >> /usr/local/bin/fusionbox-traffic-guard << 'TGEOF'
#!/bin/bash
# FusionBox 流量阈值保护脚本（由 fusionbox system traffic-guard 安装）
# 配置: /etc/fusionbox/traffic-guard.conf
# 状态: /var/lib/fusionbox/traffic-guard.state
# 日志: /var/log/fusionbox-traffic-guard.log

CONF="/etc/fusionbox/traffic-guard.conf"
STATE_DIR="/var/lib/fusionbox"
STATE="$STATE_DIR/traffic-guard.state"
FLAG="$STATE_DIR/traffic-guard.shutdown"
LOG="/var/log/fusionbox-traffic-guard.log"
NOTIFY_CONF="/etc/fusionbox/notify.conf"

umask 077
exec 9>"${CONF}.lock"
flock -n 9 || exit 0
[[ -f "$CONF" ]] || exit 0
. "$CONF" 2>/dev/null || exit 0

IFACE="${IFACE:-auto}"
LIMIT_GB="${LIMIT_GB:-1000}"
ACTION="${ACTION:-warn}"
CHECK_INTERVAL_MIN="${CHECK_INTERVAL_MIN:-5}"
[[ "$CHECK_INTERVAL_MIN" =~ ^[0-9]+$ ]] || CHECK_INTERVAL_MIN=5
[[ "$CHECK_INTERVAL_MIN" -lt 1 ]] && CHECK_INTERVAL_MIN=1

mkdir -p "$STATE_DIR" 2>/dev/null
touch "$LOG" 2>/dev/null

log_line() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# 日志超过 1MB 时裁剪，避免长期运行占满磁盘
log_size=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
if [[ "$log_size" =~ ^[0-9]+$ ]] && [[ "$log_size" -gt 1048576 ]]; then
  tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null
fi

# 读取网卡累计字节（字节数）
if [[ "$IFACE" == "auto" ]]; then
  cur=$(awk '{gsub(":","",$1); if ($1=="lo" || $1 ~ /^docker/ || $1 ~ /^veth/ || $1 ~ /^br-/) next; rx+=$2; tx+=$10} END{printf "%.0f %.0f", rx, tx}' /proc/net/dev 2>/dev/null)
else
  cur=$(awk -v i="$IFACE" '{gsub(":","",$1); if ($1==i) printf "%.0f %.0f", $2, $10}' /proc/net/dev 2>/dev/null)
fi
cur_rx=$(echo "$cur" | awk '{print $1+0}')
cur_tx=$(echo "$cur" | awk '{print $2+0}')

MONTH=""; LAST_RUN=0; BASE_RX=0; BASE_TX=0; TOTAL=0
[[ -f "$STATE" ]] && . "$STATE" 2>/dev/null

now=$(date +%s)
this_month=$(date '+%Y-%m')

# 节流：按 CHECK_INTERVAL_MIN 控制实际检查频率
if [[ "$MONTH" == "$this_month" && "$LAST_RUN" =~ ^[0-9]+$ ]]; then
  if [[ $((now - LAST_RUN)) -lt $((CHECK_INTERVAL_MIN * 60)) ]]; then
    exit 0
  fi
fi

if [[ "$MONTH" != "$this_month" ]]; then
  # 自然月重置（首次运行也走此分支建立基线）
  MONTH="$this_month"; TOTAL=0; BASE_RX="$cur_rx"; BASE_TX="$cur_tx"
  rm -f "$FLAG" 2>/dev/null
elif [[ ! "$BASE_RX" =~ ^[0-9]+$ || ! "$BASE_TX" =~ ^[0-9]+$ ]]; then
  BASE_RX="$cur_rx"; BASE_TX="$cur_tx"
elif [[ $cur_rx -lt $BASE_RX || $cur_tx -lt $BASE_TX ]]; then
  # 计数器回绕或重启
  TOTAL=$(( TOTAL + cur_rx + cur_tx ))
  BASE_RX="$cur_rx"; BASE_TX="$cur_tx"
else
  TOTAL=$(( TOTAL + cur_rx - BASE_RX + cur_tx - BASE_TX ))
  BASE_RX="$cur_rx"; BASE_TX="$cur_tx"
fi

_fb_atomic_state "$STATE" "MONTH=$MONTH
LAST_RUN=$now
BASE_RX=$BASE_RX
BASE_TX=$BASE_TX
TOTAL=$TOTAL" || exit 1

limit_bytes=$(awk -v g="$LIMIT_GB" 'BEGIN{printf "%.0f", g*1073741824}' 2>/dev/null)
limit_bytes=${limit_bytes:-0}
used_gb=$(awk -v b="$TOTAL" 'BEGIN{printf "%.2f", b/1073741824}' 2>/dev/null)
used_gb=${used_gb:-0}

if [[ "$limit_bytes" =~ ^[0-9]+$ ]] && [[ "$limit_bytes" -gt 0 ]] && \
   [[ "$TOTAL" -ge "$limit_bytes" ]] && [[ ! -f "$FLAG" ]]; then
  note="[FusionBox] 流量告警：本月已用 ${used_gb} GB，超过阈值 ${LIMIT_GB} GB（网卡: $IFACE，动作: $ACTION）"
  log_line "$note"

  # Telegram 通知（若已配置 /etc/fusionbox/notify.conf）
  if [[ -f "$NOTIFY_CONF" ]]; then
    t=$(grep -m1 '^TG_BOT_TOKEN=' "$NOTIFY_CONF" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r')
    c=$(grep -m1 '^TG_CHAT_ID=' "$NOTIFY_CONF" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | tr -d '\r')
    if [[ -n "$t" && -n "$c" ]]; then
      _fb_telegram_send "$t" "$c" "$note" || exit 1
    fi
  fi

  if [[ "$ACTION" == "shutdown" ]]; then
    echo "$note" | wall 2>/dev/null || true
    shutdown -h +5 "FusionBox: 流量超过阈值 ${LIMIT_GB} GB" 2>/dev/null || exit 1
  elif [[ "$ACTION" != warn ]]; then
    exit 1
  fi
  _fb_atomic_state "$FLAG" "$this_month" || exit 1
fi
TGEOF
  chmod 755 /usr/local/bin/fusionbox-traffic-guard

  cat > /etc/cron.d/fusionbox-traffic-guard << 'TCEOF'
# FusionBox 流量阈值保护（每 5 分钟检查一次）
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root /usr/local/bin/fusionbox-traffic-guard >/dev/null 2>&1
TCEOF
  chmod 644 /etc/cron.d/fusionbox-traffic-guard
}

_traffic_guard_status() {
  msg ""
  local iface limit action interval
  iface=$(_traffic_guard_conf_get IFACE); iface=${iface:-auto}
  limit=$(_traffic_guard_conf_get LIMIT_GB); limit=${limit:-1000}
  action=$(_traffic_guard_conf_get ACTION); action=${action:-warn}
  interval=$(_traffic_guard_conf_get CHECK_INTERVAL_MIN); interval=${interval:-5}

  msg "  ${F_BOLD}配置:${F_RESET} IFACE=$iface  LIMIT_GB=$limit  ACTION=$action  INTERVAL=${interval}min"

  local cur
  if [[ "$iface" == "auto" ]]; then
    cur=$(awk '{gsub(":","",$1); if ($1=="lo" || $1 ~ /^docker/ || $1 ~ /^veth/ || $1 ~ /^br-/) next; rx+=$2; tx+=$10} END{printf "%.0f %.0f", rx, tx}' /proc/net/dev 2>/dev/null)
  else
    cur=$(awk -v i="$iface" '{gsub(":","",$1); if ($1==i) printf "%.0f %.0f", $2, $10}' /proc/net/dev 2>/dev/null)
  fi
  local now_rx now_tx
  now_rx=$(echo "$cur" | awk '{print $1+0}')
  now_tx=$(echo "$cur" | awk '{print $2+0}')
  msg "  ${F_BOLD}网卡累计:${F_RESET} RX $(awk -v b="$now_rx" 'BEGIN{printf "%.2f", b/1073741824}') GB / TX $(awk -v b="$now_tx" 'BEGIN{printf "%.2f", b/1073741824}') GB"

  if [[ -f /var/lib/fusionbox/traffic-guard.state ]]; then
    local MONTH="" TOTAL=0 BASE_RX=0 BASE_TX=0 LAST_RUN=0
    . /var/lib/fusionbox/traffic-guard.state 2>/dev/null
    local used_gb; used_gb=$(awk -v b="${TOTAL:-0}" 'BEGIN{printf "%.3f", b/1073741824}')
    msg "  ${F_BOLD}本月已用:${F_RESET} ${used_gb} GB / ${limit} GB（统计月: ${MONTH:-未知}）"
    local pct=0
    if [[ "$limit" =~ ^[0-9]+$ ]] && [[ "$limit" -gt 0 ]]; then
      pct=$(awk -v u="$used_gb" -v l="$limit" 'BEGIN{printf "%d", (u*100)/l}')
    fi
    msg "  ${F_BOLD}使用比例:${F_RESET} ${pct}%"
  else
    msg "  ${F_BOLD}本月已用:${F_RESET} 暂无统计数据（脚本首次运行后建立基线）"
  fi

  if [[ -f /var/lib/fusionbox/traffic-guard.shutdown ]]; then
    msg "  ${F_YELLOW}已触发过超限处理（本月内不再重复触发）${F_RESET}"
  fi
  msg "  ${F_BOLD}cron:${F_RESET} $([[ -f /etc/cron.d/fusionbox-traffic-guard ]] && echo "已安装 (每 5 分钟)" || echo "未安装")"
  msg "  ${F_BOLD}日志:${F_RESET} /var/log/fusionbox-traffic-guard.log"
  if [[ -f /var/log/fusionbox-traffic-guard.log ]]; then
    tail -n 5 /var/log/fusionbox-traffic-guard.log 2>/dev/null | sed 's/^/    /'
  fi
}

system_traffic_guard() {
  _require_root
  local bin="/usr/local/bin/fusionbox-traffic-guard"
  local cron_file="/etc/cron.d/fusionbox-traffic-guard"
  local conf="/etc/fusionbox/traffic-guard.conf"

  while true; do
    clear
    _print_banner
    msg_title "流量阈值保护"
    msg ""
    if [[ -x "$bin" && -f "$cron_file" ]]; then
      msg "  ${F_BOLD}状态:${F_RESET} ${F_GREEN}已安装${F_RESET}"
      msg "  ${F_BOLD}网卡:${F_RESET} $(_traffic_guard_conf_get IFACE)"
      msg "  ${F_BOLD}阈值:${F_RESET} $(_traffic_guard_conf_get LIMIT_GB) GB"
      msg "  ${F_BOLD}动作:${F_RESET} $(_traffic_guard_conf_get ACTION)"
    else
      msg "  ${F_BOLD}状态:${F_RESET} ${F_YELLOW}未安装${F_RESET}"
      msg_warn "安装后每 5 分钟检查一次，天然月周期统计流量"
    fi
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 安装 / 更新流量保护"
    msg "  ${F_GREEN} 2${F_RESET}) 查看状态（当前用量 / 阈值）"
    msg "  ${F_GREEN} 3${F_RESET}) 修改阈值 / 动作"
    msg "  ${F_GREEN} 4${F_RESET}) 卸载"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-4]: " tg_choice || { msg ""; break; }

    case "$tg_choice" in
      1)
        msg ""
        local iface limit action interval act_sel
        iface=$(_traffic_guard_conf_get IFACE); iface=${iface:-auto}
        limit=$(_traffic_guard_conf_get LIMIT_GB); limit=${limit:-1000}
        action=$(_traffic_guard_conf_get ACTION); action=${action:-warn}
        interval=$(_traffic_guard_conf_get CHECK_INTERVAL_MIN); interval=${interval:-5}

        msg_tip "IFACE=auto 表示汇总除 lo/docker*/veth*/br-* 以外的全部网卡"
        iface=$(read_input "监控网卡 (auto 或具体网卡名)" "$iface") || { pause; continue; }
        if [[ "$iface" != "auto" && ! "$iface" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
          msg_err "网卡名格式无效: $iface"
          pause; continue
        fi
        limit=$(read_input "流量上限 (GB/月)" "$limit") || { pause; continue; }
        if [[ ! "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
          msg_err "流量上限必须为正整数（GB）"
          pause; continue
        fi
        interval=$(read_input "检查间隔 (分钟)" "$interval") || { pause; continue; }
        if [[ ! "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
          interval=5
          msg_warn "间隔无效，已使用默认值 5 分钟"
        fi

        msg ""
        msg "  超限动作: 1) warn 仅告警 (默认)  2) shutdown 超限后 5 分钟关机"
        act_sel=$(read_input "请选择动作" "1") || { pause; continue; }
        if [[ "$act_sel" == "2" ]]; then
          msg_warn "shutdown 模式会在流量超限后 5 分钟自动关机，可能中断线上业务"
          if confirm "确认启用 shutdown 模式？" && confirm "再次确认：超限后自动执行关机？"; then
            action="shutdown"
          else
            msg_info "已保持 warn 模式"
            action="warn"
          fi
        else
          action="warn"
        fi

        _traffic_guard_conf_write "$iface" "$limit" "$action" "$interval"
        msg_ok "配置已写入 $conf (权限 600)"
        _traffic_guard_install_bin
        msg_ok "已安装 /usr/local/bin/fusionbox-traffic-guard"
        msg_ok "已安装 cron: $cron_file (每 5 分钟)"
        if [[ "$action" == "shutdown" ]]; then
          msg_warn "当前为 shutdown 模式，流量超限后将自动关机"
        else
          msg_ok "当前为 warn 模式，超限仅记录日志与告警"
        fi
        _log_write "流量阈值保护已安装 (IFACE=$iface, LIMIT=${limit}GB, ACTION=$action)"
        pause ;;
      2)
        _traffic_guard_status
        pause ;;
      3)
        if [[ ! -f "$conf" ]]; then
          msg_warn "尚未配置，请先执行「安装 / 更新流量保护」"
          pause; continue
        fi
        msg ""
        local n_limit n_action n_interval n_act
        n_limit=$(_traffic_guard_conf_get LIMIT_GB); n_limit=${n_limit:-1000}
        n_limit=$(read_input "新的流量上限 (GB/月)" "$n_limit") || { pause; continue; }
        if [[ ! "$n_limit" =~ ^[0-9]+$ ]] || [[ "$n_limit" -lt 1 ]]; then
          msg_err "流量上限必须为正整数（GB）"
          pause; continue
        fi
        n_interval=$(_traffic_guard_conf_get CHECK_INTERVAL_MIN); n_interval=${n_interval:-5}
        n_interval=$(read_input "检查间隔 (分钟)" "$n_interval") || { pause; continue; }
        [[ "$n_interval" =~ ^[0-9]+$ ]] && [[ "$n_interval" -ge 1 ]] || n_interval=5

        msg "  超限动作: 1) warn 仅告警  2) shutdown 超限后关机"
        n_act=$(read_input "请选择动作" "1") || { pause; continue; }
        n_action=$(_traffic_guard_conf_get ACTION); n_action=${n_action:-warn}
        if [[ "$n_act" == "2" ]]; then
          msg_warn "shutdown 模式会在流量超限后 5 分钟自动关机"
          if confirm "确认启用 shutdown 模式？" && confirm "再次确认：超限后自动执行关机？"; then
            n_action="shutdown"
          else
            n_action="warn"
            msg_info "已保持 warn 模式"
          fi
        elif [[ "$n_act" == "1" ]]; then
          n_action="warn"
        fi

        local cur_iface; cur_iface=$(_traffic_guard_conf_get IFACE); cur_iface=${cur_iface:-auto}
        _traffic_guard_conf_write "$cur_iface" "$n_limit" "$n_action" "$n_interval"
        # 阈值变化后允许本周期内重新触发
        rm -f /var/lib/fusionbox/traffic-guard.shutdown 2>/dev/null
        msg_ok "已更新配置: LIMIT_GB=$n_limit ACTION=$n_action INTERVAL=${n_interval}min"
        _log_write "流量阈值已更新 (LIMIT=${n_limit}GB, ACTION=$n_action)"
        pause ;;
      4)
        if ! confirm "确认卸载流量阈值保护？"; then
          pause; continue
        fi
        rm -f "$bin" "$cron_file" /var/lib/fusionbox/traffic-guard.state /var/lib/fusionbox/traffic-guard.shutdown
        if confirm "是否同时删除配置文件 $conf？"; then
          rm -f "$conf"
          msg_ok "已卸载并删除配置"
        else
          msg_ok "已卸载，配置保留"
        fi
        _log_write "流量阈值保护已卸载"
        pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- Telegram 告警 ----
_notify_conf_get() {
  local key="$1"
  local conf="/etc/fusionbox/notify.conf"
  [[ -f "$conf" ]] || return 1
  sed -n "s/^[[:space:]]*${key}=//p" "$conf" | tail -1 | tr -d '"' | tr -d "'" | tr -d '\r'
}

# 用法: _notify_conf_write <token> <chat_id> <cpu> <mem> <disk> <cooldown>
_notify_conf_write() {
  local token="$1" chat="$2" acpu="$3" amem="$4" adisk="$5" cool="$6"
  umask 077
  mkdir -p /etc/fusionbox
  cat > /etc/fusionbox/notify.conf << NEOF
# FusionBox Telegram 告警配置（含凭据，权限 600）
TG_BOT_TOKEN=$token
TG_CHAT_ID=$chat
# 告警阈值（百分比）
ALERT_CPU=$acpu
ALERT_MEM=$amem
ALERT_DISK=$adisk
# 冷却时间（分钟），同一告警在冷却期内只发送一次
COOLDOWN_MIN=$cool
NEOF
  chmod 600 /etc/fusionbox/notify.conf
}

# Shared transport is embedded into generated cron scripts; credentials use stdin,
# never curl argv, exported variables, or persistent temporary credential files.
_fb_telegram_send() (
  set +x
  local token="$1" chat="$2" text="$3" response
  export -n token TG_BOT_TOKEN 2>/dev/null
  [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ && "$chat" =~ ^-?[0-9]+$ ]] || return 1
  response=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" |
    curl -q -fsS --max-time 10 --config - --data-urlencode "chat_id=$chat" --data-urlencode "text=$text" 2>/dev/null) || return 1
  printf '%s' "$response" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not isinstance(d,dict) or d.get("ok") is not True)' 2>/dev/null
)

_fb_atomic_state() (
  umask 077
  local target="$1" value="$2" staged
  staged=$(mktemp "${target}.XXXXXXXX") || return 1
  trap 'rm -f "$staged"' EXIT
  printf '%s\n' "$value" > "$staged" && mv -T "$staged" "$target"
)

# 用法: _notify_send "消息文本"（不会打印 token）
_notify_send() (
  set +x
  local text="$1"
  local token chat
  token=$(_notify_conf_get TG_BOT_TOKEN)
  chat=$(_notify_conf_get TG_CHAT_ID)

  if [[ -z "$token" || -z "$chat" ]]; then
    msg_warn "未配置 Telegram Bot Token 或 Chat ID，请先执行: fusionbox system notify"
    return 1
  fi

  if _fb_telegram_send "$token" "$chat" "$text"; then
    return 0
  fi
  msg_err "Telegram 消息发送失败（请检查 Token / Chat ID 与网络连通性）"
  return 1
)

_notify_install_check() {
  mkdir -p /usr/local/bin /etc/fusionbox /var/lib/fusionbox /var/log

  { printf '#!/bin/bash\nset +x\n'; declare -f _fb_telegram_send _fb_atomic_state; } > /usr/local/bin/fusionbox-notify-check || return 1
  cat >> /usr/local/bin/fusionbox-notify-check << 'NEOF'
#!/bin/bash
# FusionBox 资源告警检查（由 fusionbox system notify 安装）
# 配置: /etc/fusionbox/notify.conf  状态: /var/lib/fusionbox/notify.state
# 日志: /var/log/fusionbox-notify.log

CONF="/etc/fusionbox/notify.conf"
STATE_DIR="/var/lib/fusionbox"
STATE="$STATE_DIR/notify.state"
LOG="/var/log/fusionbox-notify.log"

umask 077
exec 9>"${CONF}.lock"
flock -n 9 || exit 0
[[ -f "$CONF" ]] || exit 0
. "$CONF" 2>/dev/null || exit 0

TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"
ALERT_CPU="${ALERT_CPU:-90}"
ALERT_MEM="${ALERT_MEM:-90}"
ALERT_DISK="${ALERT_DISK:-90}"
COOLDOWN_MIN="${COOLDOWN_MIN:-30}"
[[ "$COOLDOWN_MIN" =~ ^[0-9]+$ ]] || COOLDOWN_MIN=30
[[ -n "$TG_BOT_TOKEN" && -n "$TG_CHAT_ID" ]] || exit 0

mkdir -p "$STATE_DIR" 2>/dev/null
touch "$LOG" 2>/dev/null

log_line() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# CPU 使用率（1 秒采样差值）
read -r t1 i1 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null)
sleep 1
read -r t2 i2 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat 2>/dev/null)
cpu=0
dt=$(( ${t2:-0} - ${t1:-0} ))
di=$(( ${i2:-0} - ${i1:-0} ))
if [[ $dt -gt 0 ]]; then cpu=$(( (100 * (dt - di)) / dt )); fi

mem=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{if(t>0) printf "%d", (t-a)*100/t; else print 0}' /proc/meminfo 2>/dev/null)
mem=${mem:-0}
disk=$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}')
disk=${disk:-0}
host=$(hostname 2>/dev/null || echo "unknown")

alert=""
if [[ "$cpu" =~ ^[0-9]+$ ]] && [[ "$cpu" -ge "$ALERT_CPU" ]]; then alert="${alert}CPU ${cpu}% "; fi
if [[ "$mem" =~ ^[0-9]+$ ]] && [[ "$mem" -ge "$ALERT_MEM" ]]; then alert="${alert}内存 ${mem}% "; fi
if [[ "$disk" =~ ^[0-9]+$ ]] && [[ "$disk" -ge "$ALERT_DISK" ]]; then alert="${alert}磁盘 ${disk}% "; fi
[[ -z "$alert" ]] && exit 0

LAST_ALERT=0
[[ -f "$STATE" ]] && . "$STATE" 2>/dev/null
now=$(date +%s)
[[ "$LAST_ALERT" =~ ^[0-9]+$ ]] || LAST_ALERT=0
if [[ $((now - LAST_ALERT)) -lt $((COOLDOWN_MIN * 60)) ]]; then exit 0; fi


note="[FusionBox] $host 资源告警：$alert（阈值 CPU ${ALERT_CPU}% / 内存 ${ALERT_MEM}% / 磁盘 ${ALERT_DISK}%）"
log_line "$note"
_fb_telegram_send "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$note" || exit 1
_fb_atomic_state "$STATE" "LAST_ALERT=$now" || exit 1
NEOF
  chmod 755 /usr/local/bin/fusionbox-notify-check

  cat > /etc/cron.d/fusionbox-notify << 'NCEOF'
# FusionBox 资源告警（每 5 分钟检查 CPU/内存/磁盘）
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root /usr/local/bin/fusionbox-notify-check >/dev/null 2>&1
NCEOF
  chmod 644 /etc/cron.d/fusionbox-notify
}

_notify_status() {
  msg ""
  if [[ -f /etc/fusionbox/notify.conf ]]; then
    msg "  ${F_BOLD}配置文件:${F_RESET} 存在 (权限 $(stat -c%a /etc/fusionbox/notify.conf 2>/dev/null))"
  else
    msg "  ${F_BOLD}配置文件:${F_RESET} 不存在"
  fi
  msg "  ${F_BOLD}告警脚本:${F_RESET} $([[ -x /usr/local/bin/fusionbox-notify-check ]] && echo "已安装" || echo "未安装")"
  msg "  ${F_BOLD}cron 任务:${F_RESET} $([[ -f /etc/cron.d/fusionbox-notify ]] && echo "已安装 (每 5 分钟)" || echo "未安装")"
  msg "  ${F_BOLD}阈值:${F_RESET} CPU $(_notify_conf_get ALERT_CPU)% / 内存 $(_notify_conf_get ALERT_MEM)% / 磁盘 $(_notify_conf_get ALERT_DISK)%"
  msg "  ${F_BOLD}冷却:${F_RESET} $(_notify_conf_get COOLDOWN_MIN) 分钟"

  msg "  ${F_BOLD}最近告警:${F_RESET}"
  if [[ -f /var/lib/fusionbox/notify.state ]]; then
    local LAST_ALERT=0
    . /var/lib/fusionbox/notify.state 2>/dev/null
    if [[ "${LAST_ALERT:-0}" =~ ^[0-9]+$ ]] && [[ "${LAST_ALERT:-0}" -gt 0 ]]; then
      msg "    $(date -d "@$LAST_ALERT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "时间戳 $LAST_ALERT")"
    else
      msg "    暂无告警记录"
    fi
  else
    msg "    暂无告警记录"
  fi

  msg "  ${F_BOLD}最近日志:${F_RESET}"
  if [[ -f /var/log/fusionbox-notify.log ]]; then
    tail -n 10 /var/log/fusionbox-notify.log 2>/dev/null | sed 's/^/    /'
  else
    msg "    暂无日志"
  fi
}

system_notify() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "Telegram 告警"
    msg ""
    local token chat
    token=$(_notify_conf_get TG_BOT_TOKEN)
    chat=$(_notify_conf_get TG_CHAT_ID)
    if [[ -n "$token" && -n "$chat" ]]; then
      msg "  ${F_BOLD}状态:${F_RESET} ${F_GREEN}已配置${F_RESET}"
      msg "  ${F_BOLD}Token:${F_RESET} 已配置 (****${token: -4})"
      msg "  ${F_BOLD}Chat ID:${F_RESET} $chat"
      msg "  ${F_BOLD}阈值:${F_RESET} CPU $(_notify_conf_get ALERT_CPU)% / 内存 $(_notify_conf_get ALERT_MEM)% / 磁盘 $(_notify_conf_get ALERT_DISK)%"
    else
      msg "  ${F_BOLD}状态:${F_RESET} ${F_YELLOW}未配置${F_RESET}"
      msg_warn "请先选择 1 配置 Bot Token 与 Chat ID"
    fi
    msg "  ${F_BOLD}资源告警:${F_RESET} $([[ -f /etc/cron.d/fusionbox-notify ]] && echo "已安装 (每 5 分钟)" || echo "未安装")"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 配置 Token / Chat ID"
    msg "  ${F_GREEN} 2${F_RESET}) 发送测试消息"
    msg "  ${F_GREEN} 3${F_RESET}) 安装资源告警 (CPU/内存/磁盘)"
    msg "  ${F_GREEN} 4${F_RESET}) 查看状态 / 日志"
    msg "  ${F_GREEN} 5${F_RESET}) 卸载"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-5]: " notify_choice || { msg ""; break; }

    case "$notify_choice" in
      1)
        msg ""
        msg_tip "Token 获取: Telegram 找 @BotFather 创建机器人"
        msg_tip "Chat ID 获取: 向机器人发消息后访问 getUpdates，或使用 @userinfobot"
        local new_token new_chat
        new_token=$(read_input "请输入 Bot Token" "") || { pause; continue; }
        if [[ ! "$new_token" =~ ^[0-9]{6,}:[A-Za-z0-9_-]{30,}$ ]]; then
          msg_err "Token 格式无效（形如 123456789:AA****）"
          pause; continue
        fi
        new_chat=$(read_input "请输入 Chat ID（群组为负数）" "") || { pause; continue; }
        if [[ ! "$new_chat" =~ ^-?[0-9]+$ ]]; then
          msg_err "Chat ID 格式无效（应为数字）"
          pause; continue
        fi

        local acpu amem adisk cool
        acpu=$(_notify_conf_get ALERT_CPU); acpu=${acpu:-90}
        amem=$(_notify_conf_get ALERT_MEM); amem=${amem:-90}
        adisk=$(_notify_conf_get ALERT_DISK); adisk=${adisk:-90}
        cool=$(_notify_conf_get COOLDOWN_MIN); cool=${cool:-30}

        if confirm "是否修改告警阈值？"; then
          acpu=$(read_input "CPU 阈值 %" "$acpu")
          amem=$(read_input "内存阈值 %" "$amem")
          adisk=$(read_input "磁盘阈值 %" "$adisk")
          cool=$(read_input "冷却时间（分钟）" "$cool")
        fi
        [[ "$acpu" =~ ^[0-9]+$ ]] && [[ "$acpu" -ge 1 && "$acpu" -le 100 ]] || acpu=90
        [[ "$amem" =~ ^[0-9]+$ ]] && [[ "$amem" -ge 1 && "$amem" -le 100 ]] || amem=90
        [[ "$adisk" =~ ^[0-9]+$ ]] && [[ "$adisk" -ge 1 && "$adisk" -le 100 ]] || adisk=90
        [[ "$cool" =~ ^[0-9]+$ ]] && [[ "$cool" -ge 1 ]] || cool=30

        _notify_conf_write "$new_token" "$new_chat" "$acpu" "$amem" "$adisk" "$cool"
        msg_ok "配置已保存: /etc/fusionbox/notify.conf (权限 600)"
        _log_write "Telegram 告警配置已更新"
        pause ;;
      2)
        if [[ -z "$(_notify_conf_get TG_BOT_TOKEN)" ]]; then
          msg_warn "未配置 Token，请先选择 1 进行配置"
          pause; continue
        fi
        msg_info "正在发送测试消息..."
        if _notify_send "[FusionBox] 测试消息 - $(hostname 2>/dev/null) $(date '+%Y-%m-%d %H:%M:%S')"; then
          msg_ok "测试消息已发送，请检查 Telegram"
        fi
        pause ;;
      3)
        if [[ -z "$(_notify_conf_get TG_BOT_TOKEN)" ]]; then
          msg_warn "未配置 Token，请先选择 1 进行配置"
          pause; continue
        fi
        _notify_install_check
        msg_ok "已安装 /usr/local/bin/fusionbox-notify-check"
        msg_ok "已安装 cron: /etc/cron.d/fusionbox-notify (每 5 分钟)"
        msg_tip "超过阈值时发送 Telegram 消息，冷却时间内不重复发送"
        _log_write "Telegram 资源告警已安装"
        pause ;;
      4)
        _notify_status
        pause ;;
      5)
        if ! confirm "确认卸载 Telegram 资源告警（默认保留配置文件）？"; then
          pause; continue
        fi
        rm -f /etc/cron.d/fusionbox-notify /usr/local/bin/fusionbox-notify-check
        if confirm "是否同时删除配置文件 /etc/fusionbox/notify.conf（含凭据）？"; then
          rm -f /etc/fusionbox/notify.conf /var/lib/fusionbox/notify.state
          msg_ok "已卸载并删除配置"
        else
          msg_ok "已卸载，配置保留"
        fi
        _log_write "Telegram 资源告警已卸载"
        pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 网络优化分级 ----
# 探测默认路由网卡的协商速率
_system_netopt_speed() {
  local iface speed
  iface=$(ip route show default 2>/dev/null | awk '/^default/{print $5; exit}')
  if [[ -z "$iface" ]]; then
    iface=$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)
  fi
  [[ -z "$iface" ]] && return 1
  speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null)
  [[ "$speed" =~ ^[0-9]+$ ]] || return 1
  [[ "$speed" -le 0 ]] && return 1
  echo "$iface $speed"
  return 0
}

# 用法: _system_netopt_apply <1|2|3>
_system_netopt_apply() {
  local tier="$1"
  local file="/etc/sysctl.d/99-fusionbox-netopt.conf"
  local label rmem_max wmem_max rmem_def wmem_def tcp_rmem tcp_wmem somaxconn backlog port_range

  case "$tier" in
    1)
      label="≤100M"
      rmem_max=4194304;  wmem_max=4194304
      rmem_def=262144;   wmem_def=262144
      tcp_rmem="4096 87380 4194304";  tcp_wmem="4096 65536 4194304"
      somaxconn=1024; backlog=1024; port_range="1024 65535" ;;
    2)
      label="100M-1G"
      rmem_max=16777216; wmem_max=16777216
      rmem_def=1048576;  wmem_def=1048576
      tcp_rmem="4096 87380 16777216"; tcp_wmem="4096 65536 16777216"
      somaxconn=4096; backlog=4096; port_range="1024 65535" ;;
    3)
      label="≥1G"
      rmem_max=67108864; wmem_max=67108864
      rmem_def=2097152;  wmem_def=2097152
      tcp_rmem="4096 262144 67108864"; tcp_wmem="4096 262144 67108864"
      somaxconn=16384; backlog=16384; port_range="1024 65535" ;;
    *)
      msg_err "未知档位: $tier"
      return 1 ;;
  esac

  msg ""
  msg_info "即将应用网络优化档位: $label"
  msg "    net.core.rmem_max = $rmem_max    net.core.wmem_max = $wmem_max"
  msg "    net.core.rmem_default = $rmem_def    net.core.wmem_default = $wmem_def"
  msg "    net.ipv4.tcp_rmem = $tcp_rmem"
  msg "    net.ipv4.tcp_wmem = $tcp_wmem"
  msg "    net.core.somaxconn = $somaxconn    net.core.netdev_max_backlog = $backlog"
  msg "    net.ipv4.ip_local_port_range = $port_range"
  msg "    net.ipv4.tcp_fastopen = 3    net.ipv4.tcp_tw_reuse = 1"
  msg_tip "拥塞控制算法与队列算法保持系统现状，不做修改"
  confirm "确认写入 $file 并应用？" || return 1

  if [[ -f "$file" ]]; then
    local bak="/etc/fusionbox/netopt-bak-$(date +%s).conf"
    if _fb_backup_file "$file" "$bak"; then
      msg_ok "已备份原文件: $bak"
    else
      msg_err "备份原文件失败，已取消操作"
      return 1
    fi
  fi

  local snapshot="/etc/fusionbox/netopt-original.conf" k value
  mkdir -p /etc/fusionbox || return 1
  if [[ ! -f "$snapshot" ]]; then
    local tmp; tmp=$(mktemp) || return 1
    for k in net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.somaxconn net.core.netdev_max_backlog net.ipv4.ip_local_port_range net.ipv4.tcp_fastopen net.ipv4.tcp_tw_reuse; do
      value=$(sysctl -n "$k") || { rm -f "$tmp"; return 1; }
      printf '%s = %s\n' "$k" "$value" >> "$tmp"
    done
    if [[ -f "$file" ]]; then cp -p "$file" "$snapshot.previous" || return 1; fi
    mv "$tmp" "$snapshot" || return 1
  fi
  cat > "$file" << NEOF
# FusionBox 网络优化 ($label)
# 由 fusionbox system netopt 生成，恢复时使用首次应用前的运行值快照
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.rmem_default = $rmem_def
net.core.wmem_default = $wmem_def
net.ipv4.tcp_rmem = $tcp_rmem
net.ipv4.tcp_wmem = $tcp_wmem
net.core.somaxconn = $somaxconn
net.core.netdev_max_backlog = $backlog
net.ipv4.ip_local_port_range = $port_range
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
NEOF
  chmod 644 "$file"

  if sysctl -p "$file" >/dev/null 2>&1; then
    msg_ok "网络优化已应用 ($label)"
  else
    msg_err "应用失败，恢复原运行值"
    sysctl -p "$snapshot" >/dev/null 2>&1
    if [[ -f "$snapshot.previous" ]]; then cp -p "$snapshot.previous" "$file"; else rm -f "$file"; fi
    return 1
  fi

  msg ""
  msg "  ${F_BOLD}当前关键参数:${F_RESET}"
  local k
  for k in net.core.rmem_max net.core.wmem_max net.core.somaxconn net.core.netdev_max_backlog net.ipv4.tcp_fastopen net.ipv4.tcp_tw_reuse; do
    msg "    $k = $(sysctl -n "$k" 2>/dev/null)"
  done
  msg "    net.ipv4.tcp_rmem = $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
  msg "    net.ipv4.tcp_wmem = $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
  _log_write "网络优化已应用 ($label)"
  return 0
}

_system_netopt_reset() {
  local file="/etc/sysctl.d/99-fusionbox-netopt.conf"
  if [[ ! -f "$file" ]]; then
    msg_warn "未找到 $file，无需恢复"
    return 0
  fi
  local snapshot="/etc/fusionbox/netopt-original.conf"
  [[ -s "$snapshot" ]] || { msg_err "没有原运行值快照，拒绝宣称已恢复"; return 1; }
  confirm "确认恢复首次优化前的实际运行值？" || return 1
  sysctl -p "$snapshot" || { msg_err "恢复失败，保留快照供重试"; return 1; }
  if [[ -f "$snapshot.previous" ]]; then
    cp -p "$snapshot.previous" "$file" || return 1
  else
    rm -f "$file" || return 1
  fi
  rm -f "$snapshot" "$snapshot.previous"
  msg_ok "已恢复优化前的运行参数和配置"

  return 0
}

system_netopt() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "网络优化分级"
    msg ""

    local det; det=$(_system_netopt_speed)
    if [[ -n "$det" ]]; then
      local det_if="${det%% *}" det_sp="${det##* }"
      local suggest="1" sname="≤100M"
      if [[ "$det_sp" -ge 1000 ]]; then
        suggest="3"; sname="≥1G"
      elif [[ "$det_sp" -gt 100 ]]; then
        suggest="2"; sname="100M-1G"
      fi
      msg "  ${F_BOLD}网卡:${F_RESET} $det_if    ${F_BOLD}协商速率:${F_RESET} ${det_sp} Mbps"
      msg "  ${F_BOLD}建议档位:${F_RESET} ${suggest}) $sname"
    else
      msg "  ${F_BOLD}网卡速率:${F_RESET} ${F_YELLOW}无法自动探测（虚拟网卡常见），请手动选择档位${F_RESET}"
    fi

    if [[ -f /etc/sysctl.d/99-fusionbox-netopt.conf ]]; then
      msg "  ${F_BOLD}优化文件:${F_RESET} 已应用 (net.core.rmem_max = $(sysctl -n net.core.rmem_max 2>/dev/null))"
    else
      msg "  ${F_BOLD}优化文件:${F_RESET} 未应用"
    fi

    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 应用 ≤100M 档（小内存/低带宽）"
    msg "  ${F_GREEN} 2${F_RESET}) 应用 100M-1G 档（通用）"
    msg "  ${F_GREEN} 3${F_RESET}) 应用 ≥1G 档（高带宽）"
    msg "  ${F_GREEN} 4${F_RESET}) 恢复默认（删除优化文件）"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-4]: " netopt_choice || { msg ""; break; }
    case "$netopt_choice" in
      1|2|3) _system_netopt_apply "$netopt_choice"; pause ;;
      4) _system_netopt_reset; pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 系统设置子菜单 ----
system_settings_menu() {
  while true; do
    clear
    _print_banner
    msg_title "系统设置"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) DNS 优化"
    msg "  ${F_GREEN} 2${F_RESET}) 修改主机名"
    msg "  ${F_GREEN} 3${F_RESET}) hosts 解析管理"
    msg "  ${F_GREEN} 4${F_RESET}) 系统更新源切换"
    msg "  ${F_GREEN} 5${F_RESET}) 系统日志管理"
    msg "  ${F_GREEN} 6${F_RESET}) Swap 管理"
    msg "  ${F_GREEN} 7${F_RESET}) 流量阈值保护"
    msg "  ${F_GREEN} 8${F_RESET}) Telegram 告警"
    msg "  ${F_GREEN} 9${F_RESET}) 网络优化分级"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-9]: " set_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$set_choice" in
      1) system_dns ;;
      2) system_hostname ;;
      3) system_hosts ;;
      4) system_mirror ;;
      5) system_log ;;
      6) system_swap ;;
      7) system_traffic_guard ;;
      8) system_notify ;;
      9) system_netopt ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- 系统工具子菜单 ----
system_tools_menu() {
  while true; do
    clear
    _print_banner
    msg_title "系统工具"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) SSH 密钥管理"
    msg "  ${F_GREEN} 2${F_RESET}) 防火墙管理"
    msg "  ${F_GREEN} 3${F_RESET}) 定时任务管理"
    msg "  ${F_GREEN} 4${F_RESET}) 磁盘管理"
    msg "  ${F_GREEN} 5${F_RESET}) 时区管理"
    msg "  ${F_GREEN} 6${F_RESET}) 回收站"
    msg "  ${F_GREEN} 7${F_RESET}) 用户管理"
    msg "  ${F_GREEN} 8${F_RESET}) 安全审计"
    msg "  ${F_GREEN} 9${F_RESET}) SSH 加固向导（密钥用户+锁定 root）"
    msg "  ${F_GREEN}10${F_RESET}) Swap 管理"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-10]: " tools_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$tools_choice" in
      1) system_sshkey ;;
      2) system_firewall ;;
      3) system_cron ;;
      4) system_disk ;;
      5) system_timezone ;;
      6) system_trash ;;
      7) system_users ;;
      8) system_security ;;
      9) system_hardening ;;
      10) system_swap ;;
      0) break ;;
    esac
  done
}

# ---- Help ----
system_help() {
  msg_title "系统管理 帮助"
  msg ""
  msg "  fusionbox system info           查看系统信息"
  msg "  fusionbox system bbr            TCP 加速管理 (BBR/BBR2/BBRplus/Lotserver)"
  msg "  fusionbox system benchmark      运行基准测试"
  msg "  fusionbox system monitor        实时系统监控"
  msg "  fusionbox system backup         备份系统配置"
  msg "  fusionbox system restore        从备份恢复"
  msg "  fusionbox system update         更新系统软件包"
  msg "  fusionbox system clean          系统清理"
  msg "  fusionbox system swap           Swap 管理"
  msg "  fusionbox system users          用户管理 (list/add/del/sudo/unsudo/passwd)"
  msg "  fusionbox system hardening      SSH 加固：新建密钥用户并收紧 root 登录"
  msg "  fusionbox system security       安全审计与加固"
  msg "  fusionbox system sshkey         SSH 密钥管理"
  msg "  fusionbox system firewall       防火墙管理 (UFW/iptables)"
  msg "  fusionbox system cron           定时任务管理"
  msg "  fusionbox system disk           磁盘管理"
  msg "  fusionbox system timezone       时区管理"
  msg "  fusionbox system trash          回收站管理"
  msg "  fusionbox system dns            DNS 优化 (预设/自定义/锁定/备份恢复)"
  msg "  fusionbox system hostname       修改主机名"
  msg "  fusionbox system hosts          hosts 解析管理"
  msg "  fusionbox system mirror         系统更新源切换 (apt/yum)"
  msg "  fusionbox system log            系统日志查看与清理"
  msg "  fusionbox system traffic-guard  流量阈值保护 (超限告警/关机)"
  msg "  fusionbox system notify         Telegram 资源告警"
  msg "  fusionbox system netopt         网络优化分级 (按网卡速率)"
  msg "  fusionbox system settings       系统设置子菜单"
  msg "  fusionbox system tools          系统工具子菜单"
  msg ""
}

# ---- Interactive Menu ----
system_menu() {
  while true; do
    clear
    _print_banner
    msg_title "系统管理"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 系统信息"
    msg "  ${F_GREEN} 2${F_RESET}) BBR 管理"
    msg "  ${F_GREEN} 3${F_RESET}) 运行基准测试"
    msg "  ${F_GREEN} 4${F_RESET}) 系统监控"
    msg "  ${F_GREEN} 5${F_RESET}) 备份系统"
    msg "  ${F_GREEN} 6${F_RESET}) 恢复系统"
    msg "  ${F_GREEN} 7${F_RESET}) 更新系统"
    msg "  ${F_GREEN} 8${F_RESET}) 系统清理"
    msg "  ${F_GREEN} 9${F_RESET}) 系统工具 (SSH/防火墙/定时任务/磁盘/时区/回收站)"
    msg "  ${F_GREEN}10${F_RESET}) 系统设置 (DNS/主机名/hosts/源/日志/流量/告警/网络优化)"
    msg "  ${F_GREEN} 0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-10]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) system_info ;;
      2) system_bbr ;;
      3) system_benchmark ;;
      4) system_monitor ;;
      5) system_backup ;;
      6) system_restore ;;
      7) system_update ;;
      8) system_clean ;;
      9) system_tools_menu ;;
      10) system_settings_menu ;;
      0) break ;;
    esac
  done
}
