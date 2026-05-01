# FusionBox Proxy Module
# Full sing-box proxy management

# ---- Paths ----
P_CORE_DIR="/etc/sing-box"
P_BIN_DIR="$P_CORE_DIR/bin"
P_CONF_DIR="$P_CORE_DIR/conf"
P_LOG_DIR="/var/log/sing-box"
P_CORE_BIN="$P_BIN_DIR/sing-box"
P_CONFIG_JSON="$P_CORE_DIR/config.json"
P_SH_DIR="$P_CORE_DIR/sh"
P_CADDY_BIN="/usr/local/bin/caddy"
P_CADDY_DIR="/etc/caddy"

# ---- Protocol definitions ----
P_PROTOCOLS=(
  "VLESS-REALITY" "vless" "tcp"
  "VLESS-HTTP2-REALITY" "vless" "http"
  "VMess-TCP" "vmess" "tcp"
  "VMess-HTTP" "vmess" "tcp"
  "VMess-WS" "vmess" "ws"
  "VMess-WS-TLS" "vmess" "ws"
  "VMess-H2-TLS" "vmess" "h2"
  "VMess-HTTPUpgrade-TLS" "vmess" "httpupgrade"
  "VLESS-WS-TLS" "vless" "ws"
  "VLESS-H2-TLS" "vless" "h2"
  "VLESS-HTTPUpgrade-TLS" "vless" "httpupgrade"
  "Trojan" "trojan" "tcp"
  "Trojan-WS-TLS" "trojan" "ws"
  "Trojan-H2-TLS" "trojan" "h2"
  "Trojan-HTTPUpgrade-TLS" "trojan" "httpupgrade"
  "Hysteria2" "hysteria2" "quic"
  "TUIC" "tuic" "quic"
  "Shadowsocks" "shadowsocks" "tcp"
  "AnyTLS" "anytls" "tcp"
  "Socks" "socks" "tcp"
)

P_SS_METHODS=(
  "aes-128-gcm" "aes-256-gcm"
  "chacha20-ietf-poly1305" "xchacha20-ietf-poly1305"
  "2022-blake3-aes-128-gcm" "2022-blake3-aes-256-gcm"
  "2022-blake3-chacha20-poly1305"
)

# ---- Main entry ----
proxy_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    install|i)          proxy_install "$@" ;;
    uninstall|un)       proxy_uninstall "$@" ;;
    add|a)              proxy_add "$@" ;;
    del|d|remove)       proxy_del "$@" ;;
    info|i)             proxy_info "$@" ;;
    change|c)           proxy_change "$@" ;;
    list|l)             proxy_list ;;
    start)              proxy_manage "start" ;;
    stop)               proxy_manage "stop" ;;
    restart)            proxy_manage "restart" ;;
    status|s)           proxy_status ;;
    log)                proxy_log ;;
    bbr)                proxy_bbr ;;
    update|u)           proxy_update "$@" ;;
    dns)                proxy_dns "$@" ;;
    url|qr)             proxy_url "$@" ;;
    version|v)          proxy_version ;;
    menu|main)          proxy_menu ;;
    help|h)             proxy_help ;;
    *)                  proxy_menu ;;
  esac
}

# ---- Install ----
proxy_install() {
  _require_root
  tr PROXY_INSTALLING "Installing sing-box core..."

  # Check existing
  if [[ -f "$P_CORE_BIN" ]]; then
    msg_warn "sing-box already installed"
    if ! confirm "$(tr MSG_CONFIRM "Reinstall?"). $(tr MSG_CONFIRM "Continue")"; then
      return
    fi
  fi

  # Create directories
  mkdir -p "$P_BIN_DIR" "$P_CONF_DIR" "$P_LOG_DIR" "$P_SH_DIR"

  # Detect arch
  local p_arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && p_arch="arm64"

  # Download latest sing-box
  msg_info "Downloading latest sing-box..."
  local tmpdir=$(mktemp -d)
  local core_ver
  core_ver=$(_download_sing_box_latest "$tmpdir" "$p_arch")

  if [[ -z "$core_ver" ]]; then
    msg_err "Failed to download sing-box. Check network."
    rm -rf "$tmpdir"
    return 1
  fi

  # Install binary
  if [[ -f "$tmpdir/sing-box" ]]; then
    cp "$tmpdir/sing-box" "$P_CORE_BIN"
    chmod +x "$P_CORE_BIN"
  else
    msg_err "Binary not found in download"
    rm -rf "$tmpdir"
    return 1
  fi

  # Generate TLS keypair
  msg_info "Generating TLS keypair..."
  local tls_out
  tls_out=$($P_CORE_BIN generate tls-keypair tls -m 456 2>/dev/null)
  echo "$tls_out" > "$P_CORE_DIR/bin/tls.cer"
  # Extract private key

  # Create default config.json
  _proxy_gen_main_config

  # Install systemd service
  _proxy_install_service

  # Verify
  if [[ -f "$P_CORE_BIN" ]]; then
    local ver=$($P_CORE_BIN version 2>/dev/null | head -1)
    msg_ok "sing-box installed: $ver"

    # Create symlinks
    ln -sf "$P_CORE_BIN" /usr/local/bin/sing-box 2>/dev/null
    ln -sf "$P_CORE_BIN" /usr/local/bin/sb 2>/dev/null

    # Add a default REALITY config
    msg_info "Creating default VLESS-REALITY config..."
    _proxy_add_reality_default

    rm -rf "$tmpdir"
    _log_write "sing-box installed: $ver"
  else
    msg_err "Installation failed"
    rm -rf "$tmpdir"
    return 1
  fi
}

_download_sing_box_latest() {
  local tmpdir="$1"; local arch="$2"
  local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local info; info=$(curl -s "$api_url" 2>/dev/null)
  local tag; tag=$(echo "$info" | grep '"tag_name"' | cut -d'"' -f4)
  [[ -z "$tag" ]] && return 1

  local filename="sing-box-${tag#v}-linux-$arch.tar.gz"
  local dl_url="https://github.com/SagerNet/sing-box/releases/download/$tag/$filename"
  msg_info "Downloading: $filename"
  _download "$dl_url" "$tmpdir/sing-box.tar.gz" || return 1

  tar xzf "$tmpdir/sing-box.tar.gz" -C "$tmpdir" 2>/dev/null
  # Find the binary (may be in a subdirectory)
  find "$tmpdir" -name "sing-box" -type f -exec cp {} "$tmpdir/" \; 2>/dev/null
  echo "$tag"
}

_proxy_gen_main_config() {
  cat > "$P_CONFIG_JSON" << 'CONFEOF'
{
  "log": {
    "level": "info",
    "output": "/var/log/sing-box/access.log",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "cf",
        "address": "https://1.1.1.1/dns-query",
        "address_resolver": "local",
        "detour": "direct"
      },
      {
        "tag": "local",
        "address": "local",
        "detour": "direct"
      }
    ],
    "rules": [
      {"domain": "example.com", "server": "local"}
    ]
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [],
    "auto_detect_interface": true
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
CONFEOF
}

_proxy_install_service() {
  if [[ "$F_INIT" == "systemd" ]]; then
    cat > /lib/systemd/system/sing-box.service << 'SEOF'
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=root
Type=simple
ExecStart=/etc/sing-box/bin/sing-box run -c /etc/sing-box/config.json -C /etc/sing-box/conf
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity
LimitNPROC=infinity

[Install]
WantedBy=multi-user.target
SEOF
    systemctl daemon-reload
    systemctl enable sing-box 2>/dev/null
  elif [[ "$F_INIT" == "openrc" ]]; then
    cat > /etc/init.d/sing-box << 'SEOF'
#!/sbin/openrc-run
supervisor=supervise-daemon
command=/etc/sing-box/bin/sing-box
command_args="run -c /etc/sing-box/config.json -C /etc/sing-box/conf"
pidfile=/run/sing-box.pid
command_user=root:root
SEOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default 2>/dev/null
  fi
}

_proxy_add_reality_default() {
  _proxy_gen_uuid
  _proxy_gen_port
  local pbk; pbk=$($P_CORE_BIN generate reality-keypair 2>/dev/null)
  local public_key; public_key=$(echo "$pbk" | grep "PublicKey" | awk '{print $2}')
  local private_key; private_key=$(echo "$pbk" | grep "PrivateKey" | awk '{print $2}')
  local sni="cloudflare.com"

  local conf="$P_CONF_DIR/00_reality.json"
  cat > "$conf" << JEOF
{
  "type": "vless",
  "tag": "reality-in",
  "listen": "::",
  "listen_port": $P_NEW_PORT,
  "tls": {
    "enabled": true,
    "server_name": "$sni",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$sni:443"
      },
      "private_key": "$private_key",
      "short_id": [""]
    }
  },
  "users": [
    {
      "uuid": "$P_NEW_UUID",
      "flow": "xtls-rprx-vision"
    }
  ]
}
JEOF

  msg_ok "Default REALITY config created"
  msg_info "Port: $P_NEW_PORT | UUID: $P_NEW_UUID | SNI: $sni"
  systemctl restart sing-box 2>/dev/null || true
}

# ---- UUID/Port generators ----
P_NEW_UUID=""; P_NEW_PORT=""
_proxy_gen_uuid() {
  P_NEW_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "$(date +%s)-$$-$RANDOM")
}
_proxy_gen_port() {
  P_NEW_PORT=0
  local port
  for i in $(seq 1 233); do
    port=$(( RANDOM % 60000 + 1024 ))
    if ! ss -tlnp 2>/dev/null | grep -q ":$port "; then
      P_NEW_PORT=$port
      return
    fi
  done
  P_NEW_PORT=$(( RANDOM % 60000 + 1024 ))
}

_get_ip() { :; }  # Use F_IP from common.sh

# ---- Uninstall ----
proxy_uninstall() {
  _require_root
  tr PROXY_UNINSTALLING "Uninstalling sing-box..."

  if ! confirm "$(tr MSG_CONFIRM "This will remove all sing-box files. Continue")"; then
    return
  fi

  proxy_manage "stop" 2>/dev/null
  proxy_manage "disable" 2>/dev/null

  rm -rf "$P_CORE_DIR" "$P_LOG_DIR"
  rm -f /usr/local/bin/sing-box /usr/local/bin/sb
  rm -f /lib/systemd/system/sing-box.service
  rm -f /etc/init.d/sing-box

  if confirm "$(tr MSG_CONFIRM "Also remove Caddy?"). $(tr MSG_CONFIRM "Continue")"; then
    proxy_manage "stop" "caddy" 2>/dev/null
    rm -f "$P_CADDY_BIN"
  fi

  msg_ok "$(tr MSG_DONE "sing-box uninstalled")"
  _log_write "sing-box uninstalled"
}

# ---- Add Config ----
proxy_add() {
  _require_root
  if [[ ! -f "$P_CORE_BIN" ]]; then
    msg_err "sing-box not installed. Install first."
    return 1
  fi

  local protocol="${1:-}"
  if [[ -z "$protocol" ]]; then
    _proxy_show_protocols
    read -p "$(tr MSG_SELECT "Select protocol") [1-${#P_PROTOCOLS[@]}]: " proto_idx
    proto_idx=$((proto_idx - 1))
  else
    proto_idx=$(_proxy_proto_to_index "$protocol")
  fi

  local p_name="${P_PROTOCOLS[$((proto_idx * 3))]}"
  local p_type="${P_PROTOCOLS[$((proto_idx * 3 + 1))]}"
  local p_transport="${P_PROTOCOLS[$((proto_idx * 3 + 2))]}"

  if [[ -z "$p_name" ]]; then
    msg_err "Invalid protocol"
    return 1
  fi

  msg_info "Adding $p_name..."

  _proxy_gen_uuid
  _proxy_gen_port

  # Build inbound config based on protocol
  _proxy_create_inbound "$p_name" "$p_type" "$p_transport"
}

_proxy_show_protocols() {
  msg_title "$(tr PROXY_LIST "Protocol List")"
  local i=1
  local idx=0
  while [[ $idx -lt ${#P_PROTOCOLS[@]} ]]; do
    msg "  ${F_GREEN}$i${F_RESET}) ${P_PROTOCOLS[$idx]}"
    i=$((i+1))
    idx=$((idx+3))
  done
  msg ""
}

_proxy_proto_to_index() {
  local input="${1,,}"
  local idx=0; local i=0
  while [[ $idx -lt ${#P_PROTOCOLS[@]} ]]; do
    local name="${P_PROTOCOLS[$idx],,}"
    if [[ "$name" == *"$input"* || "$input" == *"${P_PROTOCOLS[$((idx+1))]}"* ]]; then
      echo "$i"
      return
    fi
    i=$((i+1)); idx=$((idx+3))
  done
  echo "-1"
}

_proxy_create_inbound() {
  local p_name="$1"; local p_type="$2"; local p_transport="$3"
  local tag="proxy-${p_name,,}-${P_NEW_PORT}"
  local tag="${tag// /_}"
  local conf_file="$P_CONF_DIR/$tag.json"

  # Basic inbound JSON
  cat > "$conf_file" << JEOF
{
  "type": "$p_type",
  "tag": "$tag",
  "listen": "::",
  "listen_port": $P_NEW_PORT
JEOF

  # Add transport settings
  case "$p_transport" in
    ws)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "transport": {
    "type": "ws",
    "path": "/${P_NEW_UUID:0:8}"
  }
JEOF
      ;;
    h2)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "transport": {
    "type": "h2",
    "path": "/${P_NEW_UUID:0:8}"
  }
JEOF
      ;;
    httpupgrade)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "transport": {
    "type": "httpupgrade",
    "path": "/${P_NEW_UUID:0:8}"
  }
JEOF
      ;;
    quic)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "transport": {
    "type": "quic"
  }
JEOF
      ;;
    http)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "transport": {
    "type": "http"
  }
JEOF
      ;;
  esac

  # Add TLS settings
  case "$p_name" in
    *REALITY*|*TLS*|Trojan|Hysteria2|TUIC)
      if [[ "$p_name" == *"REALITY"* ]]; then
        _proxy_gen_reality_tls "$conf_file" "$p_name"
      elif [[ "$p_name" == "Trojan" || "$p_name" == "Hysteria2" || "$p_name" == "TUIC" ]]; then
        _proxy_gen_selfsigned_tls "$conf_file" "$p_name"
      else
        _proxy_gen_caddy_tls "$conf_file"
      fi
      ;;
  esac

  # Add user/protocol-specific fields
  case "$p_type" in
    vless|vmess)
      echo ',' >> "$conf_file"
      cat >> "$conf_file" << JEOF
  "users": [{"uuid": "$P_NEW_UUID"}]
JEOF
      [[ "$p_name" == *"REALITY"* ]] && echo ', "flow": "xtls-rprx-vision"' >> "$conf_file"
      ;;
    trojan)
      echo ',' >> "$conf_file"
      local pass; pass=$(date +%s | md5sum | head -c 16)
      cat >> "$conf_file" << JEOF
  "users": [{"password": "$pass"}]
JEOF
      ;;
    hysteria2)
      echo ',' >> "$conf_file"
      local pass; pass=$(date +%s | md5sum | head -c 16)
      cat >> "$conf_file" << JEOF
  "users": [{"password": "$pass"}]
JEOF
      ;;
    tuic)
      echo ',' >> "$conf_file"
      local pass; pass=$(date +%s | md5sum | head -c 16)
      cat >> "$conf_file" << JEOF
  "users": [{"uuid": "$P_NEW_UUID", "password": "$pass"}]
JEOF
      ;;
    shadowsocks)
      echo ',' >> "$conf_file"
      local method="aes-256-gcm"
      local pass; pass=$(date +%s | sha256sum | head -c 32)
      cat >> "$conf_file" << JEOF
  "method": "$method",
  "password": "$pass"
JEOF
      ;;
    socks)
      echo ',' >> "$conf_file"
      local user; user=$(date +%s | md5sum | head -c 8)
      local pass; pass=$(date +%s | sha256sum | head -c 16)
      cat >> "$conf_file" << JEOF
  "users": [{"username": "$user", "password": "$pass"}]
JEOF
      ;;
    anytls)
      echo ',' >> "$conf_file"
      local pass; pass=$(date +%s | sha256sum | head -c 32)
      cat >> "$conf_file" << JEOF
  "password": "$pass"
JEOF
      ;;
  esac

  echo '' >> "$conf_file"

  # Close the JSON object
  sed -i 's/,$//' "$conf_file" 2>/dev/null
  echo "}" >> "$conf_file"

  # Validate with jq if available
  if command -v jq &>/dev/null; then
    jq . "$conf_file" > /dev/null 2>&1 || {
      msg_warn "Config may be invalid, attempting fix..."
      jq . "$conf_file" 2>/dev/null | sponge "$conf_file" 2>/dev/null || true
    }
  fi

  msg_ok "$p_name config created: $conf_file"
  msg_info "Port: $P_NEW_PORT | UUID/Password generated"

  # Restart service
  proxy_manage "restart" 2>/dev/null
  _log_write "Added proxy config: $p_name (port $P_NEW_PORT)"
}

_proxy_gen_reality_tls() {
  local conf_file="$1"; local p_name="$2"
  local pbk; pbk=$($P_CORE_BIN generate reality-keypair 2>/dev/null)
  local pub_key; pub_key=$(echo "$pbk" | grep "PublicKey" | awk '{print $2}')
  local priv_key; priv_key=$(echo "$pbk" | grep "PrivateKey" | awk '{print $2}')
  local sni_list=("amazon.com" "ebay.com" "paypal.com" "cloudflare.com" "aws.amazon.com")
  local sni="${sni_list[$((RANDOM % ${#sni_list[@]}))]}"

  # For REALITY we don't add TLS fields via echo, we use in-place approach
  cat >> "$conf_file" << JEOF
  ,"tls": {
    "enabled": true,
    "server_name": "$sni",
    "reality": {
      "enabled": true,
      "handshake": {"server": "$sni:443"},
      "private_key": "$priv_key",
      "short_id": [""]
    }
  }
JEOF
}

_proxy_gen_selfsigned_tls() {
  local conf_file="$1"
  local tls_key="$P_CORE_DIR/bin/tls.key"
  local tls_cert="$P_CORE_DIR/bin/tls.cer"

  cat >> "$conf_file" << JEOF
  ,"tls": {
    "enabled": true,
    "key_path": "$tls_key",
    "certificate_path": "$tls_cert"
  }
JEOF
}

_proxy_gen_caddy_tls() {
  # For Caddy-based TLS, just mark it
  msg_info "This protocol requires Caddy for TLS. Install Caddy separately."
}

# ---- List / Info / Delete ----
proxy_list() {
  local configs=()
  for f in "$P_CONF_DIR"/*.json; do
    [[ -f "$f" && "$(basename "$f")" != "config.json" ]] && configs+=("$f")
  done

  if [[ ${#configs[@]} -eq 0 ]]; then
    msg_info "$(tr MSG_INFO "No proxy configurations found")"
    return
  fi

  msg_title "$(tr PROXY_LIST "Proxy Configurations")"
  local i=1
  for f in "${configs[@]}"; do
    local tag; tag=$(basename "$f" .json)
    local port; port=$(grep -o '"listen_port": [0-9]*' "$f" 2>/dev/null | awk '{print $2}')
    local ptype; ptype=$(grep -o '"type": "[a-z]*' "$f" 2>/dev/null | cut -d'"' -f4)
    msg "  ${F_GREEN}$i${F_RESET}) $tag ${F_CYAN}($ptype:$port)${F_RESET}"
    i=$((i+1))
  done
  msg ""
}

proxy_info() {
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "$(tr MSG_INPUT "Enter config name or number"): " name
  fi
  # Try direct path first
  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file="$P_CONF_DIR/${name}"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)
  if [[ ! -f "$conf_file" ]]; then
    msg_err "Config not found: $name"
    return 1
  fi

  msg_title "$(tr PROXY_INFO "Proxy Info"): $(basename "$conf_file" .json)"
  if command -v jq &>/dev/null; then
    jq 'del(.tls.private_key, .tls.reality.private_key)' "$conf_file"
  else
    cat "$conf_file"
  fi
  msg ""
}

proxy_del() {
  _require_root
  local name="$1"
  if [[ -z "$name" ]]; then
    proxy_list
    read -p "$(tr MSG_INPUT "Enter config name or number to delete"): " name
  fi

  local conf_file="$P_CONF_DIR/$name.json"
  [[ ! -f "$conf_file" ]] && conf_file=$(find "$P_CONF_DIR" -name "*$name*.json" 2>/dev/null | head -1)

  if [[ ! -f "$conf_file" ]]; then
    msg_err "$(tr MSG_ERROR "Config not found")"
    return 1
  fi

  if confirm "$(tr MSG_CONFIRM "Delete $(basename "$conf_file")?"). $(tr MSG_CONFIRM "Continue")"; then
    rm -f "$conf_file"
    msg_ok "$(tr MSG_DONE "Deleted")"
    proxy_manage "restart" 2>/dev/null
    _log_write "Deleted proxy config: $(basename "$conf_file")"
  fi
}

proxy_change() {
  msg_info "Change functionality: use proxy list to find configs"
  proxy_list
  msg_info "Edit the JSON file directly with: nano <config_path>"
  msg_info "Then run: fusionbox proxy restart"
}

# ---- Service Management ----
proxy_manage() {
  local action="$1"
  local service="${2:-sing-box}"

  if [[ "$service" == "sing-box" ]]; then
    local svc="sing-box"
  elif [[ "$service" == "caddy" ]]; then
    local svc="caddy"
  fi

  case "$action" in
    start)
      if [[ "$F_INIT" == "systemd" ]]; then
        systemctl start "$svc" 2>/dev/null || true
      fi
      pgrep -x "$svc" &>/dev/null && msg_ok "$svc started" || msg_err "$svc start failed"
      ;;
    stop)
      if [[ "$F_INIT" == "systemd" ]]; then
        systemctl stop "$svc" 2>/dev/null || true
      fi
      pkill -x "$svc" 2>/dev/null || true
      msg_info "$svc stopped"
      ;;
    restart)
      if [[ "$F_INIT" == "systemd" ]]; then
        systemctl restart "$svc" 2>/dev/null || true
      fi
      pkill -x "$svc" 2>/dev/null || true
      sleep 1
      if [[ -f "$P_CORE_BIN" ]] && [[ "$svc" == "sing-box" ]]; then
        nohup "$P_CORE_BIN" run -c "$P_CONFIG_JSON" -C "$P_CONF_DIR" &>/dev/null &
      fi
      sleep 1
      pgrep -x "$svc" &>/dev/null && msg_ok "$svc restarted" || msg_err "$svc restart failed"
      ;;
    disable)
      [[ "$F_INIT" == "systemd" ]] && systemctl disable "$svc" 2>/dev/null || true
      ;;
  esac
}

proxy_status() {
  msg_title "$(tr PROXY_STATUS "Proxy Status")"
  if command -v sing-box &>/dev/null; then
    local ver; ver=$(sing-box version 2>/dev/null | head -1)
    msg "  ${F_BOLD}Binary:${F_RESET} $ver"
  fi
  if pgrep -x "sing-box" &>/dev/null; then
    msg "  ${F_BOLD}Status:${F_RESET} ${F_GREEN}$(tr PROXY_RUNNING "Running")${F_RESET}"
    local pid; pid=$(pgrep -x "sing-box")
    msg "  ${F_BOLD}PID:${F_RESET} $pid"
  else
    if [[ -f "$P_CORE_BIN" ]]; then
      msg "  ${F_BOLD}Status:${F_RESET} ${F_YELLOW}$(tr PROXY_STOPPED "Stopped")${F_RESET}"
    else
      msg "  ${F_BOLD}Status:${F_RESET} ${F_RED}$(tr PROXY_NOT_INSTALLED "Not installed")${F_RESET}"
    fi
  fi

  local count; count=$(find "$P_CONF_DIR" -name "*.json" 2>/dev/null | wc -l)
  msg "  ${F_BOLD}Configs:${F_RESET} $count"
  msg ""
}

proxy_log() {
  local log_file="$P_LOG_DIR/access.log"
  if [[ -f "$log_file" ]]; then
    msg_info "Tailing log file (Ctrl+C to exit)..."
    tail -f "$log_file" 2>/dev/null || msg_err "Cannot read log"
  else
    msg_info "No log file found at $log_file"
    journalctl -u sing-box --no-pager -n 50 2>/dev/null || true
  fi
}

# ---- BBR ----
proxy_bbr() {
  _require_root
  if [[ $(uname -r | cut -d. -f1) -ge 4 ]]; then
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    sysctl -p 2>/dev/null
    msg_ok "$(tr BBR_ENABLED "BBR enabled successfully")"
    _log_write "BBR enabled"
  else
    msg_err "$(tr BBR_FAILED "BBR requires kernel 4.9+")"
  fi
}

# ---- Update ----
proxy_update() {
  _require_root
  local component="${1:-core}"
  case "$component" in
    core|c)
      msg_info "$(tr PROXY_UPDATE "Updating core")..."
      local tmpdir=$(mktemp -d)
      local arch="amd64"; [[ "$F_ARCH" == "arm64" ]] && arch="arm64"
      local ver; ver=$(_download_sing_box_latest "$tmpdir" "$arch")
      if [[ -n "$ver" && -f "$tmpdir/sing-box" ]]; then
        systemctl stop sing-box 2>/dev/null || true
        cp "$tmpdir/sing-box" "$P_CORE_BIN"
        chmod +x "$P_CORE_BIN"
        systemctl start sing-box 2>/dev/null || true
        msg_ok "Updated to $ver"
        _log_write "sing-box core updated to $ver"
      else
        msg_err "Update failed"
      fi
      rm -rf "$tmpdir"
      ;;
    caddy)
      msg_info "Updating Caddy..."
      curl -fsSL https://caddyserver.com/api/download -o /usr/local/bin/caddy 2>/dev/null && \
        chmod +x /usr/local/bin/caddy && \
        msg_ok "Caddy updated" || msg_err "Caddy update failed"
      ;;
  esac
}

# ---- DNS ----
proxy_dns() {
  local dns_server="${1:-cloudflare}"
  msg_info "Setting DNS to $dns_server..."
  local dns_addr="https://1.1.1.1/dns-query"
  case "$dns_server" in
    1111|1.1.1.1|cloudflare) dns_addr="https://1.1.1.1/dns-query" ;;
    8888|8.8.8.8|google)     dns_addr="https://dns.google/dns-query" ;;
    *) dns_addr="$dns_server" ;;
  esac

  if [[ -f "$P_CONFIG_JSON" ]]; then
    # Use jq to update DNS
    jq ".dns.servers[0].address = \"$dns_addr\"" "$P_CONFIG_JSON" > /tmp/sing-box-config.json && \
      mv /tmp/sing-box-config.json "$P_CONFIG_JSON" && \
      msg_ok "DNS updated to $dns_addr" || msg_err "DNS update failed"
    proxy_manage "restart" 2>/dev/null
  fi
}

# ---- URL/QR ----
proxy_url() {
  local name="$1"
  proxy_info "$name"
  if [[ -n "$name" && -f "$P_CONF_DIR/$name.json" ]]; then
    local port; port=$(grep -o '"listen_port": [0-9]*' "$P_CONF_DIR/$name.json" | awk '{print $2}')
    local ptype; ptype=$(grep -o '"type": "[a-z]*' "$P_CONF_DIR/$name.json" | cut -d'"' -f4)
    local ip="${F_IP:-$(curl -s ip.sb 2>/dev/null)}"
    local uuid; uuid=$(grep -o '"uuid": "[^"]*"' "$P_CONF_DIR/$name.json" | cut -d'"' -f4)
    local pass; pass=$(grep -o '"password": "[^"]*"' "$P_CONF_DIR/$name.json" | cut -d'"' -f4)

    if [[ -n "$ip" && -n "$port" ]]; then
      case "$ptype" in
        vless)
          local u="vless://$uuid@$ip:$port?type=tcp&security=reality&flow=xtls-rprx-vision"
          msg_tip "URL: $u"
          ;;
        shadowsocks)
          local u="ss://$(echo -n "aes-256-gcm:$pass@$ip:$port" | base64 -w0 2>/dev/null || true)"
          msg_tip "URL: $u"
          ;;
        trojan)
          msg_tip "trojan://$pass@$ip:$port"
          ;;
        hysteria2)
          msg_tip "hysteria2://$pass@$ip:$port"
          ;;
        tuic)
          msg_tip "tuic://$uuid:$pass@$ip:$port"
          ;;
        *)
          msg_info "Port: $ip:$port"
          ;;
      esac

      if command -v qrencode &>/dev/null; then
        _check_pkg qrencode qrencode
        qrencode -t ansiutf8 "$u" 2>/dev/null || true
      else
        msg_info "Install qrencode for QR codes"
      fi
    fi
  fi
}

proxy_version() {
  if command -v sing-box &>/dev/null; then
    sing-box version 2>/dev/null | head -5
  else
    msg_info "$(tr PROXY_NOT_INSTALLED "Not installed")"
  fi
}

# ---- Help ----
proxy_help() {
  msg_title "$(tr MOD_PROXY "Proxy Management") Help"
  msg ""
  msg "  fusionbox proxy install              $(tr PROXY_INSTALLING "Install sing-box")"
  msg "  fusionbox proxy uninstall            $(tr PROXY_UNINSTALLING "Uninstall")"
  msg "  fusionbox proxy add [protocol]       $(tr PROXY_ADD "Add config")"
  msg "  fusionbox proxy list                 $(tr PROXY_LIST "List configs")"
  msg "  fusionbox proxy info [name]          $(tr PROXY_INFO "View config")"
  msg "  fusionbox proxy del [name]           $(tr PROXY_DEL "Delete config")"
  msg "  fusionbox proxy start|stop|restart   $(tr PROXY_STATUS "Service control")"
  msg "  fusionbox proxy status               $(tr PROXY_STATUS "Show status")"
  msg "  fusionbox proxy bbr                  $(tr PROXY_BBR "Enable BBR")"
  msg "  fusionbox proxy update [core|caddy]  $(tr PROXY_UPDATE "Update component")"
  msg "  fusionbox proxy dns [server]         $(tr MSG_INFO "Set DNS")"
  msg "  fusionbox proxy log                  $(tr MSG_INFO "View log")"
  msg ""
  msg "  ${F_BOLD}Protocol short names:${F_RESET}"
  msg "  reality/r, ss, trojan, hy/hy2, tuic, ws, tcp, quic, socks, anytls"
  msg ""
}

# ---- Interactive Menu ----
proxy_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(tr MOD_PROXY "Proxy Management")"
    msg ""
    proxy_status
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) $(tr PROXY_INSTALLING "Install sing-box")"
    msg "  ${F_GREEN}2${F_RESET}) $(tr PROXY_ADD "Add Configuration")"
    msg "  ${F_GREEN}3${F_RESET}) $(tr PROXY_LIST "List Configurations")"
    msg "  ${F_GREEN}4${F_RESET}) $(tr PROXY_INFO "View/Info")"
    msg "  ${F_GREEN}5${F_RESET}) $(tr PROXY_DEL "Delete Configuration")"
    msg "  ${F_GREEN}6${F_RESET}) $(tr PROXY_STATUS "Start/Stop/Restart")"
    msg "  ${F_GREEN}7${F_RESET}) $(tr PROXY_BBR "Enable BBR")"
    msg "  ${F_GREEN}8${F_RESET}) $(tr PROXY_UPDATE "Update Core")"
    msg "  ${F_GREEN}9${F_RESET}) $(tr MSG_INFO "DNS / Logs")"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""

    read -p "$(tr MSG_SELECT "Select") [0-9]: " choice
    case "$choice" in
      1) proxy_install; pause ;;
      2) proxy_add; pause ;;
      3) proxy_list; pause ;;
      4) proxy_info; pause ;;
      5) proxy_del; pause ;;
      6)
        msg "1) Start  2) Stop  3) Restart"
        read -p "$(tr MSG_SELECT "Action"): " act
        case "$act" in 1) proxy_manage "start" ;; 2) proxy_manage "stop" ;; 3) proxy_manage "restart" ;; esac
        pause
        ;;
      7) proxy_bbr; pause ;;
      8) proxy_update; pause ;;
      9) proxy_dns; proxy_log; pause ;;
      0) break ;;
    esac
  done
}
