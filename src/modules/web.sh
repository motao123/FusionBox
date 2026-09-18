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
    sites|site-list)       web_sites "$@" ;;
    site-del|sitedel)      web_site_del "$@" ;;
    site-alias|alias)      web_site_alias "$@" ;;
    guard|cc)              web_guard "$@" ;;
    wordpress|wp)          web_wordpress "$@" ;;
    menu|main)             web_menu ;;
    help|h)                web_help ;;
    *)                     web_menu ;;
  esac
}

# ---- 工具函数 ----
_web_validate_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]
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
  if ! _web_validate_domain "$domain"; then
    msg_err "域名格式不合法: $domain"
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
<h1>欢迎访问 $domain</h1>
<p class="info">本站由 FusionBox 搭建</p>
<p class="info">创建于 $(date)</p>
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
    msg_err "nginx 配置校验失败，已删除 $nginx_conf"
    pause; return 1
  fi
  systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  msg_ok "网站已创建: http://$domain"
  msg_info "根目录: $web_root"
  _log_write "网站已创建: $domain"

  pause
}

# ---- SSL Certificate ----
web_ssl() {
  _require_root
  local arg="${1:-}"

  # 子命令直达: fusionbox web ssl status|renew|auto
  case "$arg" in
    status|st)         web_ssl_status; return $? ;;
    renew|now|r)       web_ssl_renew; return $? ;;
    auto|autorenew)    web_ssl_autorenew; return $? ;;
  esac

  msg_title "SSL 证书"
  msg ""

  local domain="$arg"

  # 无域名参数时显示子菜单（选项 1 保持原有签发流程）
  if [[ -z "$domain" ]]; then
    msg "  ${F_GREEN}1${F_RESET}) 申请/签发 SSL 证书"
    msg "  ${F_GREEN}2${F_RESET}) 查看证书状态与到期监控"
    msg "  ${F_GREEN}3${F_RESET}) 立即续期全部证书"
    msg "  ${F_GREEN}4${F_RESET}) 自动续期管理 (cron)"
    msg "  ${F_GREEN}0${F_RESET}) 返回"
    msg ""
    local ssl_choice=""
    read -p "请选择 [0-4]: " ssl_choice || return
    case "$ssl_choice" in
      1) ;;   # 继续下方签发流程
      2) web_ssl_status; return ;;
      3) web_ssl_renew; return ;;
      4) web_ssl_autorenew; return ;;
      *) return ;;
    esac
  fi

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
      if certbot --nginx -d "$domain" --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null || \
         certbot --nginx -d "$domain" 2>/dev/null; then
        msg_ok "SSL 证书申请完成: $domain"
        msg_info "已支持自动续期：fusionbox web ssl auto"
        _log_write "SSL 证书已获取: $domain"
      else
        msg_err "SSL 证书申请失败，请检查域名 DNS。"
        msg_info "详细日志: /var/log/letsencrypt/letsencrypt.log"
      fi
    else
      msg_info "未指定域名，Certbot 已安装可供手动使用。"
    fi
  else
    msg_err "Certbot 安装失败，请检查系统软件源。"
  fi

  msg ""
  msg "  ${F_BOLD}已有证书:${F_RESET}"
  certbot certificates 2>/dev/null || msg "    无"
  pause
}

# ---- SSL 到期监控与自动续期 ----

# 读取证书信息，输出 "到期时间|剩余天数"；无法解析时返回 1
_web_cert_info() {
  local cert="$1"
  [[ -f "$cert" ]] || return 1
  command -v openssl &>/dev/null || return 1
  local enddate end_ts now_ts
  enddate=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
  [[ -z "$enddate" ]] && return 1
  end_ts=$(date -d "$enddate" +%s 2>/dev/null) || return 1
  now_ts=$(date +%s)
  local delta=$((end_ts - now_ts))
  # Round negative partial days down so recently expired certificates stay negative.
  (( delta < 0 )) && delta=$((delta - 86399))
  printf '%s|%s' "$enddate" "$(( delta / 86400 ))"
}

# 仅返回证书剩余天数
_web_cert_days() {
  local info
  info=$(_web_cert_info "$1" 2>/dev/null) || return 1
  echo "${info##*|}"
}

# 证书状态与到期监控
web_ssl_status() {
  _require_root
  msg_title "SSL 证书状态与到期监控"
  msg ""

  command -v openssl &>/dev/null || _install_pkg openssl 2>/dev/null || true

  # 是否有可用证书
  local found=0 c
  for c in /etc/letsencrypt/live/*/fullchain.pem; do
    [[ -f "$c" ]] && { found=1; break; }
  done

  local total=0 ok=0 warning=0 expired=0
  if [[ $found -eq 0 ]]; then
    msg_info "未找到证书：/etc/letsencrypt/live 下没有 fullchain.pem"
  else
    msg "  ${F_BOLD}域名 | 到期时间 | 剩余天数${F_RESET}"
    msg "  ------------------------------------------------------------"
    local d name cert info enddate days color tail
    for d in /etc/letsencrypt/live/*/; do
      [[ -d "$d" ]] || continue
      cert="${d}fullchain.pem"
      [[ -f "$cert" ]] || continue
      name=$(basename "$d")

      info=$(_web_cert_info "$cert")
      if [[ -z "$info" ]]; then
        # openssl 缺失或日期无法解析
        enddate="未知"; days="?"; color="$F_YELLOW"; tail=""
      else
        enddate="${info%%|*}"; days="${info##*|}"
        color="$F_GREEN"; tail=""
      fi

      total=$((total + 1))
      if [[ "$days" =~ ^-?[0-9]+$ ]]; then
        if (( days < 0 )); then
          color="$F_RED"; tail="  ${F_RED}(已过期)${F_RESET}"; expired=$((expired + 1))
        elif (( days < 15 )); then
          color="$F_YELLOW"; tail="  ${F_YELLOW}(即将过期)${F_RESET}"; warning=$((warning + 1))
        else
          ok=$((ok + 1))
        fi
      else
        warning=$((warning + 1))
      fi
      msg "  ${F_BOLD}${name}${F_RESET} | ${enddate} | ${color}${days} 天${F_RESET}${tail}"
    done
    msg ""
    msg "  共 ${total} 个证书：${F_GREEN}${ok} 正常${F_RESET} / ${F_YELLOW}${warning} 需关注${F_RESET} / ${F_RED}${expired} 已过期${F_RESET}"
  fi

  # certbot 自身信息作为补充
  if command -v certbot &>/dev/null; then
    msg ""
    msg "  ${F_BOLD}certbot certificates（补充）:${F_RESET}"
    local cbo line
    cbo=$(certbot certificates 2>/dev/null | grep -E "Certificate Name|Domains|Expiry Date")
    if [[ -n "$cbo" ]]; then
      while IFS= read -r line; do
        msg "  ${line#"${line%%[![:space:]]*}"}"
      done <<< "$cbo"
    else
      msg "    无"
    fi
  elif [[ $found -eq 0 ]]; then
    msg_warn "未安装 certbot，暂不能续期（可运行 fusionbox web ssl 安装）"
  fi

  pause
}

# 立即续期全部证书
web_ssl_renew() {
  _require_root
  msg_title "证书续期 (certbot renew)"
  msg ""

  if ! command -v certbot &>/dev/null; then
    msg_err "未安装 Certbot，请先运行: fusionbox web ssl"
    pause; return 1
  fi

  if ! confirm "将执行 certbot renew 续期全部证书并重载 Nginx，确认继续？"; then
    return
  fi

  local renew_log
  renew_log=$(mktemp /tmp/fusionbox-certbot-renew.XXXXXXXX.log) || return 1
  msg_info "正在续期（以下为 certbot 真实输出）..."
  msg ""
  certbot renew 2>&1 | tee "$renew_log"
  local rc=${PIPESTATUS[0]}
  msg ""

  if [[ $rc -eq 0 ]]; then
    if ! { systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null; }; then
      msg_err "续期流程完成，但 Nginx 重载失败"
      return 1
    fi
    msg_ok "续期流程完成，Nginx 已重载"
    _log_write "certbot renew 执行成功"
  else
    msg_err "续期失败（退出码 $rc）"
    msg_info "日志路径: /var/log/letsencrypt/letsencrypt.log"
    msg_info "本次输出已保存: $renew_log"
    _log_write "certbot renew 失败 rc=$rc"
  fi
  pause
  return "$rc"
}

# 自动续期（cron）安装/查看/卸载
_web_ssl_existing_schedule() {
  local unit
  for unit in certbot.timer snap.certbot.renew.timer certbot-renew.timer; do
    if systemctl is-enabled "$unit" >/dev/null 2>&1 || systemctl is-active "$unit" >/dev/null 2>&1; then
      printf '%s\n' "$unit"; return 0
    fi
  done
  if grep -rEl '^[^#]*certbot[[:space:]].*renew' /etc/cron.d /etc/cron.daily /etc/crontab 2>/dev/null; then return 0; fi
  crontab -l 2>/dev/null | grep -E '^[^#]*certbot[[:space:]].*renew'
}

web_ssl_autorenew() {
  _require_root
  local cron_file="/etc/cron.d/fusionbox-cert-renew"

  msg_title "证书自动续期管理"
  msg ""

  if ! command -v certbot &>/dev/null; then
    msg_warn "未检测到 certbot，请先安装并签发证书: fusionbox web ssl"
    msg_info "安装完成后可再次运行: fusionbox web ssl auto"
    pause; return 1
  fi

  msg "  ${F_GREEN}1${F_RESET}) 安装/更新自动续期"
  msg "  ${F_GREEN}2${F_RESET}) 查看自动续期状态"
  msg "  ${F_GREEN}3${F_RESET}) 卸载自动续期"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  local ar_choice=""
  read -p "请选择 [0-3]: " ar_choice || return

  case "$ar_choice" in
    1)
      local existing
      if existing=$(_web_ssl_existing_schedule); then
        msg_info "已有续期任务，保留现有调度: $existing"
        return 0
      fi
      if ! confirm "将写入 $cron_file（每天自动续期），确认继续？"; then
        return
      fi
      # 随机分钟：避免大批机器在同一分钟集中请求 CA
      local rnd_min=$((RANDOM % 60))
      mkdir -p /etc/cron.d || return 1
      [[ ! -L "$cron_file" ]] || return 1
      local cron_tmp
      cron_tmp=$(mktemp "${cron_file}.XXXXXXXX") || return 1
      if ! cat > "$cron_tmp" << AEOF
# FusionBox 证书自动续期（由 fusionbox web ssl auto 生成）
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# 每天 03:00-03:59 之间随机分钟执行，避免多机同时请求 CA
$rnd_min 3 * * * root certbot renew --quiet --deploy-hook "systemctl reload nginx"
AEOF
      then
        rm -f "$cron_tmp"
        msg_err "写入 $cron_file 失败，请检查目录权限"
        pause; return 1
      fi
      chmod 644 "$cron_tmp" && mv -T "$cron_tmp" "$cron_file" || { rm -f "$cron_tmp"; return 1; }
      msg_ok "自动续期已配置: 每天 03:$(printf '%02d' "$rnd_min") 执行"
      msg_info "任务内容: certbot renew --quiet --deploy-hook \"systemctl reload nginx\""
      if ! command -v cron &>/dev/null && ! command -v crond &>/dev/null; then
        msg_warn "未检测到 cron/crond 服务，定时任务可能不会执行（请安装 cron）"
      fi
      _log_write "证书自动续期已配置 (min=$rnd_min)"
      ;;
    2)
      _web_ssl_existing_schedule || msg_warn "未发现已启用的系统续期任务"
      if [[ -f "$cron_file" ]]; then
        msg_ok "自动续期已启用: $cron_file"
        msg ""
        while IFS= read -r line; do
          msg "  $line"
        done < "$cron_file"
      else
        msg_info "未配置自动续期，可选择 1 安装"
      fi
      ;;
    3)
      if [[ ! -f "$cron_file" ]]; then
        msg_info "未找到 $cron_file，无需卸载"
      else
        if ! confirm "确认卸载证书自动续期（删除 $cron_file）？"; then
          return
        fi
        cp "$cron_file" "$cron_file.fb-bak-$(date +%s)" 2>/dev/null
        rm -f "$cron_file"
        msg_ok "自动续期已卸载"
        _log_write "证书自动续期已卸载"
      fi
      ;;
    *) return ;;
  esac
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
        read -r -p "数据库名: " db_name
        [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "数据库名仅允许字母数字下划线"; return 1; }
        printf 'CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4;\n' "$db_name" | mysql 2>/dev/null && \
          msg_ok "数据库 '$db_name' 已创建" || msg_err "创建失败"
        ;;
      2)
        read -r -p "用户名: " db_user
        read -r -p "密码: " db_pass   # -r 必须保留：不带 -r 的 read 会吞掉密码中的反斜杠
        read -r -p "数据库: " db_name
        [[ "$db_user" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "用户名仅允许字母数字下划线"; return 1; }
        [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || { msg_err "数据库名仅允许字母数字下划线"; return 1; }
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
  local conf_bak=""
  if [[ -f "$nginx_conf" ]]; then
    conf_bak="$nginx_conf.fb-bak-$(date +%s)"
    cp "$nginx_conf" "$conf_bak"
    # Add security headers in http block if not present
    if grep -q "X-Content-Type-Options" "$nginx_conf" 2>/dev/null; then
      msg_info "安全头已存在，跳过"
    elif sed -i '/http {/a\    add_header X-Content-Type-Options nosniff;\n    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-XSS-Protection "1; mode=block";' "$nginx_conf" 2>/dev/null; then
      msg_ok "安全头已添加"
    else
      msg_warn "无法添加安全头"
    fi
    if ! nginx -t 2>/dev/null; then
      cp "$conf_bak" "$nginx_conf"
      msg_err "nginx 配置校验失败，已回滚"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null || true
    cp "$nginx_conf" "$conf_bak"
  fi

  # Rate limiting
  read -p "是否启用速率限制？（每 IP 限制 10 请求/秒）[Y/n]: " rate_ans
  if [[ ! "$rate_ans" =~ ^[Nn] ]]; then
    grep -q "limit_req_zone" "$nginx_conf" 2>/dev/null || \
      sed -i '/http {/a\    limit_req_zone $binary_remote_addr zone=fusionbox:10m rate=10r/s;' "$nginx_conf" 2>/dev/null
    if ! nginx -t 2>/dev/null; then
      [[ -n "$conf_bak" ]] && cp "$conf_bak" "$nginx_conf"
      msg_err "nginx 配置校验失败，已回滚"
      pause; return 1
    fi
    nginx -s reload 2>/dev/null || true
    msg_ok "速率限制已配置 (10 请求/秒)"
  fi
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
    local conf_bak="$nginx_conf.fb-bak-$(date +%s)"
    cp "$nginx_conf" "$conf_bak" 2>/dev/null

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

    if ! nginx -t 2>/dev/null; then
      cp "$conf_bak" "$nginx_conf" 2>/dev/null
      msg_err "nginx 配置校验失败，已回滚"
      pause; return 1
    fi
    nginx -s reload 2>/dev/null || true
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
  read -p "请选择 [0-17]: " app_choice || return   # stdin 关闭时退出

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
  if ! _web_validate_domain "$domain"; then
    msg_err "域名格式不合法: $domain"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  if ! _web_validate_domain "$domain"; then
    msg_err "域名格式不合法: $domain"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
  chmod 600 "$app_dir/docker-compose.yml"

  cd "$app_dir" || return 1
  if ! docker compose up -d 2>/dev/null; then
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
    msg_err "部署失败，请执行 docker compose logs 查看"
    pause; return 1
  fi
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
      if ! _web_validate_domain "$domain"; then
        msg_err "域名格式不合法: $domain"
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
        msg_err "nginx 配置校验失败，已删除 $domain 配置"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
      msg_ok "反向代理已配置: $domain → $backend"
      _log_write "反向代理已配置: $domain → $backend"
      ;;
    2)
      local domain; domain=$(read_input "请输入域名")
      local backend; backend=$(read_input "请输入后端地址")
      [[ -z "$domain" || -z "$backend" ]] && { msg_err "域名和后端不能为空"; pause; return; }
      if ! _web_validate_domain "$domain"; then
        msg_err "域名格式不合法: $domain"
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
        msg_warn "Certbot 未安装，请手动申请 SSL 或运行: fusionbox web ssl $domain"
      fi
      if ! nginx -t 2>/dev/null; then
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        msg_err "nginx 配置校验失败，已删除 $domain 配置"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
      msg_ok "HTTPS 反向代理已配置: $domain → $backend"
      ;;
    3)
      local domain; domain=$(read_input "请输入域名")
      if ! _web_validate_domain "$domain"; then
        msg_err "域名格式不合法: $domain"
        pause; return 1
      fi
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
      if ! nginx -t 2>/dev/null; then
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        msg_err "nginx 配置校验失败，已删除 $domain 配置"
        pause; return 1
      fi
      systemctl reload nginx 2>/dev/null
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
      if ! _web_validate_domain "$domain"; then
        msg_err "域名格式不合法: $domain"
        pause; return 1
      fi
      if [[ -f "/etc/nginx/sites-available/$domain" ]]; then
        if ! confirm "确认删除反向代理站点 $domain？"; then
          pause; return
        fi
        local del_bak; del_bak=$(mktemp)
        cp "/etc/nginx/sites-available/$domain" "$del_bak"
        rm -f "/etc/nginx/sites-available/$domain" "/etc/nginx/sites-enabled/$domain"
        if ! nginx -t 2>/dev/null; then
          cp "$del_bak" "/etc/nginx/sites-available/$domain"
          rm -f "$del_bak"
          msg_err "nginx 配置校验失败，已回滚"
          pause; return 1
        fi
        rm -f "$del_bak"
        systemctl reload nginx 2>/dev/null
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

  # stream 块只能放在 nginx 主配置层；Ubuntu/Debian 的 nginx 默认不带 stream 模块，
  # 必须先确保模块存在（libnginx-mod-stream），否则追加的 stream{} 会让 nginx 起不来。
  # 注意 --with-stream=dynamic 表示动态模块（可能未加载），不能当作已支持
  if [[ "$st_choice" =~ ^[1-3]$ ]]; then
    if ls /etc/nginx/modules-enabled/*stream* >/dev/null 2>&1 \
       || ls /usr/lib/nginx/modules/ngx_stream_module.so >/dev/null 2>&1 \
       || nginx -V 2>&1 | tr ' ' '\n' | grep -qx -- '--with-stream'; then
      : # 模块已就绪（动态已装或静态编译）
    else
      msg_info "正在安装 nginx stream 模块 (libnginx-mod-stream)..."
      _install_pkg libnginx-mod-stream 2>/dev/null || _install_pkg nginx-mod-stream 2>/dev/null || {
        msg_err "无法安装 stream 模块，L4 转发不可用"
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
      msg_err "追加 stream 块后 nginx 配置校验失败，已还原 nginx.conf"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null
  fi

  case "$st_choice" in
    1)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址 (如 192.168.1.100:22)")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "nginx 配置校验失败，已回滚"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
      msg_ok "TCP 转发: 0.0.0.0:$listen_port → $target"
      _log_write "Stream TCP: $listen_port → $target"
      ;;
    2)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "nginx 配置校验失败，已回滚"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
      msg_ok "UDP 转发: 0.0.0.0:$listen_port → $target"
      _log_write "Stream UDP: $listen_port → $target"
      ;;
    3)
      local listen_port; listen_port=$(read_input "监听端口")
      local target; target=$(read_input "目标地址")
      local st_bak; st_bak=$(mktemp)
      cp "$stream_conf" "$st_bak" 2>/dev/null
      echo "server { listen $listen_port; proxy_pass $target; }" >> "$stream_conf"
      echo "server { listen $listen_port udp; proxy_pass $target; }" >> "$stream_conf"
      if ! nginx -t 2>/dev/null; then
        cp "$st_bak" "$stream_conf" 2>/dev/null; rm -f "$st_bak"
        msg_err "nginx 配置校验失败，已回滚"
        pause; return 1
      fi
      rm -f "$st_bak"
      systemctl reload nginx 2>/dev/null
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
        local total_lines; total_lines=$(wc -l < "$stream_conf")
        if [[ ! "$del_line" =~ ^[0-9]+$ ]] || [[ "$del_line" -lt 1 || "$del_line" -gt "$total_lines" ]]; then
          msg_err "行号不合法 (1-$total_lines)"
          pause; return 1
        fi
        if ! confirm "确认删除第 $del_line 行？"; then
          pause; return
        fi
        local st_bak; st_bak=$(mktemp)
        cp "$stream_conf" "$st_bak"
        sed -i "${del_line}d" "$stream_conf"
        if ! nginx -t 2>/dev/null; then
          cp "$st_bak" "$stream_conf"; rm -f "$st_bak"
          msg_err "nginx 配置校验失败，已回滚"
          pause; return 1
        fi
        rm -f "$st_bak"
        systemctl reload nginx 2>/dev/null
        msg_ok "已删除"
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
      msg_warn "请先停止写入服务；文件备份不是数据库快照，链接与特殊文件将被拒绝。"
      python3 "$FUSION_SRC/lib/archive.py" create web "$backup_file" || return 1
      msg_ok "备份已创建: $backup_file"
      _log_write "站点数据已备份: $backup_file"
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
        read -r -p "选择要恢复的备份: " choice
        [[ "$choice" =~ ^[1-9][0-9]{0,5}$ ]] || return 1
        local idx=$((choice-1))
        if [[ $idx -ge 0 && $idx -lt ${#backups[@]} ]]; then
          if confirm "确认恢复？这将覆盖现有数据！"; then
            python3 "$FUSION_SRC/lib/archive.py" restore web "${backups[$idx]}" || return 1
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
            local rc_inst; rc_inst=$(mktemp)
            if _download "https://rclone.org/install.sh" "$rc_inst"; then
              bash "$rc_inst" || _install_pkg rclone
            else
              _install_pkg rclone
            fi
            rm -f "$rc_inst"
          fi
          msg "  请先配置 rclone: fusionbox panels rclone"
          read -p "rclone 远程名称: " rclone_remote
          if ! [[ "$rclone_remote" =~ ^[A-Za-z0-9_@.:/-]+$ ]]; then
            msg_err "远程名称包含非法字符"
            pause; return 1
          fi
          read -p "备份保留天数: " keep_days
          keep_days=${keep_days:-7}
          if ! [[ "$keep_days" =~ ^[0-9]+$ ]]; then
            msg_err "保留天数必须为数字"
            pause; return 1
          fi
          # Add cron job
          local cron_cmd="0 3 * * * tar czf /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz /var/www/ /opt/docker/ && rclone copy /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz \"${rclone_remote}:backups/\" && find /tmp -name 'site_backup_*.tar.gz' -mtime +${keep_days} -delete"
          (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
          msg_ok "定时远程备份已配置 (每天 3:00, 保留 ${keep_days} 天)"
          ;;
        2)
          read -p "远程主机 (user@host): " ssh_host
          read -p "远程目录: " ssh_dir
          if ! [[ "$ssh_host" =~ ^[A-Za-z0-9_@.:/-]+$ ]]; then
            msg_err "远程主机包含非法字符"
            pause; return 1
          fi
          if [[ -n "$ssh_dir" ]] && ! [[ "$ssh_dir" =~ ^[A-Za-z0-9_@.:/-]+$ ]]; then
            msg_err "远程目录包含非法字符"
            pause; return 1
          fi
          local cron_cmd="0 3 * * * tar czf /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz /var/www/ /opt/docker/ && scp /tmp/site_backup_\$(date +\%Y\%m\%d).tar.gz \"${ssh_host}:${ssh_dir}/\""
          (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
          msg_ok "SCP 定时备份已配置"
          ;;
        3)
          read -p "远程主机 (user@host): " ssh_host
          read -p "远程目录: " ssh_dir
          if ! [[ "$ssh_host" =~ ^[A-Za-z0-9_@.:/-]+$ ]]; then
            msg_err "远程主机包含非法字符"
            pause; return 1
          fi
          if [[ -n "$ssh_dir" ]] && ! [[ "$ssh_dir" =~ ^[A-Za-z0-9_@.:/-]+$ ]]; then
            msg_err "远程目录包含非法字符"
            pause; return 1
          fi
          local cron_cmd="0 3 * * * rsync -az /var/www/ \"${ssh_host}:${ssh_dir}/www/\" && rsync -az /opt/docker/ \"${ssh_host}:${ssh_dir}/docker/\""
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
  msg_title "站点清单"
  msg ""

  if ! command -v nginx &>/dev/null; then
    msg_warn "Nginx 未安装，无法读取站点配置（fusionbox web lnmp 可安装）"
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
    msg_info "未发现已配置站点（/etc/nginx/sites-enabled 与 /etc/nginx/conf.d 为空）"
    pause; return
  fi

  msg "  ${F_BOLD}域名 | 端口 | 类型 | 根目录/后端 | 证书剩余 | 配置文件${F_RESET}"
  msg "  ----------------------------------------------------------------------------"

  local total=0
  local domains=()
  while IFS='|' read -r conf name port root proxy cert; do
    [[ -z "$name$port$root$proxy" ]] && continue
    total=$((total + 1))

    # 类型：反代 > PHP > 静态
    local type="静态"
    if [[ -n "$proxy" ]]; then
      type="反代"
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
          cert_info="${F_RED}已过期${F_RESET}"
        elif (( days < 15 )); then
          cert_info="${F_YELLOW}${days} 天${F_RESET}"
        else
          cert_info="${F_GREEN}${days} 天${F_RESET}"
        fi
      else
        cert_info="未知"
      fi
    fi

    msg "  ${F_BOLD}${name}${F_RESET} | ${port:--} | $type | $target | $cert_info | $conf"

    local primary="${name%% *}"
    [[ -n "$primary" ]] && domains+=("$primary")
  done < "$parsed"
  rm -f "$parsed"

  msg ""
  msg "  共 $total 个站点"

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
        msg "  ${F_BOLD}站点目录占用:${F_RESET}"
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
  msg_title "删除站点"
  msg ""

  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    domain=$(read_input "请输入要删除的域名")
  fi
  if ! _web_validate_domain "$domain"; then
    msg_err "域名格式不合法: $domain"
    pause; return 1
  fi

  local conf_avail="/etc/nginx/sites-available/$domain"
  local conf_enabled="/etc/nginx/sites-enabled/$domain"
  local conf_d="/etc/nginx/conf.d/$domain.conf"

  if [[ ! -e "$conf_avail" && ! -L "$conf_avail" && \
        ! -e "$conf_enabled" && ! -L "$conf_enabled" && \
        ! -e "$conf_d" && ! -L "$conf_d" ]]; then
    msg_err "未找到 $domain 的站点配置"
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

  if ! confirm "确认删除站点 $domain ？（配置已备份到 $bak_dir）"; then
    return
  fi

  local del_root=0
  if [[ -d "/var/www/$domain" ]]; then
    if confirm "是否同时删除网站目录 /var/www/$domain ？（默认否，删除后不可恢复）"; then
      del_root=1
    fi
  fi

  local original expected=0
  for original in "$conf_enabled" "$conf_avail" "$conf_d"; do
    [[ -e "$original" || -L "$original" ]] && expected=$((expected+1))
  done
  [[ ${#bak_pairs[@]} -eq $expected ]] || { msg_err "配置备份不完整，取消删除"; return 1; }
  rm -f "$conf_enabled" "$conf_avail" "$conf_d" || return 1

  if ! nginx -t 2>/dev/null; then
    # 回滚配置（含软链：-L 兼容目标暂时不存在的情况）
    local pair src dst
    for pair in "${bak_pairs[@]}"; do
      src="${pair%%|*}"; dst="${pair##*|}"
      [[ -e "$dst" || -L "$dst" ]] && cp -a "$dst" "$src" 2>/dev/null
    done
    msg_err "nginx 配置校验失败，已回滚站点配置（备份: $bak_dir）"
    pause; return 1
  fi

  systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  msg_ok "站点已删除: $domain"
  msg_info "配置备份: $bak_dir"

  if [[ $del_root -eq 1 ]]; then
    rm -rf "/var/www/$domain"
    msg_ok "网站目录已删除: /var/www/$domain"
  fi

  # 证书需单独清理
  if [[ -d "/etc/letsencrypt/live/$domain" ]]; then
    msg ""
    msg_info "该域名的证书仍在 /etc/letsencrypt/live/$domain"
    if confirm "是否同时删除证书 (certbot delete --cert-name $domain)？"; then
      if command -v certbot &>/dev/null; then
        certbot delete --cert-name "$domain" --non-interactive 2>/dev/null && \
          msg_ok "证书已删除: $domain" || msg_err "证书删除失败，请手动执行 certbot delete --cert-name $domain"
      else
        msg_err "certbot 未安装，请手动清理 /etc/letsencrypt/live/$domain"
      fi
    else
      msg_info "如需清理请手动执行: certbot delete --cert-name $domain"
    fi
  fi

  _log_write "站点已删除: $domain (备份: $bak_dir)"
  pause
}

# ---- 关联多域名（server_name 别名）----
web_site_alias() {
  _require_root
  msg_title "关联多域名 (server_name 别名)"
  msg ""

  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    domain=$(read_input "请输入主域名（已配置的站点）")
  fi
  if ! _web_validate_domain "$domain"; then
    msg_err "域名格式不合法: $domain"
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
    msg_err "未找到 $domain 的站点配置，请先用 fusionbox web site 创建"
    pause; return 1
  fi
  # 软链场景：改写目标文件，避免破坏软链
  conf_real=$(readlink -f "$conf" 2>/dev/null || echo "$conf")

  local alias_domain="${2:-}"
  if [[ -z "$alias_domain" ]]; then
    alias_domain=$(read_input "请输入要关联的别名域名（如 www.$domain）")
  fi
  if ! _web_validate_domain "$alias_domain"; then
    msg_err "别名域名格式不合法: $alias_domain"
    pause; return 1
  fi
  if [[ "$alias_domain" == "$domain" ]]; then
    msg_err "别名域名不能与主域名相同"
    pause; return 1
  fi

  local already=0
  if grep -qE "^[[:space:]]*server_name[^;]*[[:space:]]${alias_domain}([[:space:]]|;)" "$conf_real" 2>/dev/null; then
    already=1
    msg_info "配置中已包含别名 $alias_domain，将跳过修改"
  fi

  # 备份
  local ts; ts=$(date +%Y%m%d%H%M%S)
  local bak_dir="/etc/fusionbox/site-bak-$ts"
  mkdir -p "$bak_dir"
  local conf_bak="$bak_dir/$(basename "$conf_real")"
  cp -a "$conf_real" "$conf_bak" 2>/dev/null || { msg_err "备份失败，取消修改"; return 1; }

  if [[ $already -eq 0 ]]; then
    if ! confirm "将把 $alias_domain 追加到 $domain 的 server_name，确认继续？"; then
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
      msg_err "未在 $conf_real 中找到 server_name $domain，未做修改"
      pause; return 1
    fi
    cat "$tmp" > "$conf_real"
    rm -f "$tmp"

    if ! nginx -t 2>/dev/null; then
      cp -a "$conf_bak" "$conf_real" 2>/dev/null
      msg_err "nginx 配置校验失败，已回滚 $conf_real"
      pause; return 1
    fi
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
    msg_ok "已关联别名: $domain + $alias_domain"
    msg_info "配置备份: $bak_dir"
  fi

  # 多域名证书
  if command -v certbot &>/dev/null; then
    if confirm "是否为 $domain 和 $alias_domain 申请/更新证书？"; then
      certbot --nginx -d "$domain" -d "$alias_domain" --expand --non-interactive --agree-tos --email admin@"$domain" 2>/dev/null || \
        certbot --nginx -d "$domain" -d "$alias_domain" --expand 2>/dev/null || \
        msg_err "证书签发失败，请检查别名域名 DNS 解析"
      systemctl reload nginx 2>/dev/null || true
    else
      msg_info "可稍后手动执行: certbot --nginx -d $domain -d $alias_domain"
    fi
  else
    msg_warn "Certbot 未安装，可运行 fusionbox web ssl 安装后签发多域名证书"
  fi

  _log_write "站点别名已关联: $domain -> $alias_domain"
  pause
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
    msg_title "防 CC 与 Cloudflare 联动"
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) 安装 nginx 防 CC (fail2ban)"
    msg "  ${F_GREEN}2${F_RESET}) 卸载 nginx 防 CC"
    msg "  ${F_GREEN}3${F_RESET}) 查看封禁状态"
    msg "  ${F_GREEN}4${F_RESET}) Cloudflare 联动配置"
    msg "  ${F_GREEN}5${F_RESET}) 负载自适应开盾 (安装/卸载/状态)"
    msg "  ${F_GREEN}0${F_RESET}) 返回"
    msg ""
    local g_choice=""
    read -p "请选择 [0-5]: " g_choice || return
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
  msg_info "原理: fail2ban 统计 nginx access.log 中同一 IP 的 4xx 请求，超阈值自动封禁"
  msg ""

  if ! confirm "将安装/配置 fail2ban 防 CC 规则，确认继续？"; then
    return
  fi

  if ! command -v fail2ban-client &>/dev/null; then
    msg_info "正在安装 fail2ban..."
    _install_pkg fail2ban || { msg_err "fail2ban 安装失败"; return 1; }
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
    msg_warn "未发现 /var/log/nginx/access.log，请确认 Nginx 已启用访问日志"
  fi

  if ! systemctl restart fail2ban 2>/dev/null; then
    msg_err "fail2ban 重启失败，请检查: systemctl status fail2ban"
    return 1
  fi

  if fail2ban-client status fusionbox-nginx-cc >/dev/null 2>&1; then
    msg_ok "nginx 防 CC 已启用: jail=fusionbox-nginx-cc (30 次/60 秒 → 封禁 3600 秒)"
    fail2ban-client status fusionbox-nginx-cc 2>/dev/null | sed 's/^/  /'
    _log_write "nginx 防 CC 已安装 (fail2ban jail: fusionbox-nginx-cc)"
  else
    msg_err "jail 未生效，请检查日志: /var/log/fail2ban.log"
    msg_info "可用 'fail2ban-client status' 排查 filter 语法"
    return 1
  fi
}

# 卸载 fail2ban 防 CC
_web_guard_cc_uninstall() {
  local filter="/etc/fail2ban/filter.d/fusionbox-nginx-cc.conf"
  local jail="/etc/fail2ban/jail.d/fusionbox-nginx-cc.local"

  if ! command -v fail2ban-client &>/dev/null; then
    msg_info "fail2ban 未安装，无需卸载"
    return
  fi

  if ! confirm "将删除 fusionbox 防 CC 规则并重启 fail2ban，确认继续？"; then
    return
  fi

  # 先解除该 jail 已封禁的 IP，避免残留 iptables 规则
  local banned ip
  banned=$(fail2ban-client status fusionbox-nginx-cc 2>/dev/null | sed -n 's/.*Banned IP list:[[:space:]]*//p')
  if [[ -n "$banned" ]]; then
    for ip in $banned; do
      fail2ban-client set fusionbox-nginx-cc unbanip "$ip" >/dev/null 2>&1 || true
    done
    msg_info "已解除封禁 IP: $banned"
  fi

  local removed=0
  if [[ -f "$filter" ]]; then
    rm -f "$filter"; removed=1; msg_ok "已删除: $filter"
  fi
  if [[ -f "$jail" ]]; then
    rm -f "$jail"; removed=1; msg_ok "已删除: $jail"
  fi
  [[ $removed -eq 0 ]] && msg_info "未发现 fusionbox 防 CC 规则文件"

  systemctl restart fail2ban 2>/dev/null || systemctl reload fail2ban 2>/dev/null || true
  msg_ok "nginx 防 CC 已卸载"
  _log_write "nginx 防 CC 已卸载"
}

# 查看 fail2ban jail 与封禁 IP
_web_guard_cc_status() {
  if ! command -v fail2ban-client &>/dev/null; then
    msg_warn "fail2ban 未安装（本菜单选项 1 可安装）"
    return
  fi
  if ! fail2ban-client status >/dev/null 2>&1; then
    msg_err "fail2ban 未运行"
    systemctl status fail2ban --no-pager 2>/dev/null | head -5 | sed 's/^/  /'
    return
  fi

  msg "  ${F_BOLD}fail2ban 总览:${F_RESET}"
  fail2ban-client status 2>/dev/null | sed 's/^/  /'

  local jails j
  jails=$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p' | tr ',' ' ')
  if [[ -z "${jails// /}" ]]; then
    msg_info "当前无活动 jail"
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

  msg "  ${F_BOLD}Cloudflare 联动配置${F_RESET}"
  msg ""
  if [[ -f "$cf_conf" ]]; then
    local zid
    zid=$(sed -n 's/^CF_ZONE_ID=//p' "$cf_conf" 2>/dev/null | tail -1)
    msg_info "配置文件: $cf_conf"
    msg "    CF_ZONE_ID: ${zid:-未设置}"
    if grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
      msg_ok "    CF_API_TOKEN: 已配置（出于安全不显示）"
    else
      msg_warn "    CF_API_TOKEN: 未配置"
    fi
  else
    msg_warn "尚未配置 Cloudflare API（$cf_conf 不存在），联动功能不可用"
  fi
  msg ""

  msg "  ${F_GREEN}1${F_RESET}) 写入/更新 API 配置 (Token + Zone ID)"
  msg "  ${F_GREEN}2${F_RESET}) 部署 IP 封禁辅助脚本 (fusionbox-cf-ban)"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  local cf_choice=""
  read -p "请选择 [0-2]: " cf_choice || return

  case "$cf_choice" in
    1)
      msg_info "Token 需要 Zone → Firewall/Rules 编辑权限；Zone ID 在 CF 控制台域名概览页获取"
      local token zone threshold
      token=$(read_input "请输入 Cloudflare API Token")
      [[ -z "$token" ]] && { msg_warn "未输入 Token，已取消"; return; }
      if ! [[ "$token" =~ ^[A-Za-z0-9_-]{10,}$ ]]; then
        msg_err "Token 格式不合法（仅允许字母数字、下划线、连字符）"
        return 1
      fi
      zone=$(read_input "请输入 Zone ID (32 位十六进制)")
      if ! [[ "$zone" =~ ^[a-fA-F0-9]{32}$ ]]; then
        msg_err "Zone ID 格式不合法，应为 32 位十六进制"
        return 1
      fi
      threshold=$(read_input "负载自适应阈值 LOAD_THRESHOLD" "5.0")
      threshold=${threshold:-5.0}
      if ! [[ "$threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        msg_err "阈值必须是数字（如 5.0）"
        return 1
      fi

      umask 077
      mkdir -p /etc/fusionbox
      [[ -f "$cf_conf" ]] && cp "$cf_conf" "$cf_conf.fb-bak-$(date +%s)" 2>/dev/null
      cat > "$cf_conf" << CFCONF
# FusionBox Cloudflare 联动配置（含密钥，请勿外泄）
CF_API_TOKEN=$token
CF_ZONE_ID=$zone
# 负载自适应开盾阈值（1 分钟负载，默认 5.0）
LOAD_THRESHOLD=$threshold
CFCONF
      chmod 600 "$cf_conf"
      msg_ok "Cloudflare 配置已写入: $cf_conf (权限 600)"
      _log_write "Cloudflare 配置已更新 (zone=$zone)"
      ;;
    2)
      if [[ ! -f "$cf_conf" ]] || ! grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        msg_warn "请先完成选项 1 配置 API Token，再部署封禁脚本"
        return
      fi
      if ! confirm "将写入 $ban_script，确认继续？"; then
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

[ -f "$CONF" ] || { echo "缺少配置文件: $CONF"; exit 1; }
# shellcheck source=/dev/null
. "$CONF"
: "${CF_API_TOKEN:?未配置 CF_API_TOKEN}"
: "${CF_ZONE_ID:?未配置 CF_ZONE_ID}"
command -v curl >/dev/null 2>&1 || { echo "需要 curl 支持"; exit 1; }

action="${1:-}"
ip="${2:-}"
if [ -z "$action" ] || [ -z "$ip" ]; then
  echo "用法: fusionbox-cf-ban ban|unban <ip>"
  exit 1
fi
case "$ip" in
  *[!0-9a-fA-F:.]*) echo "IP 格式不合法: $ip"; exit 1 ;;
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
  cf GET "/zones/$CF_ZONE_ID/firewall/access_rules/rules?mode=block&configuration%5Bvalue%5D=$1&per_page=10" \
    | grep -o '"id":"[a-f0-9]\{32\}"' | head -1 | cut -d'"' -f4
}

case "$action" in
  ban)
    rid=$(find_rule_id "$ip")
    if [ -n "$rid" ]; then
      echo "已封禁: $ip (规则 $rid)"
      exit 0
    fi
    payload=$(mktemp)
    printf '{"mode":"block","configuration":{"target":"ip","value":"%s"},"notes":"FusionBox auto ban"}' "$ip" > "$payload"
    resp=$(cf POST "/zones/$CF_ZONE_ID/firewall/access_rules/rules" "$payload")
    rm -f "$payload"
    if echo "$resp" | grep -q '"success":true'; then
      echo "已封禁: $ip"
    else
      echo "封禁失败: $ip (请检查 Token 权限)"
      exit 1
    fi
    ;;
  unban)
    rid=$(find_rule_id "$ip")
    if [ -z "$rid" ]; then
      echo "未找到封禁规则: $ip"
      exit 0
    fi
    resp=$(cf DELETE "/zones/$CF_ZONE_ID/firewall/access_rules/rules/$rid")
    if echo "$resp" | grep -q '"success":true'; then
      echo "已解封: $ip"
    else
      echo "解封失败: $ip"
      exit 1
    fi
    ;;
  *)
    echo "用法: fusionbox-cf-ban ban|unban <ip>"
    exit 1
    ;;
esac
CFBANEOF
      chmod 755 "$ban_script"
      msg_ok "封禁脚本已部署: $ban_script"
      msg ""
      msg "  ${F_BOLD}使用说明:${F_RESET}"
      msg "    手动封禁: fusionbox-cf-ban ban 1.2.3.4"
      msg "    手动解封: fusionbox-cf-ban unban 1.2.3.4"
      msg "    也可在 fail2ban action 中调用，实现自动同步封禁到 Cloudflare"
      _log_write "Cloudflare 封禁脚本已部署: $ban_script"
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

  msg "  ${F_BOLD}负载自适应开盾${F_RESET}"
  msg "  负载高于阈值时把 Cloudflare security_level 切到 under_attack，回落后恢复首次运行时的安全级别"
  msg ""
  msg "  ${F_GREEN}1${F_RESET}) 安装"
  msg "  ${F_GREEN}2${F_RESET}) 卸载"
  msg "  ${F_GREEN}3${F_RESET}) 查看状态"
  msg "  ${F_GREEN}0${F_RESET}) 返回"
  msg ""
  local ad_choice=""
  read -p "请选择 [0-3]: " ad_choice || return

  case "$ad_choice" in
    1)
      if [[ ! -f "$cf_conf" ]] || ! grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        msg_warn "未配置 Cloudflare API Token，脚本会安全跳过（可先执行本菜单选项 4 → 1）"
      fi
      if ! confirm "将写入 $g_script 并配置每 5 分钟检查，确认继续？"; then
        return
      fi
      mkdir -p /var/lib/fusionbox /usr/local/bin /etc/cron.d
      [[ -f "$g_script" ]] && cp "$g_script" "$g_script.fb-bak-$(date +%s)" 2>/dev/null

      cat > "$g_script" << 'CFGUARDEOF'
#!/bin/bash
# FusionBox Cloudflare 负载自适应开盾
# load1 > LOAD_THRESHOLD → security_level=under_attack；否则恢复初始安全级别
# 状态记录在 /var/lib/fusionbox/cf-guard.state，避免重复调用 API
CONF="/etc/fusionbox/cloudflare.conf"
STATE="/var/lib/fusionbox/cf-guard.state"
API="https://api.cloudflare.com/client/v4"

[ -f "$CONF" ] && . "$CONF"
LOAD_THRESHOLD="${LOAD_THRESHOLD:-5.0}"

if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_ZONE_ID:-}" ]; then
  echo "未配置 Cloudflare API（$CONF），安全跳过"
  exit 0
fi
command -v curl >/dev/null 2>&1 || { echo "需要 curl 支持"; exit 1; }

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

command -v python3 >/dev/null || { echo "需要 python3 解析 API 响应"; exit 1; }
umask 077
exec 9>"${STATE}.lock"
flock -n 9 || exit 0
if [ ! -s "${STATE}.original" ]; then
  original=$(curl -fsS --max-time 20 -K "$CURL_CFG" "$API/zones/$CF_ZONE_ID/settings/security_level" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d.get("success"); print(d["result"]["value"])') || exit 1
  case "$original" in off|essentially_off|low|medium|high|under_attack) ;; *) exit 1 ;; esac
  printf '%s\n' "$original" > "${STATE}.original" || exit 1
fi
[ -n "$want" ] || want=$(cat "${STATE}.original")
[ "$want" = "$last" ] && exit 0
resp=$(curl -fsS --max-time 20 -X PATCH "$API/zones/$CF_ZONE_ID/settings/security_level" \
  -K "$CURL_CFG" \
  --data "{\"value\":\"$want\"}")

if echo "$resp" | grep -q '"success":true'; then
  mkdir -p "$(dirname "$STATE")"
  echo "$want" > "$STATE"
  echo "负载 $load1 → Cloudflare security_level: $want"
else
  echo "Cloudflare API 调用失败（负载 $load1），状态未更新"
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
        msg_err "写入脚本或定时任务失败，请检查目录权限"
        pause; return 1
      fi
      chmod 644 "$g_cron"

      msg_ok "负载自适应开盾已安装 (每 5 分钟检查)"
      msg_info "阈值 LOAD_THRESHOLD 可在 $cf_conf 调整（默认 5.0）"
      _log_write "负载自适应开盾已安装"
      ;;
    2)
      if [[ ! -f "$g_script" && ! -f "$g_cron" ]]; then
        msg_info "未安装负载自适应开盾"
        return
      fi
      if ! confirm "确认卸载负载自适应开盾？（Cloudflare 当前安全级别保持不变）"; then
        return
      fi
      rm -f "$g_script" "$g_cron" "$g_state"
      msg_ok "已卸载负载自适应开盾"
      _log_write "负载自适应开盾已卸载"
      ;;
    3)
      [[ -f "$g_script" ]] && msg_ok "脚本: $g_script" || msg_info "脚本未安装"
      [[ -f "$g_cron" ]] && msg_ok "定时任务: $g_cron (每 5 分钟)" || msg_info "定时任务未配置"
      if [[ -f "$cf_conf" ]] && grep -qE '^CF_API_TOKEN=.+' "$cf_conf" 2>/dev/null; then
        local th
        th=$(sed -n 's/^LOAD_THRESHOLD=//p' "$cf_conf" 2>/dev/null | tail -1)
        th=${th:-5.0}
        msg "  当前负载(1 分钟): $(awk '{print $1}' /proc/loadavg 2>/dev/null)"
        msg "  阈值: $th"
        msg "  上次切换状态: $(cat "$g_state" 2>/dev/null || echo "未记录")"
      else
        msg_warn "未配置 Cloudflare API Token，脚本会安全跳过（不影响系统）"
      fi
      ;;
    *) return ;;
  esac
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
  msg "  fusionbox web ssl status        证书状态与到期监控"
  msg "  fusionbox web ssl renew         立即续期全部证书"
  msg "  fusionbox web ssl auto          配置/查看/卸载证书自动续期"
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
  msg "  ${F_BOLD}[站点管理]${F_RESET}"
  msg "  fusionbox web sites             站点清单（端口/类型/证书/占用）"
  msg "  fusionbox web site-del [domain] 删除站点（配置备份 + 回滚）"
  msg "  fusionbox web site-alias        关联多域名（server_name 别名）"
  msg ""
  msg "  ${F_BOLD}[反向代理]${F_RESET}"
  msg "  fusionbox web proxy             HTTP/HTTPS 反向代理"
  msg "  fusionbox web stream            TCP/UDP L4 端口转发"
  msg ""
  msg "  ${F_BOLD}[安全防护]${F_RESET}"
  msg "  fusionbox web guard             nginx 防 CC + Cloudflare 联动/自适应开盾"
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
    msg "  ${F_GREEN}14${F_RESET}) 站点清单 (域名/端口/类型/证书)"
    msg "  ${F_GREEN}15${F_RESET}) 删除站点 (含配置备份)"
    msg "  ${F_GREEN}16${F_RESET}) 关联多域名 (别名)"
    msg "  ${F_GREEN}17${F_RESET}) 防 CC / Cloudflare 联动"
    msg "  ${F_GREEN} 0${F_RESET}) 返回主菜单"
    msg ""
    read -p "请选择 [0-17]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
