# FusionBox App Market Module
# One-click software installation

# App database: category, name, pkg_manager_packages, description
MARKET_APPS=(
  "$(L MSG_MARKET_0215)"
  "$(L MSG_MARKET_0216)"
  "$(L MSG_MARKET_0217)"
  "$(L MSG_MARKET_0218)"
  "$(L MSG_MARKET_0219)"
  "$(L MSG_MARKET_0220)"
  "$(L MSG_MARKET_0221)"
  "$(L MSG_MARKET_0222)"

  "$(L MSG_MARKET_0223)"
  "$(L MSG_MARKET_0224)"
  "$(L MSG_MARKET_0225)"
  "$(L MSG_MARKET_0226)"
  "$(L MSG_MARKET_0227)"
  "$(L MSG_MARKET_0228)"
  "$(L MSG_MARKET_0229)"
  "$(L MSG_MARKET_0230)"
  "$(L MSG_MARKET_0231)"
  "$(L MSG_MARKET_0232)"

  "$(L MSG_MARKET_0233)"
  "$(L MSG_MARKET_0234)"
  "$(L MSG_MARKET_0235)"
  "$(L MSG_MARKET_0236)"
  "$(L MSG_MARKET_0237)"
  "$(L MSG_MARKET_0238)"
  "$(L MSG_MARKET_0239)"
  "$(L MSG_MARKET_0240)"
  "$(L MSG_MARKET_0241)"
  "$(L MSG_MARKET_0242)"
  "$(L MSG_MARKET_0243)"
  "$(L MSG_MARKET_0244)"
  "$(L MSG_MARKET_0245)"
  "$(L MSG_MARKET_0246)"
  "$(L MSG_MARKET_0247)"
  "$(L MSG_MARKET_0248)"

  "$(L MSG_MARKET_0249)"
  "$(L MSG_MARKET_0250)"
  "$(L MSG_MARKET_0251)"
  "$(L MSG_MARKET_0252)"
  "$(L MSG_MARKET_0253)"
  "$(L MSG_MARKET_0254)"
  "$(L MSG_MARKET_0255)"
  "$(L MSG_MARKET_0256)"

  "$(L MSG_MARKET_0257)"
  "$(L MSG_MARKET_0258)"
  "$(L MSG_MARKET_0259)"
  "$(L MSG_MARKET_0260)"
  "$(L MSG_MARKET_0261)"

  "$(L MSG_MARKET_0262)"
  "$(L MSG_MARKET_0263)"
  "$(L MSG_MARKET_0264)"

  "$(L MSG_MARKET_0265)"
  "$(L MSG_MARKET_0266)"
  "$(L MSG_MARKET_0267)"
  "$(L MSG_MARKET_0268)"

  "$(L MSG_MARKET_0269)"
  "$(L MSG_MARKET_0270)"
  "$(L MSG_MARKET_0271)"
  "$(L MSG_MARKET_0272)"

  "$(L MSG_MARKET_0273)"
  "$(L MSG_MARKET_0274)"
  "$(L MSG_MARKET_0275)"
  "$(L MSG_MARKET_0276)"

  "$(L MSG_MARKET_0277)"
  "$(L MSG_MARKET_0278)"
  "$(L MSG_MARKET_0279)"
  "$(L MSG_MARKET_0429)"
  "$(L MSG_MARKET_0280)"
  "$(L MSG_MARKET_0281)"
  "$(L MSG_MARKET_0282)"
  "$(L MSG_MARKET_0283)"
  "$(L MSG_MARKET_0284)"
  "$(L MSG_MARKET_0285)"
  "$(L MSG_MARKET_0286)"
  "$(L MSG_MARKET_0287)"
  "$(L MSG_MARKET_0288)"
)

market_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    managed)
      _require_root
      [[ $# -ge 1 ]] || { market_managed_help; return 2; }
      if ! _require_python3 "$(L MSG_MARKET_0289)"; then return 1; fi
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
  [[ $# -eq 1 && -e "$path" ]] || { msg_err "$(L MSG_MARKET_0290)"; return 2; }
  if ! command -v clamscan &>/dev/null; then
    confirm "$(L MSG_MARKET_0291)" || return 1
    _install_pkg clamav || { msg_err "$(L MSG_MARKET_0292)"; return 1; }
    freshclam 2>/dev/null || msg_warn "$(L MSG_MARKET_0293)"
  fi
  local log="/root/clamav-scan-$(date +%Y%m%d%H%M%S).log"
  msg_info "$(L MSG_MARKET_0294 "$path")"
  local rc=0
  clamscan -ri --exclude-dir="^/sys" --exclude-dir="^/proc" --exclude-dir="^/dev" "$path" > "$log" 2>&1 || rc=$?
  grep -E "^(\[)?/?|SUMMARY|Infected files|Total errors|Infected:" "$log" 2>/dev/null | tail -15 || tail -15 "$log"
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_MARKET_0295)"
  elif [[ $rc -eq 1 ]]; then
    msg_warn "$(L MSG_MARKET_0296 "$log")"
    return 1
  else
    msg_err "$(L MSG_MARKET_0297 "$rc" "$log")"
    return 1
  fi
  chmod 600 "$log"
}

market_list() {
  local filter="${1:-}"
  msg_title "$(L MSG_MARKET_0298)"
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
          dev)      msg "$(L MSG_MARKET_0299 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          net)      msg "$(L MSG_MARKET_0300 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          sys)      msg "$(L MSG_MARKET_0301 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          web)      msg "$(L MSG_MARKET_0302 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          proxy)    msg "$(L MSG_MARKET_0303 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          media)    msg "$(L MSG_MARKET_0304 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          docker)   msg "$(L MSG_MARKET_0305 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          monitor)  msg "$(L MSG_MARKET_0306 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          security) msg "$(L MSG_MARKET_0307 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
          utility)  msg "$(L MSG_MARKET_0308 "${F_BOLD}" "${F_CYAN}" "${F_RESET}")" ;;
        esac
      fi
      # Check if installed
      local installed=""
      if command -v "$(echo "$pkg" | cut -d' ' -f1)" &>/dev/null; then
        installed="$(L MSG_MARKET_0309 "${F_GREEN}" "${F_RESET}")"
      fi
      msg "  ${F_GREEN}$name${F_RESET} - $desc$installed"
    fi
  done
  msg ""
  msg_info "$(L MSG_MARKET_0310)"
  pause
}

# ---- Search ----
market_search() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    read -p "$(L MSG_MARKET_0311)" query
  fi

  msg_title "$(L MSG_MARKET_0312 "$query")"
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
  [[ $found -eq 0 ]] && msg "$(L MSG_MARKET_0313)"
  pause
}

# ---- Install ----
market_install() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    market_list
    read -p "$(L MSG_MARKET_0314)" app_name
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
    msg_err "$(L MSG_MARKET_0315 "$app_name")"
    msg_info "$(L MSG_MARKET_0316)"
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
      msg_info "$(L MSG_MARKET_0317)"
      curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy 2>/dev/null && \
        chmod +x /usr/local/bin/caddy && \
        msg_ok "$(L MSG_MARKET_0318)" || \
        _install_caddy_from_pkg
      _log_write "$(L MSG_MARKET_0319)"
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
  msg_info "$(L MSG_MARKET_0320 "$found" "${pkgs[*]}")"
  if _install_pkg "${pkgs[@]}"; then
    msg_ok "$(L MSG_MARKET_0321 "$found")"
    _log_write "$(L MSG_MARKET_0322 "$found")"
  else
    msg_err "$(L MSG_MARKET_0323 "$found")"
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
  msg_info "$(L MSG_MARKET_0324)"
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
    msg_err "$(L MSG_MARKET_0325)"
  fi
  _log_write "$(L MSG_MARKET_0326)"
  pause
}

_install_go() {
  msg_info "$(L MSG_MARKET_0327)"
  local go_ver; go_ver=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -1)
  [[ -z "$go_ver" ]] && go_ver="go1.22.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  curl -fsSL "https://go.dev/dl/${go_ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz 2>/dev/null && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go && \
    msg_ok "$(L MSG_MARKET_0328 "$go_ver")" || msg_err "$(L MSG_MARKET_0329)"
  rm -f /tmp/go.tar.gz
  _log_write "$(L MSG_MARKET_0330)"
  pause
}

_install_rust() {
  msg_info "$(L MSG_MARKET_0331)"
  # 下载到临时文件再执行，不再 curl|bash
  local rs_sh
  rs_sh=$(mktemp)
  if _download https://sh.rustup.rs "$rs_sh" && sh "$rs_sh" -y --profile minimal; then
    if [[ -f "$HOME/.cargo/bin/rustc" ]]; then
      msg_ok "$(L MSG_MARKET_0332 "$($HOME/.cargo/bin/rustc --version)")"
    fi
  else
    msg_err "$(L MSG_MARKET_0333)"
  fi
  rm -f "$rs_sh"
  _log_write "$(L MSG_MARKET_0334)"
  pause
}

_install_wordpress() {
  _require_root
  msg_info "$(L MSG_MARKET_0335)"

  # Check prerequisites
  if ! command -v nginx &>/dev/null && ! command -v apache2 &>/dev/null; then
    msg_warn "$(L MSG_MARKET_0336)"
    if ! confirm "$(L MSG_MARKET_0337)"; then return; fi
  fi

  read -p "$(L MSG_MARKET_0338)" wp_domain
  [[ -z "$wp_domain" ]] && wp_domain="localhost"

  local wp_root="/var/www/$wp_domain"
  mkdir -p "$wp_root"

  # Download WordPress
  curl -fsSL https://wordpress.org/latest.tar.gz -o /tmp/wordpress.tar.gz 2>/dev/null || {
    msg_err "$(L MSG_MARKET_0339)"
    pause; return
  }
  tar xzf /tmp/wordpress.tar.gz -C /tmp
  cp -r /tmp/wordpress/* "$wp_root/"
  chmod -R 755 "$wp_root"
  rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

  msg_ok "$(L MSG_MARKET_0340 "$wp_root")"
  msg_info "$(L MSG_MARKET_0341)"
  msg_info "$(L MSG_MARKET_0342 "$wp_domain")"
  _log_write "$(L MSG_MARKET_0343 "$wp_root")"
  pause
}

_install_prometheus() {
  _require_root
  local ver="2.52.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "$(L MSG_MARKET_0344 "$ver")"
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/prometheus/releases/download/v${ver}/prometheus-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/prometheus.tar.gz" || { msg_err "下载失败"; rm -rf "$tmpdir"; return; }

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
  msg_ok "$(L MSG_MARKET_0345)"
  rm -rf "$tmpdir"
  _log_write "$(L MSG_MARKET_0346)"
  pause
}

_install_node_exporter() {
  _require_root
  local ver="1.7.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  msg_info "$(L MSG_MARKET_0347 "$ver")"
  local tmpdir=$(mktemp -d)
  _download "https://github.com/prometheus/node_exporter/releases/download/v${ver}/node_exporter-${ver}.linux-${arch}.tar.gz" \
    "$tmpdir/ne.tar.gz" || { msg_err "下载失败"; rm -rf "$tmpdir"; return; }

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
  msg_ok "$(L MSG_MARKET_0348)"
  rm -rf "$tmpdir"
  _log_write "$(L MSG_MARKET_0349)"
  pause
}

# ---- Remove ----
market_remove() {
  _require_root
  local app_name="${1:-}"
  if [[ -z "$app_name" ]]; then
    read -p "$(L MSG_MARKET_0350)" app_name
  fi

  for app in "${MARKET_APPS[@]}"; do
    local name="${app#*:}"; name="${name%%:*}"
    if [[ "${name,,}" == "${app_name,,}" ]]; then
      local rest="${app#*:}"
      local rest2="${rest#*:}"
      local pkg="${rest2%%:*}"
      if confirm "$(L MSG_MARKET_0351 "$name")"; then
        case "$F_PKG_MGR" in
          apt) apt-get remove -y "$pkg" ;;
          yum) yum remove -y "$pkg" ;;
          apk) apk del "$pkg" ;;
        esac
        msg_ok "$(L MSG_MARKET_0352 "$name")"
        _log_write "$(L MSG_MARKET_0353 "$name")"
      fi
      pause
      return
    fi
  done
  msg_err "$(L MSG_MARKET_0315 "$app_name")"
  pause
}

# ---- Category View ----
market_category() {
  local cat="${1:-}"
  if [[ -z "$cat" ]]; then
    msg_title "$(L MSG_MARKET_0354)"
    msg ""
    msg "$(L MSG_MARKET_0355 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0356 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0357 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0358 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0359 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0360 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0361 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0362 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0363 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0364 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_MARKET_0365)" cat
  fi
  market_list "$cat"
}

# ---- Help ----
market_help() {
  msg_title "$(L MSG_MARKET_0366)"
  msg ""
  msg "$(L MSG_MARKET_0367)"
  msg "$(L MSG_MARKET_0368)"
  msg "  fusionbox market managed domain nginx --domain example.com --confirm   HTTP-only owned host mapping"
  msg "  fusionbox market managed domain nginx --remove-domain --confirm  remove owned mapping"
  msg "  fusionbox market managed tls nginx --cert /path/fullchain.pem --key /path/key.pem --confirm"
  msg "$(L MSG_MARKET_0369)"
  msg "$(L MSG_MARKET_0370)"
  msg "$(L MSG_MARKET_0371)"
  msg "$(L MSG_MARKET_0372)"
  msg "$(L MSG_MARKET_0373)"
  msg "$(L MSG_MARKET_0374)"
  msg "$(L MSG_MARKET_0375)"
  msg "$(L MSG_MARKET_0376)"
  msg "$(L MSG_MARKET_0377)"
  msg "$(L MSG_MARKET_0378)"
  msg ""
  msg "$(L MSG_MARKET_0379)"
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
  msg_title "$(L MSG_MARKET_0380)"
  msg ""
  msg "$(L MSG_MARKET_0381)"
  msg ""
  msg "$(L MSG_MARKET_0382)"
  msg "$(L MSG_MARKET_0383 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0384 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0385 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0386 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0387 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0388 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0389 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0390 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MARKET_0391 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_MARKET_0392)"
  msg "$(L MSG_MARKET_0393)"
  msg "$(L MSG_MARKET_0394)"
  msg "$(L MSG_MARKET_0395)"
  msg "$(L MSG_MARKET_0396)"
  msg "$(L MSG_MARKET_0397)"
  msg ""
  msg "$(L MSG_MARKET_0398)"
  msg "        fusionbox market managed catalog"
  msg "$(L MSG_MARKET_0399)"
  msg ""
}

# ---- Interactive Menu ----
market_managed_menu() {
  _require_root
  local action port domain cert key app
  local -a args=()
  read -r -p "$(L MSG_MARKET_0400)" app || return 1
  app="${app:-nginx}"
  # python3 is a hard dependency here: without it the catalog probe would fail
  # silently and the user would be told "不支持的受管应用 ID", which is wrong.
  if ! _require_python3 "$(L MSG_MARKET_0289)"; then
    return 1
  fi
  local catalog_out
  if ! catalog_out=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog 2>&1); then
    msg_err "$(L MSG_MARKET_0401)"
    msg "$catalog_out"
    return 1
  fi
  if ! grep -q "^${app}:" <<< "$catalog_out"; then
    msg_err "$(L MSG_MARKET_0402 "$app")"
    msg_info "$(L MSG_MARKET_0403)"
    return 1
  fi
  read -r -p "$(L MSG_MARKET_0404)" action || return 1
  case "$action" in
    tls-refresh)
      confirm "$(L MSG_MARKET_0405)" || return 1
      args+=(--confirm) ;;
    tls)
      msg_warn "$(L MSG_MARKET_0406)"
      read -r -p "$(L MSG_MARKET_0407)" cert || return 1
      if [[ -n "$cert" ]]; then
        read -r -p "$(L MSG_MARKET_0408)" key || return 1
        args+=(--cert "$cert" --key "$key")
      else args+=(--disable-tls); fi
      confirm "$(L MSG_MARKET_0409)" || return 1
      args+=(--confirm) ;;
    domain)
      msg_warn "$(L MSG_MARKET_0410)"
      read -r -p "$(L MSG_MARKET_0411)" domain || return 1
      confirm "$(L MSG_MARKET_0412)" || return 1
      args+=(--confirm)
      if [[ -n "$domain" ]]; then args+=(--domain "$domain"); else args+=(--remove-domain); fi ;;
    catalog|status) ;;
    install|reinstall|update|uninstall)
      if [[ "$action" == install ]]; then
        local details
        details=$(python3 "$FUSION_SRC/lib/market_apps.py" catalog "$app" 2>/dev/null | grep -F "$app:" | head -1) || true
        if [[ "$details" == *"HIGH PRIVILEGE"* ]]; then
          msg_warn "$(L MSG_MARKET_0413)"
          read -r -p "$(L MSG_MARKET_0414)" risk_ack || return 1
          args+=(--risk-ack "$risk_ack")
        fi
      fi
      confirm "$(L MSG_MARKET_0415 "$action")" || return 1
      args+=(--confirm)
      if [[ "$action" == reinstall ]]; then
        confirm "$(L MSG_MARKET_0416)" || return 1
        args+=(--reuse-data)
      fi
      if [[ "$action" == install || "$action" == reinstall ]]; then
        read -r -p "$(L MSG_MARKET_0417)" port || return 1
        [[ -z "$port" ]] || args+=(--port "$port")
        if confirm "$(L MSG_MARKET_0418)"; then args+=(--auto-port); fi
      fi ;;
    *) msg_err "$(L MSG_MARKET_0419)"; return 1 ;;
  esac
  python3 "$FUSION_SRC/lib/market_apps.py" "$action" "$app" "${args[@]}"
}

market_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_MARKET_0420)"
    msg ""
    msg "$(L MSG_MARKET_0421 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0422 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0423 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0424 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0425 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MARKET_0426 "${F_GREEN}" "${F_RESET}" "$(_market_managed_count)")"
    msg "$(L MSG_MARKET_0427 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_MARKET_0428)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
