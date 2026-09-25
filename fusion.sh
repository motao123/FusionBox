#!/bin/bash
# FusionBox - Ultimate Linux Management Script
# Repository: https://github.com/motao123/FusionBox

# Read-only commands may run without root; everything else (incl. menus) needs root.
FUSION_READONLY=0
case "${1:-}:${2:-}:${3:-}" in
  cluster:oracle:detect|cluster:oracle:status|cluster:oracle:help|cluster:oracle:--help|\
  cluster:oc:detect|cluster:oc:status|cluster:oc:help|cluster:oc:--help|\
  cl:oracle:detect|cl:oracle:status|cl:oracle:help|cl:oracle:--help|\
  cl:oc:detect|cl:oc:status|cl:oc:help|cl:oc:--help)
    FUSION_READONLY=1 ;;
esac

# 纯帮助入口可以无 root 运行：`fusionbox help`、`fusionbox version`，
# 以及模块帮助 `fusionbox <模块> help`（等价于 `fusionbox help <模块>`）。
# 必须把 $2 纳入判断，否则模块帮助会被下面的 root 门禁误拦（只读帮助不该要 root）。
FUSION_HELPONLY=0
# `fusionbox <模块> help`（帮助关键字在 $2）
case "${2:-}" in
  help|-h|--help)
    case "${1:-}" in
      proxy|p|system|sys|s|network|net|n|web|w|lnmp|panels|panel|tools|t|\
      market|m|apps|warp|workspace|ws|cluster|cl)
        FUSION_HELPONLY=1 ;;
    esac ;;
esac
# `fusionbox panels docker help`（帮助关键字在 $3）
case "${1:-}" in
  panels|panel|tools|t)
    case "${2:-}" in
      docker|dk) case "${3:-}" in help|-h|--help) FUSION_HELPONLY=1 ;; esac ;;
    esac ;;
esac

case "${1:-}" in
  help|h|version|v) ;;
  privacy)
    [[ "${2:-status}" == status || $EUID -eq 0 ]] || { echo "$(L MSG_MAIN_0001)"; exit 1; } ;;
  lang|language)
    [[ "${2:-status}" == status || $EUID -eq 0 ]] || { echo "$(L MSG_MAIN_0001)"; exit 1; } ;;
  *) [[ $EUID -eq 0 || $FUSION_READONLY -eq 1 || $FUSION_HELPONLY -eq 1 ]] || { echo "$(L MSG_MAIN_0001)"; exit 1; } ;;
esac

# Resolve script path through symlinks (install.sh links /usr/local/bin/fusionbox
# to /etc/fusionbox/fusion.sh; using $0 directly would break the install layout)
_source_path="${BASH_SOURCE[0]}"
# 语言包必须在根权限门禁之前就绪：门禁提示同样需要本地化。
_fb_resolve_self() {
  while [[ -L "$_source_path" ]]; do
  _link_dir="$(cd "$(dirname "$_source_path")" && pwd)"
  _source_path="$(readlink "$_source_path")"
  [[ $_source_path != /* ]] && _source_path="$_link_dir/$_source_path"
done
  export FUSION_BASE="$(cd "$(dirname "$_source_path")" && pwd)"
  export FUSION_SRC="$FUSION_BASE/src"
}
_fb_resolve_self

if [[ -f "$FUSION_SRC/lib/i18n.sh" ]]; then
  . "$FUSION_SRC/lib/i18n.sh"
  [[ -n "${FUSION_LANG:-}" ]] && F_LANG="$FUSION_LANG"
  _i18n_init
fi

# Inspection exits before normal startup loads configuration, logging or telemetry.
if [[ $FUSION_READONLY -eq 1 ]]; then
  exec python3 -B "$FUSION_SRC/lib/oracle_tools.py" "${@:3}"
fi
case "${1:-}:${2:-}" in
  system:ssh-preflight|sys:ssh-preflight|s:ssh-preflight)
    exec python3 -B "$FUSION_SRC/lib/system_safety.py" ssh-preflight "${@:3}" ;;
esac

. "$FUSION_SRC/init.sh"

# ---- Command Router ----
# Routes user commands to the appropriate module

route() {
  local cmd="$1"; shift || true

  # 统一帮助入口：`fusionbox <模块> help` 与 `fusionbox help <模块>` 完全等价。
  # 在这里归一化，而不是让 9 个模块各自调用 show_help——模块保持可独立 source。
  if [[ $# -eq 1 && ( "$1" == "help" || "$1" == "-h" || "$1" == "--help" ) ]]; then
    case "$cmd" in
      proxy|p|system|sys|s|network|net|n|web|w|lnmp|panels|panel|tools|t|\
      market|m|apps|warp|workspace|ws|cluster|cl)
        show_help "$cmd"; return $? ;;
    esac
  fi

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
      msg "$(L MSG_MAIN_0002 "$FUSION_VER")"
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
    # 界面语言：查看/切换（写入 config.yaml 的 general.lang）
    lang|language)
      lang_command "$@"
      ;;
    # FusionBox 自身日志（主菜单/帮助里也可发现）
    log|logs)
      show_logs "${1:-200}"
      ;;
    # 救援指引：出事了该敲什么
    rescue)
      _load_module "system"
      system_rescue "$@"
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
      msg_err "$(L MSG_MAIN_0003 "$cmd")"
      msg_info "$(L MSG_MAIN_0004)"
      return 1
      ;;
  esac
}

# ---- Status Overview ----
show_status() {
  _print_banner
  msg_title "$(L MSG_MAIN_0005)"
  msg ""
  msg "  ${F_BOLD}CPU:${F_RESET} $(_cpu_cores_display) | $(free -h | awk '/Mem/{print $2}') RAM"
  msg "  ${F_BOLD}Disk:${F_RESET} $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 ")"}')"
  msg "  ${F_BOLD}Kernel:${F_RESET} $F_KERNEL"
  msg "  ${F_BOLD}OS:${F_RESET} $F_OS_NAME $F_OS_VER"
  msg ""
  show_dependency_status
  msg ""

  # Check proxy status
  local proxy_status="$(L MSG_MAIN_0110)"
  if [[ -f /etc/fusionbox/proxy/current_backend ]]; then
    if systemctl is-active fusionbox-proxy &>/dev/null; then
      proxy_status="$(L MSG_MAIN_0111)"
    else
      proxy_status="$(L MSG_MAIN_0112)"
    fi
  fi
  _module_status "$(L MOD_PROXY)" "$proxy_status"

  # Check 233boy sing-box
  if [[ -x /usr/local/bin/sing-box && -d /etc/sing-box/sh ]]; then
    local sb_st
    if systemctl is-active sing-box &>/dev/null; then
      sb_st="$(L MSG_MAIN_0111)"
    else
      sb_st="$(L MSG_MAIN_0112)"
    fi
    _module_status "sing-box(233boy)" "$sb_st"
  fi

  # Check BBR
  local bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
  _module_status "BBR" "$bbr_status"

  # Check Docker
  if command -v docker &>/dev/null; then
    _module_status "Docker" "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "$(L MSG_MAIN_0006)")"
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
# 与 install.sh 同源的镜像后备：GitHub 不可达时更新检查改走 CNB Release
# （资产与 GitHub 逐字节一致，仍过 SHA256SUMS 校验）。环境变量可覆盖。
FUSION_MIRROR="${FUSION_MIRROR:-https://cnb.cool/code_free/FusionBox}"

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

# CNB 镜像更新后备（静默尝试，不打印提示、不新增语言包键）：307 Location 匿名
# 发现最新 tag，Release 资产 + SHA256SUMS 同源校验，产物写入 $1/ 下与 GitHub 路径
# 相同的文件名；通过校验返回 0 并把 tag 记入 _UPDATE_MIRROR_TAG。校验不过不落系统。
_update_from_mirror() {
  local tmpdir="$1" loc tag asset expected actual
  [[ -n "$FUSION_MIRROR" ]] || return 1
  loc="$(curl -fsSI --connect-timeout 10 --retry 2 \
    "$FUSION_MIRROR/-/releases/latest" 2>/dev/null | tr -d '\r' \
    | sed -n 's#^[Ll]ocation:[[:space:]].*/-/releases/tag/##p' | tail -n 1)"
  [[ "$loc" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  tag="$loc"
  asset="FusionBox-$tag.tar.gz"
  if [[ "${tag#v}" == "$FUSION_VER" ]]; then
    # 镜像最新版与当前一致：免去整包空下载，由调用方提前返回"已是最新"
    _UPDATE_MIRROR_TAG="$tag"
    _UPDATE_MIRROR_SAME=1
    return 0
  fi
  _UPDATE_MIRROR_SAME=0
  _update_download "$FUSION_MIRROR/-/releases/download/$tag/$asset" "$tmpdir/fusionbox.tar.gz" || return 1
  _update_download "$FUSION_MIRROR/-/releases/download/$tag/SHA256SUMS" "$tmpdir/SHA256SUMS" || return 1
  expected="$(while read -r sum name rest; do
    name="${name#\*}"
    if [[ "$name" == "$asset" && -z "$rest" && "$sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
      printf '%s\n' "${sum,,}"
    fi
  done < "$tmpdir/SHA256SUMS")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual="$(sha256sum "$tmpdir/fusionbox.tar.gz" | cut -d ' ' -f 1)" || return 1
  [[ "$actual" == "$expected" ]] || return 1
  _UPDATE_MIRROR_TAG="$tag"
  return 0
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

# Extract one version的说明段落（来自面向使用者的 docs/release-notes.md）。
# Prints the section body (without trailing blank lines) and returns 0 when found.
_update_release_notes_section() {
  local file="$1" version="$2"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  local prefix="$version"
  awk -v ver="$prefix" '
    BEGIN { printing = 0; found = 0 }
    /^## / {
      title = $0
      sub(/^##[[:space:]]+/, "", title)
      sub(/^v/, "", title)
      if (printing == 1) { exit }
      if (index(title, ver) == 1) { printing = 1; found = 1; next }
      next
    }
    printing == 1 { print }
    END { if (found == 0) exit 1 }
  ' "$file"
}

# Show what changed in this update, read from the (already verified) extracted archive.
_update_show_notes() {
  local root="$1" version="$2" notes body
  notes="$root/docs/release-notes.md"
  body="$(_update_release_notes_section "$notes" "$version")" || {
    msg "  $(_tr MSG_UPDATE_NOTES_UNAVAILABLE)"
    return 0
  }
  [[ -n "$body" ]] || { msg "  $(_tr MSG_UPDATE_NOTES_UNAVAILABLE)"; return 0; }
  msg ""
  local title_fmt; title_fmt=$(_tr MSG_UPDATE_NOTES_TITLE "本次更新内容 %s")
  # shellcheck disable=SC2059
  msg_title "$(printf "$title_fmt" "v$version")"
  while IFS= read -r line; do
    [[ -n "$line" ]] && msg "  $line" || msg ""
  done <<< "$body"
  msg ""
}

self_update() (
  local tmpdir metadata tag asset expected actual archive_root remote_ver download_status=0
  tmpdir=$(mktemp -d) || return 1
  trap 'rm -rf -- "$tmpdir"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  msg_info "$(L MSG_MAIN_0007)"

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
        msg_ok "$(L MSG_MAIN_0008)"
        return 0
      fi
      _version_is_newer "$remote_ver" "$FUSION_VER" || {
        msg_warn "$(L MSG_MAIN_0009 "$remote_ver" "$FUSION_VER")"
        return 0
      }
      msg_info "$(L MSG_MAIN_0010 "$tag")"
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
        msg_err "$(L MSG_MAIN_0011)"
        return 1
      fi
    else
      download_status=2
    fi
  else
    download_status=2
  fi

  if [[ $download_status -eq 2 ]]; then
    # GitHub 不可达或应答非法：先静默试 CNB 镜像（Release 资产与 GitHub 逐字节一致
    # 且带 SHA256SUMS 校验，优于 main 快照回落）；镜像也失败才回落 main 快照。
    if _update_from_mirror "$tmpdir"; then
      if [[ "${_UPDATE_MIRROR_SAME:-0}" == 1 ]]; then
        msg_ok "$(L MSG_MAIN_0008)"
        return 0
      fi
      tag="$_UPDATE_MIRROR_TAG"
      archive_root="FusionBox"
      download_status=0
    else
      msg "$(L MSG_MAIN_0012 "${F_YELLOW}" "${F_RESET}")"
      msg "$(L MSG_MAIN_0013 "${F_YELLOW}" "${F_RESET}")"
      _update_download "$FUSION_REPO/archive/refs/heads/main.tar.gz" "$tmpdir/fusionbox.tar.gz" || return 1
      archive_root="FusionBox-main"
      tag=""
    fi
  fi

  _update_validate_archive "$tmpdir/fusionbox.tar.gz" "$archive_root" "$tmpdir" || {
    msg_err "$(L MSG_MAIN_0014)"
    return 1
  }
  tar xzf "$tmpdir/fusionbox.tar.gz" -C "$tmpdir" || return 1
  [[ -f "$tmpdir/$archive_root/fusion.sh" && ! -L "$tmpdir/$archive_root/fusion.sh" &&
     -f "$tmpdir/$archive_root/src/lib/deploy.sh" && ! -L "$tmpdir/$archive_root/src/lib/deploy.sh" ]] || return 1
  remote_ver="$(tr -d '[:space:]' < "$tmpdir/$archive_root/version.txt")" || return 1
  [[ "$remote_ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ -z "$tag" || "$remote_ver" == "${tag#v}" ]] || {
    msg_err "$(L MSG_MAIN_0015)"
    return 1
  }
  if [[ "$remote_ver" == "$FUSION_VER" ]]; then
    msg_ok "$(L MSG_MAIN_0008)"
    return 0
  fi
  _version_is_newer "$remote_ver" "$FUSION_VER" || {
    msg_warn "$(L MSG_MAIN_0016 "$remote_ver" "$FUSION_VER")"
    return 0
  }
  # 加载刚下载并已通过校验的那份 deploy.sh，而不是机器上旧版那份：部署动作属于新版本，
  # 用旧文件会让 deploy.sh 里的改动（例如创建 fb/FB 快捷命令）推迟到下一次更新才落地。
  bash -n "$tmpdir/$archive_root/src/lib/deploy.sh" || return 1
  source "$tmpdir/$archive_root/src/lib/deploy.sh" || return 1
  fusion_validate_release "$tmpdir/$archive_root" || return 1
  fusion_deploy "$tmpdir/$archive_root" "$FUSION_BASE" || return 1
  FUSION_VER="$remote_ver"
  _telemetry_event update
  msg_ok "$(L MSG_MAIN_0017)"
  _update_show_notes "$tmpdir/$archive_root" "$remote_ver"
)

# ---- 自动更新开关 (G66)：受管 cron 条目，仅调用既有带校验的 self_update ----
_UPDATE_CRON_FILE="/etc/cron.d/fusionbox-update"

self_update_cron() {
  [[ $EUID -eq 0 ]] || { echo "$(L MSG_MAIN_0001)"; return 1; }
  local action="${1:-status}"
  case "$action" in
    status)
      if [[ -f "$_UPDATE_CRON_FILE" ]]; then
        msg_ok "$(L MSG_MAIN_0018)"
        cat "$_UPDATE_CRON_FILE"
      else
        msg "$(L MSG_MAIN_0019)"
      fi
      ;;
    on)
      [[ -x /usr/local/bin/fusionbox ]] || { msg_err "$(L MSG_MAIN_0020)"; return 1; }
      if confirm "$(L MSG_MAIN_0113)"; then
        printf '7 3 * * 0 root /usr/local/bin/fusionbox update >> /root/.config/fusionbox/logs/auto-update.log 2>&1\n' > "$_UPDATE_CRON_FILE"
        chmod 600 "$_UPDATE_CRON_FILE"
        msg_ok "$(L MSG_MAIN_0021)"
        _log_write "$(L MSG_MAIN_0114)"
      fi
      ;;
    off)
      if [[ -f "$_UPDATE_CRON_FILE" ]]; then
        rm -f "$_UPDATE_CRON_FILE"
        msg_ok "$(L MSG_MAIN_0022)"
        _log_write "$(L MSG_MAIN_0115)"
      else
        msg_info "$(L MSG_MAIN_0023)"
      fi
      ;;
    *)
      msg_err "$(L MSG_MAIN_0024 "$action")"; return 2 ;;
  esac
}

# ---- Self Uninstall ----
self_uninstall() {
  local _body_dir
  _body_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$FUSION_BASE")")"
  msg_warn "$(L MSG_MAIN_0104 "$_body_dir" "$FUSION_CONFIG_DIR")"
  msg_warn "$(L MSG_MAIN_0025)"
  confirm "$(L MSG_MAIN_0107)" || { msg_info "$(L MSG_MAIN_0026)"; return 1; }
  [[ "$FUSION_BASE" == /etc/fusionbox ]] || { msg_err "$(L MSG_MAIN_0027)"; return 1; }
  rm -rf "$FUSION_BASE/src" "$FUSION_BASE/templates"
  rm -f "$FUSION_BASE/fusion.sh" "$FUSION_BASE/install.sh" "$FUSION_BASE/version.txt"
  rm -f /usr/local/bin/fusionbox
  # 快捷命令只在确实指向本脚本时删除，同名的别人命令不碰
  local _alias _target
  for _alias in fb FB; do
    _target="/usr/local/bin/$_alias"
    if [[ -L "$_target" && "$(readlink -m -- "$_target")" == "$FUSION_BASE/fusion.sh" ]]; then
      rm -f "$_target"
    fi
  done
  msg_info "$(L MSG_MAIN_0028 "$FUSION_BASE" "$FUSION_CONFIG_DIR")"
  # 清理 k 命令别名注入
  local rc
  for rc in /root/.bashrc "$HOME/.bashrc"; do
    if [[ -f "$rc" ]] && grep -q "fusionbox/kcmd/aliases.sh" "$rc"; then
      sed -i '/fusionbox\/kcmd\/aliases\.sh/d' "$rc"
    fi
  done
  # 收尾：整个主体目录移除（含部署拷入的 configs/ 与历史 .fusionbox-backup.*，
  # 它们是程序体的一部分；用户数据在 $HOME/.config/fusionbox，设计上保留）。
  # 上一行已断言 FUSION_BASE == /etc/fusionbox，此处整体删除是安全的。
  rm -rf "$FUSION_BASE"
  msg_ok "$(L MSG_MAIN_0029)"
}

# ---- Help ----
# 模块帮助分发表：别名 -> "<模块文件> <帮助函数> <显示名>"
# 只读入口（非 root 也可用），新增模块时在此登记即可被 `fusionbox help <模块>` 命中。
_help_module_spec() {
  case "${1:-}" in
    proxy|p)              printf '%s\n' "proxy proxy_help $(L MOD_PROXY)" ;;
    system|sys|s)         printf '%s\n' "system system_help $(L MOD_SYSTEM)" ;;
    network|net|n)        printf '%s\n' "network network_help $(L MOD_NETWORK)" ;;
    web|w|lnmp)           printf '%s\n' "web web_help $(L MOD_WEB)" ;;
    panels|panel|tools|t) printf '%s\n' "panels panels_help $(L MOD_PANELS)" ;;
    market|m|apps)        printf '%s\n' "market market_help $(L MOD_MARKET)" ;;
    warp)                 printf '%s\n' "warp warp_help $(L MOD_WARP)" ;;
    workspace|ws)         printf '%s\n' "workspace workspace_help $(L MOD_WORKSPACE)" ;;
    cluster|cl)           printf '%s\n' "cluster cluster_help $(L MOD_CLUSTER)" ;;
    *) return 1 ;;
  esac
}

# 帮助里的本机探测必须有界：`docker version` 等在守护进程未运行时可能长时间阻塞，
# 帮助不应该因此卡住，因此统一加 3 秒超时（无 timeout 命令时退化为直接执行）。
# 注意：探测结果本身是「调用瞬间的宿主机状态」，两次调用之间可以合法地不同，
# 因此任何「两种写法输出一致」的断言都必须先归一化这一行（见 tests/）。
_help_probe() {
  if command -v timeout &>/dev/null; then
    timeout 3 "$@" 2>/dev/null
  else
    "$@" 2>/dev/null
  fi
}

# 本机安装状态探测（纯只读：只查文件/命令/服务，不做任何修改）
# 帮助内容列出的是“能力清单”，与“本机装没装”是两件事，这里把后者补齐。
_help_module_state() {
  local present=()
  case "$1" in
    proxy)
      if _singbox_233_installed 2>/dev/null; then
        msg_ok "$(L MSG_MAIN_0030)"
      elif [[ -d /etc/fusionbox/proxy/bin && -n "$(ls -A /etc/fusionbox/proxy/bin 2>/dev/null)" ]]; then
        msg_ok "$(L MSG_MAIN_0031)"
      else
        msg_warn "$(L MSG_MAIN_0032)"
      fi
      ;;
    system)
      msg_ok "$(L MSG_MAIN_0033)"
      ;;
    network)
      msg_ok "$(L MSG_MAIN_0033)"
      ;;
    web)
      command -v nginx &>/dev/null && present+=("nginx $(_help_probe nginx -v 2>&1 | awk -F/ '{print $2}')")
      command -v php   &>/dev/null && present+=("php $(_help_probe php -r 'echo PHP_VERSION;')")
      command -v mysql &>/dev/null && present+=("mysql")
      if [[ ${#present[@]} -gt 0 ]]; then
        msg_ok "$(L MSG_MAIN_0034 "${present[*]}")"
      else
        msg_warn "$(L MSG_MAIN_0035)"
      fi
      ;;
    panels)
      if command -v docker &>/dev/null; then
        # `docker version` 比 `docker info` 轻得多（不枚举容器/镜像），在有界探测下
        # 更不容易因超时出现「同一台机器两次结果不同」。超时只说明守护进程没在
        # 时限内回话，不等于没装，因此文案不替它下结论。
        local dver; dver="$(_help_probe docker version --format '{{.Server.Version}}')"
        msg_ok "$(L MSG_MAIN_0105 "${dver:-$(L MSG_MAIN_0106)}")"
      else
        msg_warn "$(L MSG_MAIN_0036)"
      fi
      ;;
    market)
      msg_ok "$(L MSG_MAIN_0037)"
      ;;
    warp)
      if command -v warp-cli &>/dev/null; then
        msg_ok "$(L MSG_MAIN_0038)"
      else
        msg_warn "$(L MSG_MAIN_0039)"
      fi
      ;;
    workspace)
      command -v screen &>/dev/null && present+=("screen")
      command -v tmux   &>/dev/null && present+=("tmux")
      if [[ ${#present[@]} -gt 0 ]]; then
        msg_ok "$(L MSG_MAIN_0034 "${present[*]}")"
      else
        msg_warn "$(L MSG_MAIN_0040)"
      fi
      ;;
    cluster)
      local node_count=0
      if [[ -f /etc/fusionbox/cluster/nodes.conf ]]; then
        node_count=$(grep -cve '^[[:space:]]*$' /etc/fusionbox/cluster/nodes.conf 2>/dev/null || echo 0)
      fi
      msg_ok "$(L MSG_MAIN_0041 "$node_count")"
      ;;
  esac
}

show_help() {
  _print_banner
  local mod="${1:-}"

  # `fusionbox help <模块>`：直接把该模块完整的 <模块>_help() 打出来。
  # 返回码：0 成功 / 1 未知模块 / 2 模块加载失败，便于脚本判断。
  if [[ -n "$mod" && "$mod" != "all" ]]; then
    local spec module helpfn label
    if ! spec="$(_help_module_spec "$mod")"; then
      msg_err "$(L MSG_MAIN_0042 "$mod")"
      msg ""
      msg "$(L MSG_MAIN_0043)"
      msg "$(L MSG_MAIN_0044)"
      msg ""
      [[ -t 0 ]] && pause    # 非交互下不暂停，保证退出码能传回调用脚本
      return 1
    fi
    read -r module helpfn label <<< "$spec"
    if ! _load_module "$module"; then
      msg_err "$(L MSG_MAIN_0045 "$module" "$module")"
      [[ -t 0 ]] && pause
      return 2
    fi
    "$helpfn"
    msg "$(L MSG_MAIN_0046 "${F_BOLD}" "${label}" "${F_RESET}")"
    msg "    $(_help_module_state "$module")"
    msg ""
    msg "$(L MSG_MAIN_0047 "${F_BOLD}" "${F_RESET}" "$module" "$module")"
    msg "$(L MSG_MAIN_0048 "${F_BOLD}" "${F_RESET}")"
    msg ""
    pause
    return 0
  fi

  msg_title "$(L MSG_MAIN_0049)"
  msg ""
  msg "$(L MSG_MAIN_0050 "${F_BOLD}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_MAIN_0051 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0052 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0053 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0054 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0055 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0056 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0057 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0058 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0059 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0060 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_MAIN_0061 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0062 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0063 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0064 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0065 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0066 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0067 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0068 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0108 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0069 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_MAIN_0070 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0071)"
  msg "$(L MSG_MAIN_0072)"
  msg "$(L MSG_MAIN_0073)"
  msg "$(L MSG_MAIN_0074)"
  msg "$(L MSG_MAIN_0075)"
  msg "$(L MSG_MAIN_0076)"
  msg "$(L MSG_MAIN_0077)"
  msg "$(L MSG_MAIN_0078)"
  msg "$(L MSG_MAIN_0079)"
  msg "$(L MSG_MAIN_0080)"
  msg "$(L MSG_MAIN_0081)"
  msg "$(L MSG_MAIN_0082)"
  msg ""
  msg "$(L MSG_MAIN_0083 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0084)"
  msg "$(L MSG_MAIN_0085)"
  msg ""
  msg "$(L MSG_MAIN_0086 "${F_BOLD}" "${F_RESET}")"
  msg "$(L MSG_MAIN_0087)"
  msg "$(L MSG_MAIN_0088)"
  msg "$(L MSG_MAIN_0089)"
  msg ""
  pause
}

# ---- Main Menu ----
main_menu() {
  _require_root
  while true; do
    _print_banner

    msg_title "$(L MSG_MAIN_0090)"
    msg ""
    # Dependency self-check first: users must know what is missing before they
    # hit a failure, and before the acknowledgement banner.
    show_dependency_status
    msg ""
    msg "$(L MSG_MAIN_0091 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0092 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0093 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0094 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0095 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0096 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0097 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0098 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0099 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0100 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_MAIN_0101 "${F_GREEN}" "${F_RESET}")"
    msg "  ${F_GREEN}12${F_RESET}) $(_tr MSG_PRIVACY_MENU "隐私与匿名统计")"
    msg "$(L MSG_MAIN_0102 "${F_GREEN}" "${F_RESET}")"
    msg ""
    msg "  $(_tr MSG_ACKNOWLEDGEMENT "棉花云：优质网络提供商 https://www.88sup.com")"
    msg ""

    read -p "$(L MSG_MAIN_0118)" main_choice || { msg ""; return; }   # stdin 关闭时退出，防死循环

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
      0) msg "$(L MSG_MAIN_0103)"; _log_write "$(L MSG_MAIN_0109)"; return ;;
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
    read -p "$(L MSG_MAIN_0119)" choice || return
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
