#!/bin/bash
# FusionBox - Ultimate Linux Management Script
# Repository: https://github.com/motao123/FusionBox

# Read-only commands may run without root; everything else (incl. menus) needs root.
# Oracle detect/status deliberately bypass normal startup writes so inspection stays read-only.
FUSION_READONLY=0
if [[ "$1" == "cluster" && "$2" == "oracle" && "${3:-}" =~ ^(detect|status|help)$ ]]; then
  FUSION_READONLY=1
fi
case "$1" in
  help|h|version|v|privacy)
    [[ "$1" != "privacy" || "${2:-status}" == "status" ]] || {
      [[ $EUID -ne 0 && $FUSION_READONLY -ne 1 ]] && echo "需要 root 权限" && exit 1
    }
    ;;
  cluster)
    [[ $EUID -ne 0 && $FUSION_READONLY -ne 1 ]] && echo "需要 root 权限" && exit 1
    ;;
  *) [[ $EUID -ne 0 && $FUSION_READONLY -ne 1 ]] && echo "需要 root 权限" && exit 1 ;;
esac

# Resolve script path through symlinks (install.sh links /usr/local/bin/fusionbox
# to /etc/fusionbox/fusion.sh; using $0 directly would break the install layout)
_source_path="${BASH_SOURCE[0]}"
while [[ -L "$_source_path" ]]; do
  _link_dir="$(cd "$(dirname "$_source_path")" && pwd)"
  _source_path="$(readlink "$_source_path")"
  [[ $_source_path != /* ]] && _source_path="$_link_dir/$_source_path"
done
export FUSION_BASE="$(cd "$(dirname "$_source_path")" && pwd)"
export FUSION_SRC="$FUSION_BASE/src"

. "$FUSION_SRC/init.sh"

# ---- Command Router ----
# Routes user commands to the appropriate module

route() {
  local cmd="$1"; shift || true

  case "$cmd" in
    # Proxy module
    proxy|p)
      _load_module "proxy"
      proxy_main "$@"
      ;;
    # System management
    system|sys|s)
      _load_module "system"
      system_main "$@"
      ;;
    # Network tools
    network|net|n)
      _load_module "network"
      network_main "$@"
      ;;
    # Web/LNMP
    web|w|lnmp)
      _load_module "web"
      web_main "$@"
      ;;
    # Panels & Docker
    panels|panel|tools|t)
      _load_module "panels"
      panels_main "$@"
      ;;
    # App market
    market|m|apps)
      _load_module "market"
      market_main "$@"
      ;;
    # WARP management
    warp)
      _load_module "warp"
      warp_main "$@"
      ;;
    # Workspace management
    workspace|ws)
      _load_module "workspace"
      workspace_main "$@"
      ;;
    # Cluster & tools
    cluster|cl)
      _load_module "cluster"
      cluster_main "$@"
      ;;
    # System commands
    status)
      show_status
      ;;
    version|v)
      msg "$FUSION_CODENAME v$FUSION_VER"
      msg "版本: $FUSION_VER"
      ;;
    update|up)
      if [[ "${1:-}" == "--cron" ]]; then
        shift || true
        self_update_cron "${1:-status}"
      else
        self_update
      fi
      ;;
    help|h)
      show_help "$@"
      ;;
    uninstall)
      self_uninstall
      ;;
    privacy)
      privacy_command "$@"
      ;;
    # k command shortcut - pass to system
    k)
      _load_module "cluster"
      cluster_kcmd "$@"
      ;;
    # Interactive main menu (no args)
    menu|main)
      main_menu
      ;;
    "")
      main_menu
      ;;
    *)
      msg_err "未知命令: $cmd"
      msg_info "用法: fusionbox help"
      return 1
      ;;
  esac
}

# ---- Status Overview ----
show_status() {
  _print_banner
  msg_title "系统状态概览"
  msg ""
  msg "  ${F_BOLD}CPU:${F_RESET} $(nproc --all) cores | $(free -h | awk '/Mem/{print $2}') RAM"
  msg "  ${F_BOLD}Disk:${F_RESET} $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
  msg "  ${F_BOLD}Kernel:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}OS:${F_RESET} $F_OS_NAME $F_OS_VER"
  msg ""

  # Check proxy status
  local proxy_status="未安装"
  if [[ -f /etc/fusionbox/proxy/current_backend ]]; then
    if systemctl is-active fusionbox-proxy &>/dev/null; then
      proxy_status="运行中"
    else
      proxy_status="已停止"
    fi
  fi
  _module_status "代理管理" "$proxy_status"

  # Check 233boy sing-box
  if [[ -x /usr/local/bin/sing-box && -d /etc/sing-box/sh ]]; then
    local sb_st
    if systemctl is-active sing-box &>/dev/null; then
      sb_st="运行中"
    else
      sb_st="已停止"
    fi
    _module_status "sing-box(233boy)" "$sb_st"
  fi

  # Check BBR
  local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  _module_status "BBR" "$bbr_status"

  # Check Docker
  if command -v docker &>/dev/null; then
    _module_status "Docker" "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "未运行")"
  fi

  # Check Nginx
  if command -v nginx &>/dev/null; then
    _module_status "Nginx" "$(nginx -v 2>&1 | awk -F/ '{print $2}')"
  fi

  # Check WARP
  if command -v warp-cli &>/dev/null; then
    local warp_st=$(warp-cli status 2>/dev/null | head -1)
    _module_status "WARP" "$warp_st"
  fi

  msg ""
  pause
}

# ---- Self Update ----
# NOTE: keep the repo URL in sync with install.sh (single source of truth)
FUSION_REPO="https://github.com/motao123/FusionBox"
FUSION_API="https://api.github.com/repos/motao123/FusionBox"

_update_json_string() {
  local key="$1"
  tr -d '\r\n' < "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

_version_is_newer() {
  local remote="$1" current="$2" highest
  [[ "$remote" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  highest=$(printf '%s\n%s\n' "$current" "$remote" | sort -V | tail -n 1)
  [[ "$highest" == "$remote" && "$remote" != "$current" ]]
}

_update_download() {
  local url="$1" output="$2"
  shift 2
  command -v curl &>/dev/null || return 1
  curl -fsSL --connect-timeout 10 --retry 2 "$@" "$url" -o "$output"
}

_update_validate_archive() {
  local archive="$1" root="$2" workdir="$3" entry target type line
  local listing="$workdir/archive.list" verbose="$workdir/archive.verbose"

  tar tzf "$archive" > "$listing" || return 1
  tar tvzf "$archive" > "$verbose" || return 1
  while IFS= read -r entry; do
    entry="${entry#./}"
    [[ -n "$entry" && "$entry" != /* && "$entry" != *\\* ]] || return 1
    case "/$entry/" in
      */../*|*/./*) return 1 ;;
    esac
    [[ "$entry" == "$root" || "$entry" == "$root/" || "$entry" == "$root/"* ]] || return 1
  done < "$listing"

  while IFS= read -r line; do
    type="${line:0:1}"
    [[ "$type" == "-" || "$type" == "d" ]] || return 1
  done < "$verbose"

  for target in fusion.sh install.sh version.txt src/init.sh src/lib/deploy.sh; do
    grep -Fxq "$root/$target" "$listing" || return 1
  done
}

self_update() (
  local tmpdir metadata tag asset expected actual archive_root remote_ver download_status=0
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "$tmpdir"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  msg_info "正在检查更新..."

  metadata="$tmpdir/latest-release.json"
  if _update_download "$FUSION_API/releases/latest" "$metadata" \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28'; then
    tag="$(_update_json_string tag_name "$metadata")"
    if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      remote_ver="${tag#v}"
      asset="FusionBox-$tag.tar.gz"
      archive_root="FusionBox"
      if [[ "$remote_ver" == "$FUSION_VER" ]]; then
        msg_ok "已是最新版本"
        return 0
      fi
      _version_is_newer "$remote_ver" "$FUSION_VER" || {
        msg_warn "最新稳定 Release ($remote_ver) 早于当前版本 ($FUSION_VER)，拒绝降级"
        return 0
      }
      msg_info "发现最新稳定版本 $tag，正在下载已校验的 Release 包..."
      _update_download "$FUSION_REPO/releases/download/$tag/$asset" "$tmpdir/fusionbox.tar.gz" || download_status=1
      if [[ $download_status -eq 0 ]]; then
        _update_download "$FUSION_REPO/releases/download/$tag/SHA256SUMS" "$tmpdir/SHA256SUMS" || download_status=1
      fi
      if [[ $download_status -eq 0 ]]; then
        expected="$(while read -r sum name rest; do
          name="${name#\*}"
          if [[ "$name" == "$asset" && -z "$rest" && "$sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
            printf '%s\n' "${sum,,}"
          fi
        done < "$tmpdir/SHA256SUMS")"
        [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || download_status=1
      fi
      if [[ $download_status -eq 0 ]]; then
        actual="$(sha256sum "$tmpdir/fusionbox.tar.gz" | cut -d ' ' -f 1)" || download_status=1
        [[ "$actual" == "$expected" ]] || download_status=1
      fi
      if [[ $download_status -ne 0 ]]; then
        msg_err "Release 资产下载或 SHA256 校验失败；为避免降级到未校验内容，更新已停止"
        return 1
      fi
    else
      download_status=2
    fi
  else
    download_status=2
  fi

  if [[ $download_status -eq 2 ]]; then
    msg "${F_YELLOW}[WARN]${F_RESET} GitHub latest Release API 不可用或受限，回退到 main 分支快照。"
    msg "${F_YELLOW}[WARN]${F_RESET} main 快照没有 Release SHA256SUMS，无法提供发布资产级完整性校验。"
    _update_download "$FUSION_REPO/archive/refs/heads/main.tar.gz" "$tmpdir/fusionbox.tar.gz" || return 1
    archive_root="FusionBox-main"
    tag=""
  fi

  _update_validate_archive "$tmpdir/fusionbox.tar.gz" "$archive_root" "$tmpdir" || {
    msg_err "归档结构或路径安全检查失败"
    return 1
  }
  tar xzf "$tmpdir/fusionbox.tar.gz" -C "$tmpdir" || return 1
  [[ -f "$tmpdir/$archive_root/fusion.sh" && ! -L "$tmpdir/$archive_root/fusion.sh" &&
     -f "$tmpdir/$archive_root/src/lib/deploy.sh" && ! -L "$tmpdir/$archive_root/src/lib/deploy.sh" ]] || return 1
  remote_ver="$(tr -d '[:space:]' < "$tmpdir/$archive_root/version.txt")" || return 1
  [[ "$remote_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ -z "$tag" || "$remote_ver" == "${tag#v}" ]] || {
    msg_err "Release 版本与归档内容不一致"
    return 1
  }
  if [[ "$remote_ver" == "$FUSION_VER" ]]; then
    msg_ok "已是最新版本"
    return 0
  fi
  _version_is_newer "$remote_ver" "$FUSION_VER" || {
    msg_warn "远端版本 ($remote_ver) 早于当前版本 ($FUSION_VER)，拒绝降级"
    return 0
  }
  source "$FUSION_BASE/src/lib/deploy.sh" || return 1
  fusion_validate_release "$tmpdir/$archive_root" || return 1
  fusion_deploy "$tmpdir/$archive_root" "$FUSION_BASE" || return 1
  FUSION_VER="$remote_ver"
  _telemetry_event update
  msg_ok "更新完成，重新运行 fusionbox 生效"
)

# ---- 自动更新开关 (G66)：受管 cron 条目，仅调用既有带校验的 self_update ----
_UPDATE_CRON_FILE="/etc/cron.d/fusionbox-update"

self_update_cron() {
  [[ $EUID -eq 0 ]] || { echo "需要 root 权限"; return 1; }
  local action="${1:-status}"
  case "$action" in
    status)
      if [[ -f "$_UPDATE_CRON_FILE" ]]; then
        msg_ok "自动更新: 已启用（每周日 03:07）"
        cat "$_UPDATE_CRON_FILE"
      else
        msg "  自动更新: 未启用（fusionbox update --cron on 开启）"
      fi
      ;;
    on)
      [[ -x /usr/local/bin/fusionbox ]] || { msg_err "仅支持已安装到 /usr/local/bin/fusionbox 的部署"; return 1; }
      if confirm "启用每周自动更新（周日 03:07 自动运行 fusionbox update 并写日志）？"; then
        printf '7 3 * * 0 root /usr/local/bin/fusionbox update >> /root/.config/fusionbox/logs/auto-update.log 2>&1\n' > "$_UPDATE_CRON_FILE"
        chmod 600 "$_UPDATE_CRON_FILE"
        msg_ok "自动更新已启用（cron.d/fusionbox-update）"
        _log_write "自动更新已启用"
      fi
      ;;
    off)
      if [[ -f "$_UPDATE_CRON_FILE" ]]; then
        rm -f "$_UPDATE_CRON_FILE"
        msg_ok "自动更新已关闭"
        _log_write "自动更新已关闭"
      else
        msg_info "本就未启用"
      fi
      ;;
    *)
      msg_err "未知参数: $action（可用: status/on/off）"; return 2 ;;
  esac
}

# ---- Self Uninstall ----
self_uninstall() {
  msg_warn "将删除 FusionBox 本体：$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$FUSION_BASE")")、/usr/local/bin/fusionbox、$FUSION_CONFIG_DIR（业务状态、配置与日志保留）"
  msg_warn "各模块安装的服务（代理、面板、Docker 等）不会被卸载，请先在对应模块内清理"
  confirm "确认卸载 FusionBox 本体？" || { msg_info "已取消"; return 1; }
  [[ "$FUSION_BASE" == /etc/fusionbox ]] || { msg_err "仅支持卸载 /etc/fusionbox 中的安装"; return 1; }
  rm -rf "$FUSION_BASE/src" "$FUSION_BASE/templates"
  rm -f "$FUSION_BASE/fusion.sh" "$FUSION_BASE/install.sh" "$FUSION_BASE/version.txt"
  rm -f /usr/local/bin/fusionbox
  msg_info "业务状态、配置与日志已保留: $FUSION_BASE 和 $FUSION_CONFIG_DIR"
  # 清理 k 命令别名注入
  local rc
  for rc in /root/.bashrc "$HOME/.bashrc"; do
    if [[ -f "$rc" ]] && grep -q "fusionbox/kcmd/aliases.sh" "$rc"; then
      sed -i '/fusionbox\/kcmd\/aliases\.sh/d' "$rc"
    fi
  done
  msg_ok "FusionBox 本体已卸载"
}

# ---- Help ----
show_help() {
  _print_banner
  msg_title "FusionBox 帮助"
  msg ""
  msg "  ${F_BOLD}用法:${F_RESET} fusionbox <命令> [选项]"
  msg ""
  msg "  ${F_BOLD}模块:${F_RESET}"
  msg "  ${F_GREEN}proxy, p${F_RESET}        代理管理 - 多后端代理管理"
  msg "  ${F_GREEN}system, sys${F_RESET}      系统管理 - BBR、基准测试、备份、工具"
  msg "  ${F_GREEN}network, net${F_RESET}     网络工具 - IP、流媒体、测速"
  msg "  ${F_GREEN}web${F_RESET}              网站部署 - LNMP、网站、SSL、反代"
  msg "  ${F_GREEN}panels, tools${F_RESET}    面板与工具 - Docker、面板、实用工具"
  msg "  ${F_GREEN}market${F_RESET}           应用市场 - 一键安装应用"
  msg "  ${F_GREEN}warp${F_RESET}             WARP 管理 - Cloudflare WARP 解锁"
  msg "  ${F_GREEN}workspace, ws${F_RESET}    后台工作区 - Screen/Tmux 管理"
  msg "  ${F_GREEN}cluster, cl${F_RESET}      集群控制 - 多服务器/游戏服务端"
  msg ""
  msg "  ${F_BOLD}命令:${F_RESET}"
  msg "  ${F_GREEN}status${F_RESET}            系统状态概览"
  msg "  ${F_GREEN}update${F_RESET}            更新 FusionBox"
  msg "  ${F_GREEN}uninstall${F_RESET}         卸载 FusionBox 本体"
  msg "  ${F_GREEN}privacy${F_RESET}           隐私与匿名统计设置"
  msg "  ${F_GREEN}version${F_RESET}           显示版本"
  msg "  ${F_GREEN}help${F_RESET}              显示帮助"
  msg ""
  msg "  ${F_BOLD}示例:${F_RESET}"
  msg "  fusionbox proxy add              # 添加代理配置"
  msg "  fusionbox system bbr             # BBR 管理"
  msg "  fusionbox system tools           # 系统工具 (SSH/防火墙/磁盘/...)"
  msg "  fusionbox network speedtest      # 网速测试"
  msg "  fusionbox web lnmp               # 安装 LNMP"
  msg "  fusionbox web deploy             # LDNMP 应用部署"
  msg "  fusionbox web proxy              # 反向代理"
  msg "  fusionbox panels docker          # Docker 管理"
  msg "  fusionbox warp install           # 安装 WARP"
  msg "  fusionbox cluster game           # 游戏服务端"
  msg ""

  # Quick reference per module
  local mod="${1:-all}"
  if [[ "$mod" == "all" ]]; then
    msg "  ${F_BOLD}提示:${F_RESET} fusionbox help <模块> 查看模块详细帮助"
  fi
  pause
}

# ---- Main Menu ----
main_menu() {
  _require_root
  while true; do
    _print_banner

    msg_title "主菜单"
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 代理管理"
    msg "  ${F_GREEN} 2${F_RESET}) 系统管理"
    msg "  ${F_GREEN} 3${F_RESET}) 网络工具"
    msg "  ${F_GREEN} 4${F_RESET}) 网站部署"
    msg "  ${F_GREEN} 5${F_RESET}) 面板与工具"
    msg "  ${F_GREEN} 6${F_RESET}) 应用市场"
    msg "  ${F_GREEN} 7${F_RESET}) WARP 管理"
    msg "  ${F_GREEN} 8${F_RESET}) 后台工作区"
    msg "  ${F_GREEN} 9${F_RESET}) 集群控制与工具"
    msg "  ${F_GREEN}10${F_RESET}) 系统状态"
    msg "  ${F_GREEN}11${F_RESET}) 帮助"
    msg "  ${F_GREEN}12${F_RESET}) $(_tr MSG_PRIVACY_MENU "隐私与匿名统计")"
    msg "  ${F_GREEN} 0${F_RESET}) 退出"
    msg ""
    msg "  $(_tr MSG_ACKNOWLEDGEMENT "棉花云：优质网络提供商 https://www.88sup.com")"
    msg ""

    read -p "请选择 [0-12]: " main_choice || { msg ""; return; }   # stdin 关闭时退出，防死循环

    case "$main_choice" in
      1) route proxy ;;
      2) route system ;;
      3) route network ;;
      4) route web ;;
      5) route panels ;;
      6) route market ;;
      7) route warp ;;
      8) route workspace ;;
      9) route cluster ;;
      10) show_status ; pause ;;
      11) show_help ;;
      12) privacy_menu ;;
      0) msg "再见！"; _log_write "FusionBox 会话已结束"; return ;;
      *) ;;
    esac
  done
}

privacy_menu() {
  while true; do
    _print_banner
    msg_title "$(_tr MSG_PRIVACY_MENU "隐私与匿名统计")"
    msg ""
    privacy_command status
    msg ""
    msg "  ${F_GREEN}1${F_RESET}) On"
    msg "  ${F_GREEN}2${F_RESET}) Off"
    msg "  ${F_GREEN}3${F_RESET}) Reset ID"
    msg "  ${F_GREEN}0${F_RESET}) Back"
    msg ""
    local choice
    read -p "请选择 [0-3]: " choice || return
    case "$choice" in
      1) privacy_command on; pause ;;
      2) privacy_command off; pause ;;
      3) privacy_command reset-id; pause ;;
      0) return ;;
      *) ;;
    esac
  done
}

# ---- Entry ----
if [[ "${FUSION_READONLY:-0}" != "1" ]]; then
  _log_write "FusionBox v$FUSION_VER started with args: $*"
  _telemetry_event heartbeat
fi

# Route the command
route "$@"
