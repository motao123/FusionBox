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
    deploy|app)            web_deploy_app "$@" ;;
    proxy|rp)              web_reverse_proxy "$@" ;;
    stream|l4)             web_stream_proxy "$@" ;;
    sitedata|backup)       web_site_data "$@" ;;
    wordpress|wp)          web_wordpress "$@" ;;
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

# ---- LDNMP 应用部署 (Docker化) ----
web_deploy_app() {
  _require_root
  msg_title "LDNMP 应用部署"
  msg ""

  if ! command -v docker &>/dev/null; then
    msg_warn "Docker 未安装"
    if confirm "是否安装 Docker？"; then
      _load_module "panels"
      panels_docker_install
    else
      pause; return
    fi
  fi

  msg "  ${F_BOLD}选择要部署的应用:${F_RESET}"
  msg ""
  msg "  ${F_CYAN}[内容管理系统]${F_RESET}"
  msg "  ${F_GREEN} 1${F_RESET}) WordPress"
  msg "  ${F_GREEN} 2${F_RESET}) Typecho"
  msg "  ${F_GREEN} 3${F_RESET}) Halo (现代化博客)"
  msg "  ${F_GREEN} 4${F_RESET}) Discuz! Q"
  msg ""
  msg "  ${F_CYAN}[网盘与文件管理]${F_RESET}"
  msg "  ${F_GREEN} 5${F_RESET}) 可道云 (KodExplorer)"
  msg "  ${F_GREEN} 6${F_RESET}) Nextcloud"
  msg "  ${F_GREEN} 7${F_RESET}) Alist (多存储聚合)"
  msg ""
  msg "  ${F_CYAN}[媒体与影视]${F_RESET}"
  msg "  ${F_GREEN} 8${F_RESET}) 苹果 CMS"
  msg "  ${F_GREEN} 9${F_RESET}) Emby (媒体服务器)"
  msg "  ${F_GREEN}10${F_RESET}) Jellyfin (媒体服务器)"
  msg ""
  msg "  ${F_CYAN}[论坛与社区]${F_RESET}"
  msg "  ${F_GREEN}11${F_RESET}) Flarum"
  msg "  ${F_GREEN}12${F_RESET}) LinkStack (链接聚合)"
  msg ""
  msg "  ${F_CYAN}[工具与服务]${F_RESET}"
  msg "  ${F_GREEN}13${F_RESET}) Bitwarden (密码管理)"
  msg "  ${F_GREEN}14${F_RESET}) Uptime Kuma (监控面板)"
  msg "  ${F_GREEN}15${F_RESET}) IT-Tools (开发工具箱)"
  msg "  ${F_GREEN}16${F_RESET}) Memos (备忘录)"
  msg "  ${F_GREEN}17${F_RESET}) Vaultwarden (Bitwarden 轻量版)"
  msg ""
  msg "  ${F_GREEN} 0${F_RESET}) 返回"
  msg ""
  read -p "请选择 [0-17]: " app_choice

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
  local domain; domain=$(read_input "请输入域名（如 wp.example.com）" "localhost")
  local db_pass; db_pass=$(read_input "请输入 MySQL root 密码" "$(openssl rand -hex 12)")
  local wp_pass; wp_pass=$(read_input "请输入 WordPress 管理员密码" "$(openssl rand -hex 8)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "WordPress 已部署"
  msg "  访问: http://${domain}:8080"
  msg "  数据库密码: $db_pass"
  msg "  数据目录: $app_dir"
  _log_write "WordPress 已部署到 $app_dir"
  pause
}

# Typecho 一键部署
_deploy_typecho() {
  _require_root
  local app_dir="/opt/docker/typecho"
  local domain; domain=$(read_input "请输入域名" "localhost")
  local db_pass; db_pass=$(read_input "请输入数据库密码" "$(openssl rand -hex 12)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Typecho 已部署"
  msg "  访问: http://${domain}:8081"
  _log_write "Typecho 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Halo 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8090"
  _log_write "Halo 已部署"
  pause
}

# Discuz Q 一键部署
_deploy_discuz() {
  _require_root
  local app_dir="/opt/docker/discuz"
  local db_pass; db_pass=$(read_input "请输入数据库密码" "$(openssl rand -hex 12)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Discuz! Q 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8082"
  _log_write "Discuz Q 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "可道云已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8083"
  _log_write "可道云已部署"
  pause
}

# Nextcloud 一键部署
_deploy_nextcloud() {
  _require_root
  local app_dir="/opt/docker/nextcloud"
  local db_pass; db_pass=$(read_input "请输入数据库密码" "$(openssl rand -hex 12)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Nextcloud 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8084"
  _log_write "Nextcloud 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  sleep 3
  local admin_pass=$(docker logs alist 2>&1 | grep "password" | awk -F': ' '{print $NF}' | tail -1)
  msg_ok "Alist 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):5244"
  msg "  管理员: admin"
  msg "  密码: ${admin_pass:-查看 docker logs alist}"
  _log_write "Alist 已部署"
  pause
}

# 苹果 CMS 一键部署
_deploy_apple_cms() {
  _require_root
  local app_dir="/opt/docker/apple_cms"
  local db_pass; db_pass=$(read_input "请输入数据库密码" "$(openssl rand -hex 12)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "苹果 CMS 已部署 (需要手动下载源码)"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8085"
  _log_write "苹果 CMS 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Emby 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8096"
  msg "  媒体目录: $app_dir/media"
  _log_write "Emby 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Jellyfin 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8097"
  _log_write "Jellyfin 已部署"
  pause
}

# Flarum 一键部署
_deploy_flarum() {
  _require_root
  local app_dir="/opt/docker/flarum"
  local db_pass; db_pass=$(read_input "请输入数据库密码" "$(openssl rand -hex 12)")

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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Flarum 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8086"
  _log_write "Flarum 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "LinkStack 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8087"
  _log_write "LinkStack 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Bitwarden (Vaultwarden) 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8088"
  _log_write "Bitwarden 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Uptime Kuma 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):3001"
  _log_write "Uptime Kuma 已部署"
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

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "IT-Tools 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):8880"
  _log_write "IT-Tools 已部署"
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
    image: neosmemo/memos:latest
    container_name: memos
    restart: always
    ports:
      - "5230:5230"
    volumes:
      - ./data:/var/opt/memos
MEOF

  cd "$app_dir" && docker compose up -d 2>/dev/null
  msg_ok "Memos 已部署"
  msg "  访问: http://$(hostname -I | awk '{print $1}'):5230"
  _log_write "Memos 已部署"
  pause
}

# Vaultwarden 一键部署
_deploy_vaultwarden() {
  _deploy_bitwarden
}

# ---- 反向代理管理 ----
web_reverse_proxy() {
  _require_root
  msg_title "反向代理管理"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_err "Nginx 未安装"
    pause; return
  fi

  msg "  ${F_GREEN}1${F_RESET}) 添加 HTTP 反向代理"
  msg "  ${F_GREEN}2${F_RESET}) 添加 HTTPS 反向代理 (自动 SSL)"
  msg "  ${F_GREEN}3${F_RESET}) 添加负载均衡 (多后端)"
  msg "  ${F_GREEN}4${F_RESET}) 列出现有代理配置"
  msg "  ${F_GREEN}5${F_RESET}) 删除代理配置"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  read -p "请选择: " rp_choice

  case "$rp_choice" in
    1)
      local domain; domain=$(read_input "请输入域名")
      local backend; backend=$(read_input "请输入后端地址 (如 127.0.0.1:3000)")
      [[ -z "$domain" || -z "$backend" ]] && { msg_err "域名和后端不能为空"; pause; return; }

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
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "反向代理已配置: $domain → $backend"
      _log_write "反向代理已配置: $domain → $backend"
      ;;
    2)
      local domain; domain=$(read_input "请输入域名")
      local backend; backend=$(read_input "请输入后端地址")
      [[ -z "$domain" || -z "$backend" ]] && { msg_err "域名和后端不能为空"; pause; return; }

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
        msg_warn "Certbot 未安装，请手动申请 SSL 或运行: fusionbox web ssl $domain"
      fi
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "HTTPS 反向代理已配置: $domain → $backend"
      ;;
    3)
      local domain; domain=$(read_input "请输入域名")
      local upstream_name="upstream_${domain//./_}"
      msg "请输入后端地址（每行一个，空行结束）:"
      local backends=""
      local i=1
      while true; do
        read -p "  后端 $i: " be
        [[ -z "$be" ]] && break
        backends+="    server $be;\n"
        i=$((i+1))
      done
      [[ -z "$backends" ]] && { msg_err "至少需要一个后端"; pause; return; }

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
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "负载均衡已配置: $domain ($(($i-1)) 个后端)"
      _log_write "负载均衡已配置: $domain"
      ;;
    4)
      msg_info "现有代理配置:"
      for f in /etc/nginx/sites-available/*; do
        [[ -f "$f" ]] && msg "  $(basename "$f")"
      done
      ;;
    5)
      read -p "请输入要删除的域名: " domain
      if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
        rm -f "/etc/nginx/sites-available/$domain"
        rm -f "/etc/nginx/sites-enabled/$domain"
        nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
        msg_ok "已删除: $domain"
      else
        msg_err "配置不存在"
      fi
      ;;
  esac
  pause
}

# ---- Stream L4 代理 ----
web_stream_proxy() {
  _require_root
  msg_title "Stream L4 代理"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_err "Nginx 未安装"
    pause; return
  fi

  msg "  ${F_GREEN}1${F_RESET}) 添加 TCP 端口转发"
  msg "  ${F_GREEN}2${F_RESET}) 添加 UDP 端口转发"
  msg "  ${F_GREEN}3${F_RESET}) 添加 TCP+UDP 转发"
  msg "  ${F_GREEN}4${F_RESET}) 列出 stream 规则"
  msg "  ${F_GREEN}5${F_RESET}) 删除 stream 规则"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  read -p "请选择: " st_choice

  local stream_conf="/etc/nginx/stream.d/fusionbox-stream.conf"
  mkdir -p /etc/nginx/stream.d 2>/dev/null

  # Ensure stream block exists in nginx.conf
  if ! grep -q "stream {" /etc/nginx/nginx.conf 2>/dev/null; then
    echo -e "\nstream {\n    include /etc/nginx/stream.d/*.conf;\n}" >> /etc/nginx/nginx.conf
  fi

  case "$st_choice" in
    1)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址 (如 192.168.1.100:22)")
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "TCP 转发: 0.0.0.0:$listen_port → $target"
      _log_write "Stream TCP: $listen_port → $target"
      ;;
    2)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址")
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "UDP 转发: 0.0.0.0:$listen_port → $target"
      _log_write "Stream UDP: $listen_port → $target"
      ;;
    3)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址")
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
      msg_ok "TCP+UDP 转发: 0.0.0.0:$listen_port → $target"
      ;;
    4)
      if [[ -f "$stream_conf" ]]; then
        msg_info "Stream 规则:"
        nl -ba "$stream_conf"
      else
        msg "暂无 stream 规则"
      fi
      ;;
    5)
      if [[ -f "$stream_conf" ]]; then
        nl -ba "$stream_conf"
        read -p "输入要删除的行号: " del_line
        if [[ -n "$del_line" ]]; then
          sed -i "${del_line}d" "$stream_conf"
          nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
          msg_ok "已删除"
        fi
      fi
      ;;
  esac
  pause
}

# ---- 站点数据管理 ----
web_site_data() {
  _require_root
  msg_title "站点数据管理"
  msg ""

  msg "  ${F_BOLD}网站数据目录:${F_RESET}"
  du -h --max-depth=1 /var/www/ 2>/dev/null | sort -rh | head -10

  msg ""
  msg "  ${F_BOLD}Docker 数据:${F_RESET}"
  du -h --max-depth=1 /opt/docker/ 2>/dev/null | sort -rh | head -10

  msg ""
  msg "  ${F_GREEN}1${F_RESET}) 备份所有站点数据"
  msg "  ${F_GREEN}2${F_RESET}) 恢复站点数据"
  msg "  ${F_GREEN}3${F_RESET}) 配置定时远程备份"
  msg "  ${F_GREEN}4${F_RESET}) 清理旧备份"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  read -p "请选择: " sd_choice

  case "$sd_choice" in
    1)
      local backup_dir="/root/site_backups"
      mkdir -p "$backup_dir"
      local date_str=$(date '+%Y%m%d_%H%M%S')
      local backup_file="$backup_dir/site_data_$date_str.tar.gz"
      msg_info "正在备份..."
      tar czf "$backup_file" /var/www/ /opt/docker/ /etc/nginx/ 2>/dev/null
      if [[ -f "$backup_file" ]]; then
        local size=$(du -h "$backup_file" | cut -f1)
        msg_ok "备份已创建: $backup_file ($size)"
        _log_write "站点数据已备份: $backup_file"
      fi
      ;;
    2)
      local backup_dir="/root/site_backups"
      local backups=()
      for f in "$backup_dir"/site_data_*.tar.gz; do
        [[ -f "$f" ]] && backups+=("$f")
      done
      if [[ ${#backups[@]} -eq 0 ]]; then
        msg_warn "无可用备份"
      else
        local i=1
        for f in "${backups[@]}"; do
          msg "  $i) $(basename "$f") ($(du -h "$f" | cut -f1))"
          i=$((i+1))
        done
        read -p "选择要恢复的备份: " choice
        local idx=$((choice-1))
        if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
          if confirm "确认恢复？这将覆盖现有数据！"; then
            tar xzf "${backups[$idx]}" -C /
            msg_ok "恢复完成"
          fi
        fi
      fi
      ;;
    3)
      msg "  ${F_BOLD}远程备份配置${F_RESET}"
      msg "  1) Rclone (S3/WebDAV/FTP)"
      msg "  2) SCP (SSH 远程)"
      msg "  3) rsync"
      read -p "请选择: " remote_type
      case "$remote_type" in
        1)
          if ! command -v rclone &>/dev/null; then
            msg_info "正在安装 rclone..."
            curl -fsSL https://rclone.org/install.sh 2>/dev/null | bash
          fi
          msg "  请先配置 rclone: fusionbox panels rclone"
          read -p "rclone 远程名称: " rclone_remote
          read -p "备份保留天数: " keep_days
          keep_days=${keep_days:-7}
          # Add cron job
          local cron_cmd="0 3 * * * tar czf /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz /var/www/ /opt/docker/ && rclone copy /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz ${rclone_remote}:backups/ && find /tmp -name 'site_backup_*.tar.gz' -mtime +${keep_days} -delete"
          (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
          msg_ok "定时远程备份已配置 (每天 3:00, 保留 ${keep_days} 天)"
          ;;
        2)
          read -p "远程主机 (user@host): " ssh_host
          read -p "远程目录: " ssh_dir
          local cron_cmd="0 3 * * * tar czf /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz /var/www/ /opt/docker/ && scp /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz ${ssh_host}:${ssh_dir}/"
          (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
          msg_ok "SCP 定时备份已配置"
          ;;
        3)
          read -p "远程主机 (user@host): " ssh_host
          read -p "远程目录: " ssh_dir
          local cron_cmd="0 3 * * * rsync -az /var/www/ ${ssh_host}:${ssh_dir}/www/ && rsync -az /opt/docker/ ${ssh_host}:${ssh_dir}/docker/"
          (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
          msg_ok "rsync 定时同步已配置"
          ;;
      esac
      _log_write "定时远程备份已配置"
      ;;
    4)
      read -p "保留最近几天的备份？(默认 7): " keep_days
      keep_days=${keep_days:-7}
      find /root/site_backups/ -name "site_data_*.tar.gz" -mtime "+$keep_days" -delete 2>/dev/null
      msg_ok "已清理 ${keep_days} 天前的备份"
      ;;
  esac
  pause
}

# ---- WordPress 快速部署 (快捷) ----
web_wordpress() {
  _deploy_wordpress
}

# ---- Help ----
web_help() {
  msg_title "网站部署 帮助"
  msg ""
  msg "  ${F_BOLD}[基础环境]${F_RESET}"
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
  msg "  ${F_BOLD}[应用部署]${F_RESET}"
  msg "  fusionbox web deploy            LDNMP 应用一键部署"
  msg "  fusionbox web wordpress         快速部署 WordPress"
  msg ""
  msg "  ${F_BOLD}[反向代理]${F_RESET}"
  msg "  fusionbox web proxy             HTTP/HTTPS 反向代理"
  msg "  fusionbox web stream            TCP/UDP L4 端口转发"
  msg ""
  msg "  ${F_BOLD}[数据管理]${F_RESET}"
  msg "  fusionbox web sitedata          站点数据备份/恢复/远程备份"
  msg ""
}

# ---- Interactive Menu ----
web_menu() {
  while true; do
    clear
    _print_banner
    msg_title "网站部署"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 安装 LNMP"
    msg "  ${F_GREEN} 2${F_RESET}) 安装 LAMP"
    msg "  ${F_GREEN} 3${F_RESET}) 创建网站"
    msg "  ${F_GREEN} 4${F_RESET}) SSL 证书"
    msg "  ${F_GREEN} 5${F_RESET}) Nginx 管理"
    msg "  ${F_GREEN} 6${F_RESET}) PHP 管理"
    msg "  ${F_GREEN} 7${F_RESET}) MySQL 管理"
    msg "  ${F_GREEN} 8${F_RESET}) Web 防火墙 / 安全"
    msg "  ${F_GREEN} 9${F_RESET}) 网站优化"
    msg "  ${F_GREEN}10${F_RESET}) LDNMP 应用部署 (WordPress/Typecho/Halo/...)"
    msg "  ${F_GREEN}11${F_RESET}) 反向代理 (HTTP/HTTPS/负载均衡)"
    msg "  ${F_GREEN}12${F_RESET}) Stream L4 代理 (TCP/UDP 端口转发)"
    msg "  ${F_GREEN}13${F_RESET}) 站点数据管理"
    msg "  ${F_GREEN} 0${F_RESET}) 返回主菜单"
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
      10) web_deploy_app ;;
      11) web_reverse_proxy ;;
      12) web_stream_proxy ;;
      13) web_site_data ;;
      0) break ;;
    esac
  done
}
