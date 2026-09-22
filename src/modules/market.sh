# FusionBox App Market Module
# One-click software installation

# App database: category, name, pkg_manager_packages, description
MARKET_APPS=(
  "$(L MSG_MARKET_0001)"
  "$(L MSG_MARKET_0002)"
  "$(L MSG_MARKET_0003)"
  "$(L MSG_MARKET_0004)"
  "$(L MSG_MARKET_0005)"
  "$(L MSG_MARKET_0006)"
  "$(L MSG_MARKET_0007)"
  "$(L MSG_MARKET_0008)"

  "$(L MSG_MARKET_0009)"
  "$(L MSG_MARKET_0010)"
  "$(L MSG_MARKET_0011)"
  "$(L MSG_MARKET_0012)"
  "$(L MSG_MARKET_0013)"
  "$(L MSG_MARKET_0014)"
  "$(L MSG_MARKET_0015)"
  "$(L MSG_MARKET_0016)"
  "$(L MSG_MARKET_0017)"
  "$(L MSG_MARKET_0018)"

  "$(L MSG_MARKET_0019)"
  "$(L MSG_MARKET_0020)"
  "$(L MSG_MARKET_0021)"
  "$(L MSG_MARKET_0022)"
  "$(L MSG_MARKET_0023)"
  "$(L MSG_MARKET_0024)"
  "$(L MSG_MARKET_0025)"
  "$(L MSG_MARKET_0026)"
  "$(L MSG_MARKET_0027)"
  "$(L MSG_MARKET_0028)"
  "$(L MSG_MARKET_0029)"
  "$(L MSG_MARKET_0030)"
  "$(L MSG_MARKET_0031)"
  "$(L MSG_MARKET_0032)"
  "$(L MSG_MARKET_0033)"
  "$(L MSG_MARKET_0034)"

  "$(L MSG_MARKET_0035)"
  "$(L MSG_MARKET_0036)"
  "$(L MSG_MARKET_0037)"
  "$(L MSG_MARKET_0038)"
  "$(L MSG_MARKET_0039)"
  "$(L MSG_MARKET_0040)"
  "$(L MSG_MARKET_0041)"
  "$(L MSG_MARKET_0042)"

  "$(L MSG_MARKET_0043)"
  "$(L MSG_MARKET_0044)"
  "$(L MSG_MARKET_0045)"
  "$(L MSG_MARKET_0046)"
  "$(L MSG_MARKET_0047)"

  "$(L MSG_MARKET_0048)"
  "$(L MSG_MARKET_0049)"
  "$(L MSG_MARKET_0050)"

  "$(L MSG_MARKET_0051)"
  "$(L MSG_MARKET_0052)"
  "$(L MSG_MARKET_0053)"
  "$(L MSG_MARKET_0054)"

  "$(L MSG_MARKET_0055)"
  "$(L MSG_MARKET_0056)"
  "$(L MSG_MARKET_0057)"
  "$(L MSG_MARKET_0058)"

  "$(L MSG_MARKET_0059)"
  "$(L MSG_MARKET_0060)"
  "$(L MSG_MARKET_0061)"
  "$(L MSG_MARKET_0062)"

  "$(L MSG_MARKET_0063)"
  "$(L MSG_MARKET_0064)"
  "$(L MSG_MARKET_0065)"
  "utility:Warp:cloudflare-warp:Cloudflare WARP VPN"
  "$(L MSG_MARKET_0066)"
  "$(L MSG_MARKET_0067)"
  "$(L MSG_MARKET_0068)"
  "$(L MSG_MARKET_0069)"
  "$(L MSG_MARKET_0070)"
  "$(L MSG_MARKET_0071)"
  "$(L MSG_MARKET_0072)"
  "$(L MSG_MARKET_0073)"
  "$(L MSG_MARKET_0074)"
)

market_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    managed)
      _require_root
      [[ $# -ge 1 ]] || { market_managed_help; return 2; }
      if ! _require_python3 "$(L MSG_MARKET_0075)"; then return 1; fi
      # Stage feedback: image pull + container up + health wait are the slow
      # parts. The Python layer keeps its stdout machine-readable, so tell the
      # user what to expect before the (possibly long) call instead of faking
      # per-phase timing we cannot observe from here.
      case "${1:-}" in
        install|reinstall)
          msg_info "$(_tr MSG_MARKET_STAGES "过程: 校验端口 → 拉取镜像 → 创建容器 → 等待健康检查（可能较慢，请勿中断）")"
          ;;
      esac
      python3 "$FUSION_SRC/lib/market_apps.py" "$@"
      ;;
    clamav|scan)      market_clamav "$@" ;;
    list|l)           market_list "$@" ;;
    search|s)         market_search "$@" ;;
    install|i)        market_install "$@" ;;
    remove|rm)        market_remove "$@" ;;
    category|cat)     market_category "$@" ;;
    menu|main)        market_menu ;;
    help|h)           market_help ;;
    *)                _module_unknown_cmd "market" "$cmd" ;;
  esac
}

# ---- List all apps ----# ---- ClamAV 病毒扫描动作 (G19)：为 market 的 clamav 安装条目补扫描能力 ----
market_clamav() {
  _require_root
  local path="${1:-}"
  [[ $# -eq 1 && -e "$path" ]] || { msg_err "$(L MSG_MARKET_0076)"; return 2; }
  if ! command -v clamscan &>/dev/null; then
    confirm "$(L MSG_MARKET_0077)" || return 1
    _install_pkg clamav || { msg_err "$(L MSG_MARKET_0078)"; return 1; }
    freshclam 2>/dev/null || msg_warn "$(L MSG_MARKET_0079)"
  fi
  local log="/root/clamav-scan-$(date +%Y%m%d%H%M%S).log"
  msg_info "$(L MSG_MARKET_0080 "$path")"
  local rc=0
  clamscan -ri --exclude-dir="^/sys" --exclude-dir="^/proc" --exclude-dir="^/dev" "$path" > "$log" 2>&1 || rc=$?
  grep -E "^(\[)?/?|SUMMARY|Infected files|Total errors|Infected:" "$log" 2>/dev/null | tail -15 || tail -15 "$log"
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_MARKET_0081)"
  elif [[ $rc -eq 1 ]]; then
    msg_warn "$(L MSG_MARKET_0082 "$log")"
    return 1
  else
    msg_err "$(L MSG_MARKET_0083 "$rc" "$log")"
    return 1
  fi
  chmod 600 "$log"
}

market_list() {
  local filter="${1:-}"
  msg_title "$(L MSG_MARKET_0084)"
  msg ""

  local current_cat=""
  for app in "${MARKET_APPS[@]}"; do
    local cat="${app%%:*}"
    local rest="${app#*:}"
    local name="${rest%%:*}"
    local rest2="${rest#*:}"
    local pkg="${rest2%%:*}"
    local desc="${rest2#*:}"

    if [[ -z "$filter" || "$cat" == "$filter" ]]; then
      if [[ "$cat" != "$current_cat" ]]; then
        current_cat="$cat"
        case "$cat" in
          dev)      msg "$(L MSG_MARKET_0085 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          net)      msg "$(L MSG_MARKET_0086 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          sys)      msg "$(L MSG_MARKET_0087 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          web)      msg "$(L MSG_MARKET_0088 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          proxy)    msg "$(L MSG_MARKET_0089 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          media)    msg "$(L MSG_MARKET_0090 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          docker)   msg "$(L MSG_MARKET_0091 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          monitor)  msg "$(L MSG_MARKET_0092 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          security) msg "$(L MSG_MARKET_0093 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          utility)  msg "$(L MSG_MARKET_0094 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
        esac
      fi
      # Check if installed
      local installed=""
      if command -v "$(echo "$pkg" | cut -d' ' -f1)" &>/dev/null; then
        installed="$(L MSG_MARKET_0095 "${F_GREEN}" "${F_RESET}")"
      fi
      msg "  ${F_GREEN}$name${F_RESET} - $desc$installed"
    fi
  done
  msg ""
  msg_info "$(L MSG_MARKET_0096)"
  pause
}

# ---- Search ----
market_search() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    read -p "$(L MSG_MARKET_0097)" query
  fi

  msg_title "$(L MSG_MARKET_0098 "$query")"
  msg ""
  local found=0
  for app in "${MARKET_APPS[@]}"; do
    if echo "$app" | grep -qi "$query"; then
      local name="${app#*:}"; name="${name%%:*}"
      local desc="${app##*:}"
      msg "  ${F_GREEN}$name${F_RESET} - $desc"
      found=1
    fi
  done
  [[ $found -eq 0 ]] && msg "$(L MSG_MARKET_0099)"
  pause
}

# ---- Install ----
market_install() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    market_list
    read -p "$(L MSG_MARKET_0100)" app_name
  fi

  local found=""
  local pkg_name=""
  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" || "${name,,}" == *"${app_name,,}"* ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      pkg_name="${rest2%%:*}"
      found="$name"
      break
    fi
  done

  if [[ -z "$found" ]]; then
    msg_err "$(L MSG_MARKET_0101 "$app_name")"
    msg_info "$(L MSG_MARKET_0102)"
    pause
    return
  fi

  # Handle special installs
  case "$found" in
    "Docker CE")
      _load_module panels   # panels 函数未加载时会 command not found
      panels_docker_install
      return
      ;;
    "Caddy")
      msg_info "$(L MSG_MARKET_0103)"
      curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy 2>/dev/null && \
        chmod +x /usr/local/bin/caddy && \
        msg_ok "$(L MSG_MARKET_0104)" || \
        _install_caddy_from_pkg
      _log_write "$(L MSG_MARKET_0105)"
      pause
      return
      ;;
    "Speedtest CLI")
      _install_pkg speedtest-cli 2>/dev/null || pip3 install speedtest-cli 2>/dev/null
      ;;
    "FRP")
      _load_module panels
      panels_frp
      return
      ;;
    "Rclone")
      _load_module panels
      panels_rclone
      return
      ;;
    "WordPress")
      _install_wordpress
      return
      ;;
    "Node.js")
      _install_nodejs
      return
      ;;
    "Go")
      _install_go
      return
      ;;
    "Rust")
      _install_rust
      return
      ;;
    "Prometheus")
      _install_prometheus
      return
      ;;
    "Node_Exporter")
      _install_node_exporter
      return
      ;;
  esac

  # Standard package install
  local pkgs=($pkg_name)
  msg_info "$(L MSG_MARKET_0106 "$found" "${pkgs[*]}")"
  if _install_pkg "${pkgs[@]}"; then
    msg_ok "$(L MSG_MARKET_0107 "$found")"
    _log_write "$(L MSG_MARKET_0108 "$found")"
  else
    msg_err "$(L MSG_MARKET_0109 "$found")"
  fi
  pause
}

_install_caddy_from_pkg() {
  case "$F_PKG_MGR" in
    apt) _install_pkg caddy ;;
    yum) _install_pkg caddy ;;
    apk) _install_pkg caddy ;;
  esac
}

_install_nodejs() {
  msg_info "$(L MSG_MARKET_0110)"
  # 下载到临时文件再执行，不再 curl|bash
  local ns_sh
  ns_sh=$(mktemp)
  if _download https://deb.nodesource.com/setup_20.x "$ns_sh" && bash "$ns_sh" && _install_pkg nodejs; then
    :
  elif _download https://rpm.nodesource.com/setup_20.x "$ns_sh" && bash "$ns_sh" && _install_pkg nodejs; then
    :
  else
    _install_pkg nodejs
  fi
  rm -f "$ns_sh"
  if command -v node &>/dev/null; then
    msg_ok "Node.js: $(node --version 2>/dev/null)"
    msg_ok "npm: $(npm --version 2>/dev/null)"
  else
    msg_err "$(L MSG_MARKET_0111)"
  fi
  _log_write "$(L MSG_MARKET_0112)"
  pause
}

_install_go() {
  msg_info "$(L MSG_MARKET_0113)"
  local go_ver; go_ver=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1)
  [[ -z "$go_ver" ]] && go_ver="go1.22.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  curl -fsSL "https://go.dev/dl/${go_ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz 2>/dev/null && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go && \
    msg_ok "$(L MSG_MARKET_0114 "$go_ver")" || msg_err "$(L MSG_MARKET_0115)"
  rm -f /tmp/go.tar.gz
  _log_write "$(L MSG_MARKET_0116)"
  pause
}

_install_rust() {
  msg_info "$(L MSG_MARKET_0117)"
  # 下载到临时文件再执行，不再 curl|bash
  local rs_sh
  rs_sh=$(mktemp)
  if _download https://sh.rustup.rs "$rs_sh" && sh "$rs_sh" -y --profile minimal; then
    if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
      msg_ok "$(L MSG_MARKET_0118 "$($HOME/.cargo/bin/rustc --version)")"
    fi
  else
    msg_err "$(L MSG_MARKET_0119)"
  fi
  rm -f "$rs_sh"
  _log_write "$(L MSG_MARKET_0120)"
  pause
}

_install_wordpress() {
  _require_root
  msg_info "$(L MSG_MARKET_0121)"

  # Check prerequisites
  if ! command -v nginx &>/dev/null && ! command -v apache2 &>/dev/null; then
    msg_warn "$(L MSG_MARKET_0122)"
    if ! confirm "$(L MSG_MARKET_0123)"; then return; fi
  fi

  read -p "$(L MSG_MARKET_0124)" wp_domain
  [[ -z "$wp_domain" ]] && wp_domain="localhost"

  local wp_root="/var/www/$wp_domain"
  mkdir -p "$wp_root"

  # Download WordPress
  curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz 2>/dev/null || {
    msg_err "$(L MSG_MARKET_0125)"
    pause; return
  }
  tar xzf /tmp/wordpress.tar.gz -C /tmp
  cp -r /tmp/wordpress/* "$wp_root/"
  chmod -R 755 "$wp_root"
  rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

  msg_ok "$(L MSG_MARKET_0126 "$wp_root")"
  msg_info "$(L MSG_MARKET_0127)"
  msg_info "$(L MSG_MARKET_0128 "$wp_domain")"
  _log_write "$(L MSG_MARKET_0129 "$wp_root")"
  pause
}

_install_prometheus() {
  _require_root
  local ver="2.52.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "$(L MSG_MARKET_0130 "$ver")"
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/prometheus/releases/download/v${ver}/prometheus-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/prometheus.tar.gz" || { msg_err "$(L MSG_MARKET_0125)"; rm -rf "$tmpdir"; return; }

  tar xzf "$tmpdir/prometheus.tar.gz" -C "$tmpdir"
  mkdir -p /etc/prometheus /var/lib/prometheus
  cp "$tmpdir/prometheus-${ver}.linux-${arch}"/{prometheus,promtool} /usr/local/bin/
  cp -r "$tmpdir/prometheus-${ver}.linux-${arch}"/{consoles,console_libraries} /etc/prometheus/
  cp "$tmpdir/prometheus-${ver}.linux-${arch}"/prometheus.yml /etc/prometheus/

  useradd -rs /bin/false prometheus 2>/dev/null || true
  chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

  cat > /lib/systemd/system/prometheus.service << PR2
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus
Restart=on-failure

[Install]
WantedBy=multi-user.target
PR2
  systemctl daemon-reload && systemctl enable --now prometheus 2>/dev/null
  msg_ok "$(L MSG_MARKET_0131)"
  rm -rf "$tmpdir"
  _log_write "$(L MSG_MARKET_0132)"
  pause
}

_install_node_exporter() {
  _require_root
  local ver="1.7.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "$(L MSG_MARKET_0133 "$ver")"
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/ne.tar.gz" || { msg_err "$(L MSG_MARKET_0125)"; rm -rf "$tmpdir"; return; }

  tar xzf "$tmpdir/ne.tar.gz" -C "$tmpdir"
  cp "$tmpdir/node_exporter-${ver}.linux-${arch}/node_exporter" /usr/local/bin/

  useradd -rs /bin/false node_exporter 2>/dev/null || true

  cat > /lib/systemd/system/node_exporter.service << NE2
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure

[Install]
WantedBy=multi-user.target
NE2
  systemctl daemon-reload && systemctl enable --now node_exporter 2>/dev/null
  msg_ok "$(L MSG_MARKET_0134)"
  rm -rf "$tmpdir"
  _log_write "$(L MSG_MARKET_0135)"
  pause
}

# ---- Remove ----
market_remove() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    read -p "$(L MSG_MARKET_0136)" app_name
  fi

  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      local pkg="${rest2%%:*}"
      if confirm "$(L MSG_MARKET_0137 "$name")"; then
        case "$F_PKG_MGR" in
          apt) apt-get remove -y "$pkg" ;;
          yum) yum remove -y "$pkg" ;;
          apk) apk del "$pkg" ;;
        esac
        msg_ok "$(L MSG_MARKET_0138 "$name")"
        _log_write "$(L MSG_MARKET_0139 "$name")"
      fi
      pause
      return
    fi
  done
  msg_err "$(L MSG_MARKET_0101 "$app_name")"
  pause
}

# ---- Category View ----
market_category() {
  local cat="${1:-}"
  if [[ -z "$cat" ]]; then
    msg_title "$(L MSG_MARKET_0140)"
    msg ""
    msg "$(L MSG_MARKET_0141 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0142 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0143 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0144 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0145 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0146 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0147 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0148 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0149 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0150 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_MARKET_0151)" cat
  fi
  market_list "$cat"
}

# ---- Help ----
market_help() {
  msg_title "$(L MSG_MARKET_0152)"
  msg ""
  msg "$(L MSG_MARKET_0153)"
  msg "$(L MSG_MARKET_0154)"
  msg "  fusionbox market managed domain nginx --domain example.com --confirm   HTTP-only owned host mapping"
  msg "  fusionbox market managed domain nginx --remove-domain --confirm  remove owned mapping"
  msg "  fusionbox market managed tls nginx --cert /path/fullchain.pem --key /path/key.pem --confirm"
  msg "$(L MSG_MARKET_0155)"
  msg "$(L MSG_MARKET_0156)"
  msg "$(L MSG_MARKET_0157)"
  msg "$(L MSG_MARKET_0158)"
  msg "$(L MSG_MARKET_0159)"
  msg "$(L MSG_MARKET_0160)"
  msg "$(L MSG_MARKET_0161)"
  msg "$(L MSG_MARKET_0162)"
  msg "$(L MSG_MARKET_0163)"
  msg "$(L MSG_MARKET_0164)"
  msg ""
  msg "$(L MSG_MARKET_0165)"
  msg ""
}

# Count of managed catalog entries, read live so the menu never goes stale.
_market_managed_count() {
  command -v python3 &>/dev/null || { printf '?'; return; }
  python3 "$FUSION_SRC/lib/market_apps.py" catalog 2>/dev/null | grep -c '^[a-z0-9][a-z0-9_-]*:' || printf '?'
}

# ---- Managed subcommand help (never let argparse leak English usage) ----
market_managed_help() {
  _require_root
  msg_title "$(L MSG_MARKET_0166)"
  msg ""
  msg "$(L MSG_MARKET_0167)"
  msg ""
  msg "$(L MSG_MARKET_0168)"
  msg "$(L MSG_MARKET_0169 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0170 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0171 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0172 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0173 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0174 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0175 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0176 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0177 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_MARKET_0178)"
  msg "$(L MSG_MARKET_0179)"
  msg "$(L MSG_MARKET_0180)"
  msg "$(L MSG_MARKET_0181)"
  msg "$(L MSG_MARKET_0182)"
  msg "$(L MSG_MARKET_0183)"
  msg ""
  msg "$(L MSG_MARKET_0184)"
  msg "        fusionbox market managed catalog"
  msg "$(L MSG_MARKET_0185)"
  msg ""
}

# ---- Interactive Menu ----
market_managed_menu() {
  _require_root
  local action port domain cert key app
  local -a args=()
  read -r -p "$(L MSG_MARKET_0186)" app || return 1
  app="${app:-nginx}"
  # python3 is a hard dependency here: without it the catalog probe would fail
  # silently and the user would be told "不支持的受管应用 ID", which is wrong.
  if ! _require_python3 "$(L MSG_MARKET_0075)"; then
    return 1
  fi
  local catalog_out
  if ! catalog_out=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog 2>&1); then
    msg_err "$(L MSG_MARKET_0187)"
    msg "$catalog_out"
    return 1
  fi
  if ! grep -q "^${app}:" <<< "$catalog_out"; then
    msg_err "$(L MSG_MARKET_0188 "$app")"
    msg_info "$(L MSG_MARKET_0189)"
    return 1
  fi
  read -r -p "$(L MSG_MARKET_0190)" action || return 1
  case "$action" in
    tls-refresh)
      confirm "$(L MSG_MARKET_0191)" || return 1
      args+=(--confirm) ;;
    tls)
      msg_warn "$(L MSG_MARKET_0192)"
      read -r -p "$(L MSG_MARKET_0193)" cert || return 1
      if [[ -n "$cert" ]]; then
        read -r -p "$(L MSG_MARKET_0194)" key || return 1
        args+=(--cert "$cert" --key "$key")
      else args+=(--disable-tls); fi
      confirm "$(L MSG_MARKET_0195)" || return 1
      args+=(--confirm) ;;
    domain)
      msg_warn "$(L MSG_MARKET_0196)"
      read -r -p "$(L MSG_MARKET_0197)" domain || return 1
      confirm "$(L MSG_MARKET_0198)" || return 1
      args+=(--confirm)
      if [[ -n "$domain" ]]; then args+=(--domain "$domain"); else args+=(--remove-domain); fi ;;
    catalog|status) ;;
    install|reinstall|update|uninstall)
      if [[ "$action" == install ]]; then
        local details
        details=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog "$app" 2>/dev/null | grep -F "$app:" | head -1) || true
        if [[ "$details" == *"HIGH PRIVILEGE"* ]]; then
          msg_warn "$(L MSG_MARKET_0199)"
          read -r -p "$(L MSG_MARKET_0200)" risk_ack || return 1
          args+=(--risk-ack "$risk_ack")
        fi
      fi
      confirm "$(L MSG_MARKET_0201 "$action")" || return 1
      args+=(--confirm)
      if [[ "$action" == reinstall ]]; then
        confirm "$(L MSG_MARKET_0202)" || return 1
        args+=(--reuse-data)
      fi
      if [[ "$action" == install || "$action" == reinstall ]]; then
        read -r -p "$(L MSG_MARKET_0203)" port || return 1
        [[ -z "$port" ]] || args+=(--port "$port")
        if confirm "$(L MSG_MARKET_0204)"; then args+=(--auto-port); fi
      fi ;;
    *) msg_err "$(L MSG_MARKET_0205)"; return 1 ;;
  esac
  python3 "$FUSION_SRC/lib/market_apps.py" "$action" "$app" "${args[@]}"
}

market_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_MARKET_0206)"
    msg ""
    msg "$(L MSG_MARKET_0207 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0208 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0209 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0210 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0211 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0212 "${F_GREEN}" "${F_RESET}" "$(_market_managed_count)")"
    msg "$(L MSG_MARKET_0213 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_MARKET_0214)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) market_list; pause ;;
      2) market_category; pause ;;
      3) market_search; pause ;;
      4) market_install; pause ;;
      5) market_remove; pause ;;
      6) market_managed_menu; pause ;;
      0) break ;;
    esac
  done
}
