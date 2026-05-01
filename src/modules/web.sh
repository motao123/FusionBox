# FusionBox Web/LNMP Deployment Module
# LNMP, website management, SSL

web_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    lnmp|install-lnmp)     web_install_lnmp "$@" ;;
    lamp|install-lamp)     web_install_lamp "$@" ;;
    site|create)           web_create_site "$@" ;;
    ssl|cert)              web_ssl "$@" ;;
    nginx|ng)              web_nginx "$@" ;;
    php)                   web_php "$@" ;;
    mysql|db)              web_mysql "$@" ;;
    firewall|waf)          web_firewall "$@" ;;
    optimize|perf)         web_optimize "$@" ;;
    menu|main)             web_menu ;;
    help|h)                web_help ;;
    *)                     web_menu ;;
  esac
}

# ---- Install LNMP ----
web_install_lnmp() {
  _require_root
  msg_title "$(tr WEB_LNMP "Install LNMP (Linux + Nginx + MySQL + PHP)")"
  msg ""

  if ! confirm "$(tr MSG_CONFIRM "This will install Nginx, MySQL, and PHP. Continue?")"; then
    return
  fi

  # Check existing
  if command -v nginx &>/dev/null; then
    msg_warn "Nginx already installed: $(nginx -v 2>&1)"
  fi

  # Install Nginx
  msg_info "Installing Nginx..."
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
    msg_ok "Nginx installed: $(nginx -v 2>&1)"
  fi

  # Install MySQL/MariaDB
  msg_info "Installing MariaDB..."
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
    msg_ok "MariaDB installed"
    msg_info "Run 'mysql_secure_installation' to secure your DB"
  fi

  # Install PHP
  msg_info "Installing PHP 8.2..."
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
    _install_pkg "${php_pkgs[@]}" 2>/dev/null || msg_warn "Some PHP packages may not have installed"

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
    msg_ok "PHP installed: ${php_ver:-PHP 8.2}"
  fi

  # Install Redis
  if confirm "$(tr MSG_CONFIRM "Install Redis for caching?")"; then
    _install_pkg redis
    case "$F_PKG_MGR" in
      apt|yum) systemctl enable --now redis 2>/dev/null ;;
      apk) rc-update add redis default 2>/dev/null; rc-service redis start 2>/dev/null ;;
    esac
    msg_ok "Redis installed"
  fi

  msg ""
  msg_ok "$(tr WEB_LNMP "LNMP stack installed successfully!")"
  msg ""
  msg "  ${F_BOLD}Web root:${F_RESET} /var/www/html"
  msg "  ${F_BOLD}Nginx:${F_RESET} $(nginx -v 2>&1)"
  php -v 2>/dev/null | head -1 | xargs -I{} msg "  ${F_BOLD}PHP:${F_RESET} {}"
  msg "  ${F_BOLD}MariaDB:${F_RESET} $(mariadbd --version 2>/dev/null | head -1 || mysql --version 2>/dev/null)"
  msg "  ${F_BOLD}PHP-FPM:${F_RESET} $(pgrep php-fpm | wc -l) processes"

  _log_write "LNMP stack installed"
  pause
}

# ---- Install LAMP ----
web_install_lamp() {
  _require_root
  msg_info "$(tr WEB_LAMP "LAMP install uses Apache instead of Nginx")"

  if ! confirm "$(tr MSG_CONFIRM "Continue with LAMP installation?")"; then
    return
  fi

  _install_pkg apache2 2>/dev/null || _install_pkg httpd 2>/dev/null || msg_err "Apache install failed"

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
  msg_info "Apache is running alongside Nginx on alt port or as replacement"
  pause
}

# ---- Create Website ----
web_create_site() {
  _require_root
  msg_title "$(tr WEB_SITE "Create Website")"
  msg ""

  local domain; domain=$(read_input "$(tr MSG_INPUT "Domain name (e.g., example.com)")")
  [[ -z "$domain" ]] && domain="localhost"

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
<h1>Welcome to $domain</h1>
<p class="info">This site is powered by FusionBox</p>
<p class="info">Created on $(date)</p>
</body>
</html>
HEOF
  chmod -R 755 "$web_root"

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
  nginx -t 2>/dev/null && {
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
    msg_ok "Website created: http://$domain"
    msg_info "Root: $web_root"
    _log_write "Website created: $domain"
  } || {
    msg_err "Nginx config test failed, check $nginx_conf"
  }

  pause
}

# ---- SSL Certificate ----
web_ssl() {
  _require_root
  local domain="${1:-}"

  msg_title "$(tr WEB_SSL "SSL Certificate")"
  msg ""

  if ! command -v certbot &>/dev/null; then
    msg_info "Installing Certbot..."
    case "$F_PKG_MGR" in
      apt)
        _install_pkg certbot python3-certbot-nginx
        ;;
      yum)
        _install_pkg epel-release certbot python3-certbot-nginx
        ;;
      apk)
        _install_pkg certbot certbot-nginx
        ;;
    esac
  fi

  if command -v certbot &>/dev/null; then
    if [[ -z "$domain" ]]; then
      read -p "$(tr MSG_INPUT "Domain for SSL"): " domain
    fi
    if [[ -n "$domain" ]]; then
      msg_info "Obtaining SSL certificate for $domain..."
      certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null || \
        certbot --nginx -d "$domain" 2>/dev/null || \
        msg_err "SSL certificate failed. Check domain DNS."
      _log_write "SSL obtained for $domain"
    else
      msg_info "No domain specified. Certbot installed for manual use."
    fi
  fi

  msg ""
  msg "  ${F_BOLD}Existing certificates:${F_RESET}"
  certbot certificates 2>/dev/null || msg "    None"
  pause
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
        pgrep -x nginx &>/dev/null && msg_ok "Nginx: running" || msg_info "Nginx: stopped"
      else
        msg_err "Nginx not installed"
      fi
      ;;
    reload)
      nginx -s reload 2>/dev/null && msg_ok "Nginx reloaded" || msg_err "Reload failed"
      ;;
    config)
      local config_dir="/etc/nginx"
      msg_info "Available configs in $config_dir:"
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
    msg_info "Installed PHP modules:"
    php -m 2>/dev/null | sort | while read -r mod; do
      msg "  $mod"
    done

    msg ""
    msg "  1) Update PHP config (memory/upload limits)"
    read -p "Select: " php_choice
    if [[ "$php_choice" == "1" ]]; then
      local php_ini; php_ini=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
      if [[ -f "$php_ini" ]]; then
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$php_ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$php_ini"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$php_ini"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
        systemctl reload php*-fpm 2>/dev/null || nginx -s reload 2>/dev/null || true
        msg_ok "PHP limits updated"
      fi
    fi
  else
    msg_err "PHP not installed. Use 'fusionbox web lnmp' to install."
  fi
  pause
}

# ---- MySQL ----
web_mysql() {
  _require_root
  if command -v mysql &>/dev/null; then
    msg_title "MySQL Management"
    msg ""
    msg "  1) Create database"
    msg "  2) Create database user"
    msg "  3) Show databases"
    msg "  4) Run mysql_secure_installation"
    msg "  0) Back"
    read -p "Select: " db_choice

    case "$db_choice" in
      1)
        read -p "Database name: " db_name
        mysql -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4;" 2>/dev/null && \
          msg_ok "Database '$db_name' created" || msg_err "Create failed"
        ;;
      2)
        read -p "Username: " db_user
        read -p "Password: " db_pass
        read -p "Database: " db_name
        mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass'; GRANT ALL ON \`$db_name\`.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && \
          msg_ok "User '$db_user' granted access to '$db_name'" || msg_err "Create failed"
        ;;
      3)
        mysql -e "SHOW DATABASES;" 2>/dev/null
        ;;
      4)
        mysql_secure_installation
        ;;
    esac
  else
    msg_err "MySQL/MariaDB not installed"
  fi
  pause
}

# ---- Web Firewall ----
web_firewall() {
  _require_root
  _install_pkg libnginx-mod-http-headers-more-filter 2>/dev/null || true

  msg_info "Enabling web security headers..."
  local nginx_conf="/etc/nginx/nginx.conf"
  if [[ -f "$nginx_conf" ]]; then
    # Add security headers in http block if not present
    grep -q "X-Content-Type-Options" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    add_header X-Content-Type-Options nosniff;\n    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-XSS-Protection "1; mode=block";' "$nginx_conf" 2>/dev/null && \
      msg_ok "Security headers added" || msg_warn "Could not add headers"
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  fi

  # Rate limiting
  read -p "Enable rate limiting? (limit 10 req/s per IP) [Y/n]: " rate_ans
  if [[ ! "$rate_ans" =~ ^[Nn] ]]; then
    grep -q "limit_req_zone" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    limit_req_zone $binary_remote_addr zone=fusionbox:10m rate=10r/s;' "$nginx_conf" 2>/dev/null
    msg_ok "Rate limiting configured (10 req/s)"
  fi

  nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true
  _log_write "Web firewall configured"
  pause
}

# ---- Optimize ----
web_optimize() {
  _require_root
  msg_title "$(tr WEB_OPTIMIZE "Website Optimization")"

  if command -v nginx &>/dev/null; then
    msg_info "Optimizing Nginx..."
    local nginx_conf="/etc/nginx/nginx.conf"

    # Optimize worker processes
    local cpu_count; cpu_count=$(nproc --all)
    sed -i "s/worker_processes .*/worker_processes $cpu_count;/" "$nginx_conf" 2>/dev/null

    # Optimize worker connections
    sed -i "s/worker_connections .*/worker_connections 10240;/" "$nginx_conf" 2>/dev/null

    # Add gzip settings
    grep -q "gzip_vary" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    gzip on;\n    gzip_vary on;\n    gzip_min_length 1024;\n    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;' "$nginx_conf" 2>/dev/null

    # Enable sendfile and tcp_nopush
    sed -i 's/# tcp_nopush/tcp_nopush/' "$nginx_conf" 2>/dev/null
    sed -i 's/# tcp_nodelay/tcp_nodelay/' "$nginx_conf" 2>/dev/null

    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null
    msg_ok "Nginx optimized: $cpu_count workers, gzip enabled"
    _log_write "Nginx optimized"
  fi

  # PHP-FPM optimization
  if command -v php-fpm8.2 &>/dev/null || command -v php-fpm &>/dev/null; then
    msg_info "Optimizing PHP-FPM..."
    local php_conf
    for conf in /etc/php/*/fpm/pool.d/www.conf; do
      if [[ -f "$conf" ]]; then
        sed -i 's/pm.max_children = .*/pm.max_children = 50/' "$conf"
        sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' "$conf"
        sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' "$conf"
        sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 15/' "$conf"
      fi
    done
    systemctl reload php*-fpm 2>/dev/null || true
    msg_ok "PHP-FPM optimized"
  fi

  pause
}

# ---- Help ----
web_help() {
  msg_title "$(tr MOD_WEB "Web/LNMP Deployment") Help"
  msg ""
  msg "  fusionbox web lnmp              $(tr WEB_LNMP "Install LNMP stack")"
  msg "  fusionbox web lamp              $(tr WEB_LAMP "Install LAMP stack")"
  msg "  fusionbox web site              $(tr WEB_SITE "Create a website")"
  msg "  fusionbox web ssl [domain]      $(tr WEB_SSL "Get SSL certificate")"
  msg "  fusionbox web nginx             $(tr MSG_INFO "Nginx management")"
  msg "  fusionbox web php               $(tr MSG_INFO "PHP management")"
  msg "  fusionbox web mysql             $(tr MSG_INFO "MySQL management")"
  msg "  fusionbox web firewall          $(tr WEB_FIREWALL "Configure web firewall")"
  msg "  fusionbox web optimize          $(tr WEB_OPTIMIZE "Optimize web performance")"
  msg ""
}

# ---- Interactive Menu ----
web_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(tr MOD_WEB "Web/LNMP Deployment")"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) $(tr WEB_LNMP "Install LNMP")"
    msg "  ${F_GREEN}2${F_RESET}) $(tr WEB_LAMP "Install LAMP")"
    msg "  ${F_GREEN}3${F_RESET}) $(tr WEB_SITE "Create Website")"
    msg "  ${F_GREEN}4${F_RESET}) $(tr WEB_SSL "SSL Certificate")"
    msg "  ${F_GREEN}5${F_RESET}) Nginx Management"
    msg "  ${F_GREEN}6${F_RESET}) PHP Management"
    msg "  ${F_GREEN}7${F_RESET}) MySQL Management"
    msg "  ${F_GREEN}8${F_RESET}) Web Firewall / Security"
    msg "  ${F_GREEN}9${F_RESET}) $(tr WEB_OPTIMIZE "Optimize")"
    msg "  ${F_GREEN}0${F_RESET}) $(tr MSG_EXIT "Back to Main Menu")"
    msg ""
    read -p "$(tr MSG_SELECT "Select") [0-9]: " choice
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
      0) break ;;
    esac
  done
}
