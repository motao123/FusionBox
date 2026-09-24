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

# ---- i18n 核心（语言包加载 + 键式查询 L/_tr）----
# 独立成文件：fusion.sh 的根权限门禁早于本文件加载，也需要本地化提示。
if ! declare -F L >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "$FUSION_SRC/lib/i18n.sh"
fi

# ---- Utility Functions ----

msg() { echo -e "$*"; }
msg_info() { msg "${F_CYAN}[${F_BOLD}INFO${F_RESET}${F_CYAN}]${F_RESET} $*"; }
msg_ok()  { msg "${F_GREEN}[${F_BOLD}OK${F_RESET}${F_GREEN}]${F_RESET} $*"; }
msg_err() { msg "${F_RED}[${F_BOLD}ERROR${F_RESET}${F_RED}]${F_RESET} $*"; }
msg_warn(){ msg "${F_YELLOW}[${F_BOLD}WARN${F_RESET}${F_YELLOW}]${F_RESET} $*"; }
msg_title(){ msg "${F_BOLD}${F_CYAN}======== $* ========${F_RESET}"; }
msg_tip() { msg "${F_GREEN}$*${F_RESET}"; }

# ---- Long-running task progress (stage counter) ----
# Stage names are intentionally coarse: we show "which step of how many"
# instead of a fake percentage we cannot measure for package installs.
_F_PROGRESS_TOTAL=0
_F_PROGRESS_CURRENT=0

progress_begin() {
  _F_PROGRESS_TOTAL="${1:-0}"
  _F_PROGRESS_CURRENT=0
}

progress_step() {
  local label="$1"
  _F_PROGRESS_CURRENT=$((_F_PROGRESS_CURRENT + 1))
  if [[ "${_F_PROGRESS_TOTAL:-0}" -gt 0 ]]; then
    msg "${F_CYAN}[${_F_PROGRESS_CURRENT}/${_F_PROGRESS_TOTAL}]${F_RESET} $label"
  else
    msg "${F_CYAN}[${_F_PROGRESS_CURRENT}]${F_RESET} $label"
  fi
}

progress_end() {
  _F_PROGRESS_TOTAL=0
  _F_PROGRESS_CURRENT=0
}

# 语言字符串查询（L / _tr / _load_lang / _init_lang / _i18n_*）已迁到 src/lib/i18n.sh，
# 由本文件顶部按需加载，此处不再重复定义——重复定义会覆盖新实现。

# ---- User Interaction ----

pause() {
  # 非交互场景（管道/CI/重定向）直接返回：只读输出不该卡在「按 Enter 继续」。
  [[ -t 0 ]] || return 0
  msg ""
  msg "$(L MSG_COMMON_0001)"
  read -r || exit 0   # stdin 已关闭（CI/管道）时干净退出，避免菜单死循环
}

confirm() {
  local msg_str="${1:-$(L MSG_COMMON_0025)} [$F_GREEN y $F_RESET/N]: "
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

# ---- Unknown subcommand guard ----
# 模块级未知子命令的统一出口。
# 旧行为是静默滑进交互菜单：拼错命令的用户不会收到任何提示，脚本/CI 下还会
# 因为 read 阻塞而卡住。这里明确报错并给出可执行的下一步，返回 2（区别于成功 0）。
_module_unknown_cmd() {
  local module="$1" cmd="${2:-}"
  msg_err "$(L MSG_COMMON_0016 "${cmd:-$(L MSG_COMMON_0017)}")"
  msg_info "$(L MSG_COMMON_0002 "${module}")"
  msg_info "$(L MSG_COMMON_0003 "${module}")"
  msg_info "$(L MSG_COMMON_0004 "${module}")"
  return 2
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

  # 显式配置（lang: en / zh_CN）优先于环境变量；`auto` 表示"尚未选择"，
  # 此时 FUSION_LANG 单次覆盖必须能生效——安装器总会写入 lang: auto，
  # 若让 auto 也压过环境变量，docs/i18n.md 承诺的 FUSION_LANG=en 单次覆盖永远无效。
  F_LANG="${CONFIG_general_lang:-$F_LANG}"
  if [[ -z "$F_LANG" || "$F_LANG" == "auto" ]] && [[ -n "${FUSION_LANG:-}" ]]; then
    F_LANG="$FUSION_LANG"
  fi

  # general.color=false 时清空全部 ANSI 变量：颜色在 msg()/msg_*() 层统一生效，
  # 置空即全局无色，无需改动任何调用点（i18n 文案不含内嵌转义码）。
  case "${CONFIG_general_color:-true}" in
    false|False|FALSE|0|no|off) F_COLOR=0 ;;
    *)                          F_COLOR=1 ;;
  esac
  if [[ "${F_COLOR:-1}" -eq 0 ]]; then
    F_RED=''; F_GREEN=''; F_YELLOW=''; F_BLUE=''; F_MAGENTA=''; F_CYAN=''
    F_BOLD=''; F_ULINE=''; F_RESET=''
  fi
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
    printf "$(L MSG_COMMON_0005)"
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
    msg_info "$(L MSG_COMMON_0006 "${pkgs[*]}")"
    _install_pkg "${pkgs[@]}" || {
      msg_err "$(L MSG_COMMON_0007 "${pkgs[*]}")"
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
    printf "$(L MSG_COMMON_0008)" "$avail" "$host"
  else
    printf "$(L MSG_COMMON_0009)" "${avail:-$host}"
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
  # HOME 不可写（如容器里的 nobody、只读挂载）时静默停用日志：
  # 帮助等只读路径不该被 mkdir/append 报错噪声污染，功能照常。
  if mkdir -p "$FUSION_LOG_DIR" 2>/dev/null; then
    F_LOG_OK=1
  else
    F_LOG_OK=0
    return 0
  fi
  _log_write "$(L MSG_COMMON_0026)"
}

_log_write() {
  [[ "${F_LOG_OK:-1}" == 1 ]] || return 0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$FUSION_LOG_DIR/fusionbox.log" 2>/dev/null
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
    *)      printf "$(L MSG_COMMON_0010)" "$pkg" ;;
  esac
}

# _require_cmd <command> <package> [影响说明]
# Returns 0 when available; otherwise prints a Chinese reason + next step.
_require_cmd() {
  local cmd="$1" pkg="${2:-$1}" impact="${3:-}"
  if command -v "$cmd" &>/dev/null; then
    return 0
  fi
  local _impact=""
  [[ -n "$impact" ]] && _impact="$(L MSG_COMMON_0019 "$impact")"
  msg_err "$(L MSG_COMMON_0018 "$cmd" "$_impact")"
  msg_info "$(L MSG_COMMON_0020 "$(_pkg_install_hint "$pkg")")"
  return 1
}

_require_python3() {
  _require_cmd python3 python3 "${1:-$(L MSG_COMMON_0027)}"
}

_require_docker() {
  _require_cmd docker docker.io "$(L MSG_COMMON_0028)"
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
  local impact="${1:-$(L MSG_COMMON_0029)}"
  _require_docker || return 1
  if _docker_compose_v2_present; then
    return 0
  fi
  msg_err "$(L MSG_COMMON_0011 "$impact")"
  msg_info "$(L MSG_COMMON_0024 "$(_pkg_install_hint docker-compose-plugin)")"
  msg_info "$(L MSG_COMMON_0012)"
  return 1
}

# _require_docker_daemon [影响说明] — CLI present but daemon unreachable.
_require_docker_daemon() {
  local impact="${1:-$(L MSG_COMMON_0030)}"
  _require_docker || return 1
  if docker info &>/dev/null; then
    return 0
  fi
  msg_err "$(L MSG_COMMON_0013 "$impact")"
  msg_info "$(L MSG_COMMON_0014)"
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
      local _src; _src="$(_scope_sources "$scope" | awk '{print $1}')"
      msg_warn "$(L MSG_COMMON_0021 "$scope" "$root" "$_src")" >&2
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
  # i18n: keep English locale free of Chinese here too (the menu shows this line
  # on every entry, so an untranslated literal would be very visible).
  local line_fmt; line_fmt=$(_tr MSG_DEP_LINE "依赖自检: python3 %s | docker %s | docker compose v2 %s | curl %s")
  # shellcheck disable=SC2059
  msg "${F_BOLD}$(printf "$line_fmt" "$py" "$dk" "$dc" "$cur")${F_RESET}"
  if [[ "$py" == '✗' ]]; then
    msg "  ${F_YELLOW}$(_tr MSG_DEP_MISSING_PY "python3 缺失 → 受影响: 系统备份/恢复、用户与 SSH 管理、受管应用市场、集群")${F_RESET}"
    msg "  $(_tr MSG_INSTALL_HINT "安装") : $(_pkg_install_hint python3)"
  fi
  if [[ "$dc" == '✗' ]]; then
    msg "  ${F_YELLOW}$(_tr MSG_DEP_MISSING_COMPOSE "docker compose v2 缺失 → 受影响: 受管应用市场、Compose 备份/迁移")${F_RESET}"
    [[ "$dk" == '✗' ]] && msg "  $(_tr MSG_INSTALL_HINT "安装") : $(_pkg_install_hint docker.io)"
    msg "  $(_tr MSG_INSTALL_HINT "安装") compose: $(_pkg_install_hint docker-compose-plugin)"
  fi
  if [[ "$py" == '✓' && "$dc" == '✓' ]]; then
    msg_ok "$(_tr MSG_DEP_OK "关键依赖齐备")"
  fi
}

# ---- 界面语言（`fusionbox lang`）----
# 语言包为两套完整实现（src/i18n/zh_CN.sh 与 en.sh），此处只负责查看与切换。

_i18n_switch() {
  local want="$1"
  _config_set_general lang "$want" || { msg_err "$(L MSG_COMMON_0035)"; return 1; }
  CONFIG_general_lang="$want"
  _i18n_init                                  # 立即生效：后续输出即用新语言
  msg_ok "$(L MSG_COMMON_0036 "$(_i18n_display_name "$F_LANG")")"
}

lang_command() {
  local action="${1:-status}"
  case "$action" in
    status|"")
      msg "$(L MSG_COMMON_0032 "$(_i18n_display_name "$F_LANG")")"
      msg "$(L MSG_COMMON_0033)"
      ;;
    zh_CN|zh|cn)  _i18n_switch zh_CN ;;
    en|english)   _i18n_switch en ;;
    auto)         _i18n_switch auto ;;
    *) msg_err "$(L MSG_COMMON_0034 "$action")"; return 2 ;;
  esac
}

# ---- Optional command hint (ping/mtr/nmap/... are only needed by some tasks) ----
_require_optional_cmd() {
  local cmd="$1" pkg="${2:-$1}" feature="${3:-$(L MSG_COMMON_0031)}"
  if command -v "$cmd" &>/dev/null; then
    return 0
  fi
  msg_warn "$(L MSG_COMMON_0015 "$cmd" "$feature")"
  msg_info "$(L MSG_COMMON_0020 "$(_pkg_install_hint "$pkg")")"
  return 1
}

# ---- Log viewer ----
show_logs() {
  local lines="${1:-200}" log_file="$FUSION_LOG_DIR/fusionbox.log"
  msg_title "$(_tr MSG_LOG_TITLE "FusionBox 日志")"
  msg "  $(_tr MSG_LOG_FILE "日志文件") : $log_file"
  msg ""
  if [[ ! -f "$log_file" ]]; then
    msg_warn "$(_tr MSG_LOG_EMPTY "暂无日志文件（尚未产生记录）")"
    return 0
  fi
  local total; total=$(wc -l < "$log_file" 2>/dev/null || echo 0)
  msg "  $(_tr MSG_LOG_SHOW "显示最近") $lines / $total:"
  msg ""
  tail -n "$lines" "$log_file"
  msg ""
  msg_info "$(_tr MSG_LOG_FULL "完整日志") : $log_file"
}
