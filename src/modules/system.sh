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
  msg_title "$(tr SYS_INFO "System Information")"
  msg ""

  # CPU
  local cpu_model; cpu_model=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs)
  local cpu_cores; cpu_cores=$(nproc --all)
  msg "  ${F_BOLD}CPU:${F_RESET} ${cpu_model:-unknown} (${cpu_cores} cores)"

  # Load
  local load; load=$(uptime | awk -F'average:' '{print $2}' | xargs)
  msg "  ${F_BOLD}Load:${F_RESET} $load"

  # Memory
  msg "  ${F_BOLD}Memory:${F_RESET}"
  free -h | awk 'NR==1{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'
  free -h | awk 'NR==2{print "            " $1 "\t" $2 "\t" $3 "\t" $4}'

  # Disk
  msg "  ${F_BOLD}Disk:${F_RESET}"
  df -h / /boot /home 2>/dev/null | awk 'NR>0{print "            " $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5}'

  # Network
  msg "  ${F_BOLD}Network:${F_RESET}"
  ip addr show | grep -E "inet " | grep -v "127.0.0.1" | awk '{print "            " $NF ": " $2}'

  # OS
  msg "  ${F_BOLD}OS:${F_RESET} $F_OS_NAME $F_OS_VER ($F_ARCH)"
  msg "  ${F_BOLD}Kernel:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}Uptime:${F_RESET} $(uptime -p 2>/dev/null | sed 's/up //')"
  msg "  ${F_BOLD}Virtualization:${F_RESET} $F_VIRT"

  # BBR status
  local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  msg "  ${F_BOLD}TCP CC:${F_RESET} $cc"
  local qdisc; qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")
  msg "  ${F_BOLD}Qdisc:${F_RESET} $qdisc"

  # Security
  if command -v ufw &>/dev/null; then
    msg "  ${F_BOLD}UFW:${F_RESET} $(ufw status 2>/dev/null | head -1)"
  fi
  if command -v fail2ban-client &>/dev/null; then
    msg "  ${F_BOLD}Fail2Ban:${F_RESET} $(fail2ban-client status 2>/dev/null | head -1 || echo "running")"
  fi

  # Docker
  if command -v docker &>/dev/null; then
    msg "  ${F_BOLD}Docker:${F_RESET} $(docker --version 2>/dev/null)"
  fi

  # Proxy status
  if command -v sing-box &>/dev/null; then
    local sb_status="stopped"
    pgrep -x sing-box &>/dev/null && sb_status="running"
    msg "  ${F_BOLD}Proxy:${F_RESET} sing-box ($sb_status)"
  fi

  msg ""
  pause
}

# ---- BBR Management ----
system_bbr() {
  _require_root
  msg_title "$(tr SYS_BBR "BBR Management")"
  msg ""

  local cc; cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
  msg "  ${F_BOLD}Current:${F_RESET} $cc"

  if [[ "$cc" == "bbr" ]]; then
    msg_ok "$(tr BBR_ALREADY "BBR is already enabled")"
    msg ""
    msg "  1) Disable BBR (revert to cubic)"
    msg "  0) Back"
    read -p "$(tr MSG_SELECT "Select"): " bbr_choice
    if [[ "$bbr_choice" == "1" ]]; then
      sed -i '/tcp_congestion_control/d' /etc/sysctl.conf
      sed -i '/default_qdisc/d' /etc/sysctl.conf
      echo "net.ipv4.tcp_congestion_control = cubic" >> /etc/sysctl.conf
      echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
      sysctl -p 2>/dev/null
      msg_info "Reverted to cubic"
    fi
    return
  fi

  # Check kernel version
  local kmaj; kmaj=$(uname -r | cut -d. -f1)
  local kmin; kmin=$(uname -r | cut -d. -f2)

  if [[ $kmaj -lt 4 ]] || [[ $kmaj -eq 4 && $kmin -lt 9 ]]; then
    msg_err "$(tr BBR_FAILED "BBR requires kernel 4.9+")"
    msg_info "Current kernel: $(uname -r)"
    if confirm "$(tr MSG_CONFIRM "Install a newer kernel?")"; then
      _system_install_kernel
    fi
    return
  fi

  # Enable BBR and fq
  cat >> /etc/sysctl.conf << 'SEOF'

# FusionBox BBR Settings
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
SEOF
  sysctl -p 2>/dev/null
  msg_ok "$(tr BBR_ENABLED "BBR enabled successfully")"

  # Show verification
  msg_info "Verification:"
  sysctl net.ipv4.tcp_congestion_control
  lsmod | grep tcp_bbr 2>/dev/null || msg_info "tcp_bbr module may need module load"
  _log_write "BBR enabled"
  pause
}

_system_install_kernel() {
  case "$F_PKG_MGR" in
    apt)
      msg_info "Updating package list..."
      apt-get update -y
      msg_info "Installing kernel from ELrepo..."
      # Try to install a newer kernel
      apt-get install -y linux-image-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null || \
      apt-get install -y --install-recommends linux-generic-hwe-$(lsb_release -r -s 2>/dev/null) 2>/dev/null
      msg_info "Kernel installed. Reboot required."
      if confirm "$(tr MSG_CONFIRM "Reboot now?")"; then
        reboot
      fi
      ;;
    yum)
      # Install ELrepo and kernel-lt
      rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 2>/dev/null || true
      yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm 2>/dev/null || true
      yum --enablerepo=elrepo-kernel install -y kernel-lt 2>/dev/null || true
      if grub2-set-default 0 2>/dev/null; then
        msg_info "Kernel installed. Reboot required."
        confirm "$(tr MSG_CONFIRM "Reboot now?")" && reboot
      fi
      ;;
  esac
}

# ---- Benchmark (SuperBench style) ----
system_benchmark() {
  _require_root
  msg_title "$(tr SYS_BENCHMARK "System Benchmark")"
  msg ""
  msg_info "Running basic benchmarks..."

  # CPU - simple sieve
  msg "  ${F_BOLD}CPU Cores:${F_RESET} $(nproc --all)"
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
  msg "  ${F_BOLD}CPU Benchmark:${F_RESET} $prime_count primes in ${cpu_time}s (50k sieve)"

  # Memory speed test
  msg "  ${F_BOLD}Memory:${F_RESET}"
  free -h | awk '/Mem:/{printf "    Total: %s  Used: %s  Free: %s\n", $2, $3, $4}'
  free -h | awk '/Swap:/{printf "    Swap: %s  Used: %s  Free: %s\n", $2, $3, $4}'

  # Disk I/O test
  msg "  ${F_BOLD}Disk I/O (dd test):${F_RESET}"
  local io_write; io_write=$(dd if=/dev/zero of=/tmp/fusionbench bs=1M count=1024 conv=fdatasync 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "    Write: ${io_write:-test failed}"
  sync
  local io_read; io_read=$(dd if=/tmp/fusionbench of=/dev/null bs=1M count=1024 2>&1 | tail -1 | awk -F', ' '{print $NF}')
  msg "    Read:  ${io_read:-test failed}"
  rm -f /tmp/fusionbench

  # Network speed test
  msg "  ${F_BOLD}Network:${F_RESET}"
  _get_ip
  msg "    IPv4: ${F_IP:-unknown}"
  msg "    IPv6: ${F_IPV6:-unknown}"

  # Optional: download speedtest
  if confirm "$(tr MSG_CONFIRM "Run internet speed test? (downloads test file)")"; then
    msg_info "Testing download speed..."
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
    msg "    Download: ~${speed_mbps} Mbps"
    rm -f /tmp/speedtest
  fi

  msg ""
  _log_write "Benchmark completed"
  pause
}

# ---- System Monitor (top-like) ----
system_monitor() {
  msg_title "$(tr SYS_MONITOR "System Monitor")"
  msg "Press Ctrl+C to exit"
  msg ""

  local interval="${1:-5}"
  while true; do
    clear
    msg "${F_BOLD}${F_CYAN}FusionBox System Monitor (refreshing every ${interval}s)${F_RESET}"
    msg "${F_BOLD}Date:${F_RESET} $(date '+%Y-%m-%d %H:%M:%S')"
    msg ""

    # CPU & Load
    msg "${F_BOLD}[CPU & Load]${F_RESET}"
    local load; load=$(cat /proc/loadavg 2>/dev/null)
    msg "  Load Average: $load"
    msg "  Processes: $(ps aux | wc -l)"

    # CPU usage
    local cpu_idle; cpu_idle=$(top -bn1 2>/dev/null | grep "%Cpu" | awk '{print $8}' | cut -d. -f1)
    if [[ -n "$cpu_idle" && "$cpu_idle" -le 100 ]]; then
      msg "  CPU Usage: $((100 - cpu_idle))%"
    fi

    # Top processes
    msg ""
    msg "${F_BOLD}[Top CPU Processes]${F_RESET}"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | awk 'NR>1{printf "  %-12s %-6s %-5s %s\n", $1, $2, $3"%", $11}'

    # Memory
    msg ""
    msg "${F_BOLD}[Memory]${F_RESET}"
    free -h | awk 'NR==1{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'
    free -h | awk 'NR==2{printf "  %-10s %-10s %-10s %s\n", $1, $2, $3, $4}'

    # Disk
    msg ""
    msg "${F_BOLD}[Disk]${F_RESET}"
    df -h / 2>/dev/null | awk 'NR==2{printf "  %-15s %-10s %-10s %s\n", $1, $2, $3, $5}'

    # Network connections
    msg ""
    msg "${F_BOLD}[Network]${F_RESET}"
    if command -v ss &>/dev/null; then
      msg "  Connections: $(ss -tlnp 2>/dev/null | wc -l) listening, $(ss -tan 2>/dev/null | wc -l) total"
    fi
    msg "  IP: ${F_IP:-$(curl -s ip.sb 2>/dev/null || echo "N/A")}"

    # Proxy
    if pgrep -x "sing-box" &>/dev/null; then
      msg "  Proxy: ${F_GREEN}sing-box running${F_RESET}"
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

  msg_title "$(tr SYS_BACKUP "System Backup")"
  msg ""

  local dirs_to_backup=(
    "/etc/sing-box" "/etc/nginx" "/etc/caddy"
    "/etc/fusionbox" "/var/www"
    "/opt/docker"
  )

  msg_info "Backing up to: $backup_file"
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
      msg_ok "Backup created: $backup_file ($size)"
      _log_write "System backup created: $backup_file"
    else
      msg_err "Backup failed"
    fi
  else
    msg_warn "No directories to backup"
  fi
  pause
}

system_restore() {
  _require_root
  local backup_dir="${1:-/root/backups}"

  msg_title "$(tr SYS_RESTORE "System Restore")"
  msg ""

  local backups=()
  for f in "$backup_dir"/fusionbox_backup_*.tar.gz; do
    [[ -f "$f" ]] && backups+=("$f")
  done

  if [[ ${#backups[@]} -eq 0 ]]; then
    msg_warn "No backups found in $backup_dir"
    pause
    return
  fi

  msg_info "Available backups:"
  local i=1
  for f in "${backups[@]}"; do
    local size; size=$(du -h "$f" | cut -f1)
    local date_str; date_str=$(basename "$f" .tar.gz | sed 's/fusionbox_backup_//')
    msg "  $i) $date_str ($size)"
    i=$((i+1))
  done
  msg ""

  read -p "$(tr MSG_SELECT "Select backup to restore"): " choice
  local idx=$((choice - 1))
  if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
    if confirm "$(tr MSG_CONFIRM "This will overwrite existing files. Continue")"; then
      tar xzf "${backups[$idx]}" -C /
      msg_ok "$(tr MSG_DONE "Restore completed")"
      _log_write "System restored from ${backups[$idx]}"
    fi
  fi
  pause
}

# ---- System Update ----
system_update() {
  _require_root
  msg_title "$(tr SYS_UPDATE "System Update")"
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

  msg_ok "$(tr MSG_DONE "System updated")"
  _log_write "System updated"

  if [[ -f /var/run/reboot-required ]]; then
    msg_warn "Reboot required to apply updates"
    if confirm "$(tr MSG_CONFIRM "Reboot now?")"; then
      reboot
    fi
  fi
  pause
}

# ---- System Cleanup ----
system_clean() {
  _require_root
  msg_title "$(tr SYS_CLEAN "System Cleanup")"
  msg ""

  msg_info "Cleaning package cache..."
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

  msg_info "Cleaning journal logs..."
  journalctl --vacuum-time=7d 2>/dev/null || true

  msg_info "Cleaning temporary files..."
  rm -rf /tmp/*.tmp 2>/dev/null || true
  rm -rf /tmp/fusion* 2>/dev/null || true

  msg_info "Cleaning Docker (if installed)..."
  if command -v docker &>/dev/null; then
    docker system prune -f --volumes 2>/dev/null || true
  fi

  msg_ok "$(tr MSG_DONE "System cleaned")"
  _log_write "System cleanup completed"
  pause
}

# ---- Swap Management ----
system_swap() {
  _require_root
  msg_title "Swap Management"
  msg ""

  msg "  Current swap:"
  swapon --show 2>/dev/null || msg "    No swap active"
  free -h | awk '/Swap:/{printf "    %s %s %s\n", $2, $3, $4}'

  msg ""
  msg "  1) Create swap file (2GB)"
  msg "  2) Remove all swap"
  msg "  0) Back"
  read -p "$(tr MSG_SELECT "Select"): " sw_choice

  case "$sw_choice" in
    1)
      if confirm "$(tr MSG_CONFIRM "Create 2GB swap file")"; then
        dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q "/swapfile" /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
        msg_ok "Swap created (2GB)"
        free -h | grep Swap
        _log_write "2GB swap created"
      fi
      ;;
    2)
      if confirm "$(tr MSG_CONFIRM "WARNING: Remove all swap?")"; then
        swapoff -a 2>/dev/null || true
        rm -f /swapfile 2>/dev/null || true
        sed -i '/swapfile/d' /etc/fstab
        msg_ok "Swap removed"
        _log_write "Swap removed"
      fi
      ;;
  esac
  pause
}

# ---- User Management ----
system_users() {
  _require_root
  msg_title "User Management"
  msg ""
  msg "  ${F_BOLD}System Users:${F_RESET}"
  awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s, shell=%s)\n", $1, $3, $7}' /etc/passwd
  msg ""
  msg "  ${F_BOLD}Recently logged in:${F_RESET}"
  last -n 10 2>/dev/null | head -10
  msg ""
  pause
}

# ---- Security Audit ----
system_security() {
  _require_root
  msg_title "Security Audit"
  msg ""

  msg "${F_BOLD}[SSH Configuration]${F_RESET}"
  local ssh_port; ssh_port=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
  msg "  SSH Port: ${ssh_port:-22 (default)}"
  if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "  ${F_YELLOW}Root login: enabled (consider disabling)${F_RESET}"
  else
    msg "  ${F_GREEN}Root login: disabled or key-only${F_RESET}"
  fi
  if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
    msg "  ${F_YELLOW}Password auth: enabled (consider key-only)${F_RESET}"
  fi

  msg ""
  msg "${F_BOLD}[Firewall]${F_RESET}"
  if command -v ufw &>/dev/null; then
    ufw status 2>/dev/null | head -5
  elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --list-all 2>/dev/null | head -5
  else
    msg "  No firewall detected (recommended: ufw)"
  fi

  msg ""
  msg "${F_BOLD}[Fail2Ban]${F_RESET}"
  if command -v fail2ban-client &>/dev/null; then
    fail2ban-client status 2>/dev/null || msg "  fail2ban not running"
  else
    msg "  Not installed (recommended)"
  fi

  msg ""
  msg "${F_BOLD}[Open Ports]${F_RESET}"
  ss -tlnp 2>/dev/null | awk 'NR>1{printf "  %s %s\n", $4, $NF}'

  msg ""
  msg "  1) Install & enable UFW firewall"
  msg "  2) Install Fail2Ban"
  msg "  3) Change SSH port"
  msg "  0) Back"
  read -p "$(tr MSG_SELECT "Select"): " sec_choice

  case "$sec_choice" in
    1)
      _install_pkg ufw
      ufw allow ssh
      ufw --force enable
      msg_ok "UFW enabled (SSH allowed)"
      ;;
    2)
      _install_pkg fail2ban
      systemctl enable --now fail2ban 2>/dev/null || true
      msg_ok "Fail2Ban installed & started"
      ;;
    3)
      read -p "$(tr MSG_INPUT "New SSH port"): " new_port
      if [[ -n "$new_port" && "$new_port" =~ ^[0-9]+$ ]]; then
        sed -i "s/^#\?Port .*/Port $new_port/" /etc/ssh/sshd_config
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
        msg_ok "SSH port changed to $new_port"
        if command -v ufw &>/dev/null; then
          ufw allow "$new_port"/tcp
        fi
        _log_write "SSH port changed to $new_port"
      fi
      ;;
  esac
  pause
}

# ---- Help ----
system_help() {
  msg_title "$(tr MOD_SYSTEM "System Management") Help"
  msg ""
  msg "  fusionbox system info           $(tr SYS_INFO "System information overview")"
  msg "  fusionbox system bbr            $(tr SYS_BBR "BBR management")"
  msg "  fusionbox system benchmark      $(tr SYS_BENCHMARK "Run system benchmark")"
  msg "  fusionbox system monitor        $(tr SYS_MONITOR "Real-time system monitor")"
  msg "  fusionbox system backup         $(tr SYS_BACKUP "Backup system configs")"
  msg "  fusionbox system restore        $(tr SYS_RESTORE "Restore from backup")"
  msg "  fusionbox system update         $(tr SYS_UPDATE "Update system packages")"
  msg "  fusionbox system clean          $(tr SYS_CLEAN "System cleanup")"
  msg "  fusionbox system swap           Swap management"
  msg "  fusionbox system security       Security audit & hardening"
  msg ""
}

# ---- Interactive Menu ----
system_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(tr MOD_SYSTEM "System Management")"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) $(tr SYS_INFO "System Information")"
    msg "  ${F_GREEN}2${F_RESET}) $(tr SYS_BBR "BBR Management")"
    msg "  ${F_GREEN}3${F_RESET}) $(tr SYS_BENCHMARK "Run Benchmark")"
    msg "  ${F_GREEN}4${F_RESET}) $(tr SYS_MONITOR "System Monitor")"
    msg "  ${F_GREEN}5${F_RESET}) $(tr SYS_BACKUP "Backup System")"
    msg "  ${F_GREEN}6${F_RESET}) $(tr SYS_RESTORE "Restore System")"
    msg "  ${F_GREEN}7${F_RESET}) $(tr SYS_UPDATE "Update System")"
    msg "  ${F_GREEN}8${F_RESET}) $(tr SYS_CLEAN "System Cleanup")"
    msg "  ${F_GREEN}9${F_RESET}) Swap & Security"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "$(tr MSG_SELECT "Select") [0-9]: " choice
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
