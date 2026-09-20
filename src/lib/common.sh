# FusionBox 公共函数库
# 颜色定义、日志、用户交互、配置加载

# Colors
F_RED='\e[31m'; F_GREEN='\e[32m'; F_YELLOW='\e[33m'
F_BLUE='\e[34m'; F_MAGENTA='\e[35m'; F_CYAN='\e[36m'
F_BOLD='\e[1m'; F_ULINE='\e[4m'; F_RESET='\e[0m'

# Module directories - auto-detect base path
if [[ -n "$FUSION_BASE" ]]; then
  FUSION_DIR="$FUSION_BASE"
elif [[ -d "/etc/fusionbox" ]]; then
  FUSION_DIR="/etc/fusionbox"
else
  FUSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
FUSION_SRC="${FUSION_SRC:-$FUSION_DIR/src}"
FUSION_MODULES="$FUSION_SRC/modules"
FUSION_LIB="$FUSION_SRC/lib"
FUSION_CONFIG_DIR="${HOME:-/root}/.config/fusionbox"
FUSION_CONFIG="$FUSION_CONFIG_DIR/config.yaml"
FUSION_LOG_DIR="$FUSION_CONFIG_DIR/logs"
FUSION_I18N_DIR="$FUSION_SRC/i18n"
FUSION_TELEMETRY_ID_FILE="$FUSION_CONFIG_DIR/telemetry-id"
FUSION_TELEMETRY_CONSENT_FILE="$FUSION_CONFIG_DIR/telemetry-consent"
# Production collector URL is a controlled project constant. Sends remain disabled
# unless the operator explicitly enables anonymous statistics.
readonly FUSION_TELEMETRY_ENDPOINT="https://fusionbox-telemetry.gdindex-demo.workers.dev/v1/event"

# State variables
F_LANG="auto"
F_COLOR=1

declare -A _LANG_DATA

# ---- Utility Functions ----

msg() { echo -e "$*"; }
msg_info() { msg "${F_CYAN}[${F_BOLD}INFO${F_RESET}${F_CYAN}]${F_RESET} $*"; }
msg_ok()  { msg "${F_GREEN}[${F_BOLD}OK${F_RESET}${F_GREEN}]${F_RESET} $*"; }
msg_err() { msg "${F_RED}[${F_BOLD}ERROR${F_RESET}${F_RED}]${F_RESET} $*"; }
msg_warn(){ msg "${F_YELLOW}[${F_BOLD}WARN${F_RESET}${F_YELLOW}]${F_RESET} $*"; }
msg_title(){ msg "${F_BOLD}${F_CYAN}======== $* ========${F_RESET}"; }
msg_tip() { msg "${F_GREEN}$*${F_RESET}"; }

# Load language strings
# Usage: L <key>
L() {
  local key="$1"
  echo "${_LANG_DATA[$key]:-$key}"
}

_load_lang() {
  local lang="$1"
  _LANG_DATA=()
  if [[ -f "$FUSION_I18N_DIR/$lang.sh" ]]; then
    source "$FUSION_I18N_DIR/$lang.sh"
    local v
    for v in $(compgen -v | grep -E '^(MSG_|MOD_|SYS_|NET_|WEB_|PANEL_|MARKET_|BBR_|PROXY_)'); do
      _LANG_DATA[$v]="${!v}"
    done
  fi
}

_init_lang() {
  if [[ "$F_LANG" == "auto" ]]; then
    local lang_env="${LANG:-en_US.UTF-8}"
    if [[ "$lang_env" =~ zh_CN|zh_ ]]; then
      _load_lang "zh_CN"
    else
      _load_lang "en"
    fi
  else
    _load_lang "$F_LANG"
  fi
}

# Print text with color using i18n
# NOTE: must NOT be named "tr" — that would shadow /usr/bin/tr and silently
# break every `| tr` pipeline in the project (this bug shipped in v1.1.0)
_tr() {
  local key="$1"
  local text="${_LANG_DATA[$key]:-$2}"
  echo -e "$text"
}

# ---- User Interaction ----

pause() {
  msg ""
  msg "按 Enter 键继续..."
  read -r || exit 0   # stdin 已关闭（CI/管道）时干净退出，避免菜单死循环
}

confirm() {
  local msg_str="${1:-确认执行？} [$F_GREEN y $F_RESET/N]: "
  msg "$msg_str"
  local ans=""
  read -r ans || return 1   # EOF/中断一律视为拒绝
  [[ "$ans" =~ ^[Yy]$ ]] && return 0 || return 1
}

select_option() {
  local prompt="$1"; shift
  local options=("$@")
  local i=0
  msg "$prompt" >&2
  for opt in "${options[@]}"; do
    i=$((i+1))
    msg "  $F_GREEN$i$F_RESET) $opt" >&2
  done
  msg "" >&2
  local choice=""
  read -r choice || return 1
  echo "$choice"
}

read_input() {
  local prompt="$1"
  local default="${2:-}"
  msg "$prompt: " >&2
  local value=""
  read -r value || return 1
  [[ -z "$value" && -n "$default" ]] && value="$default"
  echo "$value"
}

# ---- Config loading ----

_load_config() {
  if [[ -f "$FUSION_CONFIG" ]]; then
    # Simple YAML parser for one level of sections containing scalar values.
    local section=""
    while IFS= read -r line; do
      [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
      if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(#.*)?$ ]]; then
        section="${BASH_REMATCH[1]}"
      elif [[ -n "$section" && "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
        local key="${section}_${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        val="${val%%#*}"
        val="${val#"${val%%[! ]*}"}"; val="${val%"${val##*[! ]}"}"
        val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        [[ -n "$val" ]] && printf -v "CONFIG_$key" '%s' "$val"
      fi
    done < "$FUSION_CONFIG"
  fi

  # Override with env vars
  [[ -n "${FUSION_LANG:-}" ]] && F_LANG="$FUSION_LANG"
  F_LANG="${CONFIG_general_lang:-$F_LANG}"
}

_config_set_general() (
  local key="$1" value="$2" line tmp mode="600"
  [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
  [[ "$value" =~ ^[a-zA-Z0-9_.-]+$ ]] || return 2
  mkdir -p "$FUSION_CONFIG_DIR" || return 1
  chmod 700 "$FUSION_CONFIG_DIR" 2>/dev/null || true
  [[ ! -L "$FUSION_CONFIG" ]] || return 1
  tmp=$(mktemp "$FUSION_CONFIG_DIR/.config.yaml.XXXXXX") || return 1
  trap 'rm -f -- "$tmp"' EXIT
  [[ ! -e "$FUSION_CONFIG" ]] || mode=$(stat -c '%a' "$FUSION_CONFIG" 2>/dev/null || printf '600')
  if [[ "$mode" =~ ^[0-7]+$ ]] && (( 8#$mode > 8#600 )); then
    mode="600"
  fi

  local in_general=0 found_general=0 found_key=0
  if [[ -f "$FUSION_CONFIG" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(#.*)?$ ]]; then
        if (( in_general && ! found_key )); then
          printf '  %s: %s\n' "$key" "$value" >> "$tmp"
          found_key=1
        fi
        in_general=0
        if [[ "${BASH_REMATCH[1]}" == "general" ]]; then
          in_general=1
          found_general=1
        fi
      fi
      if (( in_general )) && [[ "$line" =~ ^([[:space:]]+)${key}:[[:space:]]*[^#]*([[:space:]]*#.*)?$ ]]; then
        printf '%s%s: %s%s\n' "${BASH_REMATCH[1]}" "$key" "$value" "${BASH_REMATCH[2]}" >> "$tmp"
        found_key=1
      else
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$FUSION_CONFIG"
  fi
  if (( in_general && ! found_key )); then
    printf '  %s: %s\n' "$key" "$value" >> "$tmp"
  fi
  if (( ! found_general )); then
    [[ ! -s "$tmp" ]] || printf '\n' >> "$tmp"
    printf 'general:\n  %s: %s\n' "$key" "$value" >> "$tmp"
  fi
  chmod "$mode" "$tmp" 2>/dev/null || chmod 600 "$tmp" || return 1
  mv -f -- "$tmp" "$FUSION_CONFIG" || return 1
  trap - EXIT
)

# ---- Anonymous telemetry (explicit opt-in only) ----

_telemetry_endpoint() {
  if [[ "${FUSION_TELEMETRY_TEST_MODE:-0}" == "1" &&
        "${FUSION_TELEMETRY_TEST_ENDPOINT:-}" =~ ^https?://(127\.0\.0\.1|localhost)(:[0-9]+)?(/|$) ]]; then
    printf '%s' "$FUSION_TELEMETRY_TEST_ENDPOINT"
  else
    printf '%s' "$FUSION_TELEMETRY_ENDPOINT"
  fi
}

_telemetry_new_id() {
  local uuid hex
  uuid=$(command cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
  if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    uuid=$(command uuidgen -r 2>/dev/null || true)
  fi
  if [[ ! "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    hex=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n') || return 1
    [[ ${#hex} -eq 32 ]] || return 1
    uuid="${hex:0:8}-${hex:8:4}-4${hex:13:3}-a${hex:17:3}-${hex:20:12}"
  fi
  printf '%s\n' "${uuid,,}"
}

_telemetry_id() (
  local id tmp
  if [[ -f "$FUSION_TELEMETRY_ID_FILE" && ! -L "$FUSION_TELEMETRY_ID_FILE" ]]; then
    IFS= read -r id < "$FUSION_TELEMETRY_ID_FILE" || true
    if [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
      chmod 600 "$FUSION_TELEMETRY_ID_FILE" 2>/dev/null || true
      printf '%s\n' "$id"
      return 0
    fi
  fi
  [[ ! -L "$FUSION_TELEMETRY_ID_FILE" ]] || return 1
  mkdir -p "$FUSION_CONFIG_DIR" || return 1
  chmod 700 "$FUSION_CONFIG_DIR" 2>/dev/null || true
  id=$(_telemetry_new_id) || return 1
  tmp=$(mktemp "$FUSION_CONFIG_DIR/.telemetry-id.XXXXXX") || return 1
  trap 'rm -f -- "$tmp"' EXIT
  (umask 077; printf '%s\n' "$id" > "$tmp") || return 1
  chmod 600 "$tmp" || return 1
  mv -f -- "$tmp" "$FUSION_TELEMETRY_ID_FILE" || return 1
  trap - EXIT
  printf '%s\n' "$id"
)

_telemetry_record_consent() (
  local decision="$1" tmp
  [[ "$decision" == "enabled" || "$decision" == "disabled" ]] || return 2
  [[ ! -L "$FUSION_TELEMETRY_CONSENT_FILE" ]] || return 1
  mkdir -p "$FUSION_CONFIG_DIR" || return 1
  chmod 700 "$FUSION_CONFIG_DIR" 2>/dev/null || true
  tmp=$(mktemp "$FUSION_CONFIG_DIR/.telemetry-consent.XXXXXX") || return 1
  trap 'rm -f -- "$tmp"' EXIT
  (umask 077; printf '%s\n' "$decision" > "$tmp") || return 1
  chmod 600 "$tmp" || return 1
  mv -f -- "$tmp" "$FUSION_TELEMETRY_CONSENT_FILE" || return 1
  trap - EXIT
)

_telemetry_consent_is_interactive() {
  [[ -t 0 && -t 1 && "${FUSION_NONINTERACTIVE:-0}" != "1" ]]
}

# Called only after a successful installer deployment. Existing user configs are
# authoritative and are never changed or used to trigger another prompt.
_telemetry_install_consent() {
  local config_existed="${1:-1}" decision='' answer=''
  [[ "$config_existed" == "0" ]] || return 0

  if [[ -f "$FUSION_TELEMETRY_CONSENT_FILE" && ! -L "$FUSION_TELEMETRY_CONSENT_FILE" ]]; then
    IFS= read -r decision < "$FUSION_TELEMETRY_CONSENT_FILE" || true
  fi
  case "$decision" in
    enabled)
      _telemetry_id >/dev/null || return 1
      _config_set_general stats true || return 1
      CONFIG_general_stats=true
      return 0
      ;;
    disabled)
      CONFIG_general_stats=false
      return 0
      ;;
  esac

  if _telemetry_consent_is_interactive; then
    printf '是否允许发送匿名安装与使用统计？不包含命令参数或业务数据 [y/N]: '
    read -r answer || answer=''
  fi
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    _telemetry_id >/dev/null || return 1
    _config_set_general stats true || return 1
    if ! _telemetry_record_consent enabled; then
      _config_set_general stats false >/dev/null 2>&1 || true
      _telemetry_record_consent disabled >/dev/null 2>&1 || true
      CONFIG_general_stats=false
      return 1
    fi
    CONFIG_general_stats=true
  else
    _config_set_general stats false || return 1
    CONFIG_general_stats=false
    _telemetry_record_consent disabled
  fi
}

_telemetry_event() {
  [[ "${CONFIG_general_stats:-false}" == "true" ]] || return 0
  local event="$1" endpoint id payload os arch
  case "$event" in
    install|update|uninstall|heartbeat) ;;
    *) return 2 ;;
  esac
  command -v curl &>/dev/null || return 0
  endpoint=$(_telemetry_endpoint)
  [[ -n "$endpoint" ]] || return 0
  id=$(_telemetry_id) || return 0
  [[ "$FUSION_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
  case "${F_OS:-other}" in
    debian|ubuntu|centos|rocky|almalinux|fedora|arch) os="$F_OS" ;;
    *) os="other" ;;
  esac
  case "$(uname -m 2>/dev/null)" in
    x86_64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    armv7l) arch="armv7l" ;;
    *) arch="other" ;;
  esac
  printf -v payload '{"schema_version":1,"event":"%s","installation_id":"%s","version":"%s","os":"%s","arch":"%s"}' \
    "$event" "${id//-/}" "$FUSION_VER" "$os" "$arch"
  (curl -fsS --connect-timeout 2 --max-time 3 \
    -H 'Content-Type: application/json' --data-binary "$payload" \
    "$endpoint" </dev/null >/dev/null 2>&1) &
}

privacy_command() {
  local action="${1:-status}"
  case "$action" in
    status)
      if [[ "${CONFIG_general_stats:-false}" == "true" ]]; then
        msg_ok "$(_tr MSG_PRIVACY_ENABLED "匿名统计: 已开启")"
      else
        msg "$(_tr MSG_PRIVACY_DISABLED "匿名统计: 已关闭")"
      fi
      ;;
    on)
      local old_stats="${CONFIG_general_stats:-false}"
      _telemetry_id >/dev/null || { msg_err "$(_tr MSG_PRIVACY_ID_FAILED "无法创建匿名标识")"; return 1; }
      _config_set_general stats true || { msg_err "$(_tr MSG_PRIVACY_SAVE_FAILED "无法保存隐私设置")"; return 1; }
      _telemetry_record_consent enabled || { msg_err "$(_tr MSG_PRIVACY_SAVE_FAILED "无法保存隐私设置")"; return 1; }
      CONFIG_general_stats=true
      msg_ok "$(_tr MSG_PRIVACY_ENABLED "匿名统计: 已开启")"
      [[ "$old_stats" == "true" ]] || _telemetry_event heartbeat
      ;;
    off)
      _config_set_general stats false || { msg_err "$(_tr MSG_PRIVACY_SAVE_FAILED "无法保存隐私设置")"; return 1; }
      _telemetry_record_consent disabled || { msg_err "$(_tr MSG_PRIVACY_SAVE_FAILED "无法保存隐私设置")"; return 1; }
      CONFIG_general_stats=false
      msg_ok "$(_tr MSG_PRIVACY_DISABLED "匿名统计: 已关闭")"
      ;;
    reset-id)
      if [[ "${CONFIG_general_stats:-false}" != "true" ]]; then
        msg_err "$(_tr MSG_PRIVACY_RESET_DISABLED "请先开启匿名统计")"
        return 1
      fi
      [[ ! -L "$FUSION_TELEMETRY_ID_FILE" ]] || { msg_err "$(_tr MSG_PRIVACY_ID_FAILED "无法创建匿名标识")"; return 1; }
      rm -f -- "$FUSION_TELEMETRY_ID_FILE" || return 1
      _telemetry_id >/dev/null || { msg_err "$(_tr MSG_PRIVACY_ID_FAILED "无法创建匿名标识")"; return 1; }
      msg_ok "$(_tr MSG_PRIVACY_ID_RESET "匿名标识已重置")"
      ;;
    *)
      msg_err "$(_tr MSG_PRIVACY_USAGE "用法: fusionbox privacy status|on|off|reset-id")"
      return 2
      ;;
  esac
}

# ---- System detection ----

_detect_env() {
  # OS Detection
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    F_OS="${ID:-unknown}"
    F_OS_VER="${VERSION_ID:-}"
    F_OS_NAME="${NAME:-}"
  else
    F_OS="unknown"
  fi

  # Architecture
  F_ARCH=$(uname -m)
  case "$F_ARCH" in
    x86_64|amd64) F_ARCH="amd64" ;;
    aarch64|arm64) F_ARCH="arm64" ;;
    *) F_ARCH="unknown" ;;
  esac

  # Package manager
  if command -v apt &>/dev/null; then
    F_PKG_MGR="apt"
  elif command -v yum &>/dev/null; then
    F_PKG_MGR="yum"
  elif command -v apk &>/dev/null; then
    F_PKG_MGR="apk"
  elif command -v zypper &>/dev/null; then
    F_PKG_MGR="zypper"
  else
    F_PKG_MGR="unknown"
  fi

  # Init system
  if pidof systemd &>/dev/null; then
    F_INIT="systemd"
  elif command -v openrc &>/dev/null; then
    F_INIT="openrc"
  else
    F_INIT="unknown"
  fi

  # Root check
  F_IS_ROOT=0
  [[ $EUID -eq 0 ]] && F_IS_ROOT=1

  # Virtualization detection
  if [[ -f /proc/cpuinfo ]] && grep -qi hypervisor /proc/cpuinfo 2>/dev/null; then
    F_VIRT="yes"
  else
    F_VIRT="no"
  fi

  # Kernel version
  F_KERNEL=$(uname -r)
  F_KERNEL_MAJOR=$(echo "$F_KERNEL" | cut -d. -f1)
  F_KERNEL_MINOR=$(echo "$F_KERNEL" | cut -d. -f2)

  # IP
  F_IP=""
  F_IPV6=""

  # Module paths
  F_MODULES_LIST=(
    "proxy"    "$FUSION_MODULES/proxy.sh"
    "system"   "$FUSION_MODULES/system.sh"
    "network"  "$FUSION_MODULES/network.sh"
    "web"      "$FUSION_MODULES/web.sh"
    "panels"   "$FUSION_MODULES/panels.sh"
    "market"   "$FUSION_MODULES/market.sh"
    "warp"     "$FUSION_MODULES/warp.sh"
    "workspace" "$FUSION_MODULES/workspace.sh"
    "cluster"  "$FUSION_MODULES/cluster.sh"
  )
}

_get_ip() {
  F_IP=$(curl -s4 --connect-timeout 5 https://ip.sb 2>/dev/null || \
         curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
         wget -qO- --timeout=5 https://ip.sb 2>/dev/null || true)
  F_IPV6=$(curl -s6 --connect-timeout 5 https://ip.sb 2>/dev/null || true)
}

# ---- Package Management ----

_install_pkg() {
  local pkgs=("$@")
  case "$F_PKG_MGR" in
    apt)  apt-get update -y && apt-get install -y "${pkgs[@]}" ;;
    yum)  yum install -y "${pkgs[@]}" ;;
    apk)  apk add "${pkgs[@]}" ;;
    zypper) zypper install -y "${pkgs[@]}" ;;
    *)    msg_err "$(_tr MSG_ERROR "未知的包管理器")"; return 1 ;;
  esac
}

_check_pkg() {
  local cmd="$1"; shift
  local pkgs=("$@")
  if ! command -v "$cmd" &>/dev/null; then
    msg_info "正在安装 ${pkgs[*]}..."
    _install_pkg "${pkgs[@]}" || {
      msg_err "安装 ${pkgs[*]} 失败"
      return 1
    }
  fi
}

# ---- CPU accounting ----
# `nproc --all` reports host cores, which is misleading inside containers where
# cgroup limits apply. Report both so users can judge the machine correctly.
_cpu_cores_available() {
  local n
  # cgroup v2
  if [[ -r /sys/fs/cgroup/cpu.max ]]; then
    read -r quota period < /sys/fs/cgroup/cpu.max 2>/dev/null || true
    if [[ "$quota" =~ ^[0-9]+$ && "$period" =~ ^[0-9]+$ && "$period" -gt 0 ]]; then
      n=$(( (quota + period - 1) / period ))
      (( n > 0 )) && { printf '%s' "$n"; return; }
    fi
  fi
  # cgroup v1
  if [[ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us && -r /sys/fs/cgroup/cpu/cpu.cfs_period_us ]]; then
    local q pr
    q=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo -1)
    pr=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo 0)
    if [[ "$q" =~ ^[0-9]+$ && "$pr" =~ ^[0-9]+$ && "$q" -gt 0 && "$pr" -gt 0 ]]; then
      n=$(( (q + pr - 1) / pr ))
      (( n > 0 )) && { printf '%s' "$n"; return; }
    fi
  fi
  # cpuset restriction
  if [[ -r /sys/fs/cgroup/cpuset.cpus.effective ]] && [[ -s /sys/fs/cgroup/cpuset.cpus.effective ]]; then
    n=$(nproc 2>/dev/null || echo 0)
    (( n > 0 )) && { printf '%s' "$n"; return; }
  fi
  nproc 2>/dev/null || echo 0
}

_cpu_cores_host() { nproc --all 2>/dev/null || echo 0; }

_cpu_cores_display() {
  local avail host
  avail=$(_cpu_cores_available)
  host=$(_cpu_cores_host)
  if [[ -n "$avail" && -n "$host" && "$avail" != "$host" ]]; then
    printf '可用 %s 核 / 宿主 %s 核' "$avail" "$host"
  else
    printf '%s 核' "${avail:-$host}"
  fi
}

# ---- File Helpers ----

_download() {
  local url="$1"; local output="$2"
  if command -v curl &>/dev/null; then
    curl -sL --connect-timeout 10 --retry 3 -o "$output" "$url"
  elif command -v wget &>/dev/null; then
    wget -qO "$output" --timeout=10 --tries=3 "$url"
  else
    return 1
  fi
}

# ---- Logging ----

_init_log() {
  mkdir -p "$FUSION_LOG_DIR"
  _log_write "=== FusionBox 会话已启动 ==="
}

_log_write() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$FUSION_LOG_DIR/fusionbox.log"
}

# ---- Dependency checks ----
# Central guard for runtime dependencies. Missing python3 used to produce a
# misleading "不支持的应用 ID" in the managed market and various English errors
# across 50+ call sites; every python3 invocation must go through _require_python3.

# Install hint for the detected package manager (never runs the install itself).
_pkg_install_hint() {
  local pkg="$1"
  case "$F_PKG_MGR" in
    apt)    printf 'apt-get update && apt-get install -y %s' "$pkg" ;;
    yum)    printf 'yum install -y %s' "$pkg" ;;
    apk)    printf 'apk add %s' "$pkg" ;;
    zypper) printf 'zypper install -y %s' "$pkg" ;;
    *)      printf '请用系统包管理器安装 %s' "$pkg" ;;
  esac
}

# _require_cmd <command> <package> [影响说明]
# Returns 0 when available; otherwise prints a Chinese reason + next step.
_require_cmd() {
  local cmd="$1" pkg="${2:-$1}" impact="${3:-}"
  if command -v "$cmd" &>/dev/null; then
    return 0
  fi
  msg_err "缺少必需命令: $cmd${impact:+（影响：$impact）}"
  msg_info "安装方式: $(_pkg_install_hint "$pkg")"
  return 1
}

_require_python3() {
  _require_cmd python3 python3 "${1:-备份/恢复、系统信息、受管应用市场等}"
}

_require_docker() {
  _require_cmd docker docker.io "Docker 管理、受管应用市场"
}

# Docker CLI present? (daemon check is separate so we can explain each case)
_docker_cli_present() { command -v docker &>/dev/null; }

# Docker Compose v2 present? Silent probe, no error output.
_docker_compose_v2_present() {
  command -v docker &>/dev/null || return 1
  docker compose version &>/dev/null
}

# _require_docker_compose [影响说明]
_require_docker_compose() {
  local impact="${1:-受管应用市场}"
  _require_docker || return 1
  if _docker_compose_v2_present; then
    return 0
  fi
  msg_err "缺少 Docker Compose v2（影响：$impact）"
  msg_info "请安装 compose 插件：$(_pkg_install_hint docker-compose-plugin)"
  msg_info "或参考: https://docs.docker.com/compose/install/linux/"
  return 1
}

# _require_docker_daemon [影响说明] — CLI present but daemon unreachable.
_require_docker_daemon() {
  local impact="${1:-Docker 管理}"
  _require_docker || return 1
  if docker info &>/dev/null; then
    return 0
  fi
  msg_err "Docker 守护进程不可用（影响：$impact）"
  msg_info "请检查服务状态: systemctl status docker（或 service docker status）"
  return 1
}

# Parse a comma separated scope list and keep only scopes whose sources exist.
# Usage: _filter_existing_scopes <root> <scopes> ; writes kept scopes to stdout,
# skipped ones are reported on stderr as "scope:path" lines.
_scope_sources() {
  case "$1" in
    config)    printf 'etc/nginx etc/caddy' ;;
    fusion)    printf 'etc/fusionbox' ;;
    web)       printf 'var/www etc/nginx etc/caddy' ;;
    docker)    printf 'opt/docker' ;;
    ssh)       printf 'etc/ssh' ;;
    cron)      printf 'etc/crontab etc/cron.d var/spool/cron' ;;
    usr-local) printf 'usr/local' ;;
    home)      printf 'home' ;;
    *)         printf '' ;;
  esac
}

_filter_existing_scopes() {
  local root="${1:-/}" scopes="$2" scope source kept=""
  local old_ifs="$IFS"
  IFS=','
  for scope in $scopes; do
    IFS="$old_ifs"
    scope="${scope// /}"
    [[ -n "$scope" ]] || continue
    local found=0
    for source in $(_scope_sources "$scope"); do
      if [[ -e "$root/$source" ]]; then found=1; break; fi
    done
    if [[ $found -eq 1 ]]; then
      kept="${kept:+$kept,}$scope"
    else
      msg_warn "已跳过 scope ${scope}（$root/$(_scope_sources "$scope" | awk '{print $1}') 不存在）" >&2
    fi
    IFS=','
  done
  IFS="$old_ifs"
  printf '%s' "$kept"
}

# ---- Dependency self-check (shown on first menu entry) ----
# One-shot report of runtime dependencies and which modules are affected.
show_dependency_status() {
  local py='✗' dk='✗' dc='✗' cur='✗' line
  command -v python3 &>/dev/null && py='✓'
  command -v docker &>/dev/null && dk='✓'
  _docker_compose_v2_present && dc='✓'
  command -v curl &>/dev/null && cur='✓'
  msg "${F_BOLD}依赖自检:${F_RESET} python3 $py | docker $dk | docker compose v2 $dc | curl $cur"
  if [[ "$py" == '✗' ]]; then
    msg "  ${F_YELLOW}python3 缺失 → 受影响: 系统备份/恢复、用户与 SSH 管理、受管应用市场、集群${F_RESET}"
    msg "  安装: $(_pkg_install_hint python3)"
  fi
  if [[ "$dc" == '✗' ]]; then
    msg "  ${F_YELLOW}docker compose v2 缺失 → 受影响: 受管应用市场、Compose 备份/迁移${F_RESET}"
    [[ "$dk" == '✗' ]] && msg "  安装: $(_pkg_install_hint docker.io)"
    msg "  安装 compose 插件: $(_pkg_install_hint docker-compose-plugin)"
  fi
  if [[ "$py" == '✓' && "$dc" == '✓' ]]; then
    msg_ok "关键依赖齐备"
  fi
}

# ---- Optional command hint (ping/mtr/nmap/... are only needed by some tasks) ----
_require_optional_cmd() {
  local cmd="$1" pkg="${2:-$1}" feature="${3:-该功能}"
  if command -v "$cmd" &>/dev/null; then
    return 0
  fi
  msg_warn "未找到 $cmd，无法执行$feature"
  msg_info "安装方式: $(_pkg_install_hint "$pkg")"
  return 1
}

# ---- Log viewer ----
show_logs() {
  local lines="${1:-200}" log_file="$FUSION_LOG_DIR/fusionbox.log"
  msg_title "FusionBox 日志"
  msg "  日志文件: $log_file"
  msg ""
  if [[ ! -f "$log_file" ]]; then
    msg_warn "暂无日志文件（尚未产生记录）"
    return 0
  fi
  local total; total=$(wc -l < "$log_file" 2>/dev/null || echo 0)
  msg "  共 $total 行，显示最近 $lines 行:"
  msg ""
  tail -n "$lines" "$log_file"
  msg ""
  msg_info "完整日志: $log_file"
}
