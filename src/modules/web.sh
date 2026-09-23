# FusionBox Web/LNMP Deployment Module
# LNMP, website management, SSL

web_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    lnmp|install-lnmp)     web_install_lnmp "$@" ;;
    lamp|install-lamp)     web_install_lamp "$@" ;;
    site|create)           web_create_site "$@" ;;
    ssl|cert|acme)         web_ssl "$@" ;;
    nginx|ng)              web_nginx "$@" ;;
    php)                   web_php "$@" ;;
    mysql|db)              web_mysql "$@" ;;
    firewall|waf)          web_firewall "$@" ;;
    optimize|perf)         web_optimize "$@" ;;
    deploy|app)            web_deploy_app "$@" ;;
    proxy|rp)              web_reverse_proxy "$@" ;;
    stream|l4)             web_stream_proxy "$@" ;;
    sitedata|backup)       web_site_data "$@" ;;
    sites|site-list)       web_sites "$@" ;;
    site-del|sitedel)      web_site_del "$@" ;;
    site-alias|alias)      web_site_alias "$@" ;;
    guard|cc)              web_guard "$@" ;;
    wordpress|wp)          web_wordpress "$@" ;;
    clone)                 web_site_clone "$@" ;;
    cache)                 web_cache "$@" ;;
    goaccess|logstats)     web_goaccess "$@" ;;
    upgrade|upgrade-comp)  web_upgrade "$@" ;;
    uninstall-lnmp)        web_uninstall_lnmp ;;
    tune)                  web_tune "$@" ;;
    brotli)                web_brotli "$@" ;;
    wp-redis)              web_wp_redis "$@" ;;
    menu|main)             web_menu ;;
    help|h)                web_help ;;
    *)                     _module_unknown_cmd "web" "$cmd" ;;
  esac
}

# ---- 工具函数 ----
_web_validate_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]
}

_web_acme_domain_valid() {
  local domain="${1,,}" label rest
  [[ ${#domain} -le 253 && "$domain" == *.* && "$domain" != *..* ]] || return 1
  rest="$domain"
  while [[ -n "$rest" ]]; do
    label="${rest%%.*}"
    [[ "$label" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1
    [[ "$rest" == *.* ]] || break
    rest="${rest#*.}"
  done
  # 保留 TLD 守卫保护的是生产签发路径；显式覆盖 ACME 目录（Pebble/staging 测试）
  # 时由调用方传入第二参数放行。
  if [[ -z "${2:-}" ]]; then
    [[ "$domain" != *.local && "$domain" != *.localhost && "$domain" != *.invalid && "$domain" != *.test ]]
  else
    return 0
  fi
}

_web_acme_email_valid() {
  local email="$1" local_part email_domain
  [[ ${#email} -le 254 && "$email" =~ ^[A-Za-z0-9.!#$%\&\'*+/=?^_\`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,63}$ ]] || return 1
  local_part="${email%@*}"; email_domain="${email#*@}"
  [[ ${#local_part} -le 64 && "$local_part" != .* && "$local_part" != *. && "$local_part" != *..* ]] || return 1
  _web_acme_domain_valid "$email_domain" "${WEB_ACME_SERVER:+allow-reserved}"
}

_web_acme_path_valid() {
  local path="$1" current="" part
  [[ "$path" =~ ^/[A-Za-z0-9_./-]+$ && "$path" != "/" && "$path" != *//* ]] || return 1
  [[ "/$path/" != */../* && "/$path/" != */./* ]] || return 1
  [[ "$(realpath -m -- "$path" 2>/dev/null)" == "$path" ]] || return 1
  IFS='/' read -r -a _web_acme_parts <<< "${path#/}"
  for part in "${_web_acme_parts[@]}"; do
    current="$current/$part"
    [[ ! -L "$current" ]] || return 1
  done
}

# ---- Install LNMP ----
web_install_lnmp() {
  _require_root
  msg_title "$(L MSG_WEB_0631)"
  msg ""

  if ! confirm "$(L MSG_WEB_0632)"; then
    return
  fi

  progress_begin 4

  # Check existing
  if command -v nginx &>/dev/null; then
    msg_warn "$(L MSG_WEB_0633 "$(nginx -v 2>&1)")"
  fi

  # Install Nginx
  progress_step "$(L MSG_WEB_0634)"
  case "$F_PKG_MGR" in
    apt)
      apt-get update -y
      _install_pkg nginx
      systemctl enable nginx 2>/dev/null
      systemctl start nginx 2>/dev/null
      ;;
    yum)
      _install_pkg epel-release nginx
      systemctl enable nginx 2>/dev/null
      systemctl start nginx 2>/dev/null
      ;;
    apk)
      _install_pkg nginx
      rc-update add nginx default 2>/dev/null
      rc-service nginx start 2>/dev/null
      ;;
  esac

  if command -v nginx &>/dev/null; then
    msg_ok "$(L MSG_WEB_0635 "$(nginx -v 2>&1)")"
  fi

  # Install MySQL/MariaDB
  progress_step "$(L MSG_WEB_0636)"
  case "$F_PKG_MGR" in
    apt)
      _install_pkg mariadb-server mariadb-client
      systemctl enable mariadb 2>/dev/null
      systemctl start mariadb 2>/dev/null
      ;;
    yum)
      _install_pkg mariadb-server mariadb
      systemctl enable mariadb 2>/dev/null
      systemctl start mariadb 2>/dev/null
      ;;
    apk)
      _install_pkg mariadb mariadb-client
      rc-update add mariadb default 2>/dev/null
      rc-service mariadb start 2>/dev/null
      ;;
  esac

  if command -v mariadb &>/dev/null || command -v mysql &>/dev/null; then
    msg_ok "$(L MSG_WEB_0637)"
    msg_info "$(L MSG_WEB_0638)"
  fi

  # Install PHP
  progress_step "$(L MSG_WEB_0639)"
  local php_pkgs=()
  case "$F_PKG_MGR" in
    apt)
      # Add PHP PPA
      _install_pkg software-properties-common
      add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
      apt-get update -y
      php_pkgs=(php8.2 php8.2-fpm php8.2-mysql php8.2-curl php8.2-gd php8.2-mbstring php8.2-xml php8.2-zip php8.2-redis php8.2-opcache)
      ;;
    yum)
      _install_pkg epel-release
      rpm -Uvh https://rpms.remirepo.net/enterprise/remi-release-7.rpm 2>/dev/null || true
      yum module enable php:remi-8.2 -y 2>/dev/null || true
      php_pkgs=(php php-fpm php-mysqlnd php-curl php-gd php-mbstring php-xml php-zip php-redis php-opcache)
      ;;
    apk)
      php_pkgs=(php82 php82-fpm php82-mysqli php82-curl php82-gd php82-mbstring php82-xml php82-zip php82-opcache)
      ;;
  esac

  if [[ ${#php_pkgs[@]} -gt 0 ]]; then
    _install_pkg "${php_pkgs[@]}" 2>/dev/null || msg_warn "$(L MSG_WEB_0640)"

    # Configure PHP-FPM
    case "$F_PKG_MGR" in
      apt)
        systemctl enable php8.2-fpm 2>/dev/null
        systemctl start php8.2-fpm 2>/dev/null
        ;;
      yum)
        systemctl enable php-fpm 2>/dev/null
        systemctl start php-fpm 2>/dev/null
        ;;
      apk)
        rc-update add php82-fpm default 2>/dev/null
        rc-service php82-fpm start 2>/dev/null
        ;;
    esac

    local php_ver; php_ver=$(php -v 2>/dev/null | head -1)
    msg_ok "$(L MSG_WEB_0641 "${php_ver:-PHP 8.2}")"
  fi

  # Install Redis
  progress_step "$(L MSG_WEB_0642)"
  if confirm "$(L MSG_WEB_0643)"; then
    _install_pkg redis
    case "$F_PKG_MGR" in
      apt|yum) systemctl enable --now redis 2>/dev/null ;;
      apk) rc-update add redis default 2>/dev/null; rc-service redis start 2>/dev/null ;;
    esac
    msg_ok "$(L MSG_WEB_0644)"
  fi

  progress_end
  msg ""
  msg_ok "$(L MSG_WEB_0645)"
  msg ""
  msg "$(L MSG_WEB_0646 "${F_BOLD}" "${F_RESET}")"
  msg "  ${F_BOLD}Nginx:${F_RESET} $(nginx -v 2>&1)"
  php -v 2>/dev/null | head -1 | xargs -I{} msg "  ${F_BOLD}PHP:${F_RESET} {}"
  msg "  ${F_BOLD}MariaDB:${F_RESET} $(mariadbd --version 2>/dev/null | head -1 || mysql --version 2>/dev/null)"
  msg "$(L MSG_WEB_0647 "${F_BOLD}" "${F_RESET}" "$(pgrep php-fpm | wc -l)")"

  _log_write "$(L MSG_WEB_0648)"
  pause
}

# ---- Install LAMP ----
web_install_lamp() {
  _require_root
  msg_info "$(L MSG_WEB_0649)"

  if ! confirm "$(L MSG_WEB_0650)"; then
    return
  fi

  _install_pkg apache2 2>/dev/null || _install_pkg httpd 2>/dev/null || msg_err "$(L MSG_WEB_0651)"

  case "$F_PKG_MGR" in
    apt)
      systemctl enable apache2 2>/dev/null
      systemctl start apache2 2>/dev/null
      a2enmod rewrite 2>/dev/null
      a2enmod ssl 2>/dev/null
      ;;
    yum)
      systemctl enable httpd 2>/dev/null
      systemctl start httpd 2>/dev/null
      ;;
  esac

  web_install_lnmp
  msg_info "$(L MSG_WEB_0652)"
  pause
}

# ---- Create Website ----
web_create_site() {
  _require_root
  msg_title "$(L MSG_WEB_0653)"
  msg ""

  local domain; domain=$(read_input "$(L MSG_WEB_0654)")
  [[ -z "$domain" ]] && domain="localhost"
  if ! _web_validate_domain "$domain"; then
    msg_err "$(L MSG_WEB_0655 "$domain")"
    pause; return 1
  fi

  local web_root="/var/www/$domain"
  mkdir -p "$web_root"

  # Create a sample index
  cat > "$web_root/index.html" << HEOF
<!DOCTYPE html>
<html>
<head><title>$domain</title>
<style>
body{font-family:Arial;margin:40px;text-align:center;background:#f5f5f5}
h1{color:#333}.info{color:#666;margin-top:20px}
</style>
</head>
<body>
<h1>$(L MSG_WEB_0625 "$domain")</h1>
<p class="info">$(L MSG_WEB_0626)</p>
<p class="info">$(L MSG_WEB_0627 "$(date)")</p>
</body>
</html>
HEOF
  find "$web_root" -type d -exec chmod 755 {} +
  find "$web_root" -type f -exec chmod 644 {} +

  # Create Nginx config
  local nginx_conf="/etc/nginx/sites-available/$domain"
  if [[ ! -d "/etc/nginx/sites-available" ]]; then
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    # Include sites-enabled in main nginx.conf if not present
    grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null || \
      sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf 2>/dev/null
  fi

  cat > "$nginx_conf" << NEOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root $web_root;
    index index.html index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
NEOF

  ln -sf "$nginx_conf" /etc/nginx/sites-enabled/ 2>/dev/null || \
    cp "$nginx_conf" /etc/nginx/conf.d/ 2>/dev/null

  # Test Nginx
  if ! nginx -t 2>/dev/null; then
    rm -f "$nginx_conf" "/etc/nginx/sites-enabled/$domain" "/etc/nginx/conf.d/$domain"
    msg_err "$(L MSG_WEB_0656 "$nginx_conf")"
    pause; return 1
  fi
  systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  msg_ok "$(L MSG_WEB_0657 "$domain")"
  msg_info "$(L MSG_WEB_0658 "$web_root")"
  _log_write "$(L MSG_WEB_0659 "$domain")"

  pause
}

# ---- ACME transaction workflow ----
_WEB_ACME_NGINX_DIR="${WEB_ACME_NGINX_DIR:-/etc/nginx}"
_WEB_ACME_LE_DIR="${WEB_ACME_LE_DIR:-/etc/letsencrypt}"
# 覆盖 ACME 目录 URL（默认走 certbot 生产配置）：指向 Pebble / Let's Encrypt
# staging 等非生产服务时必须显式传入；同时自动切换 certbot 的 config/work/logs
# 目录到受管 LE 目录，绝不污染生产 /etc/letsencrypt。
_WEB_ACME_SERVER="${WEB_ACME_SERVER:-}"
_WEB_ACME_STATE_DIR="${WEB_ACME_STATE_DIR:-/var/lib/fusionbox/acme}"
_WEB_ACME_HTTP_PORT="${WEB_ACME_HTTP_PORT:-80}"
_WEB_ACME_HTTPS_PORT="${WEB_ACME_HTTPS_PORT:-443}"

_web_acme_usage() {
  msg "$(L MSG_WEB_0660)"
  msg "$(L MSG_WEB_0661)"
  msg "$(L MSG_WEB_0662)"
  msg "$(L MSG_WEB_0663)"
  msg "$(L MSG_WEB_0664)"
  msg "  fusionbox web ssl renew [--days <1-90>]"
}

_web_cert_info() {
  local cert="$1" enddate end_ts now_ts delta
  [[ -f "$cert" ]] || return 1
  enddate=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2) || return 1
  [[ -n "$enddate" ]] || return 1
  end_ts=$(date -d "$enddate" +%s 2>/dev/null) || return 1
  now_ts=$(date +%s) || return 1
  delta=$((end_ts - now_ts)); (( delta < 0 )) && delta=$((delta - 86399))
  printf '%s|%s' "$enddate" "$((delta / 86400))"
}

_web_cert_days() {
  local info
  info=$(_web_cert_info "$1") || return 1
  printf '%s\n' "${info##*|}"
}

_web_acme_parse() {
  WEB_ACME_DOMAIN=""; WEB_ACME_EMAIL=""; WEB_ACME_WEBROOT=""; WEB_ACME_DAYS=30
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain|-d) [[ $# -ge 2 ]] || return 2; WEB_ACME_DOMAIN="${2,,}"; shift 2 ;;
      --email|-m) [[ $# -ge 2 ]] || return 2; WEB_ACME_EMAIL="$2"; shift 2 ;;
      --webroot|-w) [[ $# -ge 2 ]] || return 2; WEB_ACME_WEBROOT="$2"; shift 2 ;;
      --days) [[ $# -ge 2 ]] || return 2; WEB_ACME_DAYS="$2"; shift 2 ;;
      --server) [[ $# -ge 2 ]] || return 2; WEB_ACME_SERVER="$2"; shift 2 ;;
      *) msg_err "$(L MSG_WEB_0665 "$1")"; return 2 ;;
    esac
  done
  WEB_ACME_SERVER="${WEB_ACME_SERVER:-$_WEB_ACME_SERVER}"
  [[ -z "$WEB_ACME_SERVER" || "$WEB_ACME_SERVER" == https://* ]] || { msg_err "$(L MSG_WEB_0666)"; return 2; }
  [[ -z "$WEB_ACME_DOMAIN" ]] || _web_acme_domain_valid "$WEB_ACME_DOMAIN" "${WEB_ACME_SERVER:+allow-reserved}" || { msg_err "$(L MSG_WEB_0655 "$WEB_ACME_DOMAIN")"; return 2; }
  [[ -z "$WEB_ACME_EMAIL" ]] || _web_acme_email_valid "$WEB_ACME_EMAIL" || { msg_err "$(L MSG_WEB_0667 "$WEB_ACME_EMAIL")"; return 2; }
  [[ -z "$WEB_ACME_WEBROOT" ]] || _web_acme_path_valid "$WEB_ACME_WEBROOT" || { msg_err "$(L MSG_WEB_0668)"; return 2; }
  [[ "$WEB_ACME_DAYS" =~ ^[0-9]+$ ]] && (( WEB_ACME_DAYS >= 1 && WEB_ACME_DAYS <= 90 )) || { msg_err "$(L MSG_WEB_0669)"; return 2; }
}

_web_acme_nginx_files() {
  local f
  for f in "$_WEB_ACME_NGINX_DIR"/sites-enabled/* "$_WEB_ACME_NGINX_DIR"/conf.d/*.conf; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
}

_web_acme_site_info() {
  local domain="$1" f root proxy names
  while IFS= read -r f; do
    names=$(awk '/^[[:space:]]*server_name[[:space:]]/ { sub(/;.*/, ""); for (i=2;i<=NF;i++) print $i }' "$f" 2>/dev/null)
    grep -Fxq "$domain" <<< "$names" || continue
    root=$(awk '/^[[:space:]]*root[[:space:]]/ { gsub(/;/, "", $2); print $2; exit }' "$f")
    proxy=$(awk '/^[[:space:]]*proxy_pass[[:space:]]/ { gsub(/;/, "", $2); print $2; exit }' "$f")
    printf '%s|%s|%s\n' "$f" "$root" "$proxy"
    return 0
  done < <(_web_acme_nginx_files)
  return 1
}

_web_acme_site_conflicts() {
  local domain="$1" allowed="$2" f names count=0
  while IFS= read -r f; do
    [[ "$f" == "$allowed" ]] && continue
    names=$(awk '/^[[:space:]]*server_name[[:space:]]/ { sub(/;.*/, ""); for (i=2;i<=NF;i++) print $i }' "$f" 2>/dev/null)
    if grep -Fxq "$domain" <<< "$names"; then
      msg_err "$(L MSG_WEB_0670 "$domain" "$f")"
      count=$((count + 1))
    fi
  done < <(_web_acme_nginx_files)
  (( count == 0 ))
}

_web_acme_dns_report() {
  local domain="$1" records=""
  if command -v getent >/dev/null 2>&1; then
    records=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, -)
  elif command -v dig >/dev/null 2>&1; then
    records=$(dig +short A "$domain" 2>/dev/null; dig +short AAAA "$domain" 2>/dev/null)
    records=$(tr '\n' ',' <<< "$records" | sed 's/,$//')
  fi
  if [[ -n "$records" ]]; then msg_info "$(L MSG_WEB_0671 "$domain" "$records")"; else msg_warn "$(L MSG_WEB_0672 "$domain")"; fi
}

_web_acme_port_report() {
  local port="$1" owner="空闲" listeners=""
  if command -v ss >/dev/null 2>&1; then
    listeners=$(ss -ltnp "sport = :$port" 2>/dev/null | awk 'NR>1')
  elif command -v lsof >/dev/null 2>&1; then
    listeners=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR>1')
  fi
  if [[ -n "$listeners" ]]; then
    owner=$(tr '\n' ' ' <<< "$listeners")
    msg_info "$(L MSG_WEB_0673 "$port" "$owner")"
  else
    msg_info "$(L MSG_WEB_0674 "$port")"
  fi
}

_web_ssl_existing_schedule() {
  local unit
  for unit in certbot.timer snap.certbot.renew.timer certbot-renew.timer; do
    if systemctl is-enabled "$unit" >/dev/null 2>&1 || systemctl is-active "$unit" >/dev/null 2>&1; then
      printf '%s\n' "$unit"
      return 0
    fi
  done
  grep -rEl '^[^#]*certbot[[:space:]].*renew' /etc/cron.d /etc/cron.daily /etc/crontab 2>/dev/null | head -1
}

_web_acme_certbot_check() {
  command -v certbot >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0675)"; return 1; }
  local version plugins rc
  version=$(certbot --version 2>&1); rc=$?
  (( rc == 0 )) || { msg_err "$(L MSG_WEB_0676)"; return "$rc"; }
  [[ "$version" =~ ([0-9]+)\.([0-9]+) ]] || { msg_err "$(L MSG_WEB_0677 "$version")"; return 1; }
  (( BASH_REMATCH[1] >= 1 )) || { msg_err "$(L MSG_WEB_0678 "$version")"; return 1; }
  plugins=$(certbot plugins 2>&1); rc=$?
  (( rc == 0 )) || { msg_err "$(L MSG_WEB_0679)"; return "$rc"; }
  grep -qi 'webroot' <<< "$plugins" || { msg_err "$(L MSG_WEB_0680)"; return 1; }
  msg_info "$(L MSG_WEB_0681 "$version")"
}

_web_acme_preflight_run() {
  local domain="$1" email="$2" webroot="$3" site="" site_file="" site_root=""
  _web_acme_domain_valid "$domain" "${WEB_ACME_SERVER:+allow-reserved}" || { msg_err "$(L MSG_WEB_0682)"; return 2; }
  [[ -z "$email" ]] || _web_acme_email_valid "$email" || { msg_err "$(L MSG_WEB_0683)"; return 2; }
  [[ -z "$webroot" ]] || _web_acme_path_valid "$webroot" || { msg_err "$(L MSG_WEB_0684)"; return 2; }
  command -v nginx >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0685)"; return 1; }
  _web_acme_certbot_check || return 1
  nginx -t >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0686)"; return 1; }
  _web_acme_dns_report "$domain"
  _web_acme_port_report "$_WEB_ACME_HTTP_PORT"
  _web_acme_port_report "$_WEB_ACME_HTTPS_PORT"
  if site=$(_web_acme_site_info "$domain"); then
    IFS='|' read -r site_file site_root _ <<< "$site"
    msg_info "Nginx site: $site_file"
    _web_acme_site_conflicts "$domain" "$site_file" || return 1
    if [[ -n "$webroot" && -n "$site_root" && "$webroot" != "$site_root" ]]; then
      msg_err "$(L MSG_WEB_0687 "$site_root")"
      return 1
    fi
    if [[ -z "$site_root" || -n "${site##*|}" ]]; then
      msg_err "$(L MSG_WEB_0688)"
      return 1
    fi
    if grep -qE '^[[:space:]]*listen[[:space:]]+([^;[:space:]]+:)?443|^[[:space:]]*ssl_certificate[[:space:]]' "$site_file" 2>/dev/null; then
      msg_err "$(L MSG_WEB_0689 "$site_file")"
      return 1
    fi
  else
    msg_info "$(L MSG_WEB_0690)"
    _web_acme_site_conflicts "$domain" "" || return 1
  fi
  [[ -z "$webroot" || -d "$webroot" ]] || { msg_err "$(L MSG_WEB_0691 "$webroot")"; return 1; }
  msg_ok "$(L MSG_WEB_0692)"
}

web_ssl_preflight() {
  _require_root
  _web_acme_parse "$@"
  local rc=$?
  (( rc == 0 )) || { _web_acme_usage; return "$rc"; }
  [[ -n "$WEB_ACME_DOMAIN" ]] || { msg_err "$(L MSG_WEB_0693)"; return 2; }
  _web_acme_preflight_run "$WEB_ACME_DOMAIN" "$WEB_ACME_EMAIL" "$WEB_ACME_WEBROOT"
}

_web_acme_reload() {
  if [[ -n "${WEB_ACME_RELOAD_CMD:-}" ]]; then bash -c "$WEB_ACME_RELOAD_CMD"
  else systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null
  fi
}

_web_acme_owner_hash() {
  local kind="$1" domain="$2" root="$3" proxy="$4" cert="$5" key="$6"
  printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0' \
    "$kind" "$domain" "$root" "$proxy" "$cert" "$key" "$_WEB_ACME_HTTP_PORT" "$_WEB_ACME_HTTPS_PORT" | sha256sum | awk '{print $1}'
}

_web_acme_owned_file_ok() {
  local target="$1" kind="$2" hash="$3" marker stored
  [[ -f "$target" && ! -L "$target" ]] || return 1
  IFS= read -r marker < "$target" || return 1
  IFS= read -r stored < <(sed -n '2p' "$target") || return 1
  [[ "$marker" == "# Managed by FusionBox ACME transaction: $kind" && "$stored" == "# Owner-State-SHA256: $hash" ]]
}

_web_acme_target_available() {
  local target="$1" kind="$2" hash="$3"
  [[ ! -e "$target" && ! -L "$target" ]] && return 0
  _web_acme_owned_file_ok "$target" "$kind" "$hash" || {
    msg_err "$(L MSG_WEB_0694 "$target")"
    return 1
  }
}

_web_acme_write_challenge() {
  local domain="$1" root="$2" target="$3" tmp hash
  hash=$(_web_acme_owner_hash challenge "$domain" "$root" "" "" "") || return 1
  mkdir -p "$(dirname "$target")" "$root/.well-known/acme-challenge" || return 1
  _web_acme_target_available "$target" challenge "$hash" || return 1
  tmp=$(mktemp "$(dirname "$target")/.fusionbox-acme.XXXXXX") || return 1
  cat > "$tmp" <<EOF
# Managed by FusionBox ACME transaction: challenge
# Owner-State-SHA256: $hash
server {
    listen $_WEB_ACME_HTTP_PORT;
    server_name $domain;
    location ^~ /.well-known/acme-challenge/ { root $root; default_type text/plain; }
    location / { return 404; }
}
EOF
  chmod 644 "$tmp" && mv -f "$tmp" "$target"
}

_web_acme_verify_cert() {
  local domain="$1" cert="$2" key="$3" san cert_pub key_pub
  [[ -f "$cert" && -f "$key" ]] || { msg_err "$(L MSG_WEB_0695)"; return 1; }
  [[ ! -L "$cert" || "$(readlink -f "$cert" 2>/dev/null)" == "$_WEB_ACME_LE_DIR"/* ]] || { msg_err "$(L MSG_WEB_0696)"; return 1; }
  [[ ! -L "$key" || "$(readlink -f "$key" 2>/dev/null)" == "$_WEB_ACME_LE_DIR"/* ]] || { msg_err "$(L MSG_WEB_0697)"; return 1; }
  openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0698)"; return 1; }
  san=$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ')
  grep -Eiq "DNS:${domain//./\\.}([,[:space:]]|$)" <<< "$san" || { msg_err "$(L MSG_WEB_0699 "$domain")"; return 1; }
  cert_pub=$(openssl x509 -in "$cert" -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
  key_pub=$(openssl pkey -in "$key" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
  [[ -n "$cert_pub" && "$cert_pub" == "$key_pub" ]] || { msg_err "$(L MSG_WEB_0700)"; return 1; }
}

_web_acme_write_tls() {
  local domain="$1" root="$2" proxy="$3" cert="$4" key="$5" target="$6" tmp hash
  hash=$(_web_acme_owner_hash tls "$domain" "$root" "$proxy" "$cert" "$key") || return 1
  mkdir -p "$(dirname "$target")" || return 1
  _web_acme_target_available "$target" tls "$hash" || return 1
  tmp=$(mktemp "$(dirname "$target")/.fusionbox-tls.XXXXXX") || return 1
  {
    printf '# Managed by FusionBox ACME transaction: tls\n'
    printf '# Owner-State-SHA256: %s\n' "$hash"
    printf 'server {\n'
    printf '    listen %s ssl;\n    server_name %s;\n' "$_WEB_ACME_HTTPS_PORT" "$domain"
    printf '    ssl_certificate %s;\n    ssl_certificate_key %s;\n' "$cert" "$key"
    printf '    ssl_protocols TLSv1.2 TLSv1.3;\n'
    if [[ -n "$proxy" ]]; then
      printf '    location / {\n        proxy_pass %s;\n        proxy_set_header Host $host;\n        proxy_set_header X-Real-IP $remote_addr;\n        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n        proxy_set_header X-Forwarded-Proto $scheme;\n    }\n' "$proxy"
    else
      printf '    root %s;\n    location / { try_files $uri $uri/ =404; }\n' "$root"
    fi
    printf '}\n'
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 644 "$tmp" && mv -f "$tmp" "$target"
}

_web_acme_restore_file() {
  local target="$1" backup="$2" existed="$3"
  if [[ "$existed" == 1 ]]; then cp -p "$backup" "$target"; else rm -f "$target"; fi
}

_web_acme_issue_cleanup() {
  local original_rc="$1" challenge="$2" backup="$3" existed="$4" work="$5"
  local cleanup_rc=0
  _web_acme_restore_file "$challenge" "$backup" "$existed" || cleanup_rc=1
  if ! nginx -t >/dev/null 2>&1 || ! _web_acme_reload; then
    msg_err "$(L MSG_WEB_0701)"
    cleanup_rc=1
  fi
  rm -rf -- "$work"
  (( cleanup_rc == 0 )) || return 1
  return "$original_rc"
}

# 非生产 ACME 目录或受管 LE 目录时，显式给 certbot 传目录参数；并输出参数数组。
_web_acme_certbot_dirs() {
  local server="$1" le="$_WEB_ACME_LE_DIR"
  if [[ -n "$server" ]]; then
    CERTBOT_ARGS=(--server "$server")
  else
    CERTBOT_ARGS=()
  fi
  if [[ "$le" != "/etc/letsencrypt" ]]; then
    CERTBOT_ARGS+=(--config-dir "$le" --work-dir "$le/work" --logs-dir "$le/logs")
  fi
}

web_ssl_issue() (
  _require_root
  _web_acme_parse "$@"
  local parse_rc=$?
  (( parse_rc == 0 )) || { _web_acme_usage; return "$parse_rc"; }
  [[ -n "$WEB_ACME_DOMAIN" && -n "$WEB_ACME_EMAIL" ]] || { msg_err "$(L MSG_WEB_0702)"; return 2; }
  _web_acme_preflight_run "$WEB_ACME_DOMAIN" "$WEB_ACME_EMAIL" "$WEB_ACME_WEBROOT" || return $?

  local domain="$WEB_ACME_DOMAIN" webroot="$WEB_ACME_WEBROOT" site="" site_root="" proxy=""
  local challenge="$_WEB_ACME_NGINX_DIR/conf.d/fusionbox-acme-$domain.conf"
  local tls="$_WEB_ACME_NGINX_DIR/conf.d/fusionbox-tls-$domain.conf"
  local work cert key challenge_active=0 challenge_existed=0 tls_existed=0 rc
  work=$(mktemp -d "${TMPDIR:-/tmp}/fusionbox-acme.XXXXXXXX") || return 1
  trap 'rm -rf -- "$work"' EXIT
  if site=$(_web_acme_site_info "$domain"); then
    IFS='|' read -r _ site_root proxy <<< "$site"
    [[ -n "$webroot" ]] || webroot="$site_root"
  else
    [[ -n "$webroot" ]] || webroot="$_WEB_ACME_STATE_DIR/challenges/$domain"
    _web_acme_path_valid "$webroot" || { msg_err "$(L MSG_WEB_0703)"; return 1; }
    if [[ -e "$challenge" || -L "$challenge" ]]; then
      local challenge_hash
      challenge_hash=$(_web_acme_owner_hash challenge "$domain" "$webroot" "" "" "") || return 1
      _web_acme_owned_file_ok "$challenge" challenge "$challenge_hash" || { msg_err "$(L MSG_WEB_0704)"; return 1; }
      cp -p "$challenge" "$work/challenge.backup" || return 1
      challenge_existed=1
    fi
    _web_acme_write_challenge "$domain" "$webroot" "$challenge" || { msg_err "$(L MSG_WEB_0705)"; return 1; }
    challenge_active=1
    trap '_web_acme_issue_cleanup "$?" "$challenge" "$work/challenge.backup" "$challenge_existed" "$work"' EXIT
    if ! nginx -t >/dev/null 2>&1 || ! _web_acme_reload; then
      msg_err "$(L MSG_WEB_0706)"
      return 1
    fi
  fi
  mkdir -p "$webroot/.well-known/acme-challenge" || return 1
  msg_info "$(L MSG_WEB_0707)"
  _web_acme_certbot_dirs "$WEB_ACME_SERVER"
  certbot certonly --webroot -w "$webroot" -d "$domain" --cert-name "$domain" \
    --non-interactive --agree-tos --email "$WEB_ACME_EMAIL" "${CERTBOT_ARGS[@]}"
  rc=$?
  if (( challenge_active )); then
    _web_acme_restore_file "$challenge" "$work/challenge.backup" "$challenge_existed" || return 1
    challenge_active=0
    trap 'rm -rf -- "$work"' EXIT
    if ! nginx -t >/dev/null 2>&1 || ! _web_acme_reload; then
      msg_err "$(L MSG_WEB_0708)"
      return 1
    fi
  fi
  if (( rc != 0 )); then
    msg_err "$(L MSG_WEB_0709 "$rc")"
    return "$rc"
  fi

  cert="$_WEB_ACME_LE_DIR/live/$domain/fullchain.pem"; key="$_WEB_ACME_LE_DIR/live/$domain/privkey.pem"
  _web_acme_verify_cert "$domain" "$cert" "$key" || return 1
  [[ -n "$site_root" ]] || site_root="$webroot"
  local tls_hash
  tls_hash=$(_web_acme_owner_hash tls "$domain" "$site_root" "$proxy" "$cert" "$key") || return 1
  if [[ -e "$tls" || -L "$tls" ]]; then
    _web_acme_owned_file_ok "$tls" tls "$tls_hash" || { msg_err "$(L MSG_WEB_0710)"; return 1; }
    cp -p "$tls" "$work/tls.backup" || return 1
    tls_existed=1
  fi
  _web_acme_write_tls "$domain" "$site_root" "$proxy" "$cert" "$key" "$tls" || return 1
  if ! nginx -t >/dev/null 2>&1 || ! _web_acme_reload; then
    _web_acme_restore_file "$tls" "$work/tls.backup" "$tls_existed"
    if ! nginx -t >/dev/null 2>&1 || ! _web_acme_reload; then
      msg_err "$(L MSG_WEB_0711)"
    else
      msg_err "$(L MSG_WEB_0712)"
    fi
    return 1
  fi
  msg_ok "$(L MSG_WEB_0713 "$domain")"
  _log_write "$(L MSG_WEB_0714 "$domain")"
)

_web_acme_fingerprints() {
  local cert
  for cert in "$_WEB_ACME_LE_DIR"/live/*/fullchain.pem; do
    [[ -f "$cert" ]] || continue
    printf '%s|' "$cert"
    openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2
  done | sort
}

web_ssl_renew() {
  _require_root
  _web_acme_parse "$@"
  local parse_rc=$?
  (( parse_rc == 0 )) || { _web_acme_usage; return "$parse_rc"; }
  command -v certbot >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0675)"; return 1; }
  local certbot_version_rc=0
  certbot --version >/dev/null 2>&1 || certbot_version_rc=$?
  (( certbot_version_rc == 0 )) || return "$certbot_version_rc"
  _web_acme_certbot_check || return 1
  command -v flock >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0715)"; return 1; }
  mkdir -p "$_WEB_ACME_STATE_DIR" || return 1
  exec 9>"$_WEB_ACME_STATE_DIR/renew.lock" || return 1
  flock -n 9 || { msg_warn "$(L MSG_WEB_0716)"; return 75; }

  local cert days due=0 before after rc
  for cert in "$_WEB_ACME_LE_DIR"/live/*/fullchain.pem; do
    [[ -f "$cert" ]] || continue
    days=$(_web_cert_days "$cert" 2>/dev/null) || days=-1
    (( days <= WEB_ACME_DAYS )) && due=$((due + 1))
  done
  if (( due == 0 )); then msg_ok "$(L MSG_WEB_0717 "$WEB_ACME_DAYS")"; return 0; fi
  before=$(_web_acme_fingerprints)
  _web_acme_certbot_dirs "${WEB_ACME_SERVER:-}"
  certbot renew --non-interactive --deploy-hook /bin/true "${CERTBOT_ARGS[@]}"
  rc=$?
  (( rc == 0 )) || { msg_err "$(L MSG_WEB_0718 "$rc")"; return "$rc"; }
  after=$(_web_acme_fingerprints)
  if [[ "$before" == "$after" ]]; then msg_ok "$(L MSG_WEB_0719)"; return 0; fi
  nginx -t >/dev/null 2>&1 || { msg_err "$(L MSG_WEB_0720)"; return 1; }
  _web_acme_reload || { msg_err "$(L MSG_WEB_0721)"; return 1; }
  msg_ok "$(L MSG_WEB_0722)"
  _log_write "$(L MSG_WEB_0723)"
}

web_ssl_status() {
  _require_root
  _web_acme_parse "$@"
  local parse_rc=$?
  (( parse_rc == 0 )) || { _web_acme_usage; return "$parse_rc"; }
  local cert domain days found=0
  for cert in "$_WEB_ACME_LE_DIR"/live/*/fullchain.pem; do
    [[ -f "$cert" ]] || continue
    domain=$(basename "$(dirname "$cert")")
    [[ -z "$WEB_ACME_DOMAIN" || "$domain" == "$WEB_ACME_DOMAIN" ]] || continue
    found=1; days=$(_web_cert_days "$cert" 2>/dev/null) || days="$(L MSG_WEB_0724)"
    msg "$(L MSG_WEB_0725 "$domain" "$days" "$cert")"
  done
  (( found )) || msg_info "$(L MSG_WEB_0726)"
  _web_acme_certbot_check || true
  command -v nginx >/dev/null 2>&1 && nginx -t 2>&1 || true
}

web_ssl_autorenew() {
  web_ssl_renew "$@"
}

web_ssl() {
  local action="${1:-menu}"; [[ $# -eq 0 ]] || shift
  case "$action" in
    preflight) web_ssl_preflight "$@" ;;
    status|st) web_ssl_status "$@" ;;
    issue) web_ssl_issue "$@" ;;
    renew|now|r) web_ssl_renew "$@" ;;
    menu|main)
      msg_title "$(L MSG_WEB_0727)"
      msg "$(L MSG_WEB_0728)"
      msg "$(L MSG_WEB_0729)"
      msg "$(L MSG_WEB_0730)"
      msg "$(L MSG_WEB_0731)"
      msg "$(L MSG_WEB_0732)"
      local choice domain email webroot
      read -r -p "$(L MSG_WEB_0733)" choice || return
      case "$choice" in
        1) read -r -p "$(L MSG_WEB_0734)" domain; read -r -p "$(L MSG_WEB_0735)" email; read -r -p "$(L MSG_WEB_0736)" webroot; web_ssl_preflight --domain "$domain" ${email:+--email "$email"} ${webroot:+--webroot "$webroot"} ;;
        2) web_ssl_status ;;
        3) read -r -p "$(L MSG_WEB_0734)" domain; read -r -p "$(L MSG_WEB_0737)" email; read -r -p "$(L MSG_WEB_0736)" webroot; if [[ -n "$webroot" ]]; then web_ssl_issue --domain "$domain" --email "$email" --webroot "$webroot"; else web_ssl_issue --domain "$domain" --email "$email"; fi ;;
        4) web_ssl_renew ;;
        *) return 0 ;;
      esac ;;
    *) msg_err "$(L MSG_WEB_0738 "$action")"; _web_acme_usage; return 2 ;;
  esac
}

# ---- Nginx Management ----
web_nginx() {
  _require_root
  local action="${1:-status}"

  case "$action" in
    status)
      if command -v nginx &>/dev/null; then
        nginx -t 2>&1 | head -2
        nginx -V 2>&1 | head -1
        pgrep -x nginx &>/dev/null && msg_ok "$(L MSG_WEB_0739)" || msg_info "$(L MSG_WEB_0740)"
      else
        msg_err "$(L MSG_WEB_0741)"
      fi
      ;;
    reload)
      nginx -s reload 2>/dev/null && msg_ok "$(L MSG_WEB_0742)" || msg_err "$(L MSG_WEB_0743)"
      ;;
    config)
      local config_dir="/etc/nginx"
      msg_info "$(L MSG_WEB_0744 "$config_dir")"
      find "$config_dir" -name "*.conf" -type f 2>/dev/null | while read -r f; do
        msg "  $f"
      done
      ;;
  esac
  pause
}

# ---- PHP Management ----
web_php() {
  _require_root
  if command -v php &>/dev/null; then
    msg_info "PHP: $(php -v 2>/dev/null | head -1)"
    msg ""
    msg_info "$(L MSG_WEB_0745)"
    php -m 2>/dev/null | sort | while read -r mod; do
      msg "  $mod"
    done

    msg ""
    msg "$(L MSG_WEB_0746)"
    read -p "$(L MSG_WEB_0747)" php_choice
    if [[ "$php_choice" == "1" ]]; then
      local php_ini; php_ini=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
      if [[ -f "$php_ini" ]]; then
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$php_ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$php_ini"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$php_ini"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
        systemctl reload php*-fpm 2>/dev/null || nginx -s reload 2>/dev/null || true
        msg_ok "$(L MSG_WEB_0748)"
      fi
    fi
  else
    msg_err "$(L MSG_WEB_0749)"
  fi
  pause
}

# ---- MySQL ----
web_mysql() {
  _require_root
  if command -v mysql &>/dev/null; then
    msg_title "$(L MSG_WEB_0750)"
    msg ""
    msg "$(L MSG_WEB_0751)"
    msg "$(L MSG_WEB_0752)"
    msg "$(L MSG_WEB_0753)"
    msg "$(L MSG_WEB_0754)"
    msg "$(L MSG_WEB_0732)"
    read -p "$(L MSG_WEB_0747)" db_choice

    case "$db_choice" in
      1)
        read -r -p "$(L MSG_WEB_0755)" db_name
        [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "$(L MSG_WEB_0756)"; return 1; }
        printf 'CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4;\n' "$db_name" | mysql 2>/dev/null && \
          msg_ok "$(L MSG_WEB_0757 "$db_name")" || msg_err "$(L MSG_WEB_0758)"
        ;;
      2)
        read -r -p "$(L MSG_WEB_0759)" db_user
        read -r -p "$(L MSG_WEB_0760)" db_pass   # -r 必须保留：不带 -r 的 read 会吞掉密码中的反斜杠
        read -r -p "$(L MSG_WEB_0761)" db_name
        [[ "$db_user" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "$(L MSG_WEB_0762)"; return 1; }
        [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "$(L MSG_WEB_0756)"; return 1; }
        # SQL 字符串转义与 Bash 参数展开是不同层；展开结果不会被 Bash 二次解释。
        local esc_user="$db_user"
        esc_user=${esc_user//\\/\\\\}
        esc_user=${esc_user//\'/\'\'}
        local esc_pass="$db_pass"
        esc_pass=${esc_pass//\\/\\\\}
        esc_pass=${esc_pass//\'/\'\'}
        mysql 2>/dev/null << SQLEOF
CREATE USER '${esc_user}'@'localhost' IDENTIFIED BY '${esc_pass}';
GRANT ALL ON \`${db_name}\`.* TO '${esc_user}'@'localhost';
FLUSH PRIVILEGES;
SQLEOF
        [[ $? -eq 0 ]] && \
          msg_ok "$(L MSG_WEB_0763 "$db_user" "$db_name")" || msg_err "$(L MSG_WEB_0758)"
        ;;
      3)
        mysql -e "SHOW DATABASES;" 2>/dev/null
        ;;
      4)
        mysql_secure_installation
        ;;
    esac
  else
    msg_err "$(L MSG_WEB_0764)"
  fi
  pause
}

# ---- Web Firewall ----
web_firewall() {
  _require_root
  _install_pkg libnginx-mod-http-headers-more-filter 2>/dev/null || true

  msg_info "$(L MSG_WEB_0765)"
  local nginx_conf="/etc/nginx/nginx.conf"
  local conf_bak=""
  if [[ -f "$nginx_conf" ]]; then
    conf_bak="$nginx_conf.fb-bak-$(date +%s)"
    cp "$nginx_conf" "$conf_bak"
    # Add security headers in http block if not present
    if grep -q "X-Content-Type-Options" "$nginx_conf" 2>/dev/null; then
      msg_info "$(L MSG_WEB_0766)"
    elif sed -i '/http {/a\    add_header X-Content-Type-Options nosniff;\n    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-XSS-Protection "1; mode=block";' "$nginx_conf" 2>/dev/null; then
      msg_ok "$(L MSG_WEB_0767)"
    else
      msg_warn "$(L MSG_WEB_0768)"
    fi
    if ! nginx -t 2>/dev/null; then
      cp "$conf_bak" "$nginx_conf"
      msg_err "$(L MSG_WEB_0769)"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null || true
    cp "$nginx_conf" "$conf_bak"
  fi

  # Rate limiting
  read -p "$(L MSG_WEB_0770)" rate_ans
  if [[ ! "$rate_ans" =~ ^[Nn] ]]; then
    grep -q "limit_req_zone" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    limit_req_zone $binary_remote_addr zone=fusionbox:10m rate=10r/s;' "$nginx_conf" 2>/dev/null
    if ! nginx -t 2>/dev/null; then
      [[ -n "$conf_bak" ]] && cp "$conf_bak" "$nginx_conf"
      msg_err "$(L MSG_WEB_0769)"
      pause; return 1
    fi
    nginx -s reload 2>/dev/null || true
    msg_ok "$(L MSG_WEB_0771)"
  fi
  _log_write "$(L MSG_WEB_0772)"
  pause
}

# ---- Optimize ----
web_optimize() {
  _require_root
  msg_title "$(L MSG_WEB_0773)"

  if command -v nginx &>/dev/null; then
    msg_info "$(L MSG_WEB_0774)"
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ -f "$nginx_conf" && ! -L "$nginx_conf" ]] || return 1
    local backup_dir
    backup_dir=$(mktemp -d "${nginx_conf}.fb-backup.XXXXXX") || return 1
    local conf_bak="$backup_dir/nginx.conf"
    cp -p "$nginx_conf" "$conf_bak" || return 1

    # Optimize worker processes
    local edit_failed=0
    local cpu_count; cpu_count=$(nproc --all) || return 1
    sed -i "s/worker_processes .*/worker_processes $cpu_count;/" "$nginx_conf" 2>/dev/null || edit_failed=1

    # Optimize worker connections
    sed -i "s/worker_connections .*/worker_connections 10240;/" "$nginx_conf" 2>/dev/null || edit_failed=1

    # Add gzip settings
    grep -q "gzip_vary" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    gzip on;\n    gzip_vary on;\n    gzip_min_length 1024;\n    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;' "$nginx_conf" 2>/dev/null || edit_failed=1

    # Enable sendfile and tcp_nopush
    sed -i 's/# tcp_nopush/tcp_nopush/' "$nginx_conf" 2>/dev/null || edit_failed=1
    sed -i 's/# tcp_nodelay/tcp_nodelay/' "$nginx_conf" 2>/dev/null || edit_failed=1

    if [[ "$edit_failed" == 1 ]] || ! nginx -t 2>/dev/null || ! nginx -s reload 2>/dev/null; then
      if cp -p "$conf_bak" "$nginx_conf" && nginx -t 2>/dev/null && nginx -s reload 2>/dev/null; then
        msg_err "$(L MSG_WEB_0775 "$conf_bak")"
      else
        msg_err "$(L MSG_WEB_0776 "$conf_bak")"
      fi
      return 1
    fi
    msg_ok "$(L MSG_WEB_0777 "$cpu_count")"
    _log_write "$(L MSG_WEB_0778)"
  fi

  # PHP-FPM optimization
  if command -v php-fpm8.2 &>/dev/null || command -v php-fpm &>/dev/null; then
    msg_info "$(L MSG_WEB_0779)"
    local php_conf php_version php_bin php_service php_backup
    for php_conf in /etc/php/*/fpm/pool.d/www.conf; do
      [[ -f "$php_conf" ]] || continue
      [[ ! -L "$php_conf" ]] || return 1
      php_version="${php_conf%/fpm/pool.d/www.conf}"; php_version="${php_version##*/}"
      php_bin="php-fpm${php_version}"
      command -v "$php_bin" >/dev/null || { msg_err "$(L MSG_WEB_0780 "$php_bin")"; return 1; }
      php_service="php${php_version}-fpm"
      php_backup=$(mktemp -d "${php_conf}.fb-backup.XXXXXX") || return 1
      cp -p "$php_conf" "$php_backup/www.conf" || return 1
      if ! sed -i -e 's/pm.max_children = .*/pm.max_children = 50/' \
        -e 's/pm.start_servers = .*/pm.start_servers = 5/' \
        -e 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' \
        -e 's/pm.max_spare_servers = .*/pm.max_spare_servers = 15/' "$php_conf" || \
        ! "$php_bin" -t 2>/dev/null || ! systemctl reload "$php_service"; then
        if cp -p "$php_backup/www.conf" "$php_conf" && "$php_bin" -t 2>/dev/null && systemctl reload "$php_service"; then
          msg_err "$(L MSG_WEB_0781)"
        else
          msg_err "$(L MSG_WEB_0782 "$php_backup")"
        fi
        return 1
      fi
      msg_ok "$(L MSG_WEB_0783 "$php_service")"
    done
  fi

  pause
}

# ---- LDNMP 应用部署 (Docker化) ----
web_deploy_app() {
  _require_root
  msg_title "$(L MSG_WEB_0784)"
  msg ""

  if ! command -v docker &>/dev/null; then
    msg_warn "$(L MSG_WEB_0785)"
    if confirm "$(L MSG_WEB_0786)"; then
      _load_module "panels"
      panels_docker_install
    else
      pause; return
    fi
  fi

  msg "$(L MSG_WEB_0787 "${F_BOLD}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WEB_0788 "${F_CYAN}" "${F_RESET}")"
  msg "  ${F_GREEN} 1${F_RESET}) WordPress"
  msg "  ${F_GREEN} 2${F_RESET}) Typecho"
  msg "$(L MSG_WEB_0789 "${F_GREEN}" "${F_RESET}")"
  msg "  ${F_GREEN} 4${F_RESET}) Discuz! Q"
  msg ""
  msg "$(L MSG_WEB_0790 "${F_CYAN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0791 "${F_GREEN}" "${F_RESET}")"
  msg "  ${F_GREEN} 6${F_RESET}) Nextcloud"
  msg "$(L MSG_WEB_0792 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WEB_0793 "${F_CYAN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0794 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0795 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0796 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WEB_0797 "${F_CYAN}" "${F_RESET}")"
  msg "  ${F_GREEN}11${F_RESET}) Flarum"
  msg "$(L MSG_WEB_0798 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WEB_0799 "${F_CYAN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0800 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0801 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0802 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0803 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0804 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_WEB_0805 "${F_GREEN}" "${F_RESET}")"
  msg ""
  read -p "$(L MSG_WEB_0806)" app_choice || return   # stdin 关闭时退出

  case "$app_choice" in
    1)  _deploy_wordpress ;;
    2)  _deploy_typecho ;;
    3)  _deploy_halo ;;
    4)  _deploy_discuz ;;
    5)  _deploy_kodexplorer ;;
    6)  _deploy_nextcloud ;;
    7)  _deploy_alist ;;
    8)  _deploy_apple_cms ;;
    9)  _deploy_emby ;;
    10) _deploy_jellyfin ;;
    11) _deploy_flarum ;;
    12) _deploy_linkstack ;;
    13) _deploy_bitwarden ;;
    14) _deploy_uptime_kuma ;;
    15) _deploy_it_tools ;;
    16) _deploy_memos ;;
    17) _deploy_vaultwarden ;;
    0)  return ;;
  esac
}

# WordPress 一键部署
_deploy_wordpress() {
  _require_root
  local app_dir="/opt/docker/wordpress"
  local domain; domain=$(read_input "$(L MSG_WEB_0807)" "localhost")
  if ! _web_validate_domain "$domain"; then
    msg_err "$(L MSG_WEB_0655 "$domain")"
    pause; return 1
  fi
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0808)" "$(openssl rand -hex 12)")
  local wp_pass; wp_pass=$(read_input "$(L MSG_WEB_0809)" "$(openssl rand -hex 8)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << WPEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: wp_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wp
      MYSQL_PASSWORD: $db_pass
    volumes:
      - wp_db_data:/var/lib/mysql
    networks:
      - wp_net

  wordpress:
    image: wordpress:latest
    container_name: wp_app
    restart: always
    depends_on:
      - db
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wp
      WORDPRESS_DB_PASSWORD: $db_pass
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - wp_data:/var/www/html
    networks:
      - wp_net

volumes:
  wp_db_data:
  wp_data:

networks:
  wp_net:
WPEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0811)"
  msg "$(L MSG_WEB_0812 "${domain}")"
  msg "$(L MSG_WEB_0813 "$db_pass")"
  msg "$(L MSG_WEB_0814 "$app_dir")"
  _log_write "$(L MSG_WEB_0815 "$app_dir")"
  pause
}

# Typecho 一键部署
_deploy_typecho() {
  _require_root
  local app_dir="/opt/docker/typecho"
  local domain; domain=$(read_input "$(L MSG_WEB_0816)" "localhost")
  if ! _web_validate_domain "$domain"; then
    msg_err "$(L MSG_WEB_0655 "$domain")"
    pause; return 1
  fi
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0817)" "$(openssl rand -hex 12)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << TCEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: tc_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: typecho
      MYSQL_USER: typecho
      MYSQL_PASSWORD: $db_pass
    volumes:
      - tc_db_data:/var/lib/mysql

  typecho:
    image: joyqi/typecho:nightly-php8.1-apache
    container_name: tc_app
    restart: always
    depends_on:
      - db
    ports:
      - "8081:80"
    environment:
      TYPECHO_DB_ADAPTER: Pdo_Mysql
      TYPECHO_DB_HOST: db
      TYPECHO_DB_PORT: 3306
      TYPECHO_DB_USER: typecho
      TYPECHO_DB_PASSWORD: $db_pass
      TYPECHO_DB_DATABASE: typecho
    volumes:
      - tc_data:/app/usr

volumes:
  tc_db_data:
  tc_data:
TCEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0818)"
  msg "$(L MSG_WEB_0819 "${domain}")"
  _log_write "$(L MSG_WEB_0818)"
  pause
}

# Halo 一键部署
_deploy_halo() {
  _require_root
  local app_dir="/opt/docker/halo"
  mkdir -p "$app_dir"

  cat > "$app_dir/docker-compose.yml" << HAEOF
version: '3.8'
services:
  halo:
    image: halohub/halo:2.11
    container_name: halo
    restart: always
    ports:
      - "8090:8090"
    volumes:
      - halo_data:/root/.halo2
    command:
      - --spring.r2dbc.url=r2dbc:h2:file:///root/.halo2/db/halo
      - --spring.sql.init.platform=h2
      - --halo.external-url=http://localhost:8090/

volumes:
  halo_data:
HAEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0820)"
  msg "$(L MSG_WEB_0821 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0820)"
  pause
}

# Discuz Q 一键部署
_deploy_discuz() {
  _require_root
  local app_dir="/opt/docker/discuz"
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0817)" "$(openssl rand -hex 12)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << DZEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: dz_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: discuz
      MYSQL_USER: discuz
      MYSQL_PASSWORD: $db_pass
    volumes:
      - dz_db:/var/lib/mysql

  redis:
    image: redis:alpine
    container_name: dz_redis
    restart: always

  discuz:
    image: javaweb/discuz:latest
    container_name: dz_app
    restart: always
    depends_on:
      - db
      - redis
    ports:
      - "8082:80"
    environment:
      DB_HOST: db
      DB_NAME: discuz
      DB_USER: discuz
      DB_PASS: $db_pass
      REDIS_HOST: redis
    volumes:
      - dz_data:/var/www

volumes:
  dz_db:
  dz_data:
DZEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0822)"
  msg "$(L MSG_WEB_0823 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0824)"
  pause
}

# 可道云 一键部署
_deploy_kodexplorer() {
  _require_root
  local app_dir="/opt/docker/kodexplorer"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << KDEOF
version: '3.8'
services:
  kodexplorer:
    image: kodcloud/kodexplorer:latest
    container_name: kodexplorer
    restart: always
    ports:
      - "8083:80"
    volumes:
      - ./data:/code/data
KDEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0825)"
  msg "$(L MSG_WEB_0826 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0825)"
  pause
}

# Nextcloud 一键部署
_deploy_nextcloud() {
  _require_root
  local app_dir="/opt/docker/nextcloud"
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0817)" "$(openssl rand -hex 12)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << NCEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: nc_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: $db_pass
    volumes:
      - nc_db:/var/lib/mysql

  app:
    image: nextcloud:latest
    container_name: nc_app
    restart: always
    depends_on:
      - db
    ports:
      - "8084:80"
    environment:
      MYSQL_HOST: db
      MYSQL_DATABASE: nextcloud
      MYSQL_USER: nextcloud
      MYSQL_PASSWORD: $db_pass
    volumes:
      - nc_data:/var/www/html

volumes:
  nc_db:
  nc_data:
NCEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0827)"
  msg "$(L MSG_WEB_0828 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0827)"
  pause
}

# Alist 一键部署
_deploy_alist() {
  _require_root
  local app_dir="/opt/docker/alist"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << ALEOF
version: '3.8'
services:
  alist:
    image: xhofe/alist:latest
    container_name: alist
    restart: always
    ports:
      - "5244:5244"
    volumes:
      - ./data:/opt/alist/data
    environment:
      - PUID=0
      - PGID=0
      - UMASK=022
ALEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  sleep 3
  local admin_pass=$(docker logs alist 2>&1 | grep "password" | awk -F': ' '{print $NF}' | tail -1)
  msg_ok "$(L MSG_WEB_0829)"
  msg "$(L MSG_WEB_0830 "$(hostname -I | awk '{print $1}')")"
  msg "$(L MSG_WEB_0831)"
  msg "$(L MSG_WEB_0832 "${admin_pass:-查看 docker logs alist}")"
  _log_write "$(L MSG_WEB_0829)"
  pause
}

# 苹果 CMS 一键部署
_deploy_apple_cms() {
  _require_root
  local app_dir="/opt/docker/apple_cms"
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0817)" "$(openssl rand -hex 12)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << ACEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: ac_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: maccms
      MYSQL_USER: maccms
      MYSQL_PASSWORD: $db_pass
    volumes:
      - ac_db:/var/lib/mysql

  apple_cms:
    image: maccms:latest
    container_name: ac_app
    restart: always
    depends_on:
      - db
    ports:
      - "8085:80"
    volumes:
      - ac_data:/var/www/html

volumes:
  ac_db:
  ac_data:
ACEOF
  chmod 600 "$app_dir/docker-compose.yml"

  # Fallback: use generic PHP+MySQL if specific image not available
  cat > "$app_dir/docker-compose.yml" << ACEOF2
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: ac_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: maccms
    volumes:
      - ac_db:/var/lib/mysql

  web:
    image: php:8.1-apache
    container_name: ac_app
    restart: always
    depends_on:
      - db
    ports:
      - "8085:80"
    volumes:
      - ac_data:/var/www/html

volumes:
  ac_db:
  ac_data:
ACEOF2
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0833)"
  msg "$(L MSG_WEB_0834 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0835)"
  pause
}

# Emby 一键部署
_deploy_emby() {
  _require_root
  local app_dir="/opt/docker/emby"
  mkdir -p "$app_dir/config" "$app_dir/media"

  cat > "$app_dir/docker-compose.yml" << EMEOF
version: '3.8'
services:
  emby:
    image: emby/embyserver:latest
    container_name: emby
    restart: always
    ports:
      - "8096:8096"
    environment:
      - UID=0
      - GID=0
    volumes:
      - ./config:/config
      - ./media:/media
EMEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0836)"
  msg "$(L MSG_WEB_0837 "$(hostname -I | awk '{print $1}')")"
  msg "$(L MSG_WEB_0838 "$app_dir")"
  _log_write "$(L MSG_WEB_0836)"
  pause
}

# Jellyfin 一键部署
_deploy_jellyfin() {
  _require_root
  local app_dir="/opt/docker/jellyfin"
  mkdir -p "$app_dir/config" "$app_dir/media" "$app_dir/cache"

  cat > "$app_dir/docker-compose.yml" << JFEOF
version: '3.8'
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: always
    ports:
      - "8097:8096"
    volumes:
      - ./config:/config
      - ./cache:/cache
      - ./media:/media
JFEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0839)"
  msg "$(L MSG_WEB_0840 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0839)"
  pause
}

# Flarum 一键部署
_deploy_flarum() {
  _require_root
  local app_dir="/opt/docker/flarum"
  local db_pass; db_pass=$(read_input "$(L MSG_WEB_0817)" "$(openssl rand -hex 12)")

  mkdir -p "$app_dir"
  cat > "$app_dir/docker-compose.yml" << FLEOF
version: '3.8'
services:
  db:
    image: mariadb:10.11
    container_name: fl_db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $db_pass
      MYSQL_DATABASE: flarum
      MYSQL_USER: flarum
      MYSQL_PASSWORD: $db_pass
    volumes:
      - fl_db:/var/lib/mysql

  flarum:
    image: mondedie/flarum:stable
    container_name: fl_app
    restart: always
    depends_on:
      - db
    ports:
      - "8086:8888"
    environment:
      DB_HOST: db
      DB_NAME: flarum
      DB_USER: flarum
      DB_PASS: $db_pass
      DB_PREFIX: fl_
      FORUM_URL: http://localhost:8086
    volumes:
      - fl_data:/flarum/app/public/assets

volumes:
  fl_db:
  fl_data:
FLEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0841)"
  msg "$(L MSG_WEB_0842 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0841)"
  pause
}

# LinkStack 一键部署
_deploy_linkstack() {
  _require_root
  local app_dir="/opt/docker/linkstack"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << LLEOF
version: '3.8'
services:
  linkstack:
    image: linkstackorg/linkstack:latest
    container_name: linkstack
    restart: always
    ports:
      - "8087:80"
    environment:
      TZ: Asia/Shanghai
    volumes:
      - ./data:/htdocs
LLEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0843)"
  msg "$(L MSG_WEB_0844 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0843)"
  pause
}

# Bitwarden (标准版) 一键部署
_deploy_bitwarden() {
  _require_root
  local app_dir="/opt/docker/bitwarden"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << BWEOF
version: '3.8'
services:
  bitwarden:
    image: vaultwarden/server:latest
    container_name: bitwarden
    restart: always
    ports:
      - "8088:80"
    environment:
      WEBSOCKET_ENABLED: "true"
      SIGNUPS_ALLOWED: "true"
    volumes:
      - ./data:/data
BWEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0845)"
  msg "$(L MSG_WEB_0846 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0847)"
  pause
}

# Uptime Kuma 一键部署
_deploy_uptime_kuma() {
  _require_root
  local app_dir="/opt/docker/uptime-kuma"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << UKEOF
version: '3.8'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: always
    ports:
      - "3001:3001"
    volumes:
      - ./data:/app/data
UKEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0848)"
  msg "$(L MSG_WEB_0849 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0848)"
  pause
}

# IT-Tools 一键部署
_deploy_it_tools() {
  _require_root
  local app_dir="/opt/docker/it-tools"
  mkdir -p "$app_dir"

  cat > "$app_dir/docker-compose.yml" << ITEOF
version: '3.8'
services:
  it-tools:
    image: corentinth/it-tools:latest
    container_name: it-tools
    restart: always
    ports:
      - "8880:80"
ITEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0850)"
  msg "$(L MSG_WEB_0851 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0850)"
  pause
}

# Memos 一键部署
_deploy_memos() {
  _require_root
  local app_dir="/opt/docker/memos"
  mkdir -p "$app_dir/data"

  cat > "$app_dir/docker-compose.yml" << MEOF
version: '3.8'
services:
  memos:
    image: ghcr.io/usememos/memos:latest
    container_name: memos
    restart: always
    ports:
      - "5230:5230"
    volumes:
      - ./data:/var/opt/memos
MEOF
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "$(L MSG_WEB_0810)"
    pause; return 1
  fi
  msg_ok "$(L MSG_WEB_0852)"
  msg "$(L MSG_WEB_0853 "$(hostname -I | awk '{print $1}')")"
  _log_write "$(L MSG_WEB_0852)"
  pause
}

# Vaultwarden 一键部署
_deploy_vaultwarden() {
  _deploy_bitwarden
}

# ---- 反向代理管理 ----
web_reverse_proxy() {
  _require_root
  msg_title "$(L MSG_WEB_0854)"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_err "$(L MSG_WEB_0741)"
    pause; return
  fi

  msg "$(L MSG_WEB_0855 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0856 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0857 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0858 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0859 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
  read -p "$(L MSG_WEB_0747)" rp_choice

  case "$rp_choice" in
    1)
      local domain; domain=$(read_input "$(L MSG_WEB_0816)")
      local backend; backend=$(read_input "$(L MSG_WEB_0861)")
      [[ -z "$domain" || -z "$backend" ]] && { msg_err "$(L MSG_WEB_0862)"; pause; return; }
      if ! _web_validate_domain "$domain"; then
        msg_err "$(L MSG_WEB_0655 "$domain")"
        pause; return 1
      fi

      cat > "/etc/nginx/sites-available/$domain" << RPEOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    location / {
        proxy_pass http://$backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
RPEOF
      ln -sf "/etc/nginx/sites-available/$domain" /etc/nginx/sites-enabled/ 2>/dev/null
      if ! nginx -t 2>/dev/null; then
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        msg_err "$(L MSG_WEB_0863 "$domain")"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0864 "$domain" "$backend")"
      _log_write "$(L MSG_WEB_0864 "$domain" "$backend")"
      ;;
    2)
      local domain; domain=$(read_input "$(L MSG_WEB_0816)")
      local backend; backend=$(read_input "$(L MSG_WEB_0865)")
      [[ -z "$domain" || -z "$backend" ]] && { msg_err "$(L MSG_WEB_0862)"; pause; return; }
      if ! _web_validate_domain "$domain"; then
        msg_err "$(L MSG_WEB_0655 "$domain")"
        pause; return 1
      fi

      # First create HTTP config
      cat > "/etc/nginx/sites-available/$domain" << RPEOF2
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;

    location / {
        proxy_pass http://$backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
RPEOF2
      ln -sf "/etc/nginx/sites-available/$domain" /etc/nginx/sites-enabled/ 2>/dev/null

      # Try to get SSL cert
      if command -v certbot &>/dev/null; then
        certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null
      else
        msg_warn "$(L MSG_WEB_0866 "$domain")"
      fi
      if ! nginx -t 2>/dev/null; then
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        msg_err "$(L MSG_WEB_0863 "$domain")"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0867 "$domain" "$backend")"
      ;;
    3)
      local domain; domain=$(read_input "$(L MSG_WEB_0816)")
      if ! _web_validate_domain "$domain"; then
        msg_err "$(L MSG_WEB_0655 "$domain")"
        pause; return 1
      fi
      local upstream_name="upstream_${domain//./_}"
      msg "$(L MSG_WEB_0868)"
      local backends=""
      local i=1
      while true; do
        read -p "$(L MSG_WEB_0869 "$i")" be
        [[ -z "$be" ]] && break
        backends+="    server $be;\n"
        i=$((i+1))
      done
      [[ -z "$backends" ]] && { msg_err "$(L MSG_WEB_0870)"; pause; return; }

      cat > "/etc/nginx/sites-available/$domain" << LBEOF
upstream $upstream_name {
$backends
}

server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    location / {
        proxy_pass http://$upstream_name;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
LBEOF
      ln -sf "/etc/nginx/sites-available/$domain" /etc/nginx/sites-enabled/ 2>/dev/null
      if ! nginx -t 2>/dev/null; then
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        msg_err "$(L MSG_WEB_0863 "$domain")"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0871 "$domain" "$(($i-1))")"
      _log_write "$(L MSG_WEB_0872 "$domain")"
      ;;
    4)
      msg_info "$(L MSG_WEB_0873)"
      for f in /etc/nginx/sites-available/*; do
        [[ -f "$f" ]] && msg "  $(basename "$f")"
      done
      ;;
    5)
      read -p "$(L MSG_WEB_0874)" domain
      if ! _web_validate_domain "$domain"; then
        msg_err "$(L MSG_WEB_0655 "$domain")"
        pause; return 1
      fi
      if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
        if ! confirm "$(L MSG_WEB_0875 "$domain")"; then
          pause; return
        fi
        local del_bak; del_bak=$(mktemp)
        cp "/etc/nginx/sites-available/$domain" "$del_bak"
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        if ! nginx -t 2>/dev/null; then
          cp "$del_bak" "/etc/nginx/sites-available/$domain"
          rm -f "$del_bak"
          msg_err "$(L MSG_WEB_0769)"
          pause; return 1
        fi
        rm -f "$del_bak"
        systemctl reload nginx 2>/dev/null
        msg_ok "$(L MSG_WEB_0876 "$domain")"
      else
        msg_err "$(L MSG_WEB_0877)"
      fi
      ;;
  esac
  pause
}

# ---- Stream L4 代理 ----
web_stream_proxy() {
  _require_root
  msg_title "$(L MSG_WEB_0878)"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_err "$(L MSG_WEB_0741)"
    pause; return
  fi

  msg "$(L MSG_WEB_0879 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0880 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0881 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0882 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0883 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
  read -p "$(L MSG_WEB_0747)" st_choice

  local stream_conf="/etc/nginx/stream.d/fusionbox-stream.conf"
  mkdir -p /etc/nginx/stream.d 2>/dev/null

  # stream 块只能放在 nginx 主配置层；Ubuntu/Debian 的 nginx 默认不带 stream 模块，
  # 必须先确保模块存在（libnginx-mod-stream），否则追加的 stream{} 会让 nginx 起不来。
  # 注意 --with-stream=dynamic 表示动态模块（可能未加载），不能当作已支持
  if [[ "$st_choice" =~ ^[1-3]$ ]]; then
    if ls /etc/nginx/modules-enabled/*stream* >/dev/null 2>&1 \
       || ls /usr/lib/nginx/modules/ngx_stream_module.so >/dev/null 2>&1 \
       || nginx -V 2>&1 | tr ' ' '\n' | grep -qx -- '--with-stream'; then
      : # 模块已就绪（动态已装或静态编译）
    else
      msg_info "$(L MSG_WEB_0884)"
      _install_pkg libnginx-mod-stream 2>/dev/null || _install_pkg nginx-mod-stream 2>/dev/null || {
        msg_err "$(L MSG_WEB_0885)"
        pause; return 1
      }
    fi
  fi

  # Ensure stream block exists in nginx.conf
  if ! grep -q "stream {" /etc/nginx/nginx.conf 2>/dev/null; then
    cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.fb-bak-$(date +%s)" 2>/dev/null
    echo -e "\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}" >> /etc/nginx/nginx.conf
    if ! nginx -t 2>/dev/null; then
      # stream 块导致主配置失效：立即还原，绝不能留着坏配置
      LATEST_BAK=$(ls -t /etc/nginx/nginx.conf.fb-bak-* 2>/dev/null | head -1)
      [[ -n "$LATEST_BAK" ]] && cp "$LATEST_BAK" /etc/nginx/nginx.conf
      msg_err "$(L MSG_WEB_0886)"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null
  fi

  case "$st_choice" in
    1)
      local listen_port; listen_port=$(read_input "$(L MSG_WEB_0887)")
      local target; target=$(read_input "$(L MSG_WEB_0888)")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "$(L MSG_WEB_0769)"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0889 "$listen_port" "$target")"
      _log_write "Stream TCP: $listen_port → $target"
      ;;
    2)
      local listen_port; listen_port=$(read_input "$(L MSG_WEB_0887)")
      local target; target=$(read_input "$(L MSG_WEB_0890)")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "$(L MSG_WEB_0769)"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0891 "$listen_port" "$target")"
      _log_write "Stream UDP: $listen_port → $target"
      ;;
    3)
      local listen_port; listen_port=$(read_input "$(L MSG_WEB_0887)")
      local target; target=$(read_input "$(L MSG_WEB_0890)")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "$(L MSG_WEB_0769)"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
      msg_ok "$(L MSG_WEB_0892 "$listen_port" "$target")"
      ;;
    4)
      if [[ -f "$stream_conf" ]]; then
        msg_info "$(L MSG_WEB_0893)"
        nl -ba "$stream_conf"
      else
        msg "$(L MSG_WEB_0894)"
      fi
      ;;
    5)
      if [[ -f "$stream_conf" ]]; then
        nl -ba "$stream_conf"
        read -p "$(L MSG_WEB_0895)" del_line
        local total_lines; total_lines=$(wc -l < "$stream_conf")
        if [[ ! "$del_line" =~ ^[0-9]+$ ]] || [[ "$del_line" -lt 1 || "$del_line" -gt "$total_lines" ]]; then
          msg_err "$(L MSG_WEB_0896 "$total_lines")"
          pause; return 1
        fi
        if ! confirm "$(L MSG_WEB_0897 "$del_line")"; then
          pause; return
        fi
        local st_bak; st_bak=$(mktemp)
        cp "$stream_conf" "$st_bak"
        sed -i "${del_line}d" "$stream_conf"
        if ! nginx -t 2>/dev/null; then
          cp "$st_bak" "$stream_conf"; rm -f "$st_bak"
          msg_err "$(L MSG_WEB_0769)"
          pause; return 1
        fi
        rm -f "$st_bak"
        systemctl reload nginx 2>/dev/null
        msg_ok "$(L MSG_WEB_0898)"
      fi
      ;;
  esac
  pause
}

# ---- 站点数据管理 ----
_web_backup_jobs() {
  command -v python3 >/dev/null || { msg_err "$(L MSG_WEB_0899)"; return 1; }
  local helper="$FUSION_SRC/lib/backup_jobs.py" action job hour minute keep archive_name
  msg_warn "$(L MSG_WEB_0900)"
  msg_warn "$(L MSG_WEB_0901)"
  msg "$(L MSG_WEB_0902)"
  msg "$(L MSG_WEB_0903)"
  read -r -p "$(L MSG_WEB_0747)" action || return 1
  case "$action" in
    1)
      read -r -p "$(L MSG_WEB_0904)" job
      read -r -p "$(L MSG_WEB_0905)" hour
      read -r -p "$(L MSG_WEB_0906)" minute
      confirm "$(L MSG_WEB_0907)" || return 1
      python3 "$helper" create "$job" --hour "$hour" --minute "$minute" --ack-stable-config || return 1
      msg_ok "$(L MSG_WEB_0908)"
      ;;
    2) python3 "$helper" list ;;
    3) read -r -p "$(L MSG_WEB_0909)" job; python3 "$helper" remove "$job" ;;
    4) python3 "$helper" legacy ;;
    5)
      read -r -p "$(L MSG_WEB_0910)" job
      read -r -p "$(L MSG_WEB_0911)" keep
      python3 "$helper" retention "$job" --keep "$keep" || return 1
      if confirm "$(L MSG_WEB_0912)"; then
        python3 "$helper" retention "$job" --keep "$keep" --enable-delete || return 1
      fi
      ;;
    6)
      read -r -p "$(L MSG_WEB_0910)" job
      read -r -p "$(L MSG_WEB_0913)" archive_name
      confirm "$(L MSG_WEB_0914)" || return 1
      python3 "$helper" restore "$job" --archive "$archive_name" --ack-stopped-writers || return 1
      ;;
    7)
      read -r -p "$(L MSG_WEB_0910)" job
      confirm "$(L MSG_WEB_0915)" || return 1
      python3 "$helper" run "$job" || return 1
      ;;
    *) return 0 ;;
  esac
}

web_site_data() {
  _require_root
  msg_title "$(L MSG_WEB_0916)"
  msg ""

  msg "$(L MSG_WEB_0917 "${F_BOLD}" "${F_RESET}")"
  du -h --max-depth=1 /var/www/ 2>/dev/null | sort -rh | head -10

  msg ""
  msg "$(L MSG_WEB_0918 "${F_BOLD}" "${F_RESET}")"
  du -h --max-depth=1 /opt/docker/ 2>/dev/null | sort -rh | head -10

  msg ""
  msg "$(L MSG_WEB_0919 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0920 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0921 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0922 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
  read -p "$(L MSG_WEB_0747)" sd_choice

  case "$sd_choice" in
    1)
      local backup_dir="/root/site_backups"
      mkdir -p "$backup_dir"
      local date_str=$(date '+%Y%m%d_%H%M%S')
      local backup_file="$backup_dir/site_data_$date_str.tar.gz"
      msg_warn "$(L MSG_WEB_0923)"
      python3 "$FUSION_SRC/lib/archive.py" create web,docker "$backup_file" || return 1
      msg_ok "$(L MSG_WEB_0924 "$backup_file")"
      _log_write "$(L MSG_WEB_0925 "$backup_file")"
      ;;
    2)
      local backup_dir="/root/site_backups"
      local backups=()
      for f in "$backup_dir"/site_data_*.tar.gz; do
        [[ -f "$f" ]] && backups+=("$f")
      done
      if [[ ${#backups[@]} -eq 0 ]]; then
        msg_warn "$(L MSG_WEB_0926)"
      else
        local i=1
        for f in "${backups[@]}"; do
          msg "  $i) $(basename "$f") ($(du -h "$f" | cut -f1))"
          i=$((i+1))
        done
        read -r -p "$(L MSG_WEB_0927)" choice
        [[ "$choice" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
        local idx=$((choice-1))
        if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
          if confirm "$(L MSG_WEB_0928)"; then
            python3 "$FUSION_SRC/lib/archive.py" restore web,docker "${backups[$idx]}" --conflict replace || return 1
            msg_ok "$(L MSG_WEB_0929)"
          fi
        fi
      fi
      ;;
    3)
      _web_backup_jobs
      return $?
      ;;
    4)
      msg_warn "$(L MSG_WEB_0930)"
      _web_backup_jobs || return 1
      ;;
  esac
  pause
}

# ---- 站点克隆 (G39)：复制目录 + 生成新配置（+ 可选 WP 数据库克隆） ----
_web_clone_source_conf() {
  local domain="$1" f rp out=""
  local tmp; tmp=$(mktemp) || return 1
  for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    rp=$(readlink -f "$f" 2>/dev/null || echo "$f")
    grep -qF "$rp$" "$tmp" 2>/dev/null && continue
    if _web_parse_server_blocks "$f" | awk -F'|' -v d="$domain" '$2 == d { found=1 } END { exit !found }'; then
      _web_parse_server_blocks "$f" | awk -F'|' -v d="$domain" '$2 == d { print $1 "|" $4; exit }' >> "$tmp"
      break
    fi
  done
  out=$(tail -1 "$tmp" 2>/dev/null)
  rm -f "$tmp"
  printf '%s' "$out"
}

web_site_clone() {
  _require_root
  local src="${1:-}" new="${2:-}"
  [[ $# -eq 2 ]] || { msg_err "$(L MSG_WEB_0931)"; return 2; }
  _web_validate_domain "$new" || return 1
  [[ "$src" != "$new" ]] || { msg_err "$(L MSG_WEB_0932)"; return 1; }

  local info conf src_root
  info=$(_web_clone_source_conf "$src")
  [[ -n "$info" ]] || { msg_err "$(L MSG_WEB_0933 "$src")"; return 1; }
  conf="${info%%|*}"; src_root="${info##*|}"
  [[ -f "$conf" && -d "$src_root" ]] || { msg_err "$(L MSG_WEB_0934)"; return 1; }

  local new_root
  new_root="$(dirname "$src_root")/$new"   # 与源根目录同级；非 /var/www 布局同样成立
  local conf_dir; conf_dir=$(dirname "$(readlink -f "$conf")")
  local new_conf="$conf_dir/$new.conf"
  local link_target=""
  [[ -L "$conf" ]] && link_target=$(basename "$conf")   # sites-enabled 软链结构

  [[ -e "$new_root" ]] && { msg_err "$(L MSG_WEB_0935 "$new_root")"; return 1; }
  [[ -e "$new_conf" || -e "/etc/nginx/sites-available/$new" ]] && { msg_err "$(L MSG_WEB_0936)"; return 1; }

  msg_info "$(L MSG_WEB_0937 "$src" "$conf" "$src_root")"
  msg_info "$(L MSG_WEB_0938 "$new" "$new_conf" "$new_root")"
  confirm "$(L MSG_WEB_0939)" || { msg_info "$(L MSG_WEB_0940)"; return 1; }

  if ! cp -a "$src_root" "$new_root"; then
    msg_err "$(L MSG_WEB_0941)"
    return 1
  fi

  local avail_conf="$new_conf"
  if [[ -n "$link_target" ]]; then
    avail_conf="/etc/nginx/sites-available/$new"
  fi
  sed -e "s/\b$src\b/$new/g" -e "s#$src_root#$new_root#g" "$conf" > "$avail_conf" || {
    msg_err "$(L MSG_WEB_0942)"; rm -rf "$new_root"; return 1; }
  [[ -n "$link_target" ]] && ln -s "$avail_conf" "$new_conf"

  if ! nginx -t >/dev/null 2>&1; then
    msg_err "$(L MSG_WEB_0943)"
    rm -f "$new_conf"; [[ -n "$link_target" ]] && rm -f "$avail_conf"
    rm -rf "$new_root"
    return 1
  fi
  if ! nginx -s reload 2>/dev/null; then
    msg_warn "$(L MSG_WEB_0944)"
  fi
  msg_ok "$(L MSG_WEB_0945 "$new" "$new_root" "$new_conf")"
  _log_write "$(L MSG_WEB_0946 "$src" "$new")"

  # 可选：WP 数据库克隆（wp-config.php 存在且 mysql 可用时提供）
  if [[ -f "$src_root/wp-config.php" ]] && command -v mysql &>/dev/null && command -v mysqldump &>/dev/null; then
    if confirm "$(L MSG_WEB_0947)"; then
      local db_name db_user db_pass
      db_name=$(grep -oP "define\(\s*'DB_NAME',\s*'\K[^']+" "$src_root/wp-config.php" | tail -1)
      db_user=$(grep -oP "define\(\s*'DB_USER',\s*'\K[^']+" "$src_root/wp-config.php" | tail -1)
      db_pass=$(grep -oP "define\(\s*'DB_PASSWORD',\s*'\K[^']+" "$src_root/wp-config.php" | tail -1)
      if [[ -n "$db_name" && -n "$db_user" ]]; then
        local new_db="${db_name}_clone"
        if MYSQL_PWD="$db_pass" mysql -u "$db_user" -e "CREATE DATABASE IF NOT EXISTS \`$new_db\`;" 2>/dev/null \
          && MYSQL_PWD="$db_pass" mysqldump -u "$db_user" "$db_name" 2>/dev/null \
             | sed -e "s/$src/$new/g" | MYSQL_PWD="$db_pass" mysql -u "$db_user" "$new_db"; then
          msg_ok "$(L MSG_WEB_0948 "$new_db")"
        else
          msg_warn "$(L MSG_WEB_0949)"
        fi
      fi
    fi
  fi
}

# ---- 缓存清理 (G41)：重启 FPM/重载 Nginx + fastcgi_cache 目录 + 可选 CF purge ----
web_cache() {
  _require_root
  command -v nginx &>/dev/null || { msg_err "$(L MSG_WEB_0741)"; return 1; }
  confirm "$(L MSG_WEB_0950)" || { msg_info "$(L MSG_WEB_0940)"; return 1; }

  local u cleared=0
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    systemctl restart "$u" 2>/dev/null && msg_ok "$(L MSG_WEB_0951 "$u")"
  done < <(systemctl list-unit-files 'php*-fpm*' --no-legend 2>/dev/null | awk '{print $1}')

  local path
  while IFS= read -r path; do
    [[ -d "$path" ]] || continue
    find "$path" -mindepth 1 -delete 2>/dev/null && { msg_ok "$(L MSG_WEB_0952 "$path")"; cleared=$((cleared+1)); }
  done < <(grep -rhoP 'fastcgi_cache_path\s+\K[^; ]+' /etc/nginx/nginx.conf /etc/nginx/conf.d/*.conf 2>/dev/null | sort -u)

  nginx -s reload 2>/dev/null && msg_ok "$(L MSG_WEB_0742)" || msg_warn "$(L MSG_WEB_0953)"

  local cf_conf="/etc/fusionbox/cloudflare.conf"
  if [[ -f "$cf_conf" ]] && grep -qE '^CF_API_TOKEN=.+' "$cf_conf" && grep -qE '^CF_ZONE_ID=.+' "$cf_conf"; then
    if confirm "$(L MSG_WEB_0954)"; then
      local token zid resp
      token=$(grep -E '^CF_API_TOKEN=' "$cf_conf" | tail -1 | cut -d= -f2-)
      zid=$(grep -E '^CF_ZONE_ID=' "$cf_conf" | tail -1 | cut -d= -f2-)
      resp=$(curl -s --max-time 15 -X POST "https://api.cloudflare.com/client/v4/zones/$zid/purge_cache" \
        -H "Authorization: Bearer $token" -H "Content-Type: application/json" --data '{"purge_everything":true}' 2>/dev/null)
      [[ "$resp" =~ \"success\"[[:space:]]*:[[:space:]]*true ]] && msg_ok "$(L MSG_WEB_0955)" || msg_warn "$(L MSG_WEB_0956)"
    fi
  else
    msg_info "$(L MSG_WEB_0957)"
  fi
  _log_write "$(L MSG_WEB_0958)"
}

# ---- GoAccess 访问日志分析 (G42) ----
web_goaccess() {
  _require_root
  local domain="${1:-}"
  if ! command -v goaccess &>/dev/null; then
    confirm "$(L MSG_WEB_0959)" || return 1
    _install_pkg goaccess || { msg_err "$(L MSG_WEB_0960)"; return 1; }
  fi
  local log="/var/log/nginx/access.log"
  if [[ -n "$domain" && -f "/var/log/nginx/$domain.access.log" ]]; then
    log="/var/log/nginx/$domain.access.log"
  fi
  [[ -s "$log" ]] || { msg_err "$(L MSG_WEB_0961 "$log")"; return 1; }

  local tag; tag="${domain:-all}"
  local outdir="/root/fusionbox-reports"
  mkdir -p "$outdir" && chmod 700 "$outdir"
  local out="$outdir/goaccess-$tag-$(date +%Y%m%d%H%M%S).html"
  if goaccess "$log" -o "$out" --log-format=COMBINED 2>/dev/null; then
    chmod 600 "$out"
    msg_ok "$(L MSG_WEB_0962 "$out")"
    msg_warn "$(L MSG_WEB_0963)"
    _log_write "$(L MSG_WEB_0964 "$out")"
  else
    msg_err "$(L MSG_WEB_0965)"
    return 1
  fi
}

# ---- 组件热升级 (G49)：nginx/php/mysql/redis 按包管理器升级 ----
_web_upgrade_pkgs_for() {
  local comp="$1"
  case "$comp" in
    nginx) printf '%s\n' nginx ;;
    php)   dpkg -l 2>/dev/null | awk '/^ii  +php[0-9.]+-(fpm|common)$/{print $2}'; rpm -qa 2>/dev/null | grep -E '^php(-fpm)?[0-9.]*(-common)?$\|^php-fpm' | sort -u ;;
    mysql) dpkg -l 2>/dev/null | awk '/^ii  +(mariadb-server|mysql-server)( |$)/{print $2}'; rpm -qa 2>/dev/null | grep -E '^(mariadb-server|mysql-server)$' ;;
    redis) dpkg -l 2>/dev/null | awk '/^ii  +redis(-server)?$/{print $2}'; rpm -qa 2>/dev/null | grep -E '^redis$' ;;
  esac
}

web_upgrade() {
  _require_root
  local comp="${1:-all}"
  command -v nginx &>/dev/null || { msg_err "$(L MSG_WEB_0966)"; return 1; }

  local targets=()
  case "$comp" in
    nginx|php|mysql|redis) targets+=("$comp") ;;
    all) targets=(nginx php mysql redis) ;;
    *) msg_err "$(L MSG_WEB_0967 "$comp")"; return 2 ;;
  esac

  msg_info "$(L MSG_WEB_0968)"
  nginx -v 2>&1 | sed 's/^/  /'
  command -v php &>/dev/null && php -v 2>/dev/null | head -1 | sed 's/^/  /'
  command -v mysqld &>/dev/null && mysqld --version 2>/dev/null | sed 's/^/  /'
  command -v mariadbd &>/dev/null && mariadbd --version 2>/dev/null | sed 's/^/  /'
  command -v redis-server &>/dev/null && redis-server --version 2>/dev/null | sed 's/^/  /'
  msg ""

  local t pkgs p
  for t in "${targets[@]}"; do
    pkgs=$(_web_upgrade_pkgs_for "$t")
    [[ -n "$pkgs" ]] || { msg_info "$(L MSG_WEB_0969 "$t")"; continue; }
    confirm "$(L MSG_WEB_0970 "$t" "$pkgs")" || { msg_info "$(L MSG_WEB_0971 "$t")"; continue; }
    case "$F_PKG_MGR" in
      apt)  apt-get install --only-upgrade -y $pkgs || { msg_err "$(L MSG_WEB_0972 "$t")"; return 1; } ;;
      yum)  yum update -y $pkgs || { msg_err "$(L MSG_WEB_0973 "$t")"; return 1; } ;;
      zypper) zypper update -y $pkgs || { msg_err "$(L MSG_WEB_0973 "$t")"; return 1; } ;;
      apk)  apk upgrade "${pkgs[@]}" || { msg_err "$(L MSG_WEB_0973 "$t")"; return 1; } ;;
      *) msg_err "$(L MSG_WEB_0974)"; return 1 ;;
    esac
  done

  msg_info "$(L MSG_WEB_0975)"
  systemctl restart nginx 2>/dev/null || msg_warn "$(L MSG_WEB_0976)"
  local u
  while IFS= read -r u; do
    [[ -n "$u" ]] && systemctl restart "$u" 2>/dev/null && msg_ok "$(L MSG_WEB_0951 "$u")"
  done < <(systemctl list-unit-files 'php*-fpm*' --no-legend 2>/dev/null | awk '{print $1}')
  systemctl is-active mysql >/dev/null 2>&1 && systemctl restart mysql 2>/dev/null
  systemctl is-active mariadb >/dev/null 2>&1 && systemctl restart mariadb 2>/dev/null
  systemctl is-active redis-server >/dev/null 2>&1 && systemctl restart redis-server 2>/dev/null
  msg_ok "$(L MSG_WEB_0977)"
  msg_info "$(L MSG_WEB_0978)"
  nginx -v 2>&1 | sed 's/^/  /'
  _log_write "$(L MSG_WEB_0979 "$comp")"
}

# ---- LNMP 环境卸载 (G50)：YES 门禁 + 配置备份 + 可选数据删除 ----
web_uninstall_lnmp() {
  _require_root
  msg_title "$(L MSG_WEB_0980)"
  msg ""

  local -a comps=()
  command -v nginx &>/dev/null && comps+=(nginx)
  dpkg -l 2>/dev/null | grep -q '^ii  +php[0-9.]*-fpm' || rpm -qa 2>/dev/null | grep -q '^php-fpm' && comps+=(php)
  command -v mysql &>/dev/null || command -v mariadb &>/dev/null && comps+=(mysql)
  command -v redis-server &>/dev/null && comps+=(redis)
  [[ ${#comps[@]} -eq 0 ]] && { msg_err "$(L MSG_WEB_0981)"; return 1; }

  msg "$(L MSG_WEB_0982 "${comps[*]}")"
  msg_warn "$(L MSG_WEB_0983)"
  confirm "$(L MSG_WEB_0984)" || { msg_info "$(L MSG_WEB_0940)"; return 1; }
  local ans
  read -r -p "$(L MSG_WEB_0985)" ans || { msg_info "$(L MSG_WEB_0940)"; return 1; }
  [[ "$ans" == "YES" ]] || { msg_info "$(L MSG_WEB_0940)"; return 1; }
  read -r -p "$(L MSG_WEB_0986)" ans || ans="keep"
  local wipe="keep"; [[ "$ans" == "wipe" ]] && wipe="wipe"

  local ts; ts=$(date +%Y%m%d%H%M%S)
  local -a conf_dirs=()
  [[ -d /etc/nginx ]] && conf_dirs+=(/etc/nginx)
  [[ -d /etc/php ]] && conf_dirs+=(/etc/php)
  [[ -d /etc/mysql ]] && conf_dirs+=(/etc/mysql)
  [[ -d /etc/redis ]] && conf_dirs+=(/etc/redis)
  if [[ ${#conf_dirs[@]} -gt 0 ]]; then
    if tar czf "/root/lnmp-conf-bak-$ts.tar.gz" "${conf_dirs[@]}" 2>/dev/null; then
      chmod 600 "/root/lnmp-conf-bak-$ts.tar.gz"
      msg_ok "$(L MSG_WEB_0987 "$ts")"
    else
      msg_err "$(L MSG_WEB_0988)"
      return 1
    fi
  fi

  msg_info "$(L MSG_WEB_0989)"
  systemctl disable --now nginx 2>/dev/null
  local u
  while IFS= read -r u; do systemctl disable --now "$u" 2>/dev/null; done \
    < <(systemctl list-unit-files 'php*-fpm*' --no-legend 2>/dev/null | awk '{print $1}')
  systemctl disable --now mysql 2>/dev/null; systemctl disable --now mariadb 2>/dev/null
  systemctl disable --now redis-server 2>/dev/null

  msg_info "$(L MSG_WEB_0990)"
  local -a pkgs=()
  local p
  for p in nginx nginx-core nginx-common php-fpm libapache2-mod-php mariadb-server mariadb-client mysql-server mysql-client redis-server redis; do
    dpkg -s "$p" >/dev/null 2>&1 2>/dev/null && pkgs+=("$p")
    rpm -q "$p" >/dev/null 2>&1 && pkgs+=("$p")
  done
  dpkg -l 2>/dev/null | awk '/^ii  +php[0-9.]+-(fpm|common|cli)$/{print $2}' | while read -r p; do pkgs+=("$p"); done
  if [[ ${#pkgs[@]} -gt 0 ]]; then
    case "$F_PKG_MGR" in
      apt)    apt-get purge -y "${pkgs[@]}" || { msg_err "$(L MSG_WEB_0991)"; return 1; } ;;
      yum)    yum remove -y "${pkgs[@]}" || { msg_err "$(L MSG_WEB_0991)"; return 1; } ;;
      zypper) zypper remove -y "${pkgs[@]}" || { msg_err "$(L MSG_WEB_0991)"; return 1; } ;;
      apk)    apk del "${pkgs[@]}" || { msg_err "$(L MSG_WEB_0991)"; return 1; } ;;
    esac
  fi

  if [[ "$wipe" == "wipe" ]]; then
    msg_info "$(L MSG_WEB_0992)"
    rm -rf /var/www /var/lib/mysql /var/lib/redis
  else
    msg_info "$(L MSG_WEB_0993)"
  fi
  msg_ok "$(L MSG_WEB_0994)"
  _log_write "$(L MSG_WEB_0995 "$wipe")"
}

# ---- 站点清单 ----
# 解析 nginx server 块（容错，按行 + 花括号深度），输出 "文件|域名|端口|root|proxy|cert"
_web_parse_server_blocks() {
  local f="$1"
  awk -v file="$f" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function stmt(s,   dup, n, i, pp) {
      s = trim(s)
      if (s ~ /^server_name[ \t]/) {
        sub(/^server_name[ \t]+/, "", s)
        if (name == "") name = trim(s)
      } else if (s ~ /^listen[ \t]/) {
        sub(/^listen[ \t]+/, "", s)
        sub(/[ \t].*/, "", s)
        sub(/^\[::\]:/, "", s)
        if (s != "") {
          dup = 0
          n = split(port, pp, ",")
          for (i = 1; i <= n; i++) if (pp[i] == s) dup = 1
          if (!dup) port = (port == "" ? s : port "," s)
        }
      } else if (s ~ /^root[ \t]/) {
        sub(/^root[ \t]+/, "", s)
        if (root == "") root = trim(s)
      } else if (s ~ /^proxy_pass[ \t]/) {
        sub(/^proxy_pass[ \t]+/, "", s)
        if (proxy == "") proxy = trim(s)
      } else if (s ~ /^ssl_certificate[ \t]/) {
        sub(/^ssl_certificate[ \t]+/, "", s)
        if (cert == "") cert = trim(s)
      }
    }
    {
      line = $0
      sub(/[ \t]*#.*/, "", line)
      if (in_srv) {
        o = line; nb = gsub(/\{/, "", o)
        c = line; ne = gsub(/\}/, "", c)
        depth += nb - ne
        flat = line
        gsub(/[{}]/, ";", flat)
        n = split(flat, parts, ";")
        for (i = 1; i <= n; i++) stmt(parts[i])
        if (depth <= 0) {
          if (name != "" || port != "" || root != "" || proxy != "") \
            print file "|" name "|" port "|" root "|" proxy "|" cert
          in_srv = 0
        }
      } else if (line ~ /(^|[ \t])server[ \t]*\{/) {
        in_srv = 1; depth = 0
        name = ""; port = ""; root = ""; proxy = ""; cert = ""
        o = line; nb = gsub(/\{/, "", o)
        c = line; ne = gsub(/\}/, "", c)
        depth += nb - ne
        flat = line
        sub(/^.*server[ \t]*\{/, "", flat)
        gsub(/[{}]/, ";", flat)
        n = split(flat, parts, ";")
        for (i = 1; i <= n; i++) stmt(parts[i])
        if (depth <= 0) {
          if (name != "" || port != "" || root != "" || proxy != "") \
            print file "|" name "|" port "|" root "|" proxy "|" cert
          in_srv = 0
        }
      }
    }
  ' "$f"
}

web_sites() {
  _require_root
  msg_title "$(L MSG_WEB_0996)"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_warn "$(L MSG_WEB_0997)"
    pause; return
  fi

  local files=() f
  for f in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*.conf; do
    [[ -e "$f" || -L "$f" ]] || continue
    [[ -f "$f" ]] || continue
    files+=("$f")
  done

  # 去重：sites-enabled 常是 sites-available 的软链
  declare -A _seen_site=()
  local uniq=() rp
  for f in "${files[@]}"; do
    rp=$(readlink -f "$f" 2>/dev/null || echo "$f")
    [[ -n "${_seen_site[$rp]:-}" ]] && continue
    _seen_site[$rp]=1
    uniq+=("$f")
  done
  unset _seen_site

  local parsed; parsed=$(mktemp)
  for f in "${uniq[@]}"; do
    _web_parse_server_blocks "$f" >> "$parsed"
  done

  if [[ ! -s "$parsed" ]]; then
    rm -f "$parsed"
    msg_info "$(L MSG_WEB_0998)"
    pause; return
  fi

  msg "$(L MSG_WEB_0999 "${F_BOLD}" "${F_RESET}")"
  msg "  ----------------------------------------------------------------------------"

  local total=0
  local domains=()
  while IFS='|' read -r conf name port root proxy cert; do
    [[ -z "$name$port$root$proxy" ]] && continue
    total=$((total + 1))

    # 类型：反代 > PHP > 静态
    local type="$(L MSG_WEB_1000)"
    if [[ -n "$proxy" ]]; then
      type="$(L MSG_WEB_1001)"
    elif grep -qE "fastcgi_pass|php" "$conf" 2>/dev/null; then
      type="PHP"
    fi

    local target="-"
    [[ -n "$proxy" ]] && target="$proxy"
    [[ -z "$proxy" && -n "$root" ]] && target="$root"

    local cert_info="-" days
    if [[ -n "$cert" && -f "$cert" ]]; then
      days=$(_web_cert_days "$cert" 2>/dev/null)
      if [[ -n "$days" && "$days" =~ ^-?[0-9]+$ ]]; then
        if (( days < 0 )); then
          cert_info="$(L MSG_WEB_1002 "${F_RED}" "${F_RESET}")"
        elif (( days < 15 )); then
          cert_info="$(L MSG_WEB_1003 "${F_YELLOW}" "${days}" "${F_RESET}")"
        else
          cert_info="$(L MSG_WEB_1003 "${F_GREEN}" "${days}" "${F_RESET}")"
        fi
      else
        cert_info="$(L MSG_WEB_0724)"
      fi
    fi

    msg "  ${F_BOLD}${name}${F_RESET} | ${port:--} | $type | $target | $cert_info | $conf"

    local primary="${name%% *}"
    [[ -n "$primary" ]] && domains+=("$primary")
  done < "$parsed"
  rm -f "$parsed"

  msg ""
  msg "$(L MSG_WEB_1004 "$total")"

  # 站点目录占用
  local shown=0 d
  declare -A _seen_dir=()
  for d in "${domains[@]}"; do
    [[ -z "$d" ]] && continue
    [[ -n "${_seen_dir[$d]:-}" ]] && continue
    _seen_dir[$d]=1
    if [[ -d "/var/www/$d" ]]; then
      if [[ $shown -eq 0 ]]; then
        msg ""
        msg "$(L MSG_WEB_1005 "${F_BOLD}" "${F_RESET}")"
      fi
      msg "    $(du -sh "/var/www/$d" 2>/dev/null | cut -f1)  /var/www/$d"
      shown=$((shown + 1))
    fi
  done
  unset _seen_dir

  pause
}

# ---- 删除站点 ----
web_site_del() {
  _require_root
  msg_title "$(L MSG_WEB_1006)"
  msg ""

  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    domain=$(read_input "$(L MSG_WEB_1007)")
  fi
  if ! _web_validate_domain "$domain"; then
    msg_err "$(L MSG_WEB_0655 "$domain")"
    pause; return 1
  fi

  local conf_avail="/etc/nginx/sites-available/$domain"
  local conf_enabled="/etc/nginx/sites-enabled/$domain"
  local conf_d="/etc/nginx/conf.d/$domain.conf"

  if [[ ! -e "$conf_avail" && ! -L "$conf_avail" && \
        ! -e "$conf_enabled" && ! -L "$conf_enabled" && \
        ! -e "$conf_d" && ! -L "$conf_d" ]]; then
    msg_err "$(L MSG_WEB_1008 "$domain")"
    pause; return 1
  fi

  # 先备份（配置 -> /etc/fusionbox/site-bak-<ts>/）
  local ts; ts=$(date +%Y%m%d%H%M%S)
  local bak_dir="/etc/fusionbox/site-bak-$ts"
  mkdir -p "$bak_dir"
  local -a bak_pairs=()
  if [[ -e "$conf_avail" || -L "$conf_avail" ]]; then
    cp -a "$conf_avail" "$bak_dir/sites-available_$domain" 2>/dev/null && \
      bak_pairs+=("$conf_avail|$bak_dir/sites-available_$domain")
  fi
  if [[ -e "$conf_enabled" || -L "$conf_enabled" ]]; then
    cp -a "$conf_enabled" "$bak_dir/sites-enabled_$domain" 2>/dev/null && \
      bak_pairs+=("$conf_enabled|$bak_dir/sites-enabled_$domain")
  fi
  if [[ -e "$conf_d" || -L "$conf_d" ]]; then
    cp -a "$conf_d" "$bak_dir/conf.d_$domain.conf" 2>/dev/null && \
      bak_pairs+=("$conf_d|$bak_dir/conf.d_$domain.conf")
  fi

  if ! confirm "$(L MSG_WEB_1009 "$domain" "$bak_dir")"; then
    return
  fi

  local del_root=0
  if [[ -d "/var/www/$domain" ]]; then
    if confirm "$(L MSG_WEB_1010 "$domain")"; then
      del_root=1
    fi
  fi

  local original expected=0
  for original in "$conf_enabled" "$conf_avail" "$conf_d"; do
    [[ -e "$original" || -L "$original" ]] && expected=$((expected+1))
  done
  [[ ${#bak_pairs[@]} -eq $expected ]] || { msg_err "$(L MSG_WEB_1011)"; return 1; }
  rm -f "$conf_enabled" "$conf_avail" "$conf_d" || return 1

  if ! nginx -t 2>/dev/null; then
    # 回滚配置（含软链：-L 兼容目标暂时不存在的情况）
    local pair src dst
    for pair in "${bak_pairs[@]}"; do
      src="${pair%%|*}"; dst="${pair##*|}"
      [[ -e "$dst" || -L "$dst" ]] && cp -a "$dst" "$src" 2>/dev/null
    done
    msg_err "$(L MSG_WEB_1012 "$bak_dir")"
    pause; return 1
  fi

  systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  msg_ok "$(L MSG_WEB_1013 "$domain")"
  msg_info "$(L MSG_WEB_1014 "$bak_dir")"

  if [[ $del_root -eq 1 ]]; then
    rm -rf "/var/www/$domain"
    msg_ok "$(L MSG_WEB_1015 "$domain")"
  fi

  # 证书需单独清理
  if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
    msg ""
    msg_info "$(L MSG_WEB_1016 "$domain")"
    if confirm "$(L MSG_WEB_1017 "$domain")"; then
      if command -v certbot &>/dev/null; then
        certbot delete --cert-name "$domain" --non-interactive 2>/dev/null && \
          msg_ok "$(L MSG_WEB_1018 "$domain")" || msg_err "$(L MSG_WEB_1019 "$domain")"
      else
        msg_err "$(L MSG_WEB_1020 "$domain")"
      fi
    else
      msg_info "$(L MSG_WEB_1021 "$domain")"
    fi
  fi

  _log_write "$(L MSG_WEB_1022 "$domain" "$bak_dir")"
  pause
}

# ---- 关联多域名（server_name 别名）----
web_site_alias() {
  _require_root
  msg_title "$(L MSG_WEB_1023)"
  msg ""

  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    domain=$(read_input "$(L MSG_WEB_1024)")
  fi
  if ! _web_validate_domain "$domain"; then
    msg_err "$(L MSG_WEB_0655 "$domain")"
    pause; return 1
  fi

  # 定位配置文件
  local conf="" conf_real=""
  if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
    conf="/etc/nginx/sites-available/$domain"
  elif [[ -f "/etc/nginx/sites-enabled/$domain" ]]; then
    conf="/etc/nginx/sites-enabled/$domain"
  elif [[ -f "/etc/nginx/conf.d/$domain.conf" ]]; then
    conf="/etc/nginx/conf.d/$domain.conf"
  fi
  if [[ -z "$conf" ]]; then
    msg_err "$(L MSG_WEB_1025 "$domain")"
    pause; return 1
  fi
  # 软链场景：改写目标文件，避免破坏软链
  conf_real=$(readlink -f "$conf" 2>/dev/null || echo "$conf")

  local alias_domain="${2:-}"
  if [[ -z "$alias_domain" ]]; then
    alias_domain=$(read_input "$(L MSG_WEB_1026 "$domain")")
  fi
  if ! _web_validate_domain "$alias_domain"; then
    msg_err "$(L MSG_WEB_1027 "$alias_domain")"
    pause; return 1
  fi
  if [[ "$alias_domain" == "$domain" ]]; then
    msg_err "$(L MSG_WEB_1028)"
    pause; return 1
  fi

  local already=0
  if grep -qE "^[[:space:]]*server_name[^;]*[[:space:]]${alias_domain}([[:space:]]|;)" "$conf_real" 2>/dev/null; then
    already=1
    msg_info "$(L MSG_WEB_1029 "$alias_domain")"
  fi

  # 备份
  local ts; ts=$(date +%Y%m%d%H%M%S)
  local bak_dir="/etc/fusionbox/site-bak-$ts"
  mkdir -p "$bak_dir"
  local conf_bak="$bak_dir/$(basename "$conf_real")"
  cp -a "$conf_real" "$conf_bak" 2>/dev/null || { msg_err "$(L MSG_WEB_1030)"; return 1; }

  if [[ $already -eq 0 ]]; then
    if ! confirm "$(L MSG_WEB_1031 "$alias_domain" "$domain")"; then
      return
    fi

    local tmp; tmp=$(mktemp)
    awk -v d="$domain" -v a="$alias_domain" '
      /^[ \t]*server_name[ \t]/ {
        if (index($0, d) > 0 && index($0, a) == 0) {
          sub(/;/, " " a ";")
          hit++
        }
      }
      { print }
      END { if (hit == 0) exit 3 }
    ' "$conf_real" > "$tmp"
    local awk_rc=$?
    if [[ $awk_rc -ne 0 ]]; then
      rm -f "$tmp"
      msg_err "$(L MSG_WEB_1032 "$conf_real" "$domain")"
      pause; return 1
    fi
    cat "$tmp" > "$conf_real"
    rm -f "$tmp"

    if ! nginx -t 2>/dev/null; then
      cp -a "$conf_bak" "$conf_real" 2>/dev/null
      msg_err "$(L MSG_WEB_1033 "$conf_real")"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
    msg_ok "$(L MSG_WEB_1034 "$domain" "$alias_domain")"
    msg_info "$(L MSG_WEB_1014 "$bak_dir")"
  fi

  # 多域名证书
  if command -v certbot &>/dev/null; then
    if confirm "$(L MSG_WEB_1035 "$domain" "$alias_domain")"; then
      certbot --nginx -d "$domain" -d "$alias_domain" --expand --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null || \
        certbot --nginx -d "$domain" -d "$alias_domain" --expand 2>/dev/null || \
        msg_err "$(L MSG_WEB_1036)"
      systemctl reload nginx 2>/dev/null || true
    else
      msg_info "$(L MSG_WEB_1037 "$domain" "$alias_domain")"
    fi
  else
    msg_warn "$(L MSG_WEB_1038)"
  fi

  _log_write "$(L MSG_WEB_1039 "$domain" "$alias_domain")"
  pause
}

# ---- 调优档位 (G45/G48)：standard/high 两档，事务化修改 nginx/PHP-FPM/MySQL，支持恢复 ----
_WEB_TUNE_BACKUP_BASE="/etc/fusionbox/tune-backups"

_web_tune_backup_file() {
  local f="$1" dir="$_WEB_TUNE_BACKUP_BASE/latest" name
  [[ -f "$f" && ! -L "$f" ]] || { printf ''; return 0; }
  mkdir -p "$dir"
  name="$(printf '%s' "$f" | md5sum | cut -c1-12)_$(basename "$f")"
  cp -p "$f" "$dir/$name" || return 1
  grep -qF "$name $f" "$dir/manifest" 2>/dev/null || printf '%s %s\n' "$name" "$f" >> "$dir/manifest"
  printf '%s' "$dir/$name"
}

_web_tune_total_mem_mb() {
  awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 2048
}

_web_tune_php_bins() {
  ls /usr/sbin/php-fpm* 2>/dev/null || true
}

_web_tune_nginx() {
  local mode="$1" conf="/etc/nginx/nginx.conf"
  [[ -f "$conf" && ! -L "$conf" ]] || { msg_info "$(L MSG_WEB_1040)"; return 0; }
  local bak; bak=$(_web_tune_backup_file "$conf") || { msg_err "$(L MSG_WEB_1041)"; return 1; }
  local conn=1024
  [[ "$mode" == "high" ]] && conn=4096
  if ! sed -i "s/worker_connections .*/worker_connections $conn;/" "$conf"; then
    cp -p "$bak" "$conf"; msg_err "$(L MSG_WEB_1042)"; return 1
  fi
  if [[ "$mode" == "high" ]] && ! grep -q "gzip_vary" "$conf"; then
    sed -i '/http {/a\    gzip on;\n    gzip_vary on;\n    gzip_min_length 1024;' "$conf"
  fi
  if ! nginx -t >/dev/null 2>&1; then
    cp -p "$bak" "$conf"; nginx -t >/dev/null 2>&1
    msg_err "$(L MSG_WEB_1043)"
    return 1
  fi
  nginx -s reload >/dev/null 2>&1 || msg_warn "$(L MSG_WEB_1044)"
  msg_ok "$(L MSG_WEB_1045 "$mode" "$conn")"
  _log_write "web tune nginx $mode"
}

_web_tune_php() {
  local mode="$1" pools mem children bin
  pools=$(ls /etc/php/*/fpm/pool.d/www.conf 2>/dev/null || true)
  [[ -n "$pools" ]] || { msg_info "$(L MSG_WEB_1046)"; return 0; }
  mem=$(_web_tune_total_mem_mb)
  children=$(( mem / 80 )); [[ "$mode" == "high" ]] && children=$(( mem / 40 ))
  [ "$children" -lt 5 ] && children=5
  for pool in $pools; do
    local bak; bak=$(_web_tune_backup_file "$pool") || { msg_warn "$(L MSG_WEB_1047 "$pool")"; continue; }
    sed -i -e "s/^pm.max_children = .*/pm.max_children = $children/" \
           -e "s/^pm.start_servers = .*/pm.start_servers = 4/" \
           -e "s/^pm.min_spare_servers = .*/pm.min_spare_servers = 2/" \
           -e "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $(( children > 6 ? 6 : children ))/" "$pool"
  done
  local validated=0
  for bin in $(_web_tune_php_bins); do
    if "$bin" -t >/dev/null 2>&1; then validated=1; break; fi
  done
  if [[ $validated -eq 0 ]]; then
    for pool in $pools; do
      local name; name="$(printf '%s' "$pool" | md5sum | cut -c1-12)_$(basename "$pool")"
      cp -p "$_WEB_TUNE_BACKUP_BASE/latest/$name" "$pool" 2>/dev/null || true
    done
    msg_err "$(L MSG_WEB_1048)"
    return 1
  fi
  systemctl list-unit-files 'php*-fpm*' --no-legend 2>/dev/null | awk '{print $1}' | while IFS= read -r u; do
    systemctl reload "$u" 2>/dev/null && msg_ok "$(L MSG_WEB_1049 "$u")"
  done
  msg_ok "$(L MSG_WEB_1050 "$mode" "$children")"
  _log_write "web tune php $mode"
}

_web_tune_mysql() {
  local mode="$1" conf="" size="128M"
  [[ "$mode" == "high" ]] && size="1G"
  for conf in /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf; do
    [[ -f "$conf" && ! -L "$conf" ]] && break
    conf=""
  done
  [[ -n "$conf" ]] || { msg_info "$(L MSG_WEB_1051)"; return 0; }
  local bak; bak=$(_web_tune_backup_file "$conf") || { msg_err "$(L MSG_WEB_1047 "$conf")"; return 1; }
  if grep -qE '^innodb_buffer_pool_size' "$conf"; then
    sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = $size/" "$conf"
  else
    printf '\ninnodb_buffer_pool_size = %s\n' "$size" >> "$conf"
  fi
  msg_ok "$(L MSG_WEB_1052 "$mode" "$size")"
  _log_write "web tune mysql $mode"
}

web_tune() {
  _require_root
  local mode="${1:-show}"
  case "$mode" in
    show)
      msg_title "$(L MSG_WEB_1053)"
      msg "$(L MSG_WEB_1054 "$(grep -oP 'worker_connections\s+\K[0-9]+' /etc/nginx/nginx.conf 2>/dev/null || echo 未知)")"
      msg "$(L MSG_WEB_1055 "$(grep -h '^pm.max_children' /etc/php/*/fpm/pool.d/www.conf 2>/dev/null | head -1 | grep -oP '[0-9]+' || echo 未安装)")"
      msg "$(L MSG_WEB_1056 "$(grep -hE '^innodb_buffer_pool_size' /etc/mysql/mysql.conf.d/mysqld.cnf /etc/mysql/mariadb.conf.d/50-server.cnf 2>/dev/null | head -1 | sed 's/^[^=]*= *//' || echo 未安装)")"
      msg ""
      msg "$(L MSG_WEB_1057)"
      msg "$(L MSG_WEB_1058)"
      ;;
    standard|high)
      confirm "$(L MSG_WEB_1059 "$mode")" || { msg_info "$(L MSG_WEB_0940)"; return 1; }
      local rc=0
      _web_tune_nginx "$mode" || rc=1
      _web_tune_php "$mode" || rc=1
      _web_tune_mysql "$mode" || rc=1
      [[ $rc -eq 0 ]] && msg_ok "$(L MSG_WEB_1060 "$mode")"
      return $rc
      ;;
    restore)
      local dir="$_WEB_TUNE_BACKUP_BASE/latest"
      [[ -f "$dir/manifest" ]] || { msg_err "$(L MSG_WEB_1061)"; return 1; }
      confirm "$(L MSG_WEB_1062)" || { msg_info "$(L MSG_WEB_0940)"; return 1; }
      local name dest
      while IFS=' ' read -r name dest; do
        [[ -n "$name" && -n "$dest" ]] || continue
        cp -p "$dir/$name" "$dest" && msg_ok "$(L MSG_WEB_1063 "$dest")"
      done < "$dir/manifest"
      nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1
      msg_ok "$(L MSG_WEB_0929)"
      _log_write "web tune restore"
      ;;
    *)
      msg_err "$(L MSG_WEB_1064 "$mode")"; return 2 ;;
  esac
}

# ---- brotli 压缩开关 (G46)：Ubuntu 打包的 brotli 模块，自有 conf 文件管理 ----
_WEB_BROTLI_PKG="libnginx-mod-http-brotli-filter"
_WEB_BROTLI_CONF="/etc/nginx/conf.d/fusionbox-brotli.conf"

web_brotli() {
  _require_root
  local action="${1:-status}"
  command -v nginx &>/dev/null || { msg_err "$(L MSG_WEB_0741)"; return 1; }

  case "$action" in
    status)
      if dpkg -s "$_WEB_BROTLI_PKG" >/dev/null 2>&1; then
        msg "$(L MSG_WEB_1065 "$_WEB_BROTLI_PKG")"
      else
        msg "$(L MSG_WEB_1066)"
      fi
      if [[ -f "$_WEB_BROTLI_CONF" ]]; then
        msg "$(L MSG_WEB_1067 "$_WEB_BROTLI_CONF")"
      else
        msg "$(L MSG_WEB_1068)"
      fi
      msg "$(L MSG_WEB_1069)"
      ;;
    on)
      if ! dpkg -s "$_WEB_BROTLI_PKG" >/dev/null 2>&1; then
        confirm "$(L MSG_WEB_1070 "$_WEB_BROTLI_PKG")" || { msg_info "$(L MSG_WEB_0940)"; return 1; }
        _install_pkg "$_WEB_BROTLI_PKG" || { msg_err "$(L MSG_WEB_1071)"; return 1; }
      fi
      if [[ -f "$_WEB_BROTLI_CONF" ]]; then
        msg_info "$(L MSG_WEB_1072)"
        return 0
      fi
      cat > "$_WEB_BROTLI_CONF" << 'BREOF'
# FusionBox managed brotli compression
brotli on;
brotli_comp_level 5;
brotli_types text/plain text/css application/json application/javascript
    application/x-javascript text/xml application/xml application/xml+rss
    text/javascript image/svg+xml;
BREOF
      if ! nginx -t >/dev/null 2>&1; then
        rm -f "$_WEB_BROTLI_CONF"
        msg_err "$(L MSG_WEB_1073)"
        return 1
      fi
      nginx -s reload >/dev/null 2>&1 || msg_warn "$(L MSG_WEB_1074)"
      msg_ok "$(L MSG_WEB_1075)"
      _log_write "$(L MSG_WEB_1072)"
      ;;
    off)
      [[ -f "$_WEB_BROTLI_CONF" ]] || { msg_info "$(L MSG_WEB_1076)"; return 0; }
      rm -f "$_WEB_BROTLI_CONF"
      nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1
      msg_ok "$(L MSG_WEB_1077)"
      _log_write "$(L MSG_WEB_1078)"
      ;;
    *)
      msg_err "$(L MSG_WEB_1079 "$action")"; return 2 ;;
  esac
}

# ---- WordPress Redis 预配置 (G47)：wp-config 注入 + php -l 校验 + 回滚 ----
web_wp_redis() {
  _require_root
  local domain="${1:-}"
  [[ $# -eq 1 && -n "$domain" ]] || { msg_err "$(L MSG_WEB_1080)"; return 2; }
  local info conf root
  info=$(_web_clone_source_conf "$domain")
  [[ -n "$info" ]] || { msg_err "$(L MSG_WEB_1081 "$domain")"; return 1; }
  conf="${info%%|*}"; root="${info##*|}"
  local wpc="$root/wp-config.php"
  [[ -f "$wpc" ]] || { msg_err "$(L MSG_WEB_1082 "$domain")"; return 1; }

  if grep -q "WP_REDIS_HOST" "$wpc"; then
    msg_info "$(L MSG_WEB_1083)"
    return 0
  fi

  if ! command -v redis-cli &>/dev/null; then
    confirm "$(L MSG_WEB_1084)" || { msg_info "$(L MSG_WEB_0940)"; return 1; }
    _install_pkg redis-server || { msg_err "$(L MSG_WEB_1085)"; return 1; }
    systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null
  fi
  redis-cli ping 2>/dev/null | grep -q PONG || { msg_err "$(L MSG_WEB_1086)"; return 1; }
  if command -v php &>/dev/null && ! php -m 2>/dev/null | grep -qi '^redis$'; then
    msg_warn "$(L MSG_WEB_1087)"
    confirm "$(L MSG_WEB_1088)" || true
    _install_pkg php-redis 2>/dev/null || msg_warn "$(L MSG_WEB_1089)"
  fi

  local anchor="That's all, stop editing"
  if ! grep -qF "$anchor" "$wpc"; then
    msg_err "$(L MSG_WEB_1090)"
    return 1
  fi

  local bak; bak=$(_web_tune_backup_file "$wpc") || { msg_err "$(L MSG_WEB_1091)"; return 1; }
  sed -i "/${anchor}/i define( 'WP_REDIS_HOST', '127.0.0.1' );\ndefine( 'WP_CACHE', true );" "$wpc"
  if command -v php &>/dev/null && ! php -l "$wpc" >/dev/null 2>&1; then
    cp -p "$bak" "$wpc"
    msg_err "$(L MSG_WEB_1092)"
    return 1
  fi
  msg_ok "$(L MSG_WEB_1093)"
  msg_warn "$(L MSG_WEB_1094)"
  _log_write "$(L MSG_WEB_1095 "$domain")"
}

# ---- WordPress 快速部署 (快捷) ----
web_wordpress() {
  _deploy_wordpress
}

# ---- 防 CC 与 Cloudflare 联动 ----
web_guard() {
  _require_root

  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_WEB_1096)"
    msg ""
    msg "$(L MSG_WEB_1097 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1098 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1099 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1100 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1101 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
    msg ""
    local g_choice=""
    read -p "$(L MSG_WEB_1102)" g_choice || return
    case "$g_choice" in
      1) _web_guard_cc_install ;;
      2) _web_guard_cc_uninstall ;;
      3) _web_guard_cc_status ;;
      4) _web_guard_cf_config ;;
      5) _web_guard_cf_adaptive ;;
      0) return ;;
      *) continue ;;
    esac
    pause
  done
}

# 安装 fail2ban 防 CC
_web_guard_cc_install() {
  msg_info "$(L MSG_WEB_1103)"
  msg ""

  if ! confirm "$(L MSG_WEB_1104)"; then
    return
  fi

  if ! command -v fail2ban-client &>/dev/null; then
    msg_info "$(L MSG_WEB_1105)"
    _install_pkg fail2ban || { msg_err "$(L MSG_WEB_1106)"; return 1; }
  fi
  systemctl enable fail2ban 2>/dev/null || true

  local filter="/etc/fail2ban/filter.d/fusionbox-nginx-cc.conf"
  local jail="/etc/fail2ban/jail.d/fusionbox-nginx-cc.local"
  mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d
  # 先备份已有同名文件
  [[ -f "$filter" ]] && cp "$filter" "$filter.fb-bak-$(date +%s)" 2>/dev/null
  [[ -f "$jail" ]] && cp "$jail" "$jail.fb-bak-$(date +%s)" 2>/dev/null

  cat > "$filter" << 'F2BFILTER'
# FusionBox nginx 防 CC 过滤器（_daemon = nginx）
# 统计同一来源 IP 在 findtime 内的 4xx 请求次数
[Definition]
failregex = ^<HOST> \S+ \S+ \[[^\]]+\] "(?:GET|POST|HEAD|PUT|DELETE|OPTIONS|PATCH|CONNECT) [^"]*"\s+4\d\d\s
ignoreregex =
F2BFILTER

  cat > "$jail" << 'F2BJAIL'
[fusionbox-nginx-cc]
enabled = true
filter = fusionbox-nginx-cc
logpath = /var/log/nginx/access.log
maxretry = 30
findtime = 60
bantime = 3600
action = iptables-multiport[name=fusionbox-nginx,port="http,https"]
F2BJAIL

  if [[ ! -f /var/log/nginx/access.log ]]; then
    msg_warn "$(L MSG_WEB_1107)"
  fi

  if ! systemctl restart fail2ban 2>/dev/null; then
    msg_err "$(L MSG_WEB_1108)"
    return 1
  fi

  if fail2ban-client status fusionbox-nginx-cc >/dev/null 2>&1; then
    msg_ok "$(L MSG_WEB_1109)"
    fail2ban-client status fusionbox-nginx-cc 2>/dev/null | sed 's/^/  /'
    _log_write "$(L MSG_WEB_1110)"
  else
    msg_err "$(L MSG_WEB_1111)"
    msg_info "$(L MSG_WEB_1112)"
    return 1
  fi
}

# 卸载 fail2ban 防 CC
_web_guard_cc_uninstall() {
  local filter="/etc/fail2ban/filter.d/fusionbox-nginx-cc.conf"
  local jail="/etc/fail2ban/jail.d/fusionbox-nginx-cc.local"

  if ! command -v fail2ban-client &>/dev/null; then
    msg_info "$(L MSG_WEB_1113)"
    return
  fi

  if ! confirm "$(L MSG_WEB_1114)"; then
    return
  fi

  # 先解除该 jail 已封禁的 IP，避免残留 iptables 规则
  local banned ip
  banned=$(fail2ban-client status fusionbox-nginx-cc 2>/dev/null | sed -n 's/.*Banned IP list:[[:space:]]*//p')
  if [[ -n "$banned" ]]; then
    for ip in $banned; do
      fail2ban-client set fusionbox-nginx-cc unbanip "$ip" >/dev/null 2>&1 || true
    done
    msg_info "$(L MSG_WEB_1115 "$banned")"
  fi

  local removed=0
  if [[ -f "$filter" ]]; then
    rm -f "$filter"; removed=1; msg_ok "$(L MSG_WEB_0876 "$filter")"
  fi
  if [[ -f "$jail" ]]; then
    rm -f "$jail"; removed=1; msg_ok "$(L MSG_WEB_0876 "$jail")"
  fi
  [[ $removed -eq 0 ]] && msg_info "$(L MSG_WEB_1116)"

  systemctl restart fail2ban 2>/dev/null || systemctl reload fail2ban 2>/dev/null || true
  msg_ok "$(L MSG_WEB_1117)"
  _log_write "$(L MSG_WEB_1117)"
}

# 查看 fail2ban jail 与封禁 IP
_web_guard_cc_status() {
  if ! command -v fail2ban-client &>/dev/null; then
    msg_warn "$(L MSG_WEB_1118)"
    return
  fi
  if ! fail2ban-client status >/dev/null 2>&1; then
    msg_err "$(L MSG_WEB_1119)"
    systemctl status fail2ban --no-pager 2>/dev/null | head -5 | sed 's/^/  /'
    return
  fi

  msg "$(L MSG_WEB_1120 "${F_BOLD}" "${F_RESET}")"
  fail2ban-client status 2>/dev/null | sed 's/^/  /'

  local jails j
  jails=$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ')
  if [[ -z "${jails// /}" ]]; then
    msg_info "$(L MSG_WEB_1121)"
    return
  fi

  for j in $jails; do
    msg ""
    msg "  ${F_BOLD}Jail: $j${F_RESET}"
    fail2ban-client status "$j" 2>/dev/null | sed 's/^/    /'
  done
}

# Cloudflare 联动：配置 + 封禁辅助脚本
_web_guard_cf_config() {
  local cf_conf="/etc/fusionbox/cloudflare.conf"
  local ban_script="/usr/local/bin/fusionbox-cf-ban"

  msg "$(L MSG_WEB_1122 "${F_BOLD}" "${F_RESET}")"
  msg ""
  if [[ -f "$cf_conf" ]]; then
    local zid
    zid=$(sed -n 's/^CF_ZONE_ID=//p' "$cf_conf" 2>/dev/null | tail -1)
    msg_info "$(L MSG_WEB_1123 "$cf_conf")"
    msg "$(L MSG_WEB_1124 "${zid:-未设置}")"
    if grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
      msg_ok "$(L MSG_WEB_1125)"
    else
      msg_warn "$(L MSG_WEB_1126)"
    fi
  else
    msg_warn "$(L MSG_WEB_1127 "$cf_conf")"
  fi
  msg ""

  msg "$(L MSG_WEB_1128 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_1129 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
  msg ""
  local cf_choice=""
  read -p "$(L MSG_WEB_1130)" cf_choice || return

  case "$cf_choice" in
    1)
      msg_info "$(L MSG_WEB_1131)"
      local token zone threshold
      token=$(read_input "$(L MSG_WEB_1132)")
      [[ -z "$token" ]] && { msg_warn "$(L MSG_WEB_1133)"; return; }

      # Global API Key（37 位十六进制）不能用作 Bearer Token：现场铸造最小权限 Token
      if [[ "$token" =~ ^[a-f0-9]{37}$ ]]; then
        if ! confirm "$(L MSG_WEB_1134)"; then
          msg_warn "$(L MSG_WEB_1135)"
          return
        fi
        local cf_email
        cf_email=$(read_input "$(L MSG_WEB_1136)")
        if ! [[ "$cf_email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
          msg_err "$(L MSG_WEB_0683)"
          return 1
        fi
        local gk_cfg gk_resp
        gk_cfg=$(mktemp) || return 1
        chmod 600 "$gk_cfg"
        printf 'header = "X-Auth-Email: %s"\nheader = "X-Auth-Key: %s"\nheader = "Content-Type: application/json"\n' "$cf_email" "$token" > "$gk_cfg"
        gk_resp=$(curl -fsS --max-time 25 "https://api.cloudflare.com/client/v4/zones?per_page=50" -K "$gk_cfg" 2>/dev/null)
        if [[ -z "$gk_resp" ]] || ! echo "$gk_resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("success")' 2>/dev/null; then
          rm -f "$gk_cfg"
          msg_err "$(L MSG_WEB_1137)"
          return 1
        fi
        msg "$(L MSG_WEB_1138)"
        local zl
        zl=$(echo "$gk_resp" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for i, z in enumerate(d.get('result') or [], 1):
    print('%d|%s|%s|%s' % (i, z['id'], z['name'], z['status']))")
        rm -f "$gk_cfg"
        if [[ -z "$zl" ]]; then
          msg_err "$(L MSG_WEB_1139)"
          return 1
        fi
        local zline
        while IFS= read -r zline; do
          msg "      ${zline%%|*}) ${zline#*|}"
        done <<< "$zl"
        local zpick
        zpick=$(read_input "$(L MSG_WEB_1140)")
        local zsel
        zsel=$(echo "$zl" | awk -F'|' -v p="$zpick" '$1 == p {print $2 "|" $3}')
        if [[ -z "$zsel" ]]; then
          msg_err "$(L MSG_WEB_1141 "$zpick")"
          return 1
        fi
        zone="${zsel%%|*}"
        local zname="${zsel##*|}"
        # 权限组 ID 是 Cloudflare 全局常量：Zone Read / Zone Settings Read+Write / Firewall Services Write
        local expires
        expires=$(date -u -d '+14 days' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
        local mint_cfg mint_payload mint_resp
        mint_cfg=$(mktemp) || return 1
        chmod 600 "$mint_cfg"
        printf 'header = "X-Auth-Email: %s"\nheader = "X-Auth-Key: %s"\nheader = "Content-Type: application/json"\n' "$cf_email" "$token" > "$mint_cfg"
        mint_payload=$(printf '{"name":"fusionbox-managed (%s)","policies":[{"effect":"allow","resources":{"com.cloudflare.api.account.zone.%s":"*"},"permission_groups":[{"id":"c8fed203ed3043cba015a93ad1616f1f"},{"id":"517b21aee92c4d89936c976ba6e4be55"},{"id":"3030687196b94b638145a3953da2b699"},{"id":"43137f8d07884d3198dc0ee77ca6e79b"}]}]%s}' "$zname" "$zone" "${expires:+,\"expires_on\":\"$expires\"}")
        mint_resp=$(curl -fsS --max-time 25 -X POST "https://api.cloudflare.com/client/v4/user/tokens" -K "$mint_cfg" --data "$mint_payload" 2>/dev/null)
        rm -f "$mint_cfg"
        local minted
        minted=$(printf '%s' "$mint_resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("success"); print(d["result"]["value"])' 2>/dev/null)
        if [[ -z "$minted" ]]; then
          msg_err "$(L MSG_WEB_1142)"
          return 1
        fi
        msg_ok "$(L MSG_WEB_1143 "$zname")"
        token=$minted
      fi

      if ! [[ "$token" =~ ^[A-Za-z0-9_-]{10,}$ ]]; then
        msg_err "$(L MSG_WEB_1144)"
        return 1
      fi
      if [[ -z "$zone" ]]; then
        zone=$(read_input "$(L MSG_WEB_1145)")
        if ! [[ "$zone" =~ ^[a-fA-F0-9]{32}$ ]]; then
          msg_err "$(L MSG_WEB_1146)"
          return 1
        fi
      fi
      threshold=$(read_input "$(L MSG_WEB_1147)" "5.0")
      threshold=${threshold:-5.0}
      if ! [[ "$threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        msg_err "$(L MSG_WEB_1148)"
        return 1
      fi

      umask 077
      mkdir -p /etc/fusionbox
      [[ -f "$cf_conf" ]] && cp "$cf_conf" "$cf_conf.fb-bak-$(date +%s)" 2>/dev/null
      local cf_tmp
      cf_tmp=$(mktemp "${cf_conf}.XXXXXXXX") || return 1
      cat > "$cf_tmp" << CFCONF
# FusionBox Cloudflare 联动配置（含密钥，请勿外泄）
CF_API_TOKEN=$token
CF_ZONE_ID=$zone
# 负载自适应开盾阈值（1 分钟负载，默认 5.0）
LOAD_THRESHOLD=$threshold
CFCONF
      if [[ $? -ne 0 ]] || ! chmod 600 "$cf_tmp" || ! mv -T "$cf_tmp" "$cf_conf"; then
        rm -f "$cf_tmp"; return 1
      fi
      msg_ok "$(L MSG_WEB_1149 "$cf_conf")"
      _log_write "$(L MSG_WEB_1150 "$zone")"
      ;;
    2)
      if [[ ! -f "$cf_conf" ]] || ! grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        msg_warn "$(L MSG_WEB_1151)"
        return
      fi
      if ! confirm "$(L MSG_WEB_1152 "$ban_script")"; then
        return
      fi
      mkdir -p /usr/local/bin
      cat > "$ban_script" << 'CFBANEOF'
#!/bin/bash
# FusionBox Cloudflare IP 封禁/解封辅助脚本
# 用法: fusionbox-cf-ban ban|unban <ip>
# token 从 /etc/fusionbox/cloudflare.conf 读取，脚本不会打印密钥
set -u

CONF="/etc/fusionbox/cloudflare.conf"
API="https://api.cloudflare.com/client/v4"

[ -f "$CONF" ] || { echo "$(L MSG_WEB_1153 "$CONF")"; exit 1; }
# shellcheck source=/dev/null
. "$CONF"
: "${CF_API_TOKEN:?$(L MSG_WEB_0628)}"
: "${CF_ZONE_ID:?$(L MSG_WEB_0629)}"
command -v curl >/dev/null 2>&1 || { echo "$(L MSG_WEB_1154)"; exit 1; }

action="${1:-}"
ip="${2:-}"
if [ -z "$action" ] || [ -z "$ip" ]; then
  echo "$(L MSG_WEB_1155)"
  exit 1
fi
case "$ip" in
  *[!0-9a-fA-F:.]*) echo "$(L MSG_WEB_1156 "$ip")"; exit 1 ;;
esac

# 认证头写入 600 权限临时配置，避免 token 出现在进程命令行（ps 可见）
CURL_CFG=$(mktemp)
chmod 600 "$CURL_CFG"
trap 'rm -f "$CURL_CFG"' EXIT
printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$CF_API_TOKEN" > "$CURL_CFG"

cf() {
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -fsS --max-time 20 -X "$method" "$API$path" -K "$CURL_CFG" --data @"$data"
  else
    curl -fsS --max-time 20 -X "$method" "$API$path" -K "$CURL_CFG"
  fi
}

find_rule_id() {
  # 兼容紧凑与 pretty 两种 JSON 输出（冒号后可能带空格）
  cf GET "/zones/$CF_ZONE_ID/firewall/access_rules/rules?mode=block&configuration%5Bvalue%5D=$1&per_page=10" \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{32\}\)".*/\1/p' | head -1
}

case "$action" in
  ban)
    rid=$(find_rule_id "$ip")
    if [ -n "$rid" ]; then
      echo "$(L MSG_WEB_1157 "$ip" "$rid")"
      exit 0
    fi
    payload=$(mktemp)
    printf '{"mode":"block","configuration":{"target":"ip","value":"%s"},"notes":"FusionBox auto ban"}' "$ip" > "$payload"
    resp=$(cf POST "/zones/$CF_ZONE_ID/firewall/access_rules/rules" "$payload")
    rm -f "$payload"
    if echo "$resp" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true'; then
      echo "$(L MSG_WEB_1158 "$ip")"
    else
      echo "$(L MSG_WEB_1159 "$ip")"
      exit 1
    fi
    ;;
  unban)
    rid=$(find_rule_id "$ip")
    if [ -z "$rid" ]; then
      echo "$(L MSG_WEB_1160 "$ip")"
      exit 0
    fi
    resp=$(cf DELETE "/zones/$CF_ZONE_ID/firewall/access_rules/rules/$rid")
    if echo "$resp" | grep -Eq '"success"[[:space:]]*:[[:space:]]*true'; then
      echo "$(L MSG_WEB_1161 "$ip")"
    else
      echo "$(L MSG_WEB_1162 "$ip")"
      exit 1
    fi
    ;;
  *)
    echo "$(L MSG_WEB_1155)"
    exit 1
    ;;
esac
CFBANEOF
      chmod 755 "$ban_script"
      msg_ok "$(L MSG_WEB_1163 "$ban_script")"
      msg ""
      msg "$(L MSG_WEB_1164 "${F_BOLD}" "${F_RESET}")"
      msg "$(L MSG_WEB_1165)"
      msg "$(L MSG_WEB_1166)"
      msg "$(L MSG_WEB_1167)"
      _log_write "$(L MSG_WEB_1168 "$ban_script")"
      ;;
    *) return ;;
  esac
}

# 负载自适应开盾：安装/卸载/状态
_web_guard_cf_adaptive() {
  local g_script="/usr/local/bin/fusionbox-cf-guard"
  local g_cron="/etc/cron.d/fusionbox-cf-guard"
  local g_state="/var/lib/fusionbox/cf-guard.state"
  local cf_conf="/etc/fusionbox/cloudflare.conf"

  msg "$(L MSG_WEB_1169 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1170)"
  msg ""
  msg "$(L MSG_WEB_1171 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_1172 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_1173 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_WEB_0860 "${F_GREEN}" "${F_RESET}")"
  msg ""
  local ad_choice=""
  read -p "$(L MSG_WEB_1174)" ad_choice || return

  case "$ad_choice" in
    1)
      if [[ ! -f "$cf_conf" ]] || ! grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        msg_warn "$(L MSG_WEB_1175)"
      fi
      if ! confirm "$(L MSG_WEB_1176 "$g_script")"; then
        return
      fi
      mkdir -p /var/lib/fusionbox /usr/local/bin /etc/cron.d
      [[ -f "$g_script" ]] && cp "$g_script" "$g_script.fb-bak-$(date +%s)" 2>/dev/null

      cat > "$g_script" << 'CFGUARDEOF'
#!/bin/bash
# FusionBox Cloudflare 负载自适应开盾
# load1 > LOAD_THRESHOLD → security_level=under_attack；否则恢复初始安全级别
# 状态记录在 /var/lib/fusionbox/cf-guard.state，避免重复调用 API
set +x
set -o pipefail
CONF="/etc/fusionbox/cloudflare.conf"
API="https://api.cloudflare.com/client/v4"

[ -f "$CONF" ] && . "$CONF"
[[ "${CF_ZONE_ID:-}" =~ ^[a-fA-F0-9]{32}$ ]] || exit 1
[[ "${CF_API_TOKEN:-}" =~ ^[A-Za-z0-9_-]{10,}$ ]] || exit 1
CF_ZONE_ID=${CF_ZONE_ID,,}
STATE="/var/lib/fusionbox/cf-guard.${CF_ZONE_ID}.state"
umask 077
mkdir -p "$(dirname "$STATE")" || exit 1
exec 9>"${STATE}.lock"
flock -n 9 || exit 0
LOAD_THRESHOLD="${LOAD_THRESHOLD:-5.0}"

if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ZONE_ID:-}" ]; then
  echo "$(L MSG_WEB_1177 "$CONF")"
  exit 0
fi
command -v curl >/dev/null 2>&1 || { echo "$(L MSG_WEB_1154)"; exit 1; }

load1=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
load1="${load1:-0}"

want=""
if awk -v l="$load1" -v t="$LOAD_THRESHOLD" 'BEGIN { exit !(l > t) }' 2>/dev/null; then
  want="under_attack"
fi

last=""
[ -f "$STATE" ] && last=$(cat "$STATE" 2>/dev/null)
if [ -n "$want" ] && [ "$want" = "$last" ]; then
  exit 0
fi

# 认证头写入 600 权限临时配置，避免 token 出现在进程命令行（ps 可见）
CURL_CFG=$(mktemp)
chmod 600 "$CURL_CFG"
trap 'rm -f "$CURL_CFG"' EXIT
printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "$CF_API_TOKEN" > "$CURL_CFG"

command -v python3 >/dev/null || { echo "$(L MSG_WEB_1178)"; exit 1; }
atomic_state() {
  local staged
  staged=$(mktemp "${1}.XXXXXXXX") || return 1
  printf '%s\n' "$2" > "$staged" && mv -T "$staged" "$1" || { rm -f "$staged"; return 1; }
}
if [ ! -s "${STATE}.original" ]; then
  original=$(curl -fsS --max-time 20 -K "$CURL_CFG" "$API/zones/$CF_ZONE_ID/settings/security_level" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("success"); print(d["result"]["value"])') || exit 1
  case "$original" in off|essentially_off|low|medium|high|under_attack) ;; *) exit 1 ;; esac
  atomic_state "${STATE}.original" "$original" || exit 1
fi
[ -n "$want" ] || want=$(cat "${STATE}.original")
[ "$want" = "$last" ] && exit 0
resp=$(curl -fsS --max-time 20 -X PATCH "$API/zones/$CF_ZONE_ID/settings/security_level" \
  -K "$CURL_CFG" \
  --data "{\"value\":\"$want\"}") || exit 1

if printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(d.get("success") is not True)'; then
  atomic_state "$STATE" "$want" || exit 1
  echo "$(L MSG_WEB_1179 "$load1" "$want")"
else
  echo "$(L MSG_WEB_1180 "$load1")"
  exit 1
fi
CFGUARDEOF
      chmod 755 "$g_script"

      cat > "$g_cron" << 'CFCRONEOF'
# FusionBox 负载自适应开盾（由 fusionbox web guard 生成）
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/5 * * * * root /usr/local/bin/fusionbox-cf-guard >/dev/null 2>&1
CFCRONEOF
      if [[ ! -f "$g_script" || ! -f "$g_cron" ]]; then
        msg_err "$(L MSG_WEB_1181)"
        pause; return 1
      fi
      chmod 644 "$g_cron"

      msg_ok "$(L MSG_WEB_1182)"
      msg_info "$(L MSG_WEB_1183 "$cf_conf")"
      _log_write "$(L MSG_WEB_1184)"
      ;;
    2)
      if [[ ! -f "$g_script" && ! -f "$g_cron" ]]; then
        msg_info "$(L MSG_WEB_1185)"
        return
      fi
      if ! confirm "$(L MSG_WEB_1186)"; then
        return
      fi
      rm -f "$g_script" "$g_cron" || return 1
      msg_info "$(L MSG_WEB_1187)"
      msg_ok "$(L MSG_WEB_1188)"
      _log_write "$(L MSG_WEB_1189)"
      ;;
    3)
      [[ -f "$g_script" ]] && msg_ok "$(L MSG_WEB_1190 "$g_script")" || msg_info "$(L MSG_WEB_1191)"
      [[ -f "$g_cron" ]] && msg_ok "$(L MSG_WEB_1192 "$g_cron")" || msg_info "$(L MSG_WEB_1193)"
      if [[ -f "$cf_conf" ]] && grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        local th
        th=$(sed -n 's/^LOAD_THRESHOLD=//p' "$cf_conf" 2>/dev/null | tail -1)
        th=${th:-5.0}
        msg "$(L MSG_WEB_1194 "$(awk '{print $1}' /proc/loadavg 2>/dev/null)")"
        msg "$(L MSG_WEB_1195 "$th")"
        local status_zone
        status_zone=$(sed -n 's/^CF_ZONE_ID=//p' "$cf_conf" | tail -1)
        if [[ "$status_zone" =~ ^[a-fA-F0-9]{32}$ ]]; then
          g_state="/var/lib/fusionbox/cf-guard.${status_zone,,}.state"
          msg "$(L MSG_WEB_1196 "$(cat "$g_state" 2>/dev/null || echo "未记录")")"
        fi
      else
        msg_warn "$(L MSG_WEB_1197)"
      fi
      ;;
    *) return ;;
  esac
}

# ---- Help ----
web_help() {
  msg_title "$(L MSG_WEB_1198)"
  msg ""
  msg "$(L MSG_WEB_1199 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1200)"
  msg "$(L MSG_WEB_1201)"
  msg "$(L MSG_WEB_1202)"
  msg "$(L MSG_WEB_1203)"
  msg "$(L MSG_WEB_1204)"
  msg "$(L MSG_WEB_1205)"
  msg "$(L MSG_WEB_1206)"
  msg "$(L MSG_WEB_1207)"
  msg "$(L MSG_WEB_1208)"
  msg "$(L MSG_WEB_1209)"
  msg "$(L MSG_WEB_1210)"
  msg "$(L MSG_WEB_1211)"
  msg ""
  msg "$(L MSG_WEB_1212 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1213)"
  msg "$(L MSG_WEB_1214)"
  msg ""
  msg "$(L MSG_WEB_1215 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1216)"
  msg "$(L MSG_WEB_1217)"
  msg "$(L MSG_WEB_1218)"
  msg "$(L MSG_WEB_1219)"
  msg "$(L MSG_WEB_1220)"
  msg "$(L MSG_WEB_1221)"
  msg ""
  msg "$(L MSG_WEB_1222 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1223)"
  msg "$(L MSG_WEB_1224)"
  msg ""
  msg "$(L MSG_WEB_1225 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1226)"
  msg "$(L MSG_WEB_1227)"
  msg "$(L MSG_WEB_1228)"
  msg ""
  msg "$(L MSG_WEB_1229 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1230)"
  msg "$(L MSG_WEB_1231)"
  msg ""
  msg "$(L MSG_WEB_1232 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1233)"
  msg ""
  msg "$(L MSG_WEB_1234 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_WEB_1235)"
  msg ""
}

# ---- Interactive Menu ----
web_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_WEB_1236)"
    msg ""
    msg "$(L MSG_WEB_1237 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1238 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1239 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1240 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1241 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1242 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1243 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1244 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1245 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1246 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1247 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1248 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1249 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1250 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1251 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1252 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1253 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_WEB_1254 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_WEB_0806)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) web_install_lnmp ;;
      2) web_install_lamp ;;
      3) web_create_site ;;
      4) web_ssl ;;
      5) web_nginx; pause ;;
      6) web_php; pause ;;
      7) web_mysql; pause ;;
      8) web_firewall ;;
      9) web_optimize ;;
      10) web_deploy_app ;;
      11) web_reverse_proxy ;;
      12) web_stream_proxy ;;
      13) web_site_data ;;
      14) web_sites ;;
      15) web_site_del ;;
      16) web_site_alias ;;
      17) web_guard ;;
      0) break ;;
    esac
  done
}
