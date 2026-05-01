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
tr() {
  local key="$1"
  local text="${_LANG_DATA[$key]:-$2}"
  echo -e "$text"
}

# ---- User Interaction ----

pause() {
  msg ""
  msg "按 Enter 键继续..."
  read -r
}

confirm() {
  local msg_str="${1:-确认执行？} [$F_GREEN Y $F_RESET/n]: "
  msg "$msg_str"
  read -r ans
  [[ "$ans" =~ ^[Yy]?$ ]] && return 0 || return 1
}

select_option() {
  local prompt="$1"; shift
  local options=("$@")
  local i=0
  msg "$prompt"
  for opt in "${options[@]}"; do
    i=$((i+1))
    msg "  $F_GREEN$i$F_RESET) $opt"
  done
  msg ""
  read -r choice
  echo "$choice"
}

read_input() {
  local prompt="$1"
  local default="${2:-}"
  msg "$prompt: "
  read -r value
  [[ -z "$value" && -n "$default" ]] && value="$default"
  echo "$value"
}

# ---- Config loading ----

_load_config() {
  if [[ -f "$FUSION_CONFIG" ]]; then
    # Simple YAML parser for flat config
    local section=""
    while IFS= read -r line; do
      line="${line%%#*}"  # Remove comments
      line="${line#"${line%%[! ]*}"}"  # Trim leading spaces
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^[a-zA-Z_]+: ]]; then
        section="${line%%:*}"
      elif [[ "$line" =~ ^[[:space:]]*([a-zA-Z_]+):[[:space:]]*(.*) ]]; then
        local key="${section}_${BASH_REMATCH[1]}"
        local val="${BASH_REMATCH[2]}"
        val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        val="${val%%#*}"
        val="${val#"${val%%[! ]*}"}"; val="${val%"${val##*[! ]}"}"
        [[ -n "$val" ]] && eval "CONFIG_$key=\"\$val\""
      fi
    done < "$FUSION_CONFIG"
  fi

  # Override with env vars
  [[ -n "$FUSION_LANG" ]] && F_LANG="$FUSION_LANG"
  F_LANG="${CONFIG_general_lang:-$F_LANG}"
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
    *)    msg_err "$(tr MSG_ERROR "未知的包管理器")"; return 1 ;;
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
