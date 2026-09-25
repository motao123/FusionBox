# FusionBox System Management Module
# System administration, BBR, benchmark, backup

system_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    info|i)           system_info "$@" ;;
    bbr)              system_bbr "$@" ;;
    benchmark|bench)  system_benchmark "$@" ;;
    monitor|top)      system_monitor "$@" ;;
    backup)           _require_python3 "$(L MSG_SYS_1083)" || return 1; system_backup "$@" ;;
    restore)          _require_python3 "$(L MSG_SYS_1084)" || return 1; system_restore "$@" ;;
    update|up)        system_update "$@" ;;
    clean|cleanup)    system_clean "$@" ;;
    swap)             _require_python3 "$(L MSG_SYS_1085)" || return 1; system_swap "$@" ;;
    users)            _require_python3 "$(L MSG_SYS_1086)" || return 1; system_users "$@" ;;
    hardening)        _require_python3 "$(L MSG_SYS_1087)" || return 1; system_hardening ;;
    security|sec)     _require_python3 "$(L MSG_SYS_1088)" || return 1; system_security "$@" ;;
    ssh-preflight)    system_ssh_preflight "$@" ;;
    ssh-candidate)    _require_python3 "$(L MSG_SYS_1089)" || return 1; system_ssh_candidate "$@" ;;
    sshkey|ssh)       _require_python3 "$(L MSG_SYS_1090)" || return 1; system_sshkey "$@" ;;
    firewall|fw)      _require_python3 "$(L MSG_SYS_1091)" || return 1; system_firewall "$@" ;;
    cron|crontab)     system_cron "$@" ;;
    disk)             system_disk "$@" ;;
    timezone|tz)      system_timezone "$@" ;;
    trash)            system_trash "$@" ;;
    dns)              system_dns "$@" ;;
    hostname)         system_hostname "$@" ;;
    hosts)            system_hosts "$@" ;;
    mirror)           system_mirror "$@" ;;
    log|logs)         system_log "$@" ;;
    rescue)           system_rescue "$@" ;;
    traffic-guard)    system_traffic_guard "$@" ;;
    notify)           system_notify "$@" ;;
    login-alert)      _require_python3 "$(L MSG_SYS_1092)" || return 1; system_login_alert "$@" ;;
    netopt)           system_netopt "$@" ;;
    tuning|tune)      _require_python3 "$(L MSG_SYS_1093)" || return 1; system_tuning "$@" ;;
    fail2ban|f2b)     _require_python3 "$(L MSG_SYS_1094)" || return 1; system_fail2ban "$@" ;;
    env)              system_env "$@" ;;
    rsync)            system_rsync "$@" ;;
    file)             system_file "$@" ;;
    genpass)          system_genpass "$@" ;;
    gai)              system_gai "$@" ;;
    locale)           system_locale "$@" ;;
    reinstall)        system_reinstall ;;
    settings)         system_settings_menu ;;
    tools)            system_tools_menu ;;
    menu|main)        system_menu ;;
    help|h)           system_help ;;
    *)                _module_unknown_cmd "system" "$cmd" ;;
  esac
}

# ---- System Info ----
system_info() {
  _require_root
  msg_title "$(L MSG_SYS_1095)"
  msg ""

  # CPU
  local cpu_model; cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs)
  local cpu_cores; cpu_cores=$(_cpu_cores_display)
  msg "$(L MSG_SYS_1096 "${F_BOLD}" "${F_RESET}" "${cpu_model:-未知}" "${cpu_cores}")"

  # Load
  local load; load=$(uptime | awk -F'average:' '{print $2}' | xargs)
  msg "$(L MSG_SYS_1097 "${F_BOLD}" "${F_RESET}" "$load")"

  # Memory
  msg "$(L MSG_SYS_1098 "${F_BOLD}" "${F_RESET}")"
  free -h | awk 'NR==1{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'
  free -h | awk 'NR==2{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'

  # Disk
  msg "$(L MSG_SYS_1099 "${F_BOLD}" "${F_RESET}")"
  df -h / /boot /home 2>/dev/null | awk 'NR>0{print "            " $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}'

  # Network
  msg "$(L MSG_SYS_1100 "${F_BOLD}" "${F_RESET}")"
  ip addr show | grep -E "inet " | grep -v "127.0.0.1" | awk '{print "            " $NF ": " $2}'

  # x86-64 microarchitecture level (G68)
  if [[ "$F_ARCH" == "amd64" ]]; then
    local psabi
    psabi=$(_psabi_from_flags "$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2)")
    msg "$(L MSG_SYS_1101 "${F_BOLD}" "${F_RESET}" "${psabi}")"
  fi

  # OS
  msg "$(L MSG_SYS_1102 "${F_BOLD}" "${F_RESET}" "$F_OS_NAME" "$F_OS_VER" "$F_ARCH")"
  msg "$(L MSG_SYS_1103 "${F_BOLD}" "${F_RESET}" "$F_KERNEL")"
  msg "$(L MSG_SYS_1104 "${F_BOLD}" "${F_RESET}" "$(uptime -p 2>/dev/null | sed 's/up //')")"
  msg "$(L MSG_SYS_1105 "${F_BOLD}" "${F_RESET}" "$F_VIRT")"

  # BBR status
  local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "$(L MSG_SYS_1106)")
  msg "$(L MSG_SYS_1107 "${F_BOLD}" "${F_RESET}" "$cc")"
  local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "$(L MSG_SYS_1106)")
  msg "$(L MSG_SYS_1108 "${F_BOLD}" "${F_RESET}" "$qdisc")"

  # Security
  if command -v ufw &>/dev/null; then
    msg "  ${F_BOLD}UFW:${F_RESET} $(ufw status 2>/dev/null | head -1)"
  fi
  if command -v fail2ban-client &>/dev/null; then
    msg "$(L MSG_SYS_1109 "${F_BOLD}" "${F_RESET}" "$(fail2ban-client status 2>/dev/null | head -1 || echo "运行中")")"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    msg "  ${F_BOLD}Docker:${F_RESET} $(docker --version 2>/dev/null)"
  fi

  # Proxy status
  if [[ -f /etc/fusionbox/proxy/current_backend ]]; then
    local proxy_be
    proxy_be=$(cat /etc/fusionbox/proxy/current_backend 2>/dev/null) || true
    proxy_be=${proxy_be:-$(L MSG_SYS_1080)}
    local proxy_st="$(L MSG_SYS_1110)"
    systemctl is-active fusionbox-proxy &>/dev/null && proxy_st="$(L MSG_SYS_1111)"
    msg "$(L MSG_SYS_1112 "${F_BOLD}" "${F_RESET}" "$proxy_be" "$proxy_st")"
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
    local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "$(L MSG_SYS_1106)")
    local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "$(L MSG_SYS_1106)")
    local kver; kver=$(uname -r)
    local kernel_status; kernel_status=$(_bbr_detect_kernel_type)
    local run_status; run_status=$(_bbr_detect_run_status "$cc" "$kernel_status")

    msg_title "$(L MSG_SYS_1113)"
    msg ""
    msg "$(L MSG_SYS_1114 "${F_BOLD}" "${F_RESET}" "$F_OS_NAME" "$F_OS_VER" "$F_ARCH")"
    msg "$(L MSG_SYS_1115 "${F_BOLD}" "${F_RESET}" "$kver")"
    msg "$(L MSG_SYS_1116 "${F_BOLD}" "${F_RESET}" "$kernel_status")"
    msg "$(L MSG_SYS_1117 "${F_BOLD}" "${F_RESET}" "$run_status")"
    msg "$(L MSG_SYS_1118 "${F_BOLD}" "${F_RESET}" "$cc" "${F_BOLD}" "${F_RESET}" "$qdisc")"
    msg ""
    msg "$(L MSG_SYS_1119)"
    msg "$(L MSG_SYS_1120 "${F_BOLD}" "${F_RESET}")"
    msg "$(L MSG_SYS_1121 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1122 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1123 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1124 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1125 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1126 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1127 "${F_GREEN}" "${F_RESET}")"
    msg ""
    msg "$(L MSG_SYS_1128 "${F_BOLD}" "${F_RESET}")"
    msg "  ${F_GREEN}11${F_RESET}) BBR + FQ          ${F_GREEN}12${F_RESET}) BBR + FQ_PIE"
    msg "  ${F_GREEN}13${F_RESET}) BBR + CAKE         ${F_GREEN}14${F_RESET}) BBR2 + FQ"
    msg "  ${F_GREEN}15${F_RESET}) BBR2 + FQ_PIE      ${F_GREEN}16${F_RESET}) BBR2 + CAKE"
    msg "$(L MSG_SYS_1129 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1130 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    msg "$(L MSG_SYS_1131 "${F_BOLD}" "${F_RESET}")"
    msg "$(L MSG_SYS_1132 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1133 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1134 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    msg "$(L MSG_SYS_1135 "${F_BOLD}" "${F_RESET}")"
    msg "$(L MSG_SYS_1136 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1137 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1138 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1119)"
    msg ""
    read -p "$(L MSG_SYS_1140)" num || { msg ""; break; }   # stdin 关闭时退出，防死循环

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
      echo "$(L MSG_SYS_1141)"
    fi
  fi
}

_bbr_detect_run_status() {
  local cc="$1" ktype="$2"
  case "$cc" in
    bbr)        echo "$(L MSG_SYS_1142)" ;;
    bbr2)       echo "$(L MSG_SYS_1143)" ;;
    bbrplus)    echo "$(L MSG_SYS_1144)" ;;
    tsunami)    echo "$(L MSG_SYS_1145)" ;;
    nanqinlang) echo "$(L MSG_SYS_1146)" ;;
    cubic)   echo "$(L MSG_SYS_1147)" ;;
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
    msg_err "$(L MSG_SYS_1148)"
  fi
  local new_cc; new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  if [[ "$new_cc" == "$algo" ]]; then
    msg_ok "$(L MSG_SYS_1149 "${algo^^}" "${qdisc^^}")"
  else
    msg_warn "$(L MSG_SYS_1150 "$new_cc")"
  fi
  _log_write "$(L MSG_SYS_1151 "$algo" "$qdisc")"
  pause
}

# ---- Lotserver(锐速) ----
_bbr_enable_lotserver() {
  _bbr_remove_accel
  _install_pkg ethtool 2>/dev/null
  msg_info "$(L MSG_SYS_1152)"
  local lot_tmp; lot_tmp=$(mktemp)
  _download "https://raw.githubusercontent.com/fei5seven/lotServer/master/lotServerInstall.sh" "$lot_tmp" || {
    rm -f "$lot_tmp"
    msg_err "$(L MSG_SYS_1153)"
    pause; return
  }
  msg_warn "$(L MSG_SYS_1154)"
  if ! confirm "$(L MSG_SYS_1155)"; then
    rm -f "$lot_tmp"
    pause; return
  fi
  bash "$lot_tmp" install 2>/dev/null || {
    rm -f "$lot_tmp"
    msg_err "$(L MSG_SYS_1156)"
    pause; return
  }
  rm -f "$lot_tmp"
  sed -i '/advinacc/d' /appex/etc/config 2>/dev/null
  sed -i '/maxmode/d' /appex/etc/config 2>/dev/null
  echo -e 'advinacc="1"\nmaxmode="1"' >> /appex/etc/config 2>/dev/null
  /appex/bin/lotServer.sh restart 2>/dev/null
  msg_ok "$(L MSG_SYS_1157)"
  _log_write "$(L MSG_SYS_1158)"
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
  if confirm "$(L MSG_SYS_1159)"; then
    _bbr_remove_accel
    if [[ -e /appex/bin/lotServer.sh ]]; then
      bash /appex/bin/lotServer.sh stop 2>/dev/null
      msg_info "$(L MSG_SYS_1160)"
    fi
    msg_ok "$(L MSG_SYS_1161)"
    _log_write "$(L MSG_SYS_1161)"
  fi
  pause
}

# ---- 内核安装 ----
_bbr_install_bbr() {
  msg_info "$(L MSG_SYS_1162)"
  _system_install_kernel
}

_bbr_install_bbrplus() {
  msg_info "$(L MSG_SYS_1163)"
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
        msg_ok "$(L MSG_SYS_1164)"
        confirm "$(L MSG_SYS_1165)" && reboot
      else
        msg_err "$(L MSG_SYS_1166)"
      fi
      ;;
    yum)
      _download "https://github.com/cx9208/Linux-NetSpeed/raw/master/bbrplus/centos-bbrplus/kernel-4.14.129-bbrplus.rpm" "$tmpdir/kernel.rpm" || \
      _download "https://github.com/ylx2016/Linux-NetSpeed/raw/master/bbrplus/centos-bbrplus/kernel-4.14.129-bbrplus.rpm" "$tmpdir/kernel.rpm"
      if [[ -f "$tmpdir/kernel.rpm" ]]; then
        rpm -ivh "$tmpdir/kernel.rpm"
        _bbr_grub_update
        msg_ok "$(L MSG_SYS_1164)"
        confirm "$(L MSG_SYS_1165)" && reboot
      else
        msg_err "$(L MSG_SYS_1166)"
      fi
      ;;
    *)
      msg_err "$(L MSG_SYS_1167)"
      ;;
  esac
  rm -rf "$tmpdir"
  pause
}

_bbr_install_bbrplus_new() {
  msg_info "$(L MSG_SYS_1168)"
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "$(L MSG_SYS_1169)"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "$(L MSG_SYS_1170)"
  msg_warn "$(L MSG_SYS_1171)"
  if ! confirm "$(L MSG_SYS_1155)"; then
    rm -rf "$tmpdir"
    pause; return
  fi
  bash "$tmpdir/tcp.sh"
  rm -rf "$tmpdir"
  pause
}

_bbr_install_xanmod() {
  msg_info "$(L MSG_SYS_1172)"
  if [[ "$F_PKG_MGR" != "apt" ]]; then
    msg_err "$(L MSG_SYS_1173)"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "$(L MSG_SYS_1169)"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "$(L MSG_SYS_1170)"
  msg_warn "$(L MSG_SYS_1174)"
  if ! confirm "$(L MSG_SYS_1155)"; then
    rm -rf "$tmpdir"
    pause; return
  fi
  bash "$tmpdir/tcp.sh"
  rm -rf "$tmpdir"
  pause
}

_bbr_install_cloud() {
  msg_info "$(L MSG_SYS_1175)"
  if [[ "$F_PKG_MGR" != "apt" ]]; then
    msg_err "$(L MSG_SYS_1176)"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/tcp.sh" "$tmpdir/tcp.sh" || {
    msg_err "$(L MSG_SYS_1169)"; rm -rf "$tmpdir"; pause; return
  }
  msg_warn "$(L MSG_SYS_1170)"
  msg_warn "$(L MSG_SYS_1177)"
  if ! confirm "$(L MSG_SYS_1155)"; then
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
  msg_info "$(L MSG_SYS_1178)"
  _check_pkg gcc gcc 2>/dev/null
  _check_pkg make make 2>/dev/null
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    msg_err "$(L MSG_SYS_1179)"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/bbr/tcp_tsunami.c" "$tmpdir/tcp_tsunami.c" || \
  _download "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/bbr/tcp_tsunami.c" "$tmpdir/tcp_tsunami.c" || {
    msg_err "$(L MSG_SYS_1180)"; rm -rf "$tmpdir"; pause; return
  }
  echo "obj-m:=tcp_tsunami.o" > "$tmpdir/Makefile"
  if make -C "/lib/modules/$(uname -r)/build" M="$tmpdir" modules CC=/usr/bin/gcc 2>/dev/null; then
    cp "$tmpdir/tcp_tsunami.ko" "/lib/modules/$(uname -r)/kernel/net/ipv4/" 2>/dev/null
    depmod -a 2>/dev/null
    modprobe tcp_tsunami 2>/dev/null
    msg_ok "$(L MSG_SYS_1181)"
    if confirm "$(L MSG_SYS_1182)"; then
      _bbr_apply "tsunami" "fq"
    fi
  else
    msg_err "$(L MSG_SYS_1183 "$(uname -r)")"
  fi
  rm -rf "$tmpdir"
  _log_write "$(L MSG_SYS_1184)"
  pause
}

# ---- 编译 暴力BBR魔改版 ----
_bbr_compile_nanqinlang() {
  msg_info "$(L MSG_SYS_1185)"
  _check_pkg gcc gcc 2>/dev/null
  _check_pkg make make 2>/dev/null
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    msg_err "$(L MSG_SYS_1179)"
    pause; return
  fi
  local tmpdir=$(mktemp -d)
  _download "https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/bbr/tcp_nanqinlang.c" "$tmpdir/tcp_nanqinlang.c" || \
  _download "https://raw.githubusercontent.com/cx9208/Linux-NetSpeed/master/bbr/tcp_nanqinlang.c" "$tmpdir/tcp_nanqinlang.c" || {
    msg_err "$(L MSG_SYS_1186)"; rm -rf "$tmpdir"; pause; return
  }
  echo "obj-m := tcp_nanqinlang.o" > "$tmpdir/Makefile"
  if make -C "/lib/modules/$(uname -r)/build" M="$tmpdir" modules CC=/usr/bin/gcc 2>/dev/null; then
    cp "$tmpdir/tcp_nanqinlang.ko" "/lib/modules/$(uname -r)/kernel/net/ipv4/" 2>/dev/null
    depmod -a 2>/dev/null
    modprobe tcp_nanqinlang 2>/dev/null
    msg_ok "$(L MSG_SYS_1187)"
    if confirm "$(L MSG_SYS_1188)"; then
      _bbr_apply "nanqinlang" "fq"
    fi
  else
    msg_err "$(L MSG_SYS_1183 "$(uname -r)")"
  fi
  rm -rf "$tmpdir"
  _log_write "$(L MSG_SYS_1189)"
  pause
}

# ---- 系统网络优化 ----
_bbr_optimize_standard() {
  msg_info "$(L MSG_SYS_1190)"
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
  msg_ok "$(L MSG_SYS_1191)"
  _log_write "$(L MSG_SYS_1191)"
  pause
}

_bbr_optimize_radical() {
  msg_info "$(L MSG_SYS_1192)"
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
  msg_ok "$(L MSG_SYS_1193)"
  _log_write "$(L MSG_SYS_1193)"
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
    msg_ok "$(L MSG_SYS_1194)"
  else
    msg_ok "$(L MSG_SYS_1195)"
  fi
  _log_write "$(L MSG_SYS_1196 "$val")"
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
    msg_ok "$(L MSG_SYS_1197)"
  else
    cat >> /etc/sysctl.conf << 'SEOF'

# 启用 IPv6
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
SEOF
    sysctl -p 2>/dev/null
    msg_ok "$(L MSG_SYS_1198)"
  fi
  _log_write "$(L MSG_SYS_1199 "$val")"
  pause
}

# ---- 删除多余内核 ----
_bbr_delete_old_kernels() {
  local current_kver; current_kver=$(uname -r)
  msg_info "$(L MSG_SYS_1200 "$current_kver")"
  msg ""

  case "$F_PKG_MGR" in
    apt)
      local old_kernels=$(dpkg -l | grep linux-image | awk '{print $2}' | grep -v "$current_kver" | grep -v "linux-image-$current_kver")
      if [[ -z "$old_kernels" ]]; then
        msg_ok "$(L MSG_SYS_1201)"
        pause; return
      fi
      msg_info "$(L MSG_SYS_1202)"
      echo "$old_kernels" | while read -r k; do msg "  $k"; done
      msg ""
      if confirm "$(L MSG_SYS_1203)"; then
        echo "$old_kernels" | while read -r k; do
          apt-get purge -y "$k" 2>/dev/null
        done
        apt-get autoremove -y 2>/dev/null
        msg_ok "$(L MSG_SYS_1204)"
      fi
      ;;
    yum)
      local old_kernels=$(rpm -qa | grep kernel | grep -v "$current_kver" | grep -v "noarch")
      if [[ -z "$old_kernels" ]]; then
        msg_ok "$(L MSG_SYS_1201)"
        pause; return
      fi
      msg_info "$(L MSG_SYS_1202)"
      echo "$old_kernels" | while read -r k; do msg "  $k"; done
      msg ""
      if confirm "$(L MSG_SYS_1203)"; then
        echo "$old_kernels" | while read -r k; do
          rpm --nodeps -e "$k" 2>/dev/null
        done
        msg_ok "$(L MSG_SYS_1204)"
      fi
      ;;
    *)
      msg_err "$(L MSG_SYS_1205)"
      ;;
  esac
  _log_write "$(L MSG_SYS_1206)"
  pause
}

# ---- 代理程序 BBR 说明 ----
_bbr_proxy_info() {
  msg_title "$(L MSG_SYS_1207)"
  msg ""
  msg "$(L MSG_SYS_1208 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1209)"
  msg "$(L MSG_SYS_1210)"
  msg ""
  msg "$(L MSG_SYS_1211 "${F_BOLD}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_SYS_1212 "${F_CYAN}" "${F_RESET}")"
  msg "$(L MSG_SYS_1213)"
  msg "$(L MSG_SYS_1214)"
  msg "$(L MSG_SYS_1215)"
  msg ""
  msg "  ${F_CYAN}v2ray-core${F_RESET}:"
  msg "$(L MSG_SYS_1213)"
  msg "$(L MSG_SYS_1216)"
  msg "$(L MSG_SYS_1217)"
  msg ""
  msg "  ${F_CYAN}sing-box${F_RESET}:"
  msg "$(L MSG_SYS_1213)"
  msg "$(L MSG_SYS_1218)"
  msg "$(L MSG_SYS_1219)"
  msg ""
  msg "  ${F_CYAN}Clash.Meta${F_RESET}:"
  msg "$(L MSG_SYS_1213)"
  msg "$(L MSG_SYS_1220)"
  msg ""
  msg "$(L MSG_SYS_1221 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1222)"
  msg "$(L MSG_SYS_1223)"
  msg "$(L MSG_SYS_1224)"
  msg ""
  msg "$(L MSG_SYS_1225 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1226)"
  msg "$(L MSG_SYS_1227)"
  msg "$(L MSG_SYS_1228)"
  msg "$(L MSG_SYS_1229)"
  msg ""
  pause
}

_system_install_kernel() {
  case "$F_PKG_MGR" in
    apt)
      msg_info "$(L MSG_SYS_1230)"
      apt-get update -y
      msg_info "$(L MSG_SYS_1231)"
      apt-get install -y linux-image-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null || \
      apt-get install -y --install-recommends linux-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null
      msg_info "$(L MSG_SYS_1232)"
      if confirm "$(L MSG_SYS_1165)"; then
        reboot
      fi
      ;;
    yum)
      # Install ELrepo and kernel-lt
      rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || true
      yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm 2>/dev/null || true
      yum --enablerepo=elrepo-kernel install -y kernel-lt 2>/dev/null || true
      if grub2-set-default 0 2>/dev/null; then
        msg_info "$(L MSG_SYS_1232)"
        confirm "$(L MSG_SYS_1165)" && reboot
      fi
      ;;
  esac
}

# ---- Benchmark (SuperBench style) ----
system_benchmark() {
  _require_root
  msg_title "$(L MSG_SYS_1233)"
  msg ""
  msg_info "$(L MSG_SYS_1234)"

  # CPU - simple sieve
  msg "$(L MSG_SYS_1235 "${F_BOLD}" "${F_RESET}" "$(_cpu_cores_display)")"
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
  msg "$(L MSG_SYS_1236 "${F_BOLD}" "${F_RESET}" "${cpu_time}" "$prime_count")"

  # Memory speed test
  msg "$(L MSG_SYS_1098 "${F_BOLD}" "${F_RESET}")"
  free -h | awk '/Mem:/{printf "    Total: %s  Used: %s  Free: %s\n", $2, $3, $4}'
  free -h | awk '/Swap:/{printf "    Swap: %s  Used: %s  Free: %s\n", $2, $3, $4}'

  # Disk I/O test
  msg "$(L MSG_SYS_1237 "${F_BOLD}" "${F_RESET}")"
  local io_write; io_write=$(dd if=/dev/zero of=/tmp/fusionbench bs=1M count=1024 conv=fdatasync 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "$(L MSG_SYS_1238 "${io_write:-测试失败}")"
  sync
  local io_read; io_read=$(dd if=/tmp/fusionbench of=/dev/null bs=1M count=1024 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "$(L MSG_SYS_1239 "${io_read:-测试失败}")"
  rm -f /tmp/fusionbench

  # Network speed test
  msg "$(L MSG_SYS_1100 "${F_BOLD}" "${F_RESET}")"
  _get_ip
  msg "$(L MSG_SYS_1240 "${F_IP:-未知}")"
  msg "$(L MSG_SYS_1241 "${F_IPV6:-未知}")"

  # Optional: download speedtest
  if confirm "$(L MSG_SYS_1242)"; then
    msg_info "$(L MSG_SYS_1243)"
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
    msg "$(L MSG_SYS_1244 "${speed_mbps}")"
    rm -f /tmp/speedtest
  fi

  msg ""
  _log_write "$(L MSG_SYS_1245)"
  pause
}

# ---- System Monitor (top-like) ----
system_monitor() {
  msg_title "$(L MSG_SYS_1246)"
  msg "$(L MSG_SYS_1247)"
  msg ""

  local interval="${1:-${CONFIG_system_monitor_interval:-5}}"
  # 配置值必须为正整数，否则回退默认，避免 `sleep 0` 空转或 sleep 报错刷屏
  [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=5
  while true; do
    clear
    msg "$(L MSG_SYS_1248 "${F_BOLD}" "${F_CYAN}" "${interval}" "${F_RESET}")"
    msg "$(L MSG_SYS_1249 "${F_BOLD}" "${F_RESET}" "$(date '+%Y-%m-%d %H:%M:%S')")"
    msg ""

    # CPU & Load
    msg "$(L MSG_SYS_1250 "${F_BOLD}" "${F_RESET}")"
    local load; load=$(cat /proc/loadavg 2>/dev/null)
    msg "$(L MSG_SYS_1251 "$load")"
    msg "$(L MSG_SYS_1252 "$(ps aux | wc -l)")"

    # CPU usage
    local cpu_idle; cpu_idle=$(top -bn1 2>/dev/null | grep "%Cpu" | awk '{print $8}' | cut -d. -f1)
    if [[ -n "$cpu_idle" && "$cpu_idle" -le 100 ]]; then
      msg "$(L MSG_SYS_1253 "$((100 - cpu_idle))")"
    fi

    # Top processes
    msg ""
    msg "$(L MSG_SYS_1254 "${F_BOLD}" "${F_RESET}")"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | awk 'NR>1{printf "  %-12s %-6s %-5s %s\n", $1, $2, $3"%", $11}'

    # Memory
    msg ""
    msg "$(L MSG_SYS_1255 "${F_BOLD}" "${F_RESET}")"
    free -h | awk 'NR==1{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'
    free -h | awk 'NR==2{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'

    # Disk
    msg ""
    msg "$(L MSG_SYS_1256 "${F_BOLD}" "${F_RESET}")"
    df -h / 2>/dev/null | awk 'NR==2{printf "  %-15s %-10s %-10s %s\n", $1, $2, $3, $5}'

    # Network connections
    msg ""
    msg "$(L MSG_SYS_1257 "${F_BOLD}" "${F_RESET}")"
    if command -v ss &>/dev/null; then
      msg "$(L MSG_SYS_1258 "$(ss -tlnp 2>/dev/null | wc -l)" "$(ss -tan 2>/dev/null | wc -l)")"
    fi
    msg "  IP: ${F_IP:-$(curl -s ip.sb 2>/dev/null || echo "N/A")}"

    # Proxy
    if systemctl is-active fusionbox-proxy &>/dev/null; then
      local pbe=$(cat /etc/fusionbox/proxy/current_backend 2>/dev/null || echo "proxy")
      msg "$(L MSG_SYS_1259 "${F_GREEN}" "$pbe" "${F_RESET}")"
    fi

    sleep "$interval"
  done
}


# ---- 救援指引 (B 档)：出事时用户最需要「现在该敲什么」 ----
# 只读汇总，不修改系统。定位对标的「重装/DD」高风险功能，但只做安全的
# 「恢复指引」：列出受管服务恢复命令、备份位置、回滚步骤。
system_rescue() {
  _require_root
  local backup_dir="${1:-/root/backups}"
  msg_title "$(L MSG_SYS_1260)"
  msg ""
  msg_warn "$(L MSG_SYS_1261)"
  msg ""

  msg "$(L MSG_SYS_1262 "${F_BOLD}" "${F_RESET}")"
  if [[ -d /etc/fusionbox ]]; then
    msg "$(L MSG_SYS_1263)"
    msg "$(L MSG_SYS_1264 "$(tr -d '[:space:]' < /etc/fusionbox/version.txt 2>/dev/null || echo '未知')")"
  else
    msg "$(L MSG_SYS_1265)"
  fi
  msg "$(L MSG_SYS_1266 "$FUSION_CONFIG_DIR")"
  msg ""

  msg "$(L MSG_SYS_1267 "${F_BOLD}" "${F_RESET}")"
  local found=0 f
  for f in "$backup_dir"/fusionbox_backup_*.tar.gz; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    msg "    $(basename "$f")  ( $(du -h "$f" 2>/dev/null | cut -f1) )"
    found=1
  done
  [[ $found -eq 1 ]] || msg "$(L MSG_SYS_1268 "$backup_dir")"
  msg "$(L MSG_SYS_1269 "$backup_dir")"
  msg ""

  msg "$(L MSG_SYS_1270 "${F_BOLD}" "${F_RESET}")"
  if [[ -d /var/lib/fusionbox/compose-projects ]]; then
    local proj
    for proj in /var/lib/fusionbox/compose-projects/*.json; do
      [[ -f "$proj" ]] || continue
      msg "$(L MSG_SYS_1271 "$(basename "$proj" .json)")"
    done
    msg "$(L MSG_SYS_1272)"
    msg "$(L MSG_SYS_1273)"
  else
    msg "$(L MSG_SYS_1274)"
  fi
  msg ""

  msg "$(L MSG_SYS_1275 "${F_BOLD}" "${F_RESET}")"
  local svc
  for svc in docker nginx sshd; do
    if command -v systemctl &>/dev/null && systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service"; then
      msg "    $svc: $(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
    fi
  done
  msg "$(L MSG_SYS_1276)"
  msg ""

  msg "$(L MSG_SYS_1277 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1278)"
  msg "$(L MSG_SYS_1279)"
  msg "$(L MSG_SYS_1280)"
  msg "$(L MSG_SYS_1281)"
  msg ""

  if [[ -t 0 && "${FUSION_NONINTERACTIVE:-0}" != "1" ]]; then
    pause
  fi
}

# ---- System Backup ----
_fb_backup_scopes() {
  local scopes="fusion,web,docker" answer scope
  msg "$(L MSG_SYS_1282)" >&2
  msg "$(L MSG_SYS_1283)" >&2
  for scope in ssh cron usr-local home; do
    read -r -p "$(L MSG_SYS_1284 "$scope" "$scope")" answer || return 1
    if [[ "$answer" == "INCLUDE-$scope" ]]; then
      scopes+=",$scope"
    elif [[ -n "$answer" ]]; then
      msg_warn "$(L MSG_SYS_1285 "$scope")" >&2
    fi
  done
  printf '%s' "$scopes"
}

system_backup() {
  _require_root
  local backup_dir="${1:-${CONFIG_system_backup_dir:-/root/backups}}" scopes="${2:-}"
  mkdir -p "$backup_dir" || return 1

  local date_str; date_str=$(date '+%Y%m%d_%H%M%S')
  local backup_file="$backup_dir/fusionbox_backup_$date_str.tar.gz"

  msg_title "$(L MSG_SYS_1083)"
  msg ""
  msg_warn "$(L MSG_SYS_1286)"
  msg_warn "$(L MSG_SYS_1287)"
  [[ -n "$scopes" ]] || scopes=$(_fb_backup_scopes) || return 1
  _require_python3 "$(L MSG_SYS_1083)" || return 1
  msg_info "$(L MSG_SYS_1288 "$scopes")"
  # Fresh hosts have none of the default sources; skip what is missing (reported
  # in Chinese by archive.py) and only fail when nothing at all is left.
  local create_out
  if ! create_out=$(python3 "$FUSION_SRC/lib/archive.py" create "$scopes" "$backup_file" 2>&1); then
    msg_err "$(L MSG_SYS_1289)"
    msg "$create_out"
    msg_info "$(L MSG_SYS_1290)"
    return 1
  fi
  [[ -z "$create_out" ]] || msg "$create_out"
  msg_ok "$(L MSG_SYS_1291 "$backup_file")"
  _log_write "$(L MSG_SYS_1292 "$backup_file" "$scopes")"
  pause
}

system_restore() {
  _require_root
  local backup_dir="${1:-${CONFIG_system_backup_dir:-/root/backups}}"

  msg_title "$(L MSG_SYS_1084)"
  msg ""

  local backups=()
  for f in "$backup_dir"/fusionbox_backup_*.tar.gz; do
    [[ -f "$f" && ! -L "$f" ]] && backups+=("$f")
  done

  if [[ ${#backups[@]} -eq 0 ]]; then
    msg_warn "$(L MSG_SYS_1293 "$backup_dir")"
    pause
    return
  fi

  msg_info "$(L MSG_SYS_1294)"
  local i=1
  for f in "${backups[@]}"; do
    local size; size=$(du -h "$f" | cut -f1)
    msg "  $i) $(basename "$f") ($size)"
    i=$((i+1))
  done
  msg ""

  local choice idx restore_file scopes conflict confirm_input
  read -r -p "$(L MSG_SYS_1295)" choice
  [[ "$choice" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
  idx=$((choice - 1))
  [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]] || return 1
  restore_file="${backups[$idx]}"
  read -r -p "$(L MSG_SYS_1296)" scopes
  [[ -n "$scopes" ]] || return 1

  msg_info "$(L MSG_SYS_1297)"
  python3 "$FUSION_SRC/lib/archive.py" verify "$scopes" "$restore_file" || return 1
  python3 "$FUSION_SRC/lib/archive.py" preview "$scopes" "$restore_file" --conflict replace || return 1
  msg_warn "$(L MSG_SYS_1298)"
  msg "$(L MSG_SYS_1299)"
  read -r -p "$(L MSG_SYS_1300)" choice
  case "${choice:-1}" in
    1) conflict="abort" ;;
    2) conflict="replace" ;;
    3) conflict="skip" ;;
    *) msg_err "$(L MSG_SYS_1301)"; return 1 ;;
  esac
  python3 "$FUSION_SRC/lib/archive.py" preview "$scopes" "$restore_file" --conflict "$conflict" || return 1
  confirm "$(L MSG_SYS_1302)" || return 0
  read -r -p "$(L MSG_SYS_1303)" confirm_input
  [[ "$confirm_input" == "RESTORE" ]] || { msg_warn "$(L MSG_SYS_1304)"; return 0; }
  python3 "$FUSION_SRC/lib/archive.py" restore "$scopes" "$restore_file" --conflict "$conflict" || return 1
  msg_ok "$(L MSG_SYS_1305)"
  _log_write "$(L MSG_SYS_1306 "$restore_file" "$scopes" "$conflict")"
  pause
}

# ---- System Update ----
system_update() {
  _require_root
  msg_title "$(L MSG_SYS_1307)"
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

  msg_ok "$(L MSG_SYS_1308)"
  _log_write "$(L MSG_SYS_1309)"

  if [[ -f /var/run/reboot-required ]]; then
    msg_warn "$(L MSG_SYS_1310)"
    if confirm "$(L MSG_SYS_1165)"; then
      reboot
    fi
  fi
  pause
}

# ---- System Cleanup ----
system_clean() {
  _require_root
  msg_title "$(L MSG_SYS_1311)"
  msg ""

  msg_info "$(L MSG_SYS_1312)"
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

  msg_info "$(L MSG_SYS_1313)"
  journalctl --vacuum-time=7d 2>/dev/null || true

  msg_info "$(L MSG_SYS_1314)"
  rm -rf /tmp/*.tmp 2>/dev/null || true
  rm -rf /tmp/fusion* 2>/dev/null || true

  msg_info "$(L MSG_SYS_1315)"
  if command -v docker &>/dev/null; then
    docker system prune -f --volumes 2>/dev/null || true
  fi

  msg_ok "$(L MSG_SYS_1316)"
  _log_write "$(L MSG_SYS_1316)"
  pause
}

# ---- Swap Management ----
system_swap() {
  _require_root
  msg_title "$(L MSG_SYS_1085)"
  msg ""

  msg "$(L MSG_SYS_1317)"
  swapon --show 2>/dev/null || msg "$(L MSG_SYS_1318)"
  free -h | awk '/Swap:/{printf "    %s %s %s\n", $2, $3, $4}'

  msg ""
  msg "$(L MSG_SYS_1319)"
  msg "$(L MSG_SYS_1320)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" sw_choice

  case "$sw_choice" in
    1)
      if [[ -e /swapfile ]] || swapon --show=NAME 2>/dev/null | grep -q "/swapfile"; then
        msg_warn "$(L MSG_SYS_1323)"
        pause
        return
      fi

      read -p "$(L MSG_SYS_1324)" sw_size
      sw_size="${sw_size// /}"
      sw_size="${sw_size:-2048}"
      if [[ ! "$sw_size" =~ ^[0-9]+[GgMm]?$ ]]; then
        msg_err "$(L MSG_SYS_1325 "$sw_size")"
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
        msg_err "$(L MSG_SYS_1326 "${sw_mb}")"
        pause
        return
      fi

      local avail_mb; avail_mb=$(df -m / 2>/dev/null | awk 'NR==2{print $4}')
      if [[ "$avail_mb" =~ ^[0-9]+$ ]] && [[ $((avail_mb - sw_mb)) -lt 256 ]]; then
        msg_warn "$(L MSG_SYS_1327 "${avail_mb}" "${sw_mb}")"
        confirm "$(L MSG_SYS_1328)" || { pause; return; }
      fi

      if confirm "$(L MSG_SYS_1329 "${sw_mb}" "${sw_size}")"; then
        msg_info "$(L MSG_SYS_1330 "${sw_mb}")"
        if ! fallocate -l "${sw_mb}M" /swapfile 2>/dev/null; then
          msg_warn "$(L MSG_SYS_1331)"
          if ! dd if=/dev/zero of=/swapfile bs=1M count="$sw_mb" status=progress; then
            rm -f /swapfile
            msg_err "$(L MSG_SYS_1332)"
            pause
            return
          fi
        fi
        chmod 600 /swapfile
        if mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile 2>/dev/null; then
          grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
          msg_ok "$(L MSG_SYS_1333 "${sw_mb}")"
          free -h | grep -i swap
          _log_write "$(L MSG_SYS_1334 "${sw_mb}")"
        else
          msg_err "$(L MSG_SYS_1335)"
        fi
      fi
      ;;
    2)
      if confirm "$(L MSG_SYS_1336)"; then
        python3 "$FUSION_SRC/lib/system_safety.py" swap || return 1
        msg_ok "$(L MSG_SYS_1337)"
      fi
      ;;
  esac
  pause
}
# ---- x86-64 psABI 级别检测 (G68) ----
_psabi_from_flags() {
  local flags="$1" lvl="v1"
  if [[ "$flags" == *sse4_2* && "$flags" == *popcnt* && "$flags" == *sse4_1* && "$flags" == *ssse3* ]]; then
    lvl="v2"
  fi
  if [[ "$lvl" == "v2" && "$flags" == *avx2* && "$flags" == *bmi2* && "$flags" == *bmi* && "$flags" == *fma* && "$flags" == *movbe* ]]; then
    lvl="v3"
  fi
  if [[ "$lvl" == "v3" && "$flags" == *avx512f* && "$flags" == *avx512bw* && "$flags" == *avx512cd* && "$flags" == *avx512dq* && "$flags" == *avx512vl* ]]; then
    lvl="v4"
  fi
  printf '%s' "$lvl"
}

# ---- User Management (CRUD/sudo/password, was read-only) ----

_fb_user_check_name() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
    msg_err "$(L MSG_SYS_1338)"
    return 1
  }
}

_fb_user_read_password() {
  local label="$1" p1 p2
  read -rsp "$label: " p1 || return 1
  msg "" >&2
  if [[ -z "$p1" ]]; then
    msg_err "$(L MSG_SYS_1339)"
    return 1
  fi
  if [[ ${#p1} -gt 512 || "$p1" == *:* || "$p1" == *$'\n'* || "$p1" == *$'\r'* ]]; then
    msg_err "$(L MSG_SYS_1340)"
    return 1
  fi
  read -rsp "$(L MSG_SYS_1341)" p2 || return 1
  msg "" >&2
  if [[ "$p1" != "$p2" ]]; then
    msg_err "$(L MSG_SYS_1342)"
    return 1
  fi
  printf '%s' "$p1"
}

_fb_users_list() {
  msg "$(L MSG_SYS_1343 "${F_BOLD}" "${F_RESET}")"
  awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s, shell=%s, home=%s)\n", $1, $3, $7, $6}' /etc/passwd
  msg ""
  msg "$(L MSG_SYS_1344 "${F_BOLD}" "${F_RESET}")"
  local f base found=0
  for f in /etc/sudoers.d/90-fusionbox-*; do
    [[ -f "$f" ]] || continue
    base="${f##*/90-fusionbox-}"
    if head -n1 "$f" 2>/dev/null | grep -q "^# FusionBox managed sudo grant"; then
      msg "$(L MSG_SYS_1345 "$base")"
    else
      msg "$(L MSG_SYS_1346 "${F_YELLOW}" "$base" "${F_RESET}")"
    fi
    found=1
  done
  [[ $found -eq 0 ]] && msg "$(L MSG_SYS_1347)"
  msg ""
  msg "$(L MSG_SYS_1348 "${F_BOLD}" "${F_RESET}")"
  last -n 5 2>/dev/null | head -5
}

_fb_user_set_password() {
  local name="$1" pw
  pw=$(_fb_user_read_password "$(L MSG_SYS_1349 "$name")") || return 1
  printf '%s\n' "$pw" | python3 "$FUSION_SRC/lib/system_safety.py" passwd-set "$name" || return 1
  msg_ok "$(L MSG_SYS_1350 "$name")"
  _log_write "$(L MSG_SYS_1351 "$name")"
}

_fb_users_cmd_add() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  id "$name" &>/dev/null && { msg_err "$(L MSG_SYS_1352 "$name")"; return 1; }
  confirm "$(L MSG_SYS_1353 "$name" "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-add "$name" || return 1
  msg_ok "$(L MSG_SYS_1355 "$name")"
  _log_write "$(L MSG_SYS_1356 "$name")"
  if confirm "$(L MSG_SYS_1357 "$name")"; then
    _fb_user_set_password "$name" || msg_warn "$(L MSG_SYS_1358 "$name")"
  fi
  return 0
}

_fb_users_cmd_del() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  msg_warn "$(L MSG_SYS_1359 "$name" "$name")"
  confirm "$(L MSG_SYS_1360 "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-del "$name" || return 1
  msg_ok "$(L MSG_SYS_1361 "$name")"
  _log_write "$(L MSG_SYS_1362 "$name")"
}

_fb_users_cmd_sudo() {
  local name="${1:-}" mode="${2:-}"
  _fb_user_check_name "$name" || return 1
  local flag=""
  if [[ -z "$mode" ]]; then
    mode=$(select_option "$(L MSG_SYS_1363 "$name")" "$(L MSG_SYS_1364)" "$(L MSG_SYS_1365)") || return 1
  fi
  [[ "$mode" == "nopasswd" || "$mode" == "2" ]] && flag="nopasswd"
  confirm "$(L MSG_SYS_1366 "$name" "${flag:+免密}" "${flag:-需密码}" "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" sudo-grant "$name" $flag || return 1
  msg_ok "$(L MSG_SYS_1367 "$name")"
  _log_write "$(L MSG_SYS_1368 "$name" "${flag:-password}")"
}

_fb_users_cmd_unsudo() {
  local name="${1:-}"
  _fb_user_check_name "$name" || return 1
  confirm "$(L MSG_SYS_1369 "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" sudo-revoke "$name" || return 1
  msg_ok "$(L MSG_SYS_1370 "$name")"
  _log_write "$(L MSG_SYS_1371 "$name")"
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
    msg_title "$(L MSG_SYS_1086)"
    msg ""
    _fb_users_list
    msg "$(L MSG_SYS_1372)"
    msg "$(L MSG_SYS_1373)"
    msg "$(L MSG_SYS_1374)"
    msg "$(L MSG_SYS_1375)"
    msg "$(L MSG_SYS_1376)"
    msg "$(L MSG_SYS_1321)"
    read -p "$(L MSG_SYS_1322)" u_choice || { msg ""; return; }
    case "$u_choice" in
      1) u_name=$(read_input "$(L MSG_SYS_1377)") && _fb_users_cmd_add "$u_name" ;;
      2) u_name=$(read_input "$(L MSG_SYS_1378)") && _fb_users_cmd_del "$u_name" ;;
      3) u_name=$(read_input "$(L MSG_SYS_1379)") && _fb_users_cmd_sudo "$u_name" ;;
      4) u_name=$(read_input "$(L MSG_SYS_1379)") && _fb_users_cmd_unsudo "$u_name" ;;
      5) u_name=$(read_input "$(L MSG_SYS_1379)") && _fb_users_cmd_passwd "$u_name" ;;
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
  ssh -n -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -o IdentitiesOnly=yes -i "$keyfile" -p "$port" \
      "${user}@127.0.0.1" "true" &>/dev/null
}

_fb_hardening_root_policy() {
  # $1=用户名 $2=yes(已验证密钥登录)|no(未验证)
  local name="$1" verified="$2" choice
  if [[ "$verified" != "yes" ]]; then
    msg_warn "$(L MSG_SYS_1380)"
    confirm "$(L MSG_SYS_1381 "$name")" || { msg_info "$(L MSG_SYS_1382)"; return 1; }
  fi
  choice=$(select_option "$(L MSG_SYS_1383)" "$(L MSG_SYS_1384)" "$(L MSG_SYS_1385)" "$(L MSG_SYS_1386)") || return 1
  case "$choice" in
    1)
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin prohibit-password || return 1
      msg_ok "$(L MSG_SYS_1387)"
      _log_write "$(L MSG_SYS_1388 "$name")"
      ;;
    2)
      msg_warn "$(L MSG_SYS_1389 "$name")"
      confirm "$(L MSG_SYS_1390)" || return 1
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin no || return 1
      msg_ok "$(L MSG_SYS_1391)"
      _log_write "$(L MSG_SYS_1392 "$name")"
      ;;
    *) msg_info "$(L MSG_SYS_1382)" ;;
  esac
}

system_hardening() {
  _require_root
  msg_title "$(L MSG_SYS_1393)"
  msg ""
  msg "$(L MSG_SYS_1394)"
  msg "$(L MSG_SYS_1395 "${F_YELLOW}" "${F_RESET}")"
  msg ""

  local name
  name=$(read_input "$(L MSG_SYS_1396)") || return 1
  _fb_user_check_name "$name" || return 1
  id "$name" &>/dev/null && { msg_err "$(L MSG_SYS_1397 "$name")"; return 1; }

  msg ""
  msg "$(L MSG_SYS_1398 "${F_BOLD}" "${F_RESET}")"
  confirm "$(L MSG_SYS_1399 "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" user-add "$name" || return 1
  if confirm "$(L MSG_SYS_1400 "$name")"; then
    _fb_user_set_password "$name" || msg_warn "$(L MSG_SYS_1401 "$name")"
  fi

  msg ""
  msg "$(L MSG_SYS_1402 "${F_BOLD}" "${F_RESET}")"
  local key_source key_file=""
  key_source=$(select_option "$(L MSG_SYS_1403)" "$(L MSG_SYS_1404)" "$(L MSG_SYS_1405)") || return 1
  if [[ "$key_source" == "1" ]]; then
    msg "$(L MSG_SYS_1406)"
    local pubkey
    read -r pubkey || return 1
    pubkey="${pubkey%$'\r'}"
    _fb_pubkey_valid "$pubkey" || { msg_err "$(L MSG_SYS_1407)"; return 1; }
    python3 "$FUSION_SRC/lib/system_safety.py" user-key-install "$name" <<< "$pubkey" || return 1
  else
    local ugroup
    ugroup=$(id -gn "$name" 2>/dev/null) || ugroup="$name"
    key_file="/home/$name/.ssh/id_ed25519"
    install -d -m 700 -o "$name" -g "$ugroup" "/home/$name/.ssh" || return 1
    ssh-keygen -t ed25519 -f "$key_file" -N "" -C "fusionbox-$name" || return 1
    chown "$name:$ugroup" "$key_file" "$key_file.pub" && chmod 600 "$key_file" || return 1
    python3 "$FUSION_SRC/lib/system_safety.py" user-key-install "$name" < "${key_file}.pub" || return 1
    msg "$(L MSG_SYS_1408 "$key_file")"
  fi

  msg ""
  msg "$(L MSG_SYS_1409 "${F_BOLD}" "${F_RESET}")"
  if confirm "$(L MSG_SYS_1410 "$name")"; then
    _fb_users_cmd_sudo "$name" || msg_warn "$(L MSG_SYS_1411 "$name")"
  fi

  msg ""
  msg "$(L MSG_SYS_1412 "${F_BOLD}" "${F_RESET}")"
  local verified="no" rc=0
  if [[ -n "$key_file" ]]; then
    if _fb_hardening_verify_key_login "$name" "$key_file"; then
      msg_ok "$(L MSG_SYS_1413 "$name")"
      verified="yes"
    else
      rc=$?
      [[ $rc -eq 2 ]] && msg_warn "$(L MSG_SYS_1414)" || msg_warn "$(L MSG_SYS_1415)"
    fi
  else
    msg_info "$(L MSG_SYS_1416)"
  fi

  msg ""
  msg "$(L MSG_SYS_1417 "${F_BOLD}" "${F_RESET}")"
  _fb_hardening_root_policy "$name" "$verified" || true

  msg ""
  msg_ok "$(L MSG_SYS_1418 "$name" "$name")"
  _log_write "$(L MSG_SYS_1419 "$name" "$verified")"
}

# ---- SSH candidate preflight ----
system_ssh_preflight() {
  _require_root
  [[ $# -eq 0 ]] || { msg_err "$(L MSG_SYS_1420)"; return 2; }
  python3 -B "$FUSION_SRC/lib/system_safety.py" ssh-preflight
}

# ---- Isolated OpenSSH candidate lifecycle ----
system_ssh_candidate() {
  _require_root
  [[ $# -ge 1 ]] || {
    msg_err "$(L MSG_SYS_1421)"
    msg "$(L MSG_SYS_1422)"
    msg "$(L MSG_SYS_1423)"
    msg "$(L MSG_SYS_1424)"
    msg "$(L MSG_SYS_1425)"
    msg "$(L MSG_SYS_1426)"
    return 2
  }
  python3 -B "$FUSION_SRC/lib/openssh_candidate.py" "$@"
}

# ---- Security Audit ----
system_security() {
  _require_root
  msg_title "$(L MSG_SYS_1088)"
  msg ""

  msg "$(L MSG_SYS_1427 "${F_BOLD}" "${F_RESET}")"
  local ssh_port; ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  msg "$(L MSG_SYS_1428 "${ssh_port:-22 (默认)}")"
  if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "$(L MSG_SYS_1429 "${F_YELLOW}" "${F_RESET}")"
  else
    msg "$(L MSG_SYS_1430 "${F_GREEN}" "${F_RESET}")"
  fi
  if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "$(L MSG_SYS_1431 "${F_YELLOW}" "${F_RESET}")"
  fi

  msg ""
  msg "$(L MSG_SYS_1432 "${F_BOLD}" "${F_RESET}")"
  if command -v ufw &>/dev/null; then
    ufw status 2>/dev/null | head -5
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all 2>/dev/null | head -5
  else
    msg "$(L MSG_SYS_1433)"
  fi

  msg ""
  msg "${F_BOLD}[Fail2Ban]${F_RESET}"
  if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status 2>/dev/null || msg "$(L MSG_SYS_1434)"
  else
    msg "$(L MSG_SYS_1435)"
  fi

  msg ""
  msg "$(L MSG_SYS_1436 "${F_BOLD}" "${F_RESET}")"
  ss -tlnp 2>/dev/null | awk 'NR>1{printf "  %s %s\n", $4, $NF}'

  msg ""
  msg "$(L MSG_SYS_1437)"
  msg "$(L MSG_SYS_1438)"
  msg "$(L MSG_SYS_1439)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" sec_choice

  case "$sec_choice" in
    1)
      _install_pkg ufw
      ufw allow ssh
      ufw --force enable
      msg_ok "$(L MSG_SYS_1440)"
      ;;
    2)
      _install_pkg fail2ban
      systemctl enable --now fail2ban 2>/dev/null || true
      msg_ok "$(L MSG_SYS_1441)"
      ;;
    3)
      read -p "$(L MSG_SYS_1442)" new_port
      if [[ -z "$new_port" || ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        msg_err "$(L MSG_SYS_1443)"
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
          msg_warn "$(L MSG_SYS_1444 "$new_port")"
          confirm "$(L MSG_SYS_1445)" && fw_ok=1
        fi
        if [[ $fw_ok -eq 1 ]]; then
          python3 "$FUSION_SRC/lib/system_safety.py" ssh Port "$new_port" || return 1
          msg_warn "$(L MSG_SYS_1446)"
        else
          msg_err "$(L MSG_SYS_1447 "$new_port")"
        fi
      fi
      ;;
  esac
  pause
}

# ---- SSH 密钥管理 ----
system_sshkey() {
  _require_root
  msg_title "$(L MSG_SYS_1090)"
  msg ""

  msg "$(L MSG_SYS_1448 "${F_BOLD}" "${F_RESET}")"
  if [[ -f ~/.ssh/authorized_keys ]]; then
    python3 "$FUSION_SRC/lib/system_safety.py" keys-list || return 1
  else
    msg "$(L MSG_SYS_1449)"
  fi

  msg ""
  msg "$(L MSG_SYS_1450)"
  msg "$(L MSG_SYS_1451)"
  msg "$(L MSG_SYS_1452)"
  msg "$(L MSG_SYS_1453)"
  msg "$(L MSG_SYS_1454)"
  msg "$(L MSG_SYS_1455)"
  msg "$(L MSG_SYS_1456)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" ssh_choice

  case "$ssh_choice" in
    1)
      msg "$(L MSG_SYS_1406)"
      read -r pubkey
      pubkey="${pubkey%$'\r'}"
      local pubkey_re='^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-[a-z0-9-]+|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/=]+( .*)?$'
      if [[ -n "$pubkey" && ! "$pubkey" =~ $pubkey_re ]]; then
        msg_err "$(L MSG_SYS_1457)"
        pause
        return 1
      fi
      if [[ -n "$pubkey" ]]; then
        python3 "$FUSION_SRC/lib/system_safety.py" keys-add <<< "$pubkey" || return 1
        msg_ok "$(L MSG_SYS_1458)"
        _log_write "$(L MSG_SYS_1459)"
      fi
      ;;
    2)
      local key_type; key_type=$(select_option "$(L MSG_SYS_1460)" "$(L MSG_SYS_1461)" "RSA 4096")
      local key_file
      if [[ "$key_type" == "1" ]]; then
        key_file="$HOME/.ssh/id_ed25519"
        ssh-keygen -t ed25519 -f "$key_file" -N "" -C "fusionbox@$(hostname)" 2>/dev/null
      else
        key_file="$HOME/.ssh/id_rsa"
        ssh-keygen -t rsa -b 4096 -f "$key_file" -N "" -C "fusionbox@$(hostname)" 2>/dev/null
      fi
      if [[ -f "$key_file" ]]; then
        msg_ok "$(L MSG_SYS_1462)"
        msg "$(L MSG_SYS_1463 "$key_file")"
        msg "$(L MSG_SYS_1464 "${key_file}")"
        msg ""
        msg "$(L MSG_SYS_1465)"
        cat "${key_file}.pub"
      fi
      ;;
    3)
      if [[ -f ~/.ssh/authorized_keys ]]; then
        read -p "$(L MSG_SYS_1466)" line_num
        if [[ -n "$line_num" ]]; then
          python3 "$FUSION_SRC/lib/system_safety.py" keys-delete "$line_num" || return 1
          msg_ok "$(L MSG_SYS_1467)"
        fi
      fi
      ;;
    4)
      python3 "$FUSION_SRC/lib/system_safety.py" keys-check || return 1
      if confirm "$(L MSG_SYS_1468)"; then
        python3 "$FUSION_SRC/lib/system_safety.py" ssh PasswordAuthentication no || return 1
        msg_ok "$(L MSG_SYS_1469)"
      fi
      ;;
    5)
      msg_warn "$(L MSG_SYS_1470)"
      confirm "$(L MSG_SYS_1471)" || { msg_info "$(L MSG_SYS_1354)"; pause; return; }
      local rootpw
      rootpw=$(_fb_user_read_password "$(L MSG_SYS_1472)") || { pause; return 1; }
      printf '%s\n' "$rootpw" | python3 "$FUSION_SRC/lib/system_safety.py" passwd-set root || { pause; return 1; }
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin yes || { pause; return 1; }
      msg_ok "$(L MSG_SYS_1473)"
      msg_info "$(L MSG_SYS_1474)"
      _log_write "$(L MSG_SYS_1475)"
      ;;
    6)
      python3 "$FUSION_SRC/lib/system_safety.py" ssh PermitRootLogin prohibit-password || return 1
      msg_ok "$(L MSG_SYS_1476)"
      _log_write "$(L MSG_SYS_1477)"
      ;;
    7)
      msg "$(L MSG_SYS_1478)"
      msg "$(L MSG_SYS_1479)"
      read -p "$(L MSG_SYS_1480)" ksrc
      local iurl=""
      case "$ksrc" in
        1) read -p "$(L MSG_SYS_1481)" gh_user
           [[ "$gh_user" =~ ^[a-zA-Z0-9-]{1,39}$ ]] || { msg_err "$(L MSG_SYS_1482)"; pause; return; }
           iurl="https://github.com/${gh_user}.keys" ;;
        2) read -p "$(L MSG_SYS_1483)" iurl ;;
        *) pause; return ;;
      esac
      _fb_sshkey_import_url "$iurl" || { pause; return; }
      ;;
  esac
  pause
}
# ---- 远程公钥导入 (G21)：https 拉取 + 逐条校验确认 ----
_fb_sshkey_import_url() {
  local url="$1" tmp added=0 line
  [[ "$url" =~ ^https://[a-zA-Z0-9.-]+/ ]] || { msg_err "$(L MSG_SYS_1484 "$url")"; return 1; }
  tmp=$(mktemp) || return 1
  if ! _download "$url" "$tmp"; then
    rm -f "$tmp"
    msg_err "$(L MSG_SYS_1485 "$url")"
    return 1
  fi
  local n; n=$(grep -c . "$tmp" 2>/dev/null || echo 0)
  [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ] || { rm -f "$tmp"; msg_err "$(L MSG_SYS_1486)"; return 1; }
  msg_info "$(L MSG_SYS_1487 "$n")"
  while IFS= read -r line; do
    line="${line%$'
'}"
    [[ -n "$line" ]] || continue
    if ! _fb_pubkey_valid "$line"; then
      msg_warn "$(L MSG_SYS_1488)"
      continue
    fi
    msg "  ${line:0:60}..."
    if confirm "$(L MSG_SYS_1489)"; then
      printf '%s
' "$line" | python3 "$FUSION_SRC/lib/system_safety.py" keys-add && added=$((added+1))
    fi
  done < "$tmp"
  rm -f "$tmp"
  msg_ok "$(L MSG_SYS_1490 "$added")"
  _log_write "$(L MSG_SYS_1491 "$url" "$added")"
}

# ---- 防火墙管理 ----
system_firewall() {
  _require_root
  msg_title "$(L MSG_SYS_1492)"
  msg ""

  # Detect firewall
  local fw_type="none"
  if command -v ufw &>/dev/null; then
    fw_type="ufw"
    msg "$(L MSG_SYS_1493 "${F_BOLD}" "${F_RESET}")"
    msg "  $(ufw status 2>/dev/null | head -1)"
  elif command -v firewall-cmd &>/dev/null; then
    fw_type="firewalld"
    msg "$(L MSG_SYS_1494 "${F_BOLD}" "${F_RESET}")"
    firewall-cmd --state 2>/dev/null
  elif command -v iptables &>/dev/null; then
    fw_type="iptables"
    msg "$(L MSG_SYS_1495 "${F_BOLD}" "${F_RESET}")"
    local rule_count
    if rule_count=$(iptables -L -n 2>/dev/null | wc -l); then
      msg "$(L MSG_SYS_1496 "$rule_count")"
    else
      msg "$(L MSG_SYS_1497)"
    fi
  fi

  msg ""
  msg "$(L MSG_SYS_1498)"
  msg "$(L MSG_SYS_1499)"
  msg "$(L MSG_SYS_1500)"
  msg "$(L MSG_SYS_1501)"
  msg "$(L MSG_SYS_1502)"
  msg "$(L MSG_SYS_1503)"
  msg "$(L MSG_SYS_1504)"
  msg "$(L MSG_SYS_1505)"
  msg "$(L MSG_SYS_1506)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" fw_choice

  case "$fw_choice" in
    1)
      _install_pkg ufw
      ufw default deny incoming 2>/dev/null
      ufw default allow outgoing 2>/dev/null
      ufw allow ssh 2>/dev/null
      ufw --force enable 2>/dev/null
      msg_ok "$(L MSG_SYS_1507)"
      _log_write "$(L MSG_SYS_1508)"
      ;;
    2)
      read -p "$(L MSG_SYS_1509)" port
      if [[ -n "$port" ]]; then
        local proto; proto=$(select_option "$(L MSG_SYS_1510)" "$(L MSG_SYS_1511)" "$(L MSG_SYS_1512)" "$(L MSG_SYS_1513)")
        case "$proto" in
          2) ufw allow "$port"/tcp 2>/dev/null; iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null ;;
          3) ufw allow "$port"/udp 2>/dev/null; iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null ;;
          *) ufw allow "$port" 2>/dev/null; iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null ;;
        esac
        msg_ok "$(L MSG_SYS_1514 "$port")"
        _log_write "$(L MSG_SYS_1515 "$port")"
      fi
      ;;
    3)
      read -p "$(L MSG_SYS_1516)" port
      if [[ -n "$port" ]]; then
        ufw deny "$port" 2>/dev/null
        iptables -A INPUT -p tcp --dport "$port" -j DROP 2>/dev/null
        msg_ok "$(L MSG_SYS_1517 "$port")"
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
      read -p "$(L MSG_SYS_1518)" ip_addr
      if [[ -n "$ip_addr" ]]; then
        ufw allow from "$ip_addr" 2>/dev/null
        iptables -A INPUT -s "$ip_addr" -j ACCEPT 2>/dev/null
        msg_ok "$(L MSG_SYS_1519 "$ip_addr")"
      fi
      ;;
    6)
      read -p "$(L MSG_SYS_1520)" ip_addr
      if [[ -n "$ip_addr" ]]; then
        ufw deny from "$ip_addr" 2>/dev/null
        iptables -A INPUT -s "$ip_addr" -j DROP 2>/dev/null
        msg_ok "$(L MSG_SYS_1521 "$ip_addr")"
        _log_write "$(L MSG_SYS_1522 "$ip_addr")"
      fi
      ;;
    7)
      _install_pkg fail2ban
      systemctl enable --now fail2ban 2>/dev/null || true
      msg_ok "$(L MSG_SYS_1441)"
      ;;
    8)
      if ! command -v fail2ban-client &>/dev/null; then
        msg_err "$(L MSG_SYS_1523)"
      else
        msg "$(L MSG_SYS_1524)"
        fail2ban-client status 2>/dev/null
        msg ""
        read -p "$(L MSG_SYS_1525)" max_retry
        max_retry=${max_retry:-5}
        read -p "$(L MSG_SYS_1526)" ban_time
        ban_time=${ban_time:-3600}
        python3 "$FUSION_SRC/lib/system_safety.py" fail2ban "$max_retry" "$ban_time" || return 1
        msg_ok "$(L MSG_SYS_1527)"
      fi
      ;;
    9)
      msg_warn "$(L MSG_SYS_1528)"
      local confirm_input=""
      read -r -p "$(L MSG_SYS_1529)" confirm_input
      if [[ "$confirm_input" == "YES" ]]; then
        local ipt_bak; ipt_bak="/root/iptables-backup-$(date +%Y%m%d%H%M%S).rules"
        if iptables-save > "$ipt_bak" 2>/dev/null; then
          msg_ok "$(L MSG_SYS_1530 "$ipt_bak")"
        else
          rm -f "$ipt_bak"
          msg_warn "$(L MSG_SYS_1531)"
        fi
        ufw --force reset 2>/dev/null
        iptables -F 2>/dev/null
        iptables -X 2>/dev/null
        msg_ok "$(L MSG_SYS_1532)"
        _log_write "$(L MSG_SYS_1533 "$ipt_bak")"
      else
        msg_warn "$(L MSG_SYS_1534)"
      fi
      ;;
  esac
  pause
}

# ---- 定时任务管理 ----
system_cron() {
  _require_root
  msg_title "$(L MSG_SYS_1535)"
  msg ""

  msg "$(L MSG_SYS_1536 "${F_BOLD}" "${F_RESET}")"
  local cron_list=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$")
  if [[ -n "$cron_list" ]]; then
    echo "$cron_list" | while IFS= read -r line; do
      msg "  $line"
    done
  else
    msg "$(L MSG_SYS_1537)"
  fi

  msg ""
  msg "$(L MSG_SYS_1538)"
  msg "$(L MSG_SYS_1539)"
  msg "$(L MSG_SYS_1540)"
  msg "$(L MSG_SYS_1541)"
  msg "$(L MSG_SYS_1542)"
  msg "$(L MSG_SYS_1543)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" cron_choice

  case "$cron_choice" in
    1)
      msg "$(L MSG_SYS_1544)"
      msg "$(L MSG_SYS_1545)"
      msg "$(L MSG_SYS_1546)"
      msg "$(L MSG_SYS_1547)"
      msg "$(L MSG_SYS_1548)"
      msg ""
      read -p "$(L MSG_SYS_1549)" cron_expr
      read -p "$(L MSG_SYS_1550)" cron_cmd
      if [[ -n "$cron_expr" && -n "$cron_cmd" ]]; then
        if crontab -l 2>/dev/null | grep -qF "$cron_expr $cron_cmd"; then
          msg_warn "$(L MSG_SYS_1551)"
        else
          (crontab -l 2>/dev/null; echo "$cron_expr $cron_cmd") | crontab -
          msg_ok "$(L MSG_SYS_1552)"
          _log_write "$(L MSG_SYS_1553 "$cron_expr" "$cron_cmd")"
        fi
      fi
      ;;
    2)
      crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | nl -ba
      read -p "$(L MSG_SYS_1554)" del_line
      if [[ -n "$del_line" ]]; then
        if [[ "$del_line" =~ ^[0-9]+$ ]]; then
          crontab -l 2>/dev/null | sed "${del_line}d" | crontab -
          msg_ok "$(L MSG_SYS_1555)"
        else
          msg_err "$(L MSG_SYS_1556)"
        fi
      fi
      ;;
    3)
      crontab -e 2>/dev/null || msg_err "$(L MSG_SYS_1557)"
      ;;
    4)
      local backup_cron="0 3 * * * /bin/bash -c 'source /etc/fusionbox/src/init.sh && system_backup /root/backups fusion,web,docker'"
      if crontab -l 2>/dev/null | grep -qF "$backup_cron"; then
        msg_warn "$(L MSG_SYS_1558)"
      else
        (crontab -l 2>/dev/null; echo "$backup_cron") | crontab -
        msg_ok "$(L MSG_SYS_1559)"
        _log_write "$(L MSG_SYS_1560)"
      fi
      ;;
    5)
      local clean_cron="0 4 * * 0 journalctl --vacuum-time=7d && rm -rf /tmp/*.tmp"
      if crontab -l 2>/dev/null | grep -qF "$clean_cron"; then
        msg_warn "$(L MSG_SYS_1561)"
      else
        (crontab -l 2>/dev/null; echo "$clean_cron") | crontab -
        msg_ok "$(L MSG_SYS_1562)"
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
  msg_title "$(L MSG_SYS_1563)"
  msg ""

  msg "$(L MSG_SYS_1564 "${F_BOLD}" "${F_RESET}")"
  lsblk -f 2>/dev/null || fdisk -l 2>/dev/null | head -20

  msg ""
  msg "$(L MSG_SYS_1565 "${F_BOLD}" "${F_RESET}")"
  df -hT 2>/dev/null | awk 'NR<=10{printf "  %-20s %-8s %-8s %-8s %-5s %s\n", $1, $2, $3, $4, $5, $7}'

  msg ""
  msg "$(L MSG_SYS_1566 "${F_BOLD}" "${F_RESET}")"
  df -i / 2>/dev/null | awk 'NR==2{printf "$(L MSG_SYS_1567)", $2, $3, $4, $5}'

  msg ""
  msg "$(L MSG_SYS_1568)"
  msg "$(L MSG_SYS_1569)"
  msg "$(L MSG_SYS_1570)"
  msg "$(L MSG_SYS_1571)"
  msg "$(L MSG_SYS_1572)"
  msg "$(L MSG_SYS_1573)"
  msg "$(L MSG_SYS_1574)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" disk_choice

  case "$disk_choice" in
    1)
      read -p "$(L MSG_SYS_1575)" disk_dev
      if [[ -b "$disk_dev" ]]; then
        msg_warn "$(L MSG_SYS_1576)"
        fdisk "$disk_dev"
      else
        msg_err "$(L MSG_SYS_1577 "$disk_dev")"
      fi
      ;;
    2)
      read -p "$(L MSG_SYS_1578)" part_dev
      if [[ -b "$part_dev" ]]; then
        local fs_type; fs_type=$(select_option "$(L MSG_SYS_1579)" "$(L MSG_SYS_1580)" "xfs" "btrfs")
        msg_warn "$(L MSG_SYS_1581 "$part_dev")"
        local confirm_input=""
        read -r -p "$(L MSG_SYS_1582 "$part_dev")" confirm_input
        if [[ "$confirm_input" == "YES" ]]; then
          case "$fs_type" in
            1) mkfs.ext4 "$part_dev" ;;
            2) mkfs.xfs "$part_dev" ;;
            3) mkfs.btrfs "$part_dev" ;;
            *) mkfs.ext4 "$part_dev" ;;
          esac
          msg_ok "$(L MSG_SYS_1583)"
        else
          msg_warn "$(L MSG_SYS_1584)"
        fi
      fi
      ;;
    3)
      read -p "$(L MSG_SYS_1585)" part_dev
      read -p "$(L MSG_SYS_1586)" mount_point
      if [[ -b "$part_dev" && -n "$mount_point" ]]; then
        mkdir -p "$mount_point"
        mount "$part_dev" "$mount_point"
        if grep -qE "^[[:space:]]*${part_dev}([[:space:]]|\$)" /etc/fstab 2>/dev/null || \
           grep -qE "^[[:space:]]*[^[:space:]]+[[:space:]]+${mount_point}([[:space:]]|\$)" /etc/fstab 2>/dev/null; then
          msg_warn "$(L MSG_SYS_1587 "$part_dev" "$mount_point")"
        else
          echo "$part_dev $mount_point auto defaults 0 2" >> /etc/fstab
          msg_ok "$(L MSG_SYS_1588 "$part_dev" "$mount_point")"
        fi
      fi
      ;;
    4)
      read -p "$(L MSG_SYS_1589)" mount_point
      if [[ -n "$mount_point" ]]; then
        umount "$mount_point" 2>/dev/null && msg_ok "$(L MSG_SYS_1590 "$mount_point")" || msg_err "$(L MSG_SYS_1591)"
      fi
      ;;
    5)
      read -p "$(L MSG_SYS_1592)" disk_dev
      read -p "$(L MSG_SYS_1593)" part_num
      if [[ -b "$disk_dev" && -n "$part_num" ]]; then
        _install_pkg cloud-guest-utils 2>/dev/null || _install_pkg cloud-utils-growpart 2>/dev/null
        growpart "$disk_dev" "$part_num" 2>/dev/null && msg_ok "$(L MSG_SYS_1594)" || msg_err "$(L MSG_SYS_1595)"
        # Auto resize filesystem
        local part_dev="${disk_dev}${part_num}"
        if [[ -b "$part_dev" ]]; then
          resize2fs "$part_dev" 2>/dev/null || xfs_growfs "$part_dev" 2>/dev/null || true
          msg_ok "$(L MSG_SYS_1596)"
        fi
      fi
      ;;
    6)
      msg_info "$(L MSG_SYS_1597)"
      find / -type f -size +100M -exec du -h {} + 2>/dev/null | sort -rh | head -20
      ;;
    7)
      read -p "$(L MSG_SYS_1598)" dir_path
      dir_path=${dir_path:-/}
      du -h --max-depth=2 "$dir_path" 2>/dev/null | sort -rh | head -20
      ;;
  esac
  pause
}

# ---- 时区管理 ----
# G07 时区预设：按区域分组的 20+ 常用城市。
# 格式: "区域|IANA 时区标识|城市显示名"
# 新增城市只需在此追加一行，菜单/校验/写入逻辑无需改动（数据驱动）。
SYSTEM_TZ_PRESETS=(
  "$(L MSG_SYS_1599)"
  "$(L MSG_SYS_1600)"
  "$(L MSG_SYS_1601)"
  "$(L MSG_SYS_1602)"
  "$(L MSG_SYS_1603)"
  "$(L MSG_SYS_1604)"
  "$(L MSG_SYS_1605)"
  "$(L MSG_SYS_1606)"
  "$(L MSG_SYS_1607)"
  "$(L MSG_SYS_1608)"
  "$(L MSG_SYS_1609)"
  "$(L MSG_SYS_1610)"
  "$(L MSG_SYS_1611)"
  "$(L MSG_SYS_1612)"
  "$(L MSG_SYS_1613)"
  "$(L MSG_SYS_1614)"
  "$(L MSG_SYS_1615)"
  "$(L MSG_SYS_1616)"
  "$(L MSG_SYS_1617)"
  "$(L MSG_SYS_1618)"
  "$(L MSG_SYS_1619)"
  "$(L MSG_SYS_1620)"
  "$(L MSG_SYS_1621)"
  "$(L MSG_SYS_1622)"
  "$(L MSG_SYS_1623)"
  "$(L MSG_SYS_1624)"
  "$(L MSG_SYS_1625)"
  "$(L MSG_SYS_1626)"
  "$(L MSG_SYS_1627)"
)

# 应用时区：先做格式与存在性校验，再 timedatectl，失败时软链接兜底。
# 校验的目的不是防呆，而是防路径穿越（如 `../../etc/passwd` 被写进 /etc/timezone）。
_system_tz_apply() {
  local tz="$1"
  [[ -n "$tz" ]] || { msg_err "$(L MSG_SYS_1628)"; return 1; }
  [[ "$tz" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || {
    msg_err "$(L MSG_SYS_1629 "$tz")"; return 1; }
  [[ -f "/usr/share/zoneinfo/$tz" ]] || {
    msg_err "$(L MSG_SYS_1630 "$tz")"; return 1; }
  if command -v timedatectl &>/dev/null && timedatectl set-timezone "$tz" 2>/dev/null; then
    return 0
  fi
  ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime || return 1
  printf '%s\n' "$tz" > /etc/timezone 2>/dev/null || true
  return 0
}

_system_tz_sync() {
  _install_pkg ntp 2>/dev/null || _install_pkg chrony 2>/dev/null || true
  if command -v ntpdate &>/dev/null; then
    ntpdate pool.ntp.org 2>/dev/null && msg_ok "$(L MSG_SYS_1631)"
  elif command -v chronyc &>/dev/null; then
    chronyc makestep 2>/dev/null && msg_ok "$(L MSG_SYS_1631)"
  elif command -v timedatectl &>/dev/null; then
    timedatectl set-ntp true 2>/dev/null && msg_ok "$(L MSG_SYS_1632)"
  else
    msg_warn "$(L MSG_SYS_1633)"
  fi
  msg "$(L MSG_SYS_1634 "$(date '+%Y-%m-%d %H:%M:%S')")"
}

system_timezone() {
  _require_root
  msg_title "$(L MSG_SYS_1635)"
  msg ""

  msg "$(L MSG_SYS_1636 "${F_BOLD}" "${F_RESET}" "$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3, $4}' || cat /etc/timezone 2>/dev/null || date +%Z)")"
  msg "$(L MSG_SYS_1637 "${F_BOLD}" "${F_RESET}" "$(date '+%Y-%m-%d %H:%M:%S %Z')")"
  msg ""

  local idx=0 region="" last_region="" entry tz_id tz_label tz_choice custom_tz
  for entry in "${SYSTEM_TZ_PRESETS[@]}"; do
    region="${entry%%|*}"
    if [[ "$region" != "$last_region" ]]; then
      [[ -n "$last_region" ]] && msg ""
      msg "  ${F_BOLD}[$region]${F_RESET}"
      last_region="$region"
    fi
    idx=$((idx + 1))
    tz_id="${entry#*|}"; tz_id="${tz_id%%|*}"
    tz_label="${entry##*|}"
    msg "  $(printf '%2d' "$idx")) ${tz_label}  ${F_CYAN}${tz_id}${F_RESET}"
  done

  msg ""
  msg "$(L MSG_SYS_1638 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1639 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_SYS_1640 "${F_BOLD}" "${F_RESET}")"
  msg ""
  read -r -p "$(L MSG_SYS_1322)" tz_choice || { msg ""; return 0; }

  # 预设：纯数字且落在范围内
  if [[ "$tz_choice" =~ ^[0-9]+$ ]] && (( tz_choice >= 1 && tz_choice <= ${#SYSTEM_TZ_PRESETS[@]} )); then
    entry="${SYSTEM_TZ_PRESETS[$((tz_choice - 1))]}"
    tz_id="${entry#*|}"; tz_id="${tz_id%%|*}"
    tz_label="${entry##*|}"
    if _system_tz_apply "$tz_id"; then
      msg_ok "$(L MSG_SYS_1641 "$tz_label" "$tz_id")"
      _log_write "$(L MSG_SYS_1642 "$tz_id")"
    fi
    pause
    return 0
  fi

  case "${tz_choice,,}" in
    c|custom)
      read -r -p "$(L MSG_SYS_1643)" custom_tz || return 0
      if [[ -n "$custom_tz" ]]; then
        if _system_tz_apply "$custom_tz"; then
          msg_ok "$(L MSG_SYS_1644 "$custom_tz")"
          _log_write "$(L MSG_SYS_1642 "$custom_tz")"
        fi
      fi
      pause
      ;;
    n|ntp)
      _system_tz_sync
      pause
      ;;
    ""|0) return 0 ;;
    *)
      msg_err "$(L MSG_SYS_1645 "$tz_choice")"
      pause
      ;;
  esac
}

# ---- 回收站管理 ----
system_trash() {
  _require_root
  local trash_dir="/root/.fusionbox_trash"
  mkdir -p "$trash_dir"

  msg_title "$(L MSG_SYS_1646)"
  msg ""

  local trash_count=$(find "$trash_dir" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
  msg "$(L MSG_SYS_1647 "${F_BOLD}" "${F_RESET}" "$trash_dir")"
  msg "$(L MSG_SYS_1648 "${F_BOLD}" "${F_RESET}" "$trash_count")"

  if [[ $trash_count -gt 0 ]]; then
    msg ""
    msg "$(L MSG_SYS_1649 "${F_BOLD}" "${F_RESET}")"
    ls -lhrt "$trash_dir" 2>/dev/null | tail -10 | awk '{printf "  %s %s %s %s\n", $6, $7, $5, $9}'
  fi

  msg ""
  msg "$(L MSG_SYS_1650)"
  msg "$(L MSG_SYS_1651)"
  msg "$(L MSG_SYS_1652)"
  msg "$(L MSG_SYS_1653)"
  msg "$(L MSG_SYS_1321)"
  read -p "$(L MSG_SYS_1322)" trash_choice

  case "$trash_choice" in
    1)
      read -p "$(L MSG_SYS_1654)" target_path
      if [[ -e "$target_path" ]]; then
        local trash_name="$(basename "$target_path")_$(date +%s)"
        mv "$target_path" "$trash_dir/$trash_name"
        msg_ok "$(L MSG_SYS_1655 "$target_path" "$trash_dir" "$trash_name")"
        _log_write "$(L MSG_SYS_1656 "$target_path")"
      else
        msg_err "$(L MSG_SYS_1657 "$target_path")"
      fi
      ;;
    2)
      if [[ $trash_count -eq 0 ]]; then
        msg "$(L MSG_SYS_1658)"
      else
        ls -lhrt "$trash_dir" | tail -10 | nl -ba
        read -p "$(L MSG_SYS_1659)" restore_name
        if [[ -e "$trash_dir/$restore_name" ]]; then
          read -p "$(L MSG_SYS_1660)" restore_path
          mv "$trash_dir/$restore_name" "$restore_path"
          msg_ok "$(L MSG_SYS_1661 "$restore_path")"
        fi
      fi
      ;;
    3)
      if confirm "$(L MSG_SYS_1662)"; then
        rm -rf "$trash_dir"/*
        msg_ok "$(L MSG_SYS_1663)"
        _log_write "$(L MSG_SYS_1663)"
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
    echo "$(L MSG_SYS_1664)"
  else
    echo "$(L MSG_SYS_1665)"
  fi
}

# 用法: _system_dns_apply <标签> <DNS1> [DNS2...]
_system_dns_apply() {
  if [[ -L /etc/resolv.conf ]] || systemctl is-active systemd-resolved >/dev/null 2>&1; then
    msg_err "$(L MSG_SYS_1666)"; return 1
  fi
  local label="$1"; shift
  local -a servers=("$@")
  local s

  if [[ ${#servers[@]} -eq 0 ]]; then
    msg_err "$(L MSG_SYS_1667)"
    return 1
  fi
  for s in "${servers[@]}"; do
    if [[ ! "$s" =~ ^[0-9a-fA-F:.]+$ ]] || ! python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$s" 2>/dev/null; then
      msg_err "$(L MSG_SYS_1668 "$s")"
      return 1
    fi
  done

  msg ""
  msg_info "$(L MSG_SYS_1669 "$label")"
  for s in "${servers[@]}"; do msg "    nameserver $s"; done

  if systemctl is-active systemd-resolved &>/dev/null; then
    msg_warn "$(L MSG_SYS_1670)"
    msg_warn "$(L MSG_SYS_1671)"
  fi
  if [[ -L /etc/resolv.conf ]]; then
    msg_warn "$(L MSG_SYS_1672)"
  fi

  confirm "$(L MSG_SYS_1673)" || return 1

  local bak="/etc/resolv.conf.fb-bak-$(date +%s)"
  if [[ -e /etc/resolv.conf ]]; then
    if ! _fb_backup_file /etc/resolv.conf "$bak"; then
      msg_err "$(L MSG_SYS_1674)"
      return 1
    fi
    msg_ok "$(L MSG_SYS_1675 "$bak")"
  fi

  local staged
  staged=$(mktemp /etc/.fusionbox-dns.XXXXXXXX) || return 1
  if ! printf 'nameserver %s\n' "${servers[@]}" > "$staged" ||
     ! chmod 644 "$staged"; then
    rm -f "$staged"; return 1
  fi

  if [[ ! -L /etc/resolv.conf ]] && mv -T "$staged" /etc/resolv.conf; then
    msg_ok "$(L MSG_SYS_1676 "$label")"
    msg "$(L MSG_SYS_1677)"
    grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r s; do msg "    $s"; done
    _log_write "$(L MSG_SYS_1678 "$label")"
  else
    msg_err "$(L MSG_SYS_1679)"
    rm -f "$staged"
    return 1
  fi
  return 0
}

_system_dns_restore() {
  if [[ -L /etc/resolv.conf ]] || systemctl is-active systemd-resolved >/dev/null 2>&1; then
    msg_err "$(L MSG_SYS_1680)"; return 1
  fi
  local -a baks=()
  local f
  while IFS= read -r f; do baks+=("$f"); done < <(ls -1t /etc/resolv.conf.fb-bak-* 2>/dev/null)

  if [[ ${#baks[@]} -eq 0 ]]; then
    msg_warn "$(L MSG_SYS_1681)"
    return 1
  fi

  msg ""
  msg_info "$(L MSG_SYS_1294)"
  local i=1
  for f in "${baks[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) $(basename "$f")"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "$(L MSG_SYS_1682)" "1") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_SYS_1683)"; return 1; }
  local idx=$((sel - 1))
  if [[ $idx -lt 0 || $idx -ge ${#baks[@]} ]]; then
    msg_err "$(L MSG_SYS_1684 "${#baks[@]}")"
    return 1
  fi

  confirm "$(L MSG_SYS_1685 "$(basename "${baks[$idx]}")")" || return 1
  local staged
  staged=$(mktemp /etc/.fusionbox-dns.XXXXXXXX) || return 1
  if [[ ! -L /etc/resolv.conf ]] &&
     cp -- "${baks[$idx]}" "$staged" && chmod 644 "$staged" &&
     mv -T "$staged" /etc/resolv.conf; then
    msg_ok "$(L MSG_SYS_1686 "${baks[$idx]}")"
    grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r f; do msg "    $f"; done
    _log_write "$(L MSG_SYS_1687)"
  else
    msg_err "$(L MSG_SYS_1688)"
    return 1
  fi
}

system_dns() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1689)"
    msg ""
    msg "$(L MSG_SYS_1690 "${F_BOLD}" "${F_RESET}")"
    if [[ -f /etc/resolv.conf ]] && grep -qE "^[[:space:]]*nameserver" /etc/resolv.conf 2>/dev/null; then
      grep -E "^[[:space:]]*nameserver" /etc/resolv.conf 2>/dev/null | while IFS= read -r line; do msg "    $line"; done
    else
      msg "$(L MSG_SYS_1691)"
    fi
    msg "$(L MSG_SYS_1692 "${F_BOLD}" "${F_RESET}" "$(_system_dns_lock_status)")"
    if systemctl is-active systemd-resolved &>/dev/null; then
      msg "$(L MSG_SYS_1693 "${F_YELLOW}" "${F_RESET}")"
    fi
    msg ""
    msg "$(L MSG_SYS_1694 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1695 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1696 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1697 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1698 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1699 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1700)" dns_choice || { msg ""; break; }

    case "$dns_choice" in
      1)
        msg ""
        msg "$(L MSG_SYS_1701)"
        msg "$(L MSG_SYS_1702)"
        msg "$(L MSG_SYS_1703)"
        msg "    3) 114DNS      114.114.114.114"
        local cn_sel=""; cn_sel=$(read_input "$(L MSG_SYS_1704)" "1")
        case "$cn_sel" in
          2) _system_dns_apply "$(L MSG_SYS_1705)" 119.29.29.29 ;;
          3) _system_dns_apply "114DNS" 114.114.114.114 ;;
          *) _system_dns_apply "$(L MSG_SYS_1706)" 223.5.5.5 223.6.6.6 ;;
        esac
        pause ;;
      2)
        msg ""
        msg "$(L MSG_SYS_1707)"
        msg "    1) Cloudflare  1.1.1.1 / 1.0.0.1"
        msg "    2) Google      8.8.8.8 / 8.8.4.4"
        msg "    3) Quad9       9.9.9.9"
        local intl_sel=""; intl_sel=$(read_input "$(L MSG_SYS_1704)" "1")
        case "$intl_sel" in
          2) _system_dns_apply "Google DNS" 8.8.8.8 8.8.4.4 ;;
          3) _system_dns_apply "Quad9" 9.9.9.9 ;;
          *) _system_dns_apply "Cloudflare" 1.1.1.1 1.0.0.1 ;;
        esac
        pause ;;
      3)
        msg ""
        msg_info "$(L MSG_SYS_1708)"
        local -a custom_dns=()
        while [[ ${#custom_dns[@]} -lt 4 ]]; do
          local one_dns=""; one_dns=$(read_input "$(L MSG_SYS_1709)" "") || break
          [[ -z "$one_dns" ]] && break
          if [[ ! "$one_dns" =~ ^[0-9a-fA-F:.]+$ ]]; then
            msg_err "$(L MSG_SYS_1710 "$one_dns")"
            continue
          fi
          custom_dns+=("$one_dns")
        done
        if [[ ${#custom_dns[@]} -eq 0 ]]; then
          msg_warn "$(L MSG_SYS_1711)"
        else
          _system_dns_apply "$(L MSG_SYS_1712)" "${custom_dns[@]}"
        fi
        pause ;;
      4)
        if ! command -v chattr &>/dev/null; then
          msg_err "$(L MSG_SYS_1713)"
        elif chattr +i /etc/resolv.conf 2>/dev/null; then
          msg_ok "$(L MSG_SYS_1714)"
          _log_write "$(L MSG_SYS_1715)"
        else
          msg_err "$(L MSG_SYS_1716)"
        fi
        pause ;;
      5)
        if chattr -i /etc/resolv.conf 2>/dev/null; then
          msg_ok "$(L MSG_SYS_1717)"
          _log_write "$(L MSG_SYS_1718)"
        else
          msg_err "$(L MSG_SYS_1719)"
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
  msg_title "$(L MSG_SYS_1720)"
  msg ""

  local cur; cur=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)
  msg "$(L MSG_SYS_1721 "${F_BOLD}" "${F_RESET}" "${cur:-未知}")"
  msg ""

  local newname; newname=$(read_input "$(L MSG_SYS_1722)" "") || { pause; return 1; }
  newname="${newname// /}"
  if [[ -z "$newname" ]]; then
    msg_err "$(L MSG_SYS_1723)"
    pause; return 1
  fi
  if [[ ! "$newname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
    msg_err "$(L MSG_SYS_1724)"
    pause; return 1
  fi
  if [[ "$newname" == "$cur" ]]; then
    msg_warn "$(L MSG_SYS_1725)"
    pause; return 0
  fi
  if ! confirm "$(L MSG_SYS_1726 "$cur" "$newname")"; then
    pause; return 1
  fi

  local set_ok=0
  if command -v hostnamectl &>/dev/null && hostnamectl set-hostname "$newname" 2>/dev/null; then
    set_ok=1
    msg_ok "$(L MSG_SYS_1727)"
  else
    _fb_backup_file /etc/hostname "/etc/hostname.fb-bak-$(date +%s)" >/dev/null 2>&1
    if echo "$newname" > /etc/hostname 2>/dev/null; then
      set_ok=1
      msg_ok "$(L MSG_SYS_1728)"
    fi
  fi
  if [[ $set_ok -eq 0 ]]; then
    msg_err "$(L MSG_SYS_1729)"
    pause; return 1
  fi

  # 同步 /etc/hosts 中的 127.0.1.1 记录
  if [[ -f /etc/hosts ]]; then
    _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
    if grep -qE "^127\.0\.1\.1([[:space:]]|$)" /etc/hosts 2>/dev/null; then
      sed -i -E "s|^127\.0\.1\.1([[:space:]]).*|127.0.1.1\t$newname|" /etc/hosts
      msg_info "$(L MSG_SYS_1730)"
    else
      echo -e "127.0.1.1\t$newname" >> /etc/hosts
      msg_info "$(L MSG_SYS_1731)"
    fi
  fi

  msg ""
  msg "$(L MSG_SYS_1721 "${F_BOLD}" "${F_RESET}" "$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null)")"
  msg "  ${F_BOLD}/etc/hostname:${F_RESET} $(cat /etc/hostname 2>/dev/null)"
  msg_tip "$(L MSG_SYS_1732)"
  _log_write "$(L MSG_SYS_1733 "$newname")"
  pause
}

# ---- hosts 解析管理 ----
# 输出 "行号: 内容"，仅非注释、非空行
_system_hosts_entries() {
  awk 'NF && $1 !~ /^#/ {print NR": "$0}' /etc/hosts 2>/dev/null
}

_system_hosts_show() {
  msg "$(L MSG_SYS_1734 "${F_BOLD}" "${F_RESET}")"
  local -a entries=()
  local line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done < <(_system_hosts_entries)
  if [[ ${#entries[@]} -eq 0 ]]; then
    msg "$(L MSG_SYS_1735)"
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
  ip=$(read_input "$(L MSG_SYS_1736)" "") || return 1
  if [[ ! "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
    msg_err "$(L MSG_SYS_1737 "$ip")"
    return 1
  fi
  host=$(read_input "$(L MSG_SYS_1738)" "") || return 1
  if [[ ! "$host" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,62}$ ]]; then
    msg_err "$(L MSG_SYS_1739 "$host")"
    return 1
  fi
  if [[ -f /etc/hosts ]] && awk -v ip="$ip" -v h="$host" \
      'NF && $1 !~ /^#/ && $1==ip {for(i=2;i<=NF;i++) if($i==h) f=1} END{exit !f}' /etc/hosts; then
    msg_warn "$(L MSG_SYS_1740 "$ip" "$host")"
    return 1
  fi

  confirm "$(L MSG_SYS_1741 "$ip" "$host")" || return 1
  _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
  if echo -e "$ip\t$host" >> /etc/hosts 2>/dev/null; then
    msg_ok "$(L MSG_SYS_1742 "$ip" "$host")"
    _log_write "$(L MSG_SYS_1743 "$ip" "$host")"
  else
    msg_err "$(L MSG_SYS_1744)"
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
    msg_warn "$(L MSG_SYS_1745)"
    return 1
  fi

  msg "$(L MSG_SYS_1746 "${F_BOLD}" "${F_RESET}")"
  local i=1
  for line in "${entries[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) ${line#*: }"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "$(L MSG_SYS_1747)" "0") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_SYS_1748)"; return 1; }
  [[ "$sel" -eq 0 ]] && return 1
  if [[ "$sel" -lt 1 || "$sel" -gt ${#entries[@]} ]]; then
    msg_err "$(L MSG_SYS_1749 "${#entries[@]}")"
    return 1
  fi

  local target="${entries[$((sel - 1))]}"
  local lineno="${target%%:*}"
  local content="${target#*: }"

  confirm "$(L MSG_SYS_1750 "$content")" || return 1
  _fb_backup_file /etc/hosts "/etc/hosts.fb-bak-$(date +%s)" >/dev/null 2>&1
  if sed -i "${lineno}d" /etc/hosts 2>/dev/null; then
    msg_ok "$(L MSG_SYS_1751 "$content")"
    _log_write "$(L MSG_SYS_1752 "$content")"
  else
    msg_err "$(L MSG_SYS_1753)"
    return 1
  fi
  return 0
}

system_hosts() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1754)"
    msg ""
    _system_hosts_show
    msg ""
    msg "$(L MSG_SYS_1755 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1756 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1757 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1758)" hosts_choice || { msg ""; break; }
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
    msg_warn "$(L MSG_SYS_1759 "$dir")"
    return 1
  fi
  local flat orig rc=0
  while IFS=$'\t' read -r flat orig; do
    [[ -z "$flat" || -z "$orig" ]] && continue
    [[ -f "$dir/$flat" ]] || continue
    if ! cp -Lp "$dir/$flat" "$orig" 2>/dev/null; then
      msg_err "$(L MSG_SYS_1760 "$orig")"
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
    msg_warn "$(L MSG_SYS_1761)"
    return 1
  fi

  local matched=0
  for f in "${files[@]}"; do
    if grep -qE "archive\.ubuntu\.com|security\.ubuntu\.com|deb\.debian\.org|security\.debian\.org" "$f" 2>/dev/null; then
      matched=1
    fi
  done
  if [[ $matched -eq 0 ]]; then
    msg_warn "$(L MSG_SYS_1762)"
    msg "$(L MSG_SYS_1763)"
    return 1
  fi

  msg ""
  msg_info "$(L MSG_SYS_1764 "$host")"
  for f in "${files[@]}"; do msg "    $f"; done
  msg_warn "$(L MSG_SYS_1765)"
  confirm "$(L MSG_SYS_1766 "$label")" || return 1

  local bak_dir="/etc/fusionbox/mirror-bak-$(date +%s)"
  mkdir -p "$bak_dir" || { msg_err "$(L MSG_SYS_1767 "$bak_dir")"; return 1; }
  : > "$bak_dir/files.manifest"
  for f in "${files[@]}"; do
    local flat="${f//\//_}"
    if ! cp -Lp "$f" "$bak_dir/$flat" 2>/dev/null; then
      msg_err "$(L MSG_SYS_1768 "$f")"
      return 1
    fi
    printf '%s\t%s\n' "$flat" "$f" >> "$bak_dir/files.manifest"
  done
  msg_ok "$(L MSG_SYS_1769 "$bak_dir")"

  for f in "${files[@]}"; do
    sed -i -E "s/archive\.ubuntu\.com/$host/g; s/security\.ubuntu\.com/$host/g; s/deb\.debian\.org/$host/g; s/security\.debian\.org/$host/g" "$f" 2>/dev/null
  done

  msg_info "$(L MSG_SYS_1770)"
  local out
  if out=$(apt-get update -y 2>&1); then
    msg_ok "$(L MSG_SYS_1771 "$label" "$host")"
    _log_write "$(L MSG_SYS_1772 "$label" "$host")"
  else
    msg_err "$(L MSG_SYS_1773)"
    echo "$out" | tail -8 | sed 's/^/    /'
    if _system_mirror_restore_dir "$bak_dir"; then
      msg_warn "$(L MSG_SYS_1774 "$bak_dir")"
      _log_write "$(L MSG_SYS_1775 "$label")"
    else
      msg_err "$(L MSG_SYS_1776 "$bak_dir")"
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
    msg_warn "$(L MSG_SYS_1777)"
    return 1
  fi

  local matched=0
  for f in "${files[@]}"; do
    if grep -qE "mirror(list)?\.centos\.org|mirrors\.centos\.org" "$f" 2>/dev/null; then
      matched=1
    fi
  done
  if [[ $matched -eq 0 ]]; then
    msg_warn "$(L MSG_SYS_1778)"
    return 1
  fi

  msg ""
  msg_info "$(L MSG_SYS_1764 "$host")"
  for f in "${files[@]}"; do msg "    $f"; done
  msg_warn "$(L MSG_SYS_1779)"
  confirm "$(L MSG_SYS_1766 "$label")" || return 1

  local bak_dir="/etc/fusionbox/mirror-bak-$(date +%s)"
  mkdir -p "$bak_dir" || { msg_err "$(L MSG_SYS_1767 "$bak_dir")"; return 1; }
  : > "$bak_dir/files.manifest"
  for f in "${files[@]}"; do
    local flat="${f//\//_}"
    if ! cp -Lp "$f" "$bak_dir/$flat" 2>/dev/null; then
      msg_err "$(L MSG_SYS_1768 "$f")"
      return 1
    fi
    printf '%s\t%s\n' "$flat" "$f" >> "$bak_dir/files.manifest"
  done
  msg_ok "$(L MSG_SYS_1769 "$bak_dir")"

  for f in "${files[@]}"; do
    sed -i -E "s/mirrorlist\.centos\.org/$host/g; s/mirror\.centos\.org/$host/g; s/mirrors\.centos\.org/$host/g" "$f" 2>/dev/null
  done

  msg_info "$(L MSG_SYS_1780)"
  local out rc=0
  if command -v dnf &>/dev/null; then
    out=$(dnf makecache -y 2>&1) || rc=1
  else
    out=$(yum makecache -y 2>&1) || rc=1
  fi
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_SYS_1771 "$label" "$host")"
    _log_write "$(L MSG_SYS_1781 "$label" "$host")"
  else
    msg_err "$(L MSG_SYS_1782)"
    echo "$out" | tail -8 | sed 's/^/    /'
    if _system_mirror_restore_dir "$bak_dir"; then
      msg_warn "$(L MSG_SYS_1774 "$bak_dir")"
      _log_write "$(L MSG_SYS_1783 "$label")"
    else
      msg_err "$(L MSG_SYS_1776 "$bak_dir")"
    fi
  fi
  return 0
}

_system_mirror_restore() {
  local -a dirs=()
  local d
  while IFS= read -r d; do dirs+=("$d"); done < <(ls -1dt /etc/fusionbox/mirror-bak-* 2>/dev/null)

  if [[ ${#dirs[@]} -eq 0 ]]; then
    msg_warn "$(L MSG_SYS_1784)"
    return 1
  fi

  msg "$(L MSG_SYS_1785 "${F_BOLD}" "${F_RESET}")"
  local i=1
  for d in "${dirs[@]}"; do
    msg "  ${F_GREEN}$i${F_RESET}) $d"
    i=$((i + 1))
  done

  local sel; sel=$(read_input "$(L MSG_SYS_1682)" "1") || return 1
  [[ "$sel" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_SYS_1683)"; return 1; }
  local idx=$((sel - 1))
  if [[ $idx -lt 0 || $idx -ge ${#dirs[@]} ]]; then
    msg_err "$(L MSG_SYS_1684 "${#dirs[@]}")"
    return 1
  fi

  confirm "$(L MSG_SYS_1786 "${dirs[$idx]}")" || return 1
  if _system_mirror_restore_dir "${dirs[$idx]}"; then
    msg_ok "$(L MSG_SYS_1787)"
    case "$(_system_mirror_detect)" in
      apt)
        if apt-get update -y >/dev/null 2>&1; then
          msg_ok "$(L MSG_SYS_1788)"
        else
          msg_warn "$(L MSG_SYS_1789)"
        fi
        ;;
      yum)
        if command -v dnf &>/dev/null; then
          dnf makecache -y >/dev/null 2>&1 || msg_warn "$(L MSG_SYS_1790)"
        else
          yum makecache -y >/dev/null 2>&1 || msg_warn "$(L MSG_SYS_1790)"
        fi
        ;;
    esac
    _log_write "$(L MSG_SYS_1791 "${dirs[$idx]}")"
  else
    msg_err "$(L MSG_SYS_1792 "${dirs[$idx]}")"
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
      msg_warn "$(L MSG_SYS_1793)"
      ;;
  esac
}

system_mirror() {
  _require_root
  local kind; kind=$(_system_mirror_detect)
  if [[ "$kind" == "none" ]]; then
    msg_warn "$(L MSG_SYS_1794)"
    pause
    return 1
  fi

  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1795)"
    msg ""
    msg "$(L MSG_SYS_1796 "${F_BOLD}" "${F_RESET}" "$kind")"
    msg "$(L MSG_SYS_1797 "${F_BOLD}" "${F_RESET}")"
    msg ""
    if [[ "$kind" == "apt" ]]; then
      msg "$(L MSG_SYS_1798 "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1799 "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1800 "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1801 "${F_GREEN}" "${F_RESET}")"
    else
      msg "$(L MSG_SYS_1798 "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1799 "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1802 "${F_YELLOW}" "${F_RESET}")"
    fi
    msg "$(L MSG_SYS_1803 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1804 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1700)" mirror_choice || { msg ""; break; }

    case "$mirror_choice" in
      1)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.aliyun.com" "$(L MSG_SYS_1805)"
        else
          _system_mirror_apply_yum "mirrors.aliyun.com" "$(L MSG_SYS_1805)"
        fi
        pause ;;
      2)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.tuna.tsinghua.edu.cn" "$(L MSG_SYS_1806)"
        else
          _system_mirror_apply_yum "mirrors.tuna.tsinghua.edu.cn" "$(L MSG_SYS_1806)"
        fi
        pause ;;
      3)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.ustc.edu.cn" "$(L MSG_SYS_1807)"
        else
          msg_warn "$(L MSG_SYS_1808)"
        fi
        pause ;;
      4)
        if [[ "$kind" == "apt" ]]; then
          _system_mirror_apply_apt "mirrors.huaweicloud.com" "$(L MSG_SYS_1809)"
        else
          msg_warn "$(L MSG_SYS_1808)"
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
  msg "$(L MSG_SYS_1810 "${F_BOLD}" "${F_RESET}")"
  if command -v journalctl &>/dev/null; then
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /' || msg "$(L MSG_SYS_1811)"
  else
    du -sh /var/log 2>/dev/null | awk '{print "    /var/log: " $1}'
  fi
  msg ""
  msg "$(L MSG_SYS_1812)"
  msg "$(L MSG_SYS_1813)"
  msg "$(L MSG_SYS_1814)"
  msg "$(L MSG_SYS_1815)"
  msg "$(L MSG_SYS_1816)"
  local sel; sel=$(read_input "$(L MSG_SYS_1704)" "0") || return 1

  local arg=""
  case "$sel" in
    1) arg="--vacuum-size=100M" ;;
    2) arg="--vacuum-size=500M" ;;
    3) arg="--vacuum-size=1G" ;;
    4) arg="--vacuum-time=7d" ;;
    *) return 0 ;;
  esac

  if ! command -v journalctl &>/dev/null; then
    msg_warn "$(L MSG_SYS_1817)"
    return 1
  fi
  confirm "$(L MSG_SYS_1818 "$arg")" || return 1
  if journalctl "$arg" 2>/dev/null; then
    msg_ok "$(L MSG_SYS_1819)"
    journalctl --disk-usage 2>/dev/null | sed 's/^/    /'
    _log_write "$(L MSG_SYS_1820 "$arg")"
  else
    msg_err "$(L MSG_SYS_1821)"
    return 1
  fi
  return 0
}

system_log() {
  _require_root
  # fusionbox system log fusionbox|--self  → FusionBox 自身日志（主菜单/帮助均可发现）
  case "${1:-}" in
    fusionbox|fb|--self|self) show_logs "${2:-200}"; pause; return 0 ;;
  esac
  local has_journal=0
  command -v journalctl &>/dev/null && has_journal=1

  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1822)"
    msg ""
    if [[ $has_journal -eq 1 ]]; then
      msg "$(L MSG_SYS_1823 "${F_BOLD}" "${F_RESET}")"
    else
      msg "$(L MSG_SYS_1824 "${F_BOLD}" "${F_RESET}" "${F_YELLOW}" "${F_RESET}")"
    fi
    msg ""
    msg "$(L MSG_SYS_1825 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1826 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1827 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1828 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1829 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1830 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1700)" log_choice || { msg ""; break; }

    case "$log_choice" in
      1)
        msg ""
        msg "$(L MSG_SYS_1831 "${F_BOLD}" "${F_RESET}")"
        if [[ $has_journal -eq 1 ]]; then
          journalctl -p 3 -n 50 --no-pager 2>/dev/null || msg_warn "$(L MSG_SYS_1832)"
        else
          tail -n 50 /var/log/messages 2>/dev/null || tail -n 50 /var/log/syslog 2>/dev/null || msg_warn "$(L MSG_SYS_1833)"
        fi
        pause ;;
      2)
        local unit; unit=$(read_input "$(L MSG_SYS_1834)" "") || { pause; continue; }
        if [[ ! "$unit" =~ ^[a-zA-Z0-9@._:-]+$ ]]; then
          msg_err "$(L MSG_SYS_1835 "$unit")"
        elif [[ $has_journal -eq 1 ]]; then
          msg ""
          journalctl -u "$unit" -n 100 --no-pager 2>/dev/null || msg_warn "$(L MSG_SYS_1836 "$unit")"
        else
          msg_warn "$(L MSG_SYS_1837)"
        fi
        pause ;;
      3)
        msg ""
        msg "$(L MSG_SYS_1838 "${F_BOLD}" "${F_RESET}")"
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
        msg_tip "$(L MSG_SYS_1839)"
        pause ;;
      4)
        msg ""
        msg "$(L MSG_SYS_1840 "${F_BOLD}" "${F_RESET}")"
        if command -v dmesg &>/dev/null; then
          dmesg 2>/dev/null | tail -40 || msg_warn "$(L MSG_SYS_1841)"
        elif [[ -f /var/log/dmesg ]]; then
          tail -40 /var/log/dmesg 2>/dev/null
        else
          msg_warn "$(L MSG_SYS_1842)"
        fi
        pause ;;
      5)
        _system_log_clean
        pause ;;
      6)
        if [[ $has_journal -eq 1 ]]; then
          msg_warn "$(L MSG_SYS_1843)"
          msg ""
          journalctl -f
        else
          msg_warn "$(L MSG_SYS_1843)"
          msg ""
          tail -f /var/log/messages 2>/dev/null || tail -f /var/log/syslog 2>/dev/null || msg_warn "$(L MSG_SYS_1844)"
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
  note="$(L MSG_SYS_1845 "${used_gb}" "${LIMIT_GB}" "$IFACE" "$ACTION")"
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
    shutdown -h +5 "$(L MSG_SYS_1846 "${LIMIT_GB}")" 2>/dev/null || exit 1
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

  msg "$(L MSG_SYS_1847 "${F_BOLD}" "${F_RESET}" "$iface" "$limit" "$action" "${interval}")"

  local cur
  if [[ "$iface" == "auto" ]]; then
    cur=$(awk '{gsub(":","",$1); if ($1=="lo" || $1 ~ /^docker/ || $1 ~ /^veth/ || $1 ~ /^br-/) next; rx+=$2; tx+=$10} END{printf "%.0f %.0f", rx, tx}' /proc/net/dev 2>/dev/null)
  else
    cur=$(awk -v i="$iface" '{gsub(":","",$1); if ($1==i) printf "%.0f %.0f", $2, $10}' /proc/net/dev 2>/dev/null)
  fi
  local now_rx now_tx
  now_rx=$(echo "$cur" | awk '{print $1+0}')
  now_tx=$(echo "$cur" | awk '{print $2+0}')
  msg "$(L MSG_SYS_1848 "${F_BOLD}" "${F_RESET}" "$(awk -v b="$now_rx" 'BEGIN{printf "%.2f", b/1073741824}')" "$(awk -v b="$now_tx" 'BEGIN{printf "%.2f", b/1073741824}')")"

  if [[ -f /var/lib/fusionbox/traffic-guard.state ]]; then
    local MONTH="" TOTAL=0 BASE_RX=0 BASE_TX=0 LAST_RUN=0
    . /var/lib/fusionbox/traffic-guard.state 2>/dev/null
    local used_gb; used_gb=$(awk -v b="${TOTAL:-0}" 'BEGIN{printf "%.3f", b/1073741824}')
    msg "$(L MSG_SYS_1849 "${F_BOLD}" "${F_RESET}" "${used_gb}" "${limit}" "${MONTH:-未知}")"
    local pct=0
    if [[ "$limit" =~ ^[0-9]+$ ]] && [[ "$limit" -gt 0 ]]; then
      pct=$(awk -v u="$used_gb" -v l="$limit" 'BEGIN{printf "%d", (u*100)/l}')
    fi
    msg "$(L MSG_SYS_1850 "${F_BOLD}" "${F_RESET}" "${pct}")"
  else
    msg "$(L MSG_SYS_1851 "${F_BOLD}" "${F_RESET}")"
  fi

  if [[ -f /var/lib/fusionbox/traffic-guard.shutdown ]]; then
    msg "$(L MSG_SYS_1852 "${F_YELLOW}" "${F_RESET}")"
  fi
  msg "$(L MSG_SYS_1853 "${F_BOLD}" "${F_RESET}" "$([[ -f /etc/cron.d/fusionbox-traffic-guard ]] && echo "已安装 (每 5 分钟)" || echo "未安装")")"
  msg "$(L MSG_SYS_1854 "${F_BOLD}" "${F_RESET}")"
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
    msg_title "$(L MSG_SYS_1855)"
    msg ""
    if [[ -x "$bin" && -f "$cron_file" ]]; then
      msg "$(L MSG_SYS_1856 "${F_BOLD}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1857 "${F_BOLD}" "${F_RESET}" "$(_traffic_guard_conf_get IFACE)")"
      msg "$(L MSG_SYS_1858 "${F_BOLD}" "${F_RESET}" "$(_traffic_guard_conf_get LIMIT_GB)")"
      msg "$(L MSG_SYS_1859 "${F_BOLD}" "${F_RESET}" "$(_traffic_guard_conf_get ACTION)")"
    else
      msg "$(L MSG_SYS_1860 "${F_BOLD}" "${F_RESET}" "${F_YELLOW}" "${F_RESET}")"
      msg_warn "$(L MSG_SYS_1861)"
    fi
    msg ""
    msg "$(L MSG_SYS_1862 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1863 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1864 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1865 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1866)" tg_choice || { msg ""; break; }

    case "$tg_choice" in
      1)
        msg ""
        local iface limit action interval act_sel
        iface=$(_traffic_guard_conf_get IFACE); iface=${iface:-auto}
        limit=$(_traffic_guard_conf_get LIMIT_GB); limit=${limit:-1000}
        action=$(_traffic_guard_conf_get ACTION); action=${action:-warn}
        interval=$(_traffic_guard_conf_get CHECK_INTERVAL_MIN); interval=${interval:-5}

        msg_tip "$(L MSG_SYS_1867)"
        iface=$(read_input "$(L MSG_SYS_1868)" "$iface") || { pause; continue; }
        if [[ "$iface" != "auto" && ! "$iface" =~ ^[a-zA-Z0-9._:-]+$ ]]; then
          msg_err "$(L MSG_SYS_1869 "$iface")"
          pause; continue
        fi
        limit=$(read_input "$(L MSG_SYS_1870)" "$limit") || { pause; continue; }
        if [[ ! "$limit" =~ ^[0-9]+$ ]] || [[ "$limit" -lt 1 ]]; then
          msg_err "$(L MSG_SYS_1871)"
          pause; continue
        fi
        interval=$(read_input "$(L MSG_SYS_1872)" "$interval") || { pause; continue; }
        if [[ ! "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -lt 1 ]]; then
          interval=5
          msg_warn "$(L MSG_SYS_1873)"
        fi

        msg ""
        msg "$(L MSG_SYS_1874)"
        act_sel=$(read_input "$(L MSG_SYS_1875)" "1") || { pause; continue; }
        if [[ "$act_sel" == "2" ]]; then
          msg_warn "$(L MSG_SYS_1876)"
          if confirm "$(L MSG_SYS_1877)" && confirm "$(L MSG_SYS_1878)"; then
            action="shutdown"
          else
            msg_info "$(L MSG_SYS_1879)"
            action="warn"
          fi
        else
          action="warn"
        fi

        _traffic_guard_conf_write "$iface" "$limit" "$action" "$interval"
        msg_ok "$(L MSG_SYS_1880 "$conf")"
        _traffic_guard_install_bin
        msg_ok "$(L MSG_SYS_1881)"
        msg_ok "$(L MSG_SYS_1882 "$cron_file")"
        if [[ "$action" == "shutdown" ]]; then
          msg_warn "$(L MSG_SYS_1883)"
        else
          msg_ok "$(L MSG_SYS_1884)"
        fi
        _log_write "$(L MSG_SYS_1885 "$iface" "${limit}" "$action")"
        pause ;;
      2)
        _traffic_guard_status
        pause ;;
      3)
        if [[ ! -f "$conf" ]]; then
          msg_warn "$(L MSG_SYS_1886)"
          pause; continue
        fi
        msg ""
        local n_limit n_action n_interval n_act
        n_limit=$(_traffic_guard_conf_get LIMIT_GB); n_limit=${n_limit:-1000}
        n_limit=$(read_input "$(L MSG_SYS_1887)" "$n_limit") || { pause; continue; }
        if [[ ! "$n_limit" =~ ^[0-9]+$ ]] || [[ "$n_limit" -lt 1 ]]; then
          msg_err "$(L MSG_SYS_1871)"
          pause; continue
        fi
        n_interval=$(_traffic_guard_conf_get CHECK_INTERVAL_MIN); n_interval=${n_interval:-5}
        n_interval=$(read_input "$(L MSG_SYS_1872)" "$n_interval") || { pause; continue; }
        [[ "$n_interval" =~ ^[0-9]+$ ]] && [[ "$n_interval" -ge 1 ]] || n_interval=5

        msg "$(L MSG_SYS_1888)"
        n_act=$(read_input "$(L MSG_SYS_1875)" "1") || { pause; continue; }
        n_action=$(_traffic_guard_conf_get ACTION); n_action=${n_action:-warn}
        if [[ "$n_act" == "2" ]]; then
          msg_warn "$(L MSG_SYS_1889)"
          if confirm "$(L MSG_SYS_1877)" && confirm "$(L MSG_SYS_1878)"; then
            n_action="shutdown"
          else
            n_action="warn"
            msg_info "$(L MSG_SYS_1879)"
          fi
        elif [[ "$n_act" == "1" ]]; then
          n_action="warn"
        fi

        local cur_iface; cur_iface=$(_traffic_guard_conf_get IFACE); cur_iface=${cur_iface:-auto}
        _traffic_guard_conf_write "$cur_iface" "$n_limit" "$n_action" "$n_interval"
        # 阈值变化后允许本周期内重新触发
        rm -f /var/lib/fusionbox/traffic-guard.shutdown 2>/dev/null
        msg_ok "$(L MSG_SYS_1890 "$n_limit" "$n_action" "${n_interval}")"
        _log_write "$(L MSG_SYS_1891 "${n_limit}" "$n_action")"
        pause ;;
      4)
        if ! confirm "$(L MSG_SYS_1892)"; then
          pause; continue
        fi
        rm -f "$bin" "$cron_file" /var/lib/fusionbox/traffic-guard.state /var/lib/fusionbox/traffic-guard.shutdown
        if confirm "$(L MSG_SYS_1893 "$conf")"; then
          rm -f "$conf"
          msg_ok "$(L MSG_SYS_1894)"
        else
          msg_ok "$(L MSG_SYS_1895)"
        fi
        _log_write "$(L MSG_SYS_1896)"
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
    msg_warn "$(L MSG_SYS_1897)"
    return 1
  fi

  if _fb_telegram_send "$token" "$chat" "$text"; then
    return 0
  fi
  msg_err "$(L MSG_SYS_1898)"
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
if [[ "$mem" =~ ^[0-9]+$ ]] && [[ "$mem" -ge "$ALERT_MEM" ]]; then alert="$(L MSG_SYS_1899 "${alert}" "${mem}")"; fi
if [[ "$disk" =~ ^[0-9]+$ ]] && [[ "$disk" -ge "$ALERT_DISK" ]]; then alert="$(L MSG_SYS_1900 "${alert}" "${disk}")"; fi
[[ -z "$alert" ]] && exit 0

LAST_ALERT=0
[[ -f "$STATE" ]] && . "$STATE" 2>/dev/null
now=$(date +%s)
[[ "$LAST_ALERT" =~ ^[0-9]+$ ]] || LAST_ALERT=0
if [[ $((now - LAST_ALERT)) -lt $((COOLDOWN_MIN * 60)) ]]; then exit 0; fi


note="$(L MSG_SYS_1901 "$host" "$alert" "${ALERT_CPU}" "${ALERT_MEM}" "${ALERT_DISK}")"
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
    msg "$(L MSG_SYS_1902 "${F_BOLD}" "${F_RESET}" "$(stat -c%a /etc/fusionbox/notify.conf 2>/dev/null)")"
  else
    msg "$(L MSG_SYS_1903 "${F_BOLD}" "${F_RESET}")"
  fi
  msg "$(L MSG_SYS_1904 "${F_BOLD}" "${F_RESET}" "$([[ -x /usr/local/bin/fusionbox-notify-check ]] && echo "已安装" || echo "未安装")")"
  msg "$(L MSG_SYS_1905 "${F_BOLD}" "${F_RESET}" "$([[ -f /etc/cron.d/fusionbox-notify ]] && echo "已安装 (每 5 分钟)" || echo "未安装")")"
  msg "$(L MSG_SYS_1906 "${F_BOLD}" "${F_RESET}" "$(_notify_conf_get ALERT_CPU)" "$(_notify_conf_get ALERT_MEM)" "$(_notify_conf_get ALERT_DISK)")"
  msg "$(L MSG_SYS_1907 "${F_BOLD}" "${F_RESET}" "$(_notify_conf_get COOLDOWN_MIN)")"

  msg "$(L MSG_SYS_1908 "${F_BOLD}" "${F_RESET}")"
  if [[ -f /var/lib/fusionbox/notify.state ]]; then
    local LAST_ALERT=0
    . /var/lib/fusionbox/notify.state 2>/dev/null
    if [[ "${LAST_ALERT:-0}" =~ ^[0-9]+$ ]] && [[ "${LAST_ALERT:-0}" -gt 0 ]]; then
      msg "    $(date -d "@$LAST_ALERT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$(L MSG_SYS_1081 "$LAST_ALERT")")"
    else
      msg "$(L MSG_SYS_1909)"
    fi
  else
    msg "$(L MSG_SYS_1909)"
  fi

  msg "$(L MSG_SYS_1910 "${F_BOLD}" "${F_RESET}")"
  if [[ -f /var/log/fusionbox-notify.log ]]; then
    tail -n 10 /var/log/fusionbox-notify.log 2>/dev/null | sed 's/^/    /'
  else
    msg "$(L MSG_SYS_1911)"
  fi
}

system_notify() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1912)"
    msg ""
    local token chat
    token=$(_notify_conf_get TG_BOT_TOKEN)
    chat=$(_notify_conf_get TG_CHAT_ID)
    if [[ -n "$token" && -n "$chat" ]]; then
      msg "$(L MSG_SYS_1913 "${F_BOLD}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
      msg "$(L MSG_SYS_1914 "${F_BOLD}" "${F_RESET}" "${token: -4}")"
      msg "  ${F_BOLD}Chat ID:${F_RESET} $chat"
      msg "$(L MSG_SYS_1906 "${F_BOLD}" "${F_RESET}" "$(_notify_conf_get ALERT_CPU)" "$(_notify_conf_get ALERT_MEM)" "$(_notify_conf_get ALERT_DISK)")"
    else
      msg "$(L MSG_SYS_1915 "${F_BOLD}" "${F_RESET}" "${F_YELLOW}" "${F_RESET}")"
      msg_warn "$(L MSG_SYS_1916)"
    fi
    msg "$(L MSG_SYS_1917 "${F_BOLD}" "${F_RESET}" "$([[ -f /etc/cron.d/fusionbox-notify ]] && echo "已安装 (每 5 分钟)" || echo "未安装")")"
    msg ""
    msg "$(L MSG_SYS_1918 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1919 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1920 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1921 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1922 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1923)" notify_choice || { msg ""; break; }

    case "$notify_choice" in
      1)
        msg ""
        msg_tip "$(L MSG_SYS_1924)"
        msg_tip "$(L MSG_SYS_1925)"
        local new_token new_chat
        new_token=$(read_input "$(L MSG_SYS_1926)" "") || { pause; continue; }
        if [[ ! "$new_token" =~ ^[0-9]{6,}:[A-Za-z0-9_-]{30,}$ ]]; then
          msg_err "$(L MSG_SYS_1927)"
          pause; continue
        fi
        new_chat=$(read_input "$(L MSG_SYS_1928)" "") || { pause; continue; }
        if [[ ! "$new_chat" =~ ^-?[0-9]+$ ]]; then
          msg_err "$(L MSG_SYS_1929)"
          pause; continue
        fi

        local acpu amem adisk cool
        acpu=$(_notify_conf_get ALERT_CPU); acpu=${acpu:-90}
        amem=$(_notify_conf_get ALERT_MEM); amem=${amem:-90}
        adisk=$(_notify_conf_get ALERT_DISK); adisk=${adisk:-90}
        cool=$(_notify_conf_get COOLDOWN_MIN); cool=${cool:-30}

        if confirm "$(L MSG_SYS_1930)"; then
          acpu=$(read_input "$(L MSG_SYS_1931)" "$acpu")
          amem=$(read_input "$(L MSG_SYS_1932)" "$amem")
          adisk=$(read_input "$(L MSG_SYS_1933)" "$adisk")
          cool=$(read_input "$(L MSG_SYS_1934)" "$cool")
        fi
        [[ "$acpu" =~ ^[0-9]+$ ]] && [[ "$acpu" -ge 1 && "$acpu" -le 100 ]] || acpu=90
        [[ "$amem" =~ ^[0-9]+$ ]] && [[ "$amem" -ge 1 && "$amem" -le 100 ]] || amem=90
        [[ "$adisk" =~ ^[0-9]+$ ]] && [[ "$adisk" -ge 1 && "$adisk" -le 100 ]] || adisk=90
        [[ "$cool" =~ ^[0-9]+$ ]] && [[ "$cool" -ge 1 ]] || cool=30

        _notify_conf_write "$new_token" "$new_chat" "$acpu" "$amem" "$adisk" "$cool"
        msg_ok "$(L MSG_SYS_1935)"
        _log_write "$(L MSG_SYS_1936)"
        pause ;;
      2)
        if [[ -z "$(_notify_conf_get TG_BOT_TOKEN)" ]]; then
          msg_warn "$(L MSG_SYS_1937)"
          pause; continue
        fi
        msg_info "$(L MSG_SYS_1938)"
        if _notify_send "$(L MSG_SYS_1939 "$(hostname 2>/dev/null)" "$(date '+%Y-%m-%d %H:%M:%S')")"; then
          msg_ok "$(L MSG_SYS_1940)"
        fi
        pause ;;
      3)
        if [[ -z "$(_notify_conf_get TG_BOT_TOKEN)" ]]; then
          msg_warn "$(L MSG_SYS_1937)"
          pause; continue
        fi
        _notify_install_check
        msg_ok "$(L MSG_SYS_1941)"
        msg_ok "$(L MSG_SYS_1942)"
        msg_tip "$(L MSG_SYS_1943)"
        _log_write "$(L MSG_SYS_1944)"
        pause ;;
      4)
        _notify_status
        pause ;;
      5)
        if ! confirm "$(L MSG_SYS_1945)"; then
          pause; continue
        fi
        rm -f /etc/cron.d/fusionbox-notify /usr/local/bin/fusionbox-notify-check
        if confirm "$(L MSG_SYS_1946)"; then
          rm -f /etc/fusionbox/notify.conf /var/lib/fusionbox/notify.state
          msg_ok "$(L MSG_SYS_1894)"
        else
          msg_ok "$(L MSG_SYS_1895)"
        fi
        _log_write "$(L MSG_SYS_1947)"
        pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

# ---- SSH 登录 Telegram 通知 ----
system_login_alert() {
  _require_root
  local action="${1:-status}"
  case "$action" in
    install)
      [[ -n "$(_notify_conf_get TG_BOT_TOKEN)" && -n "$(_notify_conf_get TG_CHAT_ID)" ]] || {
        msg_err "$(L MSG_SYS_1948)"
        return 1
      }
      python3 "$FUSION_SRC/lib/system_safety.py" login-alert install || return 1
      msg_ok "$(L MSG_SYS_1949)"
      _log_write "$(L MSG_SYS_1950)"
      ;;
    status)
      python3 "$FUSION_SRC/lib/system_safety.py" login-alert status
      ;;
    test)
      python3 "$FUSION_SRC/lib/system_safety.py" login-alert test || return 1
      msg_ok "$(L MSG_SYS_1951)"
      ;;
    uninstall)
      python3 "$FUSION_SRC/lib/system_safety.py" login-alert uninstall || return 1
      msg_ok "$(L MSG_SYS_1952)"
      _log_write "$(L MSG_SYS_1953)"
      ;;
    *)
      msg_err "$(L MSG_SYS_1954)"
      return 1
      ;;
  esac
}

# ---- 六场景内核调优 ----
system_tuning() {
  _require_root
  local action="${1:-status}" profile="${2:-}"
  case "$action" in
    apply)
      case "$profile" in high|balanced|web|stream|game|db) ;; *)
        msg_err "$(L MSG_SYS_1955)"
        return 1 ;;
      esac
      python3 "$FUSION_SRC/lib/system_safety.py" tuning apply "$profile" || return 1
      msg_ok "$(L MSG_SYS_1956 "$profile")"
      _log_write "$(L MSG_SYS_1957 "$profile")"
      ;;
    status)
      python3 "$FUSION_SRC/lib/system_safety.py" tuning status
      ;;
    restore)
      python3 "$FUSION_SRC/lib/system_safety.py" tuning restore || return 1
      msg_ok "$(L MSG_SYS_1958)"
      _log_write "$(L MSG_SYS_1959)"
      ;;
    *)
      msg_err "$(L MSG_SYS_1960)"
      return 1
      ;;
  esac
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
      msg_err "$(L MSG_SYS_1961 "$tier")"
      return 1 ;;
  esac

  msg ""
  msg_info "$(L MSG_SYS_1962 "$label")"
  msg "    net.core.rmem_max = $rmem_max    net.core.wmem_max = $wmem_max"
  msg "    net.core.rmem_default = $rmem_def    net.core.wmem_default = $wmem_def"
  msg "    net.ipv4.tcp_rmem = $tcp_rmem"
  msg "    net.ipv4.tcp_wmem = $tcp_wmem"
  msg "    net.core.somaxconn = $somaxconn    net.core.netdev_max_backlog = $backlog"
  msg "    net.ipv4.ip_local_port_range = $port_range"
  msg "    net.ipv4.tcp_fastopen = 3    net.ipv4.tcp_tw_reuse = 1"
  msg_tip "$(L MSG_SYS_1963)"
  confirm "$(L MSG_SYS_1964 "$file")" || return 1

  if [[ -f "$file" ]]; then
    local bak="/etc/fusionbox/netopt-bak-$(date +%s).conf"
    if _fb_backup_file "$file" "$bak"; then
      msg_ok "$(L MSG_SYS_1965 "$bak")"
    else
      msg_err "$(L MSG_SYS_1966)"
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
    msg_ok "$(L MSG_SYS_1967 "$label")"
  else
    msg_err "$(L MSG_SYS_1968)"
    sysctl -p "$snapshot" >/dev/null 2>&1
    if [[ -f "$snapshot.previous" ]]; then cp -p "$snapshot.previous" "$file"; else rm -f "$file"; fi
    return 1
  fi

  msg ""
  msg "$(L MSG_SYS_1969 "${F_BOLD}" "${F_RESET}")"
  local k
  for k in net.core.rmem_max net.core.wmem_max net.core.somaxconn net.core.netdev_max_backlog net.ipv4.tcp_fastopen net.ipv4.tcp_tw_reuse; do
    msg "    $k = $(sysctl -n "$k" 2>/dev/null)"
  done
  msg "    net.ipv4.tcp_rmem = $(sysctl -n net.ipv4.tcp_rmem 2>/dev/null)"
  msg "    net.ipv4.tcp_wmem = $(sysctl -n net.ipv4.tcp_wmem 2>/dev/null)"
  _log_write "$(L MSG_SYS_1967 "$label")"
  return 0
}

_system_netopt_reset() {
  local file="/etc/sysctl.d/99-fusionbox-netopt.conf"
  if [[ ! -f "$file" ]]; then
    msg_warn "$(L MSG_SYS_1970 "$file")"
    return 0
  fi
  local snapshot="/etc/fusionbox/netopt-original.conf"
  [[ -s "$snapshot" ]] || { msg_err "$(L MSG_SYS_1971)"; return 1; }
  confirm "$(L MSG_SYS_1972)" || return 1
  sysctl -p "$snapshot" || { msg_err "$(L MSG_SYS_1973)"; return 1; }
  if [[ -f "$snapshot.previous" ]]; then
    cp -p "$snapshot.previous" "$file" || return 1
  else
    rm -f "$file" || return 1
  fi
  rm -f "$snapshot" "$snapshot.previous"
  msg_ok "$(L MSG_SYS_1974)"

  return 0
}

system_netopt() {
  _require_root
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_1975)"
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
      msg "$(L MSG_SYS_1976 "${F_BOLD}" "${F_RESET}" "$det_if" "${F_BOLD}" "${F_RESET}" "${det_sp}")"
      msg "$(L MSG_SYS_1977 "${F_BOLD}" "${F_RESET}" "${suggest}" "$sname")"
    else
      msg "$(L MSG_SYS_1978 "${F_BOLD}" "${F_RESET}" "${F_YELLOW}" "${F_RESET}")"
    fi

    if [[ -f /etc/sysctl.d/99-fusionbox-netopt.conf ]]; then
      msg "$(L MSG_SYS_1979 "${F_BOLD}" "${F_RESET}" "$(sysctl -n net.core.rmem_max 2>/dev/null)")"
    else
      msg "$(L MSG_SYS_1980 "${F_BOLD}" "${F_RESET}")"
    fi

    msg ""
    msg "$(L MSG_SYS_1981 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1982 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1983 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1984 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1866)" netopt_choice || { msg ""; break; }
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
    msg_title "$(L MSG_SYS_1985)"
    msg ""
    msg "$(L MSG_SYS_1986 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1987 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1988 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1989 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1990 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1991 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1992 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1993 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1994 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1995 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1996)" set_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
      10) system_env ;;
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
    msg_title "$(L MSG_SYS_1997)"
    msg ""
    msg "$(L MSG_SYS_1998 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1999 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2000 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2001 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2002 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2003 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2004 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2005 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2006 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2007 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2008 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2200 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_1139 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_2009)" tools_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
      11) system_fail2ban ;;
      12) system_reinstall ;;
      0) break ;;
    esac
  done
}

# ---- Fail2Ban 管理面板 (G11)：状态/解封/日志/参数/卸载 ----

_f2b_status() {
  command -v fail2ban-client &>/dev/null || { msg_err "$(L MSG_SYS_2010)"; return 1; }
  msg "  ${F_BOLD}jails:${F_RESET}"
  fail2ban-client status 2>/dev/null || msg "$(L MSG_SYS_2011)"
  msg ""
  msg "  ${F_BOLD}sshd jail:${F_RESET}"
  fail2ban-client status sshd 2>/dev/null || msg "$(L MSG_SYS_2012)"
}

_f2b_banned() {
  command -v fail2ban-client &>/dev/null || { msg_err "$(L MSG_SYS_2013)"; return 1; }
  local out
  out=$(fail2ban-client status sshd 2>/dev/null | awk -F'Banned IP list:' '/Banned IP list/{print $2}' | xargs) || return 1
  if [[ -n "$out" ]]; then
    msg "  $out"
  else
    msg "$(L MSG_SYS_2014)"
  fi
}

_f2b_unban_cmd() {
  local ip="${1:-}"
  [[ -n "$ip" ]] || { msg_err "$(L MSG_SYS_2015)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" f2b-unban "$ip" || return 1
  _log_write "$(L MSG_SYS_2016 "$ip")"
}

_f2b_log() {
  local n="${1:-50}"
  [[ "$n" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_SYS_2017)"; return 1; }
  [ "$n" -gt 500 ] && n=500
  if [[ -f /var/log/fail2ban.log ]]; then
    tail -n "$n" /var/log/fail2ban.log
  elif command -v journalctl &>/dev/null && systemctl cat fail2ban.service &>/dev/null; then
    journalctl -u fail2ban -n "$n" --no-pager
  else
    msg_err "$(L MSG_SYS_2018)"
    return 1
  fi
}

_f2b_params() {
  local mr="${1:-}" bt="${2:-}"
  [[ "$mr" =~ ^[1-9][0-9]{0,8}$ && "$bt" =~ ^[1-9][0-9]{0,8}$ ]] || { msg_err "$(L MSG_SYS_2019)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" fail2ban "$mr" "$bt" || return 1
  msg_ok "$(L MSG_SYS_2020)"
}

_f2b_uninstall() {
  command -v fail2ban-client &>/dev/null || { msg_err "$(L MSG_SYS_2013)"; return 1; }
  msg_warn "$(L MSG_SYS_2021)"
  msg_warn "$(L MSG_SYS_2022)"
  confirm "$(L MSG_SYS_2023)" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
  python3 "$FUSION_SRC/lib/system_safety.py" f2b-uninstall || return 1
  case "$F_PKG_MGR" in
    apt)    apt-get purge -y fail2ban || { msg_err "$(L MSG_SYS_2024)"; return 1; } ;;
    yum)    yum remove -y fail2ban || { msg_err "$(L MSG_SYS_2025)"; return 1; } ;;
    apk)    apk del fail2ban || { msg_err "$(L MSG_SYS_2025)"; return 1; } ;;
    zypper) zypper remove -y fail2ban || { msg_err "$(L MSG_SYS_2025)"; return 1; } ;;
    *) msg_err "$(L MSG_SYS_2026)"; return 1 ;;
  esac
  if command -v fail2ban-client &>/dev/null; then
    msg_warn "$(L MSG_SYS_2027)"
    return 1
  fi
  msg_ok "$(L MSG_SYS_2028)"
  _log_write "$(L MSG_SYS_2028)"
}

_f2b_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_2029)"
    msg ""
    _f2b_status
    msg ""
    msg "$(L MSG_SYS_2030)"
    msg "$(L MSG_SYS_2031)"
    msg "$(L MSG_SYS_2032)"
    msg "$(L MSG_SYS_2033)"
    msg "$(L MSG_SYS_1321)"
    read -p "$(L MSG_SYS_1322)" f2b_choice || { msg ""; return; }
    case "$f2b_choice" in
      1) f2b_ip=$(read_input "$(L MSG_SYS_2034)") && _f2b_unban_cmd "$f2b_ip" && pause ;;
      2) f2b_n=$(read_input "$(L MSG_SYS_2035)" 50) && _f2b_log "$f2b_n" && pause ;;
      3) f2b_mr=$(read_input "$(L MSG_SYS_2036)") && f2b_bt=$(read_input "$(L MSG_SYS_2037)") && _f2b_params "$f2b_mr" "$f2b_bt" && pause ;;
      4) _f2b_uninstall && pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

system_fail2ban() {
  _require_root
  local cmd="${1:-menu}"
  case "$cmd" in
    status)    _f2b_status ;;
    banned)    _f2b_banned ;;
    unban)     shift; _f2b_unban_cmd "$@" ;;
    log)       shift; _f2b_log "$@" ;;
    params)    shift; _f2b_params "$@" ;;
    uninstall) _f2b_uninstall ;;
    menu|"")   _f2b_menu ;;
    *)         msg_err "$(L MSG_SYS_2038 "$cmd")"; return 1 ;;
  esac
}

# ---- 环境变量管理 (G09)：查看/编辑/语法检查，允许清单内文件 ----

_env_candidate_files() {
  printf '%s\n' /etc/profile /etc/bash.bashrc /etc/environment
  for f in /etc/profile.d/*.sh; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
  for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do [[ -e "$f" ]] && printf '%s\n' "$f"; done
}

_env_is_shell_file() {
  case "$1" in
    /etc/environment) return 1 ;;
    *) return 0 ;;
  esac
}

_env_in_allowlist() {
  local f="$1" c
  [[ -e "$f" ]] || return 1
  c=$(readlink -f "$f" 2>/dev/null) || return 1
  local cand
  while IFS= read -r cand; do
    [[ -e "$cand" ]] || continue
    [[ "$(readlink -f "$cand" 2>/dev/null)" == "$c" ]] && return 0
  done < <(_env_candidate_files)
  return 1
}

_env_backup() {
  local f="$1" bdir="${FUSION_CONFIG_DIR:-${HOME:-/root}/.config/fusionbox}/backups/env" ts
  mkdir -p "$bdir" && chmod 700 "$bdir"
  # 时间戳只能取一次：两次 date 求值跨秒时，cp 落盘的文件名与返回给调用方的
  # 文件名会不一致，"编辑失败自动恢复"就会指向不存在的备份并静默失效
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "$bdir/$(basename "$f").$ts.bak" || return 1
  printf '%s' "$bdir/$(basename "$f").$ts.bak"
}

_env_list() {
  msg "$(L MSG_SYS_2039 "${F_BOLD}" "${F_RESET}")"
  local f line_st
  while IFS= read -r f; do
    [[ -e "$f" ]] || continue
    if _env_is_shell_file "$f" && bash -n "$f" 2>/dev/null; then
      line_st="$(L MSG_SYS_2040 "${F_GREEN}" "${F_RESET}")"
    elif ! _env_is_shell_file "$f"; then
      line_st="$(L MSG_SYS_2041)"
    else
      line_st="$(L MSG_SYS_2042 "${F_RED}" "${F_RESET}")"
    fi
    # shellcheck disable=SC2086
    msg "$(L MSG_SYS_2043 "$f" "$(wc -l < "$f" 2>/dev/null || echo '?')" "$line_st")"
  done < <(_env_candidate_files)
  msg ""
  msg "$(L MSG_SYS_2044)"
}

_env_show() {
  local f="${1:-}"
  _env_in_allowlist "$f" || { msg_err "$(L MSG_SYS_2045)"; return 1; }
  msg "  ${F_BOLD}$f:${F_RESET}"
  cat -n "$f"
}

_env_check() {
  local bad=0 f
  while IFS= read -r f; do
    [[ -e "$f" ]] || continue
    _env_is_shell_file "$f" || continue
    if bash -n "$f" 2>/dev/null; then
      msg_ok "$(L MSG_SYS_2046 "$f")"
    else
      msg_err "$(L MSG_SYS_2047 "$f")"
      bash -n "$f" 2>&1 | head -3 | sed 's/^/    /'
      bad=1
    fi
  done < <(_env_candidate_files)
  return $bad
}

_env_edit() {
  local f="${1:-}"
  _env_in_allowlist "$f" || { msg_err "$(L MSG_SYS_2045)"; return 1; }
  [[ -f "$f" && ! -L "$f" ]] || { msg_err "$(L MSG_SYS_2048)"; return 1; }
  local backup
  backup=$(_env_backup "$f") || { msg_err "$(L MSG_SYS_2049)"; return 1; }
  msg_info "$(L MSG_SYS_1769 "$backup")"
  "${EDITOR:-vi}" "$f" || { msg_warn "编辑器异常退出；原文件未由 FusionBox 改动"; return 1; }
  if _env_is_shell_file "$f" && ! bash -n "$f" 2>/dev/null; then
    msg_err "$(L MSG_SYS_2050)"
    if confirm "$(L MSG_SYS_2051 "$f")"; then
      cp -a "$backup" "$f" && msg_ok "$(L MSG_SYS_2052)" || msg_err "$(L MSG_SYS_2053 "$backup")"
    else
      msg_warn "$(L MSG_SYS_2054)"
    fi
  else
    msg_ok "$(L MSG_SYS_2055 "$f")"
    _log_write "$(L MSG_SYS_2056 "$f" "$backup")"
  fi
}

system_env() {
  _require_root
  local cmd="${1:-menu}"
  case "$cmd" in
    list)  _env_list ;;
    show)  shift; _env_show "$@" ;;
    check) _env_check ;;
    edit)  shift; _env_edit "$@" ;;
    menu)  shift || true
      msg_title "$(L MSG_SYS_2057)"
      msg ""
      _env_list
      msg "$(L MSG_SYS_2058)"
      msg "$(L MSG_SYS_2059)"
      msg "$(L MSG_SYS_2060)"
      msg "$(L MSG_SYS_1321)"
      read -p "$(L MSG_SYS_1322)" env_choice || { msg ""; return; }
      case "$env_choice" in
        1) _env_check && pause ;;
        2) env_f=$(read_input "$(L MSG_SYS_2061)") && _env_show "$env_f" && pause ;;
        3) env_f=$(read_input "$(L MSG_SYS_2061)") && _env_edit "$env_f" && pause ;;
        0) return ;;
        *) ;;
      esac ;;
    *) msg_err "$(L MSG_SYS_2062 "$cmd")"; return 1 ;;
  esac
}

# ---- rsync 同步任务管理 (G16)：持久化任务清单 + 可选 cron ----
_RSYNC_FILE="/etc/fusionbox/rsync-tasks.conf"
_RSYNC_CRON_FILE="/etc/cron.d/fusionbox-rsync"

_rsync_check_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_-]{1,32}$ ]] || { msg_err "$(L MSG_SYS_2063 "$1")"; return 1; }
}

_rsync_check_endpoint() {
  local ep="$1"
  if [[ "$ep" == *:* ]]; then
    [[ "$ep" =~ ^[a-zA-Z0-9._@-]+:/[a-zA-Z0-9._/-]*$ ]] || { msg_err "$(L MSG_SYS_2064 "$ep")"; return 1; }
  else
    [[ "$ep" == /* ]] || { msg_err "$(L MSG_SYS_2065 "$ep")"; return 1; }
  fi
}

_rsync_rewrite_cron() {
  {
    echo "# FusionBox managed rsync schedule"
    grep -v '^#' "$_RSYNC_FILE" 2>/dev/null | awk -F'|' '$5 == "daily" {printf "30 3 * * * root /usr/bin/rsync %s %s %s\n", $4, $2, $3}'
  } > "$_RSYNC_CRON_FILE"
  chmod 600 "$_RSYNC_CRON_FILE"
}

system_rsync() {
  _require_root
  local action="${1:-list}"; shift || true

  case "$action" in
    list)
      [[ -s "$_RSYNC_FILE" ]] || { msg "$(L MSG_SYS_2066)"; return 0; }
      msg "$(L MSG_SYS_2067 "${F_BOLD}" "${F_RESET}")"
      awk -F'|' '{printf "    %s: %s -> %s [%s] cron=%s\n", $1, $2, $3, ($4 ~ /delete/ ? "mirror" : "safe"), $5}' "$_RSYNC_FILE"
      ;;
    add)
      local name="${1:-}"
      _rsync_check_name "$name" || return 1
      grep -q "^$name|" "$_RSYNC_FILE" 2>/dev/null && { msg_err "$(L MSG_SYS_2068 "$name")"; return 1; }
      local src dest
      src=$(read_input "$(L MSG_SYS_2069)")
      _rsync_check_endpoint "$src" || return 1
      [[ -e "$src" ]] || { msg_err "$(L MSG_SYS_2070 "$src")"; return 1; }
      dest=$(read_input "$(L MSG_SYS_2071)")
      _rsync_check_endpoint "$dest" || return 1
      local mirror=0
      confirm "$(L MSG_SYS_2072)" && mirror=1
      local flags="-a"
      [[ $mirror -eq 1 ]] && flags="-a --delete"
      local cron="no"
      confirm "$(L MSG_SYS_2073)" && cron="daily"
      mkdir -p "$(dirname "$_RSYNC_FILE")" && touch "$_RSYNC_FILE" && chmod 600 "$_RSYNC_FILE"
      printf '%s|%s|%s|%s|%s\n' "$name" "$src" "$dest" "$flags" "$cron" >> "$_RSYNC_FILE"
      _rsync_rewrite_cron
      msg_ok "$(L MSG_SYS_2074 "$name")"
      _log_write "$(L MSG_SYS_2075 "$name")"
      ;;
    run)
      local name="${1:-}" row
      _rsync_check_name "$name" || return 1
      row=$(grep "^$name|" "$_RSYNC_FILE" 2>/dev/null | tail -1)
      [[ -n "$row" ]] || { msg_err "$(L MSG_SYS_2076 "$name")"; return 1; }
      local src dest flags
      src=$(echo "$row" | cut -d'|' -f2); dest=$(echo "$row" | cut -d'|' -f3); flags=$(echo "$row" | cut -d'|' -f4)
      msg_info "rsync $flags $src $dest"
      rsync $flags "$src" "$dest"
      ;;
    enable|disable)
      local name="${1:-}" row
      _rsync_check_name "$name" || return 1
      row=$(grep "^$name|" "$_RSYNC_FILE" 2>/dev/null | tail -1)
      [[ -n "$row" ]] || { msg_err "$(L MSG_SYS_2076 "$name")"; return 1; }
      if [[ "$action" == "enable" ]]; then
        awk -F'|' -v n="$name" 'BEGIN{OFS="|"} $1==n {$5="daily"} {print}' "$_RSYNC_FILE" > "$_RSYNC_FILE.new" && mv "$_RSYNC_FILE.new" "$_RSYNC_FILE"
      else
        awk -F'|' -v n="$name" 'BEGIN{OFS="|"} $1==n {$5="no"} {print}' "$_RSYNC_FILE" > "$_RSYNC_FILE.new" && mv "$_RSYNC_FILE.new" "$_RSYNC_FILE"
      fi
      chmod 600 "$_RSYNC_FILE"
      _rsync_rewrite_cron
      msg_ok "$(L MSG_SYS_2077 "$name" "$action")"
      ;;
    rm)
      local name="${1:-}"
      _rsync_check_name "$name" || return 1
      grep -q "^$name|" "$_RSYNC_FILE" 2>/dev/null || { msg_err "$(L MSG_SYS_2076 "$name")"; return 1; }
      confirm "$(L MSG_SYS_2078 "$name")" || { msg_info "$(L MSG_SYS_1354)"; return 1; }
      sed -i "/^$name|/d" "$_RSYNC_FILE"
      _rsync_rewrite_cron
      msg_ok "$(L MSG_SYS_2079 "$name")"
      ;;
    *)
      msg_err "$(L MSG_SYS_2080 "$action")"; return 2 ;;
  esac
}

# ---- 文件管理器 (G14)：受控的目录/文件操作，删除进回收站 ----
_FILE_TRASH="/root/.fusionbox_trash/files"

system_file() {
  _require_root
  local action="${1:-}"; shift || true

  case "$action" in
    ls)
      local d="${1:-}"
      [[ -d "$d" ]] || { msg_err "$(L MSG_SYS_2081 "$d")"; return 1; }
      ls -la --time-style=long-iso "$d" 2>/dev/null || ls -la "$d"
      ;;
    cat)
      local f="${1:-}"
      [[ -f "$f" ]] || { msg_err "$(L MSG_SYS_1657 "$f")"; return 1; }
      cat "$f"
      ;;
    mkdir)
      local d="${1:-}"
      [[ "$d" == /* ]] || { msg_err "$(L MSG_SYS_2082)"; return 1; }
      mkdir -p "$d" && msg_ok "$(L MSG_SYS_2083 "$d")"
      ;;
    cp|mv)
      local src="${1:-}" dest="${2:-}"
      [[ $# -eq 2 && -e "$src" && -n "$dest" ]] || { msg_err "$(L MSG_SYS_2084 "$action")"; return 1; }
      if [[ "$action" == "cp" ]]; then
        cp -a "$src" "$dest" && msg_ok "$(L MSG_SYS_2085)"
      else
        mv "$src" "$dest" && msg_ok "$(L MSG_SYS_2086)"
      fi
      ;;
    del)
      local f="${1:-}"
      [[ -e "$f" || -L "$f" ]] || { msg_err "$(L MSG_SYS_2087 "$f")"; return 1; }
      [[ "$f" != "/" ]] || { msg_err "$(L MSG_SYS_2088)"; return 1; }
      mkdir -p "$_FILE_TRASH"
      local name; name="$(basename "$f")_$(date +%s)"
      mv "$f" "$_FILE_TRASH/$name" && msg_ok "$(L MSG_SYS_2089 "$_FILE_TRASH" "$name")"
      ;;
    chmod)
      local mode="${1:-}" f="${2:-}"
      [[ "$mode" =~ ^[0-7]{3,4}$ && -e "$f" ]] || { msg_err "$(L MSG_SYS_2090)"; return 1; }
      chmod "$mode" "$f" && msg_ok "$(L MSG_SYS_2091)"
      ;;
    tar|untar)
      local src="${1:-}" dest="${2:-}"
      if [[ "$action" == "tar" ]]; then
        [[ -e "$src" && -n "$dest" ]] || { msg_err "$(L MSG_SYS_2092)"; return 1; }
        [[ "$dest" == *.tar.gz ]] || dest="$dest.tar.gz"
        tar czf "$dest" -C "$(dirname "$src")" "$(basename "$src")" && msg_ok "$(L MSG_SYS_2093 "$dest")"
      else
        [[ -f "$src" && -d "$dest" ]] || { msg_err "$(L MSG_SYS_2094)"; return 1; }
        tar xzf "$src" -C "$dest" && msg_ok "$(L MSG_SYS_2095 "$dest")"
      fi
      ;;
    send)
      local src="${1:-}" dest="${2:-}"
      [[ $# -eq 2 && -e "$src" ]] || { msg_err "$(L MSG_SYS_2096)"; return 2; }
      [[ "$dest" == *:* ]] || { msg_err "$(L MSG_SYS_2097)"; return 2; }
      scp -p "$src" "$dest" && msg_ok "$(L MSG_SYS_2098)"
      ;;
    *)
      msg_err "$(L MSG_SYS_2099 "$action")"; return 2 ;;
  esac
}

# ---- 小工具 (G22)：密码生成器 / IPv4-IPv6 优先级 / locale ----
_genpass_raw() {
  head -c 256 /dev/urandom 2>/dev/null
}

system_genpass() {
  local len="${1:-20}"
  [[ "$len" =~ ^[0-9]+$ ]] && [ "$len" -ge 8 ] && [ "$len" -le 128 ] || { msg_err "$(L MSG_SYS_2100)"; return 1; }
  local pw
  pw=$(_genpass_raw | tr -dc 'A-Za-z0-9!@#$%^&*' | head -c "$len")
  [[ -n "$pw" ]] && msg "$pw" || { msg_err "$(L MSG_SYS_2101)"; return 1; }
}

system_gai() {
  _require_root
  local action="${1:-status}"
  local f="/etc/gai.conf"
  case "$action" in
    status)
      if grep -q "^precedence ::ffff:0:0/96  100" "$f" 2>/dev/null; then
        msg "$(L MSG_SYS_2102)"
      else
        msg "$(L MSG_SYS_2103)"
      fi
      ;;
    v4-first)
      [[ -f "$f" ]] || { msg_err "$(L MSG_SYS_2104)"; return 1; }
      cp -p "$f" "$f.fb-bak-$(date +%s)" 2>/dev/null
      grep -q "^precedence ::ffff:0:0/96  100" "$f" || \
        printf '# FusionBox: prefer IPv4\nprecedence ::ffff:0:0/96  100\n' >> "$f"
      msg_ok "$(L MSG_SYS_2105)"
      ;;
    default)
      [[ -f "$f" ]] || { msg_err "$(L MSG_SYS_2104)"; return 1; }
      cp -p "$f" "$f.fb-bak-$(date +%s)" 2>/dev/null
      sed -i '/^# FusionBox: prefer IPv4$/d; /^precedence ::ffff:0:0\/96  100$/d' "$f"
      msg_ok "$(L MSG_SYS_2106)"
      ;;
    *) msg_err "$(L MSG_SYS_2107)"; return 2 ;;
  esac
}

system_locale() {
  _require_root
  local lang="${1:-}"
  if [[ -z "$lang" ]]; then
    msg "$(L MSG_SYS_2108 "$LANG")"
    msg "$(L MSG_SYS_2109 "$(locale -a 2>/dev/null | grep -iE 'zh_CN|en_US' | tr '\n' ' ')")"
    return 0
  fi
  [[ "$lang" =~ ^[a-zA-Z0-9_.@-]+$ ]] || { msg_err "$(L MSG_SYS_2110)"; return 1; }
  command -v update-locale &>/dev/null || { msg_err "$(L MSG_SYS_2111)"; return 1; }
  locale-gen "$lang" 2>/dev/null || msg_warn "$(L MSG_SYS_2112 "$lang")"
  update-locale "LANG=$lang" && msg_ok "$(L MSG_SYS_2113 "$lang")"
  _log_write "$(L MSG_SYS_2114 "$lang")"
}

# ---- 系统一键重装（DD，G35）：调用上游 bin456789/reinstall（GPL-3.0）----
# 上游为滚动发布的第三方脚本：本工具每次实时下载、执行前展示 SHA256 指纹但不锁定
# 版本；仅交互终端可用（整盘销毁级操作不进脚本/CI 路径），容器/OpenVZ/LXC 直接拒绝
# （上游同样不支持）；目标为 dd 镜像时跳过密码/端口交互——DD 镜像自带凭据，
# 上游的 --password 仅用于安装期观察日志。
_REINSTALL_SCRIPT_GH="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
_REINSTALL_SCRIPT_CNB="https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh"

system_reinstall() {
  _require_root
  if [[ ! -t 0 ]]; then
    msg_err "$(L MSG_SYS_2171)"
    return 2
  fi

  local virt="unknown"
  command -v systemd-detect-virt >/dev/null 2>&1 && virt="$(systemd-detect-virt 2>/dev/null || true)"
  [[ -n "$virt" ]] || virt="unknown"
  case "$virt" in
    openvz|lxc|lxc-libvirt|systemd-nspawn|docker|podman)
      msg_err "$(L MSG_SYS_2173 "$virt")"
      return 1 ;;
  esac

  msg_title "$(L MSG_SYS_2170)"
  msg ""
  msg_warn "$(L MSG_SYS_2174)"
  msg ""
  msg "$(L MSG_SYS_2172 "$virt")"
  msg ""
  confirm "$(L MSG_SYS_2175)" || { msg_info "$(L MSG_SYS_2176)"; return 1; }
  local _reinstall_yes
  read -r -p "$(L MSG_SYS_2175)" _reinstall_yes || { msg ""; return 1; }
  [[ "$_reinstall_yes" == "YES" ]] || { msg_info "$(L MSG_SYS_2176)"; return 1; }

  local -a r_args=()
  msg ""
  msg "$(L MSG_SYS_2177)"
  msg "$(L MSG_SYS_2178)"
  msg "$(L MSG_SYS_2179)"
  msg "$(L MSG_SYS_2180)"
  local choice
  read -r -p "$(L MSG_SYS_2181)" choice || { msg ""; return 1; }
  case "$choice" in
    1) r_args=(debian 12) ;;
    2) r_args=(debian 13) ;;
    3) r_args=(ubuntu 24.04) ;;
    4) r_args=(ubuntu 22.04) ;;
    5) r_args=(alpine 3.22) ;;
    6)
      local img
      read -r -p "$(L MSG_SYS_2182)" img || { msg ""; return 1; }
      [[ "$img" =~ ^https?:// ]] || { msg_err "$(L MSG_SYS_2183)"; return 1; }
      r_args=(dd --img "$img") ;;
    *) msg_err "$(L MSG_SYS_2184 "$choice")"; return 1 ;;
  esac

  local pw="" pw2=""
  if [[ "${r_args[0]}" != "dd" ]]; then
    read -r -s -p "$(L MSG_SYS_2185)" pw || { msg ""; return 1; }
    msg ""
    if [[ -z "$pw" ]]; then
      pw="$(_genpass_raw | tr -dc 'A-Za-z0-9' | head -c 20)"
      msg_ok "$(L MSG_SYS_2186 "$pw")"
    else
      read -r -s -p "$(L MSG_SYS_2187)" pw2 || { msg ""; return 1; }
      msg ""
      [[ "$pw" == "$pw2" ]] || { msg_err "$(L MSG_SYS_2188)"; return 1; }
    fi
    local sport
    read -r -p "$(L MSG_SYS_2189)" sport || { msg ""; return 1; }
    [[ -z "$sport" || "$sport" =~ ^[0-9]+$ ]] || { msg_err "$(L MSG_SYS_2184 "$sport")"; return 1; }
    [[ -n "$sport" ]] && r_args+=(--ssh-port "$sport")
    r_args+=(--password "$pw")
  fi

  local script="/tmp/fb-reinstall.$$.sh" src=""
  msg_info "$(L MSG_SYS_2190)"
  if _download "$_REINSTALL_SCRIPT_GH" "$script"; then
    src="github.com"
  elif _download "$_REINSTALL_SCRIPT_CNB" "$script"; then
    src="cnb.cool"
  else
    msg_err "$(L MSG_SYS_2191)"
    return 1
  fi
  msg "$(L MSG_SYS_2192 "$src" "$(sha256sum "$script" | awk '{print $1}')")"

  msg ""
  msg_warn "$(L MSG_SYS_2193)"
  local disp="bash reinstall.sh" a
  for a in ${r_args[@]+"${r_args[@]}"}; do
    [[ -n "$pw" && "$a" == "$pw" ]] && a="******"
    disp+=" $a"
  done
  msg "  $disp"
  read -r -p "$(L MSG_SYS_2175)" _reinstall_yes || { msg ""; return 1; }
  [[ "$_reinstall_yes" == "YES" ]] || { msg_info "$(L MSG_SYS_2176)"; return 1; }

  msg_info "$(L MSG_SYS_2194)"
  if ! bash "$script" ${r_args[@]+"${r_args[@]}"}; then
    msg_err "$(L MSG_SYS_2195)"
    rm -f "$script"
    return 1
  fi
  msg_ok "$(L MSG_SYS_2196)"
  _log_write "$(L MSG_SYS_2197 "${r_args[*]/--password*/--password ******}")"
  local rb
  read -r -p "$(L MSG_SYS_2198)" rb || return 0
  if [[ "$rb" =~ ^[Yy]$ ]]; then
    msg_info "$(L MSG_SYS_2199)"
    sleep 2
    reboot
  else
    msg_info "$(L MSG_SYS_2201)"
  fi
}

# ---- Help ----
system_help() {
  msg_title "$(L MSG_SYS_2115)"
  msg ""
  msg "$(L MSG_SYS_2116)"
  msg "$(L MSG_SYS_2117)"
  msg "$(L MSG_SYS_2118)"
  msg "$(L MSG_SYS_2119)"
  msg "$(L MSG_SYS_2120)"
  msg "$(L MSG_SYS_2121)"
  msg "$(L MSG_SYS_2122)"
  msg "$(L MSG_SYS_2123)"
  msg "$(L MSG_SYS_2124)"
  msg "$(L MSG_SYS_2125)"
  msg "$(L MSG_SYS_2126)"
  msg "$(L MSG_SYS_2127)"
  msg "$(L MSG_SYS_2128)"
  msg "$(L MSG_SYS_2129)"
  msg "$(L MSG_SYS_2130)"
  msg "$(L MSG_SYS_2131)"
  msg "$(L MSG_SYS_2132)"
  msg "$(L MSG_SYS_2133)"
  msg "$(L MSG_SYS_2134)"
  msg "$(L MSG_SYS_2135)"
  msg "$(L MSG_SYS_2136)"
  msg "$(L MSG_SYS_2137)"
  msg "$(L MSG_SYS_2138)"
  msg "$(L MSG_SYS_2139)"
  msg "$(L MSG_SYS_2140)"
  msg "$(L MSG_SYS_2141)"
  msg "$(L MSG_SYS_2142)"
  msg "$(L MSG_SYS_2143)"
  msg "$(L MSG_SYS_2144)"
  msg "$(L MSG_SYS_2145)"
  msg "$(L MSG_SYS_2146)"
  msg "$(L MSG_SYS_2147)"
  msg "$(L MSG_SYS_2148)"
  msg "$(L MSG_SYS_2149)"
  msg ""
}

# ---- Interactive Menu ----
system_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_SYS_2150)"
    msg ""
    msg "$(L MSG_SYS_2151 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2152 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2153 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2154 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2155 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2156 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2157 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2158 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2159 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2160 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_SYS_2161 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_SYS_1996)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
