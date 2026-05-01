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
  msg_title "安装 LNMP (Linux + Nginx + MySQL + PHP)"
  msg ""

  if ! confirm "将安装 Nginx、MySQL 和 PHP，确认继续？"; then
    return
  fi

  # Check existing
  if command -v nginx &>/dev/null; then
    msg_warn "Nginx 已安装: $(nginx -v 2>&1)"
  fi

  # Install Nginx
  msg_info "正在安装 Nginx..."
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
    msg_ok "Nginx 安装完成: $(nginx -v 2>&1)"
  fi

  # Install MySQL/MariaDB
  msg_info "正在安装 MariaDB..."
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
    msg_ok "MariaDB 安装完成"
    msg_info "请运行 'mysql_secure_installation' 来加固数据库"
  fi

  # Install PHP
  msg_info "正在安装 PHP 8.2..."
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
    _install_pkg "${php_pkgs[@]}" 2>/dev/null || msg_warn "部分 PHP 包可能未安装成功"

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
    msg_ok "PHP 安装完成: ${php_ver:-PHP 8.2}"
  fi

  # Install Redis
  if confirm "是否安装 Redis 缓存？"; then
    _install_pkg redis
    case "$F_PKG_MGR" in
      apt|yum) systemctl enable --now redis 2>/dev/null ;;
      apk) rc-update add redis default 2>/dev/null; rc-service redis start 2>/dev/null ;;
    esac
    msg_ok "Redis 安装完成"
  fi

  msg ""
  msg_ok "LNMP 环境安装完成！"
  msg ""
  msg "  ${F_BOLD}网站根目录:${F_RESET} /var/www/html"
  msg "  ${F_BOLD}Nginx:${F_RESET} $(nginx -v 2>&1)"
  php -v 2>/dev/null | head -1 | xargs -I{} msg "  ${F_BOLD}PHP:${F_RESET} {}"
  msg "  ${F_BOLD}MariaDB:${F_RESET} $(mariadbd --version 2>/dev/null | head -1 || mysql --version 2>/dev/null)"
  msg "  ${F_BOLD}PHP-FPM:${F_RESET} $(pgrep php-fpm | wc -l) 个进程"

  _log_write "LNMP 环境已安装"
  pause
}

# ---- Install LAMP ----
web_install_lamp() {
  _require_root
  msg_info "LAMP 使用 Apache 替代 Nginx"

  if ! confirm "确认继续安装 LAMP？"; then
    return
  fi

  _install_pkg apache2 2>/dev/null || _install_pkg httpd 2>/dev/null || msg_err "Apache 安装失败"

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
  msg_info "Apache 已与 Nginx 并行运行（备用端口或替代方案）"
  pause
}

# ---- Create Website ----
web_create_site() {
  _require_root
  msg_title "创建网站"
  msg ""

  local domain; domain=$(read_input "请输入域名（如 example.com）")
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
<h1>欢迎访问 $domain</h1>
<p class="info">本站由 FusionBox 搭建</p>
<p class="info">创建于 $(date)</p>
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
    msg_ok "网站已创建: http://$domain"
    msg_info "根目录: $web_root"
    _log_write "网站已创建: $domain"
  } || {
    msg_err "Nginx 配置测试失败，请检查 $nginx_conf"
  }

  pause
}

# ---- SSL Certificate ----
web_ssl() {
  _require_root
  local domain="${1:-}"

  msg_title "SSL 证书"
  msg ""

  if ! command -v certbot &>/dev/null; then
    msg_info "正在安装 Certbot..."
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
      read -p "请输入 SSL 域名: " domain
    fi
    if [[ -n "$domain" ]]; then
      msg_info "正在申请 $domain 的 SSL 证书..."
      certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null || \
        certbot --nginx -d "$domain" 2>/dev/null || \
        msg_err "SSL 证书申请失败，请检查域名 DNS。"
      _log_write "SSL 证书已获取: $domain"
    else
      msg_info "未指定域名，Certbot 已安装可供手动使用。"
    fi
  fi

  msg ""
  msg "  ${F_BOLD}已有证书:${F_RESET}"
  certbot certificates 2>/dev/null || msg "    无"
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
        pgrep -x nginx &>/dev/null && msg_ok "Nginx: 运行中" || msg_info "Nginx: 已停止"
      else
        msg_err "Nginx 未安装"
      fi
      ;;
    reload)
      nginx -s reload 2>/dev/null && msg_ok "Nginx 已重载" || msg_err "重载失败"
      ;;
    config)
      local config_dir="/etc/nginx"
      msg_info "$config_dir 中的可用配置:"
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
    msg_info "已安装的 PHP 模块:"
    php -m 2>/dev/null | sort | while read -r mod; do
      msg "  $mod"
    done

    msg ""
    msg "  1) 更新 PHP 配置（内存/上传限制）"
    read -p "请选择: " php_choice
    if [[ "$php_choice" == "1" ]]; then
      local php_ini; php_ini=$(php --ini 2>/dev/null | grep "Loaded Configuration" | awk '{print $NF}')
      if [[ -f "$php_ini" ]]; then
        sed -i 's/memory_limit = .*/memory_limit = 256M/' "$php_ini"
        sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$php_ini"
        sed -i 's/post_max_size = .*/post_max_size = 64M/' "$php_ini"
        sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
        systemctl reload php*-fpm 2>/dev/null || nginx -s reload 2>/dev/null || true
        msg_ok "PHP 限制已更新"
      fi
    fi
  else
    msg_err "PHP 未安装，请使用 'fusionbox web lnmp' 安装。"
  fi
  pause
}

# ---- MySQL ----
web_mysql() {
  _require_root
  if command -v mysql &>/dev/null; then
    msg_title "MySQL 管理"
    msg ""
    msg "  1) 创建数据库"
    msg "  2) 创建数据库用户"
    msg "  3) 显示数据库"
    msg "  4) 运行 mysql_secure_installation"
    msg "  0) 返回"
    read -p "请选择: " db_choice

    case "$db_choice" in
      1)
        read -p "数据库名: " db_name
        mysql -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4;" 2>/dev/null && \
          msg_ok "数据库 '$db_name' 已创建" || msg_err "创建失败"
        ;;
      2)
        read -p "用户名: " db_user
        read -p "密码: " db_pass
        read -p "数据库: " db_name
        mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass'; GRANT ALL ON \`$db_name\`.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && \
          msg_ok "用户 '$db_user' 已授权访问 '$db_name'" || msg_err "创建失败"
        ;;
      3)
        mysql -e "SHOW DATABASES;" 2>/dev/null
        ;;
      4)
        mysql_secure_installation
        ;;
    esac
  else
    msg_err "MySQL/MariaDB 未安装"
  fi
  pause
}

# ---- Web Firewall ----
web_firewall() {
  _require_root
  _install_pkg libnginx-mod-http-headers-more-filter 2>/dev/null || true

  msg_info "正在启用 Web 安全头..."
  local nginx_conf="/etc/nginx/nginx.conf"
  if [[ -f "$nginx_conf" ]]; then
    # Add security headers in http block if not present
    grep -q "X-Content-Type-Options" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    add_header X-Content-Type-Options nosniff;\n    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-XSS-Protection "1; mode=block";' "$nginx_conf" 2>/dev/null && \
      msg_ok "安全头已添加" || msg_warn "无法添加安全头"
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  fi

  # Rate limiting
  read -p "是否启用速率限制？（每 IP 限制 10 请求/秒）[Y/n]: " rate_ans
  if [[ ! "$rate_ans" =~ ^[Nn] ]]; then
    grep -q "limit_req_zone" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    limit_req_zone $binary_remote_addr zone=fusionbox:10m rate=10r/s;' "$nginx_conf" 2>/dev/null
    msg_ok "速率限制已配置 (10 请求/秒)"
  fi

  nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || true
  _log_write "Web 防火墙已配置"
  pause
}

# ---- Optimize ----
web_optimize() {
  _require_root
  msg_title "网站优化"

  if command -v nginx &>/dev/null; then
    msg_info "正在优化 Nginx..."
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
    msg_ok "Nginx 已优化: $cpu_count 个 worker，gzip 已启用"
    _log_write "Nginx 优化完成"
  fi

  # PHP-FPM optimization
  if command -v php-fpm8.2 &>/dev/null || command -v php-fpm &>/dev/null; then
    msg_info "正在优化 PHP-FPM..."
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
    msg_ok "PHP-FPM 优化完成"
  fi

  pause
}

# ---- Help ----
web_help() {
  msg_title "网站部署 帮助"
  msg ""
  msg "  fusionbox web lnmp              安装 LNMP 环境"
  msg "  fusionbox web lamp              安装 LAMP 环境"
  msg "  fusionbox web site              创建网站"
  msg "  fusionbox web ssl [domain]      申请 SSL 证书"
  msg "  fusionbox web nginx             Nginx 管理"
  msg "  fusionbox web php               PHP 管理"
  msg "  fusionbox web mysql             MySQL 管理"
  msg "  fusionbox web firewall          配置 Web 防火墙"
  msg "  fusionbox web optimize          优化 Web 性能"
  msg ""
}

# ---- Interactive Menu ----
web_menu() {
  while true; do
    clear
    _print_banner
    msg_title "网站部署"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 安装 LNMP"
    msg "  ${F_GREEN}2${F_RESET}) 安装 LAMP"
    msg "  ${F_GREEN}3${F_RESET}) 创建网站"
    msg "  ${F_GREEN}4${F_RESET}) SSL 证书"
    msg "  ${F_GREEN}5${F_RESET}) Nginx 管理"
    msg "  ${F_GREEN}6${F_RESET}) PHP 管理"
    msg "  ${F_GREEN}7${F_RESET}) MySQL 管理"
    msg "  ${F_GREEN}8${F_RESET}) Web 防火墙 / 安全"
    msg "  ${F_GREEN}9${F_RESET}) 网站优化"
    msg "  ${F_GREEN}0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-9]: " choice
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
