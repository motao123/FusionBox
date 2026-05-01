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
    read -p "请输入数字: " num

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
  sysctl -p 2>/dev/null
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
  bash <(wget --no-check-certificate -qO- https://raw.githubusercontent.com/fei5seven/lotServer/master/lotServerInstall.sh) install 2>/dev/null || {
    msg_err "Lotserver 安装失败"
    pause; return
  }
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
  msg_warn "即将运行内核安装脚本，选择选项 5 安装 BBRplus 新版内核"
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
  msg_warn "即将运行内核安装脚本，选择选项 4 安装 xanmod 内核"
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
  msg_warn "即将运行内核安装脚本，选择选项 8 安装 cloud 内核"
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
  msg "  fusionbox system bbr            TCP 加速管理 (BBR/BBR2/BBRplus/Lotserver)"
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
