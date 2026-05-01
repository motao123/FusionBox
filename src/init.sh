# FusionBox Initialization
# Loaded by fusion.sh on startup

export FUSION_VER="1.0.0"
export FUSION_CODENAME="FusionBox"

# Source common library
FUSION_SRC="${FUSION_SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
. "$FUSION_SRC/lib/common.sh" || {
  echo "致命错误：无法加载公共函数库 $FUSION_SRC/lib/common.sh"
  exit 1
}

# Detect environment
_detect_env

# Load config
_load_config

# Initialize language
_init_lang

# Initialize logging
_init_log

# Print startup banner
_print_banner() {
  clear
  msg "${F_BOLD}${F_CYAN}"
  msg "  ███████╗██╗   ██╗███████╗██╗ ██████╗ ███╗   ██╗██████╗  ██████╗ ██╗  ██╗"
  msg "  ██╔════╝██║   ██║██╔════╝██║██╔═══██╗████╗  ██║██╔══██╗██╔═══██╗╚██╗██╔╝"
  msg "  █████╗  ██║   ██║███████╗██║██║   ██║██╔██╗ ██║██████╔╝██║   ██║ ╚███╔╝ "
  msg "  ██╔══╝  ██║   ██║╚════██║██║██║   ██║██║╚██╗██║██╔══██╗██║   ██║ ██╔██╗ "
  msg "  ██║     ╚██████╔╝███████║██║╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝██╔╝ ██╗"
  msg "  ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
  msg "${F_RESET}"
  msg "  ${F_GREEN}欢迎使用 FusionBox - Linux 全能管理工具箱${F_RESET}"
  msg "  ${F_CYAN}版本: $FUSION_VER ($FUSION_CODENAME)${F_RESET}"
  msg "  ${F_YELLOW}OS: $F_OS_NAME $F_OS_VER | Arch: $F_ARCH | Kernel: $F_KERNEL${F_RESET}"
  msg ""
  _log_write "FusionBox v$FUSION_VER started on $F_OS_NAME $F_OS_VER ($F_ARCH)"
}

# -- Module Loader --

_load_module() {
  local name="$1"
  local path="$FUSION_MODULES/$name.sh"
  if [[ -f "$path" ]]; then
    . "$path"
    return 0
  fi
  return 1
}

# Check root (most operations require root)
_require_root() {
  if [[ $F_IS_ROOT -ne 1 ]]; then
    msg_err "需要 root 权限，请以 root 身份运行"
    exit 1
  fi
}

# Show module status indicator
_module_status() {
  local module="$1"
  local status="$2"
  local color="$F_GREEN"
  [[ "$status" == "stopped" || "$status" == "not_installed" ]] && color="$F_RED"
  [[ "$status" == "warning" ]] && color="$F_YELLOW"
  msg "  ${F_BOLD}[${color}${module}${F_RESET}${F_BOLD}]${F_RESET} $status"
}

# ---- Shell completion helper ----
_fusion_completion() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local cmds="proxy system network web panels market help version update status"
  COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
}
complete -F _fusion_completion fusionbox 2>/dev/null
