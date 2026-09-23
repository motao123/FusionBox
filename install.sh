#!/bin/bash
# FusionBox One-Click Installer

set -e

FUSION_BASE="/etc/fusionbox"
FUSION_REPO="https://github.com/motao123/FusionBox"
FUSION_API="https://api.github.com/repos/motao123/FusionBox"
FUSION_BRANCH="main"
FUSION_BIN="/usr/local/bin/fusionbox"

RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; CYAN='\e[36m'; BOLD='\e[1m'; RESET='\e[0m'
msg()     { echo -e "$*"; }
msg_ok()  { msg "${GREEN}[OK]${RESET} $*"; }
msg_err() { msg "${RED}[ERROR]${RESET} $*"; }
msg_info(){ msg "${CYAN}[INFO]${RESET} $*"; }

# ── 语言包（安装器双语文案）──────────────────────────────────────────────
# 下载/解压之前仓库文件尚未就位，用内置表兜底；解压出 src/i18n 后切换为完整语言包。
# 内置表由 scripts/i18n_extract.py 的同源数据生成，tests/test_i18n.py 会校验不漂移。
case "${FUSION_LANG:-${LANG:-en}}" in
  zh*) FUSION_ILANG=zh_CN ;;
  *)   FUSION_ILANG=en ;;
esac

declare -A _IL_ZH=() _IL_EN=()
_il_pack_loaded=0

# 从目录加载完整语言包（幂等；两个语言包都载入，按 FUSION_ILANG 取用）
_il_load_from() {
  local dir="$1" v
  [[ -f "$dir/zh_CN.sh" && -f "$dir/en.sh" ]] || return 1
  . "$dir/zh_CN.sh" 2>/dev/null || return 1
  while IFS= read -r v; do [[ -n "$v" ]] && _IL_ZH[$v]="${!v}"; done < <(compgen -v | grep -E "^MSG_[A-Z0-9_]+$")
  for v in $(compgen -v | grep -E "^MSG_[A-Z0-9_]+$"); do unset "$v"; done
  . "$dir/en.sh" 2>/dev/null || return 1
  while IFS= read -r v; do [[ -n "$v" ]] && _IL_EN[$v]="${!v}"; done < <(compgen -v | grep -E "^MSG_[A-Z0-9_]+$")
  for v in $(compgen -v | grep -E "^MSG_[A-Z0-9_]+$"); do unset "$v"; done
  _il_pack_loaded=1
  return 0
}

# L <key> [args...]：优先语言包，其次内置表
L() {
  local key="$1"; shift || true
  local fmt=""
  if [[ "$FUSION_ILANG" == "en" ]]; then
    fmt="${_IL_EN[$key]:-${_IL_ZH[$key]:-}}"
  else
    fmt="${_IL_ZH[$key]:-${_IL_EN[$key]:-}}"
  fi
  [[ -n "$fmt" ]] || fmt="$key"
  if (( $# )); then printf -- "$fmt" "$@"; else printf '%s' "$fmt"; fi
}

# 内置早期表（仅下载前会用到的条目）
_IL_ZH[MSG_INST_0001]="请以 root 身份运行"
_IL_ZH[MSG_INST_0002]="不支持的架构: %s"
_IL_ZH[MSG_INST_0003]="  %sFusionBox 安装程序 %s%s"
_IL_ZH[MSG_INST_0004]="  %sLinux 全能管理工具箱%s"
_IL_ZH[MSG_INST_0005]="  %s一站式 Linux 服务器管理解决方案%s"
_IL_ZH[MSG_INST_0006]="检测到: %s (%s)"
_IL_ZH[MSG_INST_0010]="发现最新稳定版本 %s，正在下载已校验的 Release 包..."
_IL_ZH[MSG_INST_0011]="%s[WARN]%s GitHub latest Release API 不可用或受限，回退到 main 分支快照。"
_IL_ZH[MSG_INST_0012]="%s[WARN]%s main 快照没有 Release SHA256SUMS，无法提供发布资产级完整性校验。"
_IL_ZH[MSG_INST_0013]="网络不可用且未找到本地文件"
_IL_ZH[MSG_INST_0014]="正在安装缺少的依赖: %s..."
_IL_ZH[MSG_INST_0015]="无法自动安装依赖 %s（未知系统: %s）"
_IL_ZH[MSG_INST_0016]="依赖安装失败: %s"
_IL_ZH[MSG_INST_0017]="正在下载 FusionBox..."
_IL_ZH[MSG_INST_0018]="main 分支快照下载失败"
_IL_ZH[MSG_INST_0019]="Release 资产下载或 SHA256 校验失败；为避免降级安装未校验内容，安装已停止"
_IL_EN[MSG_INST_0001]="Please run as root"
_IL_EN[MSG_INST_0002]="Unsupported architecture: %s"
_IL_EN[MSG_INST_0003]="  %sFusionBox installer %s%s"
_IL_EN[MSG_INST_0004]="  %sThe all-in-one Linux toolbox%s"
_IL_EN[MSG_INST_0005]="  %sOne-stop Linux server management%s"
_IL_EN[MSG_INST_0006]="Detected: %s (%s)"
_IL_EN[MSG_INST_0010]="Latest stable release %s found; downloading the checksum-verified Release package..."
_IL_EN[MSG_INST_0011]="%s[WARN]%s GitHub latest Release API unavailable or rate-limited; falling back to the main branch snapshot."
_IL_EN[MSG_INST_0012]="%s[WARN]%s The main snapshot has no Release SHA256SUMS, so release-level integrity cannot be verified."
_IL_EN[MSG_INST_0013]="Network unavailable and no local files found"
_IL_EN[MSG_INST_0014]="Installing missing dependency: %s..."
_IL_EN[MSG_INST_0015]="Cannot install dependency %s automatically (unknown system: %s)"
_IL_EN[MSG_INST_0016]="Dependency install failed: %s"
_IL_EN[MSG_INST_0017]="Downloading FusionBox..."
_IL_EN[MSG_INST_0018]="Failed to download the main branch snapshot"
_IL_EN[MSG_INST_0019]="Release asset download or SHA256 verification failed; installation stopped to avoid installing unverified content"


[[ $EUID -ne 0 ]] && msg_err "$(L MSG_INST_0001)" && exit 1

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) msg_err "$(L MSG_INST_0002 "$ARCH")"; exit 1 ;;
esac

if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  OS="${ID:-unknown}"
else
  OS="unknown"
fi

msg "${BOLD}${CYAN}"
msg "  ███████╗██╗   ██╗███████╗██╗ ██████╗ ███╗   ██╗██████╗  ██████╗ ██╗  ██╗"
msg "  ██╔════╝██║   ██║██╔════╝██║██╔═══██╗████╗  ██║██╔══██╗██╔═══██╗╚██╗██╔╝"
msg "  █████╗  ██║   ██║███████╗██║██║   ██║██╔██╗ ██║██████╔╝██║   ██║ ╚███╔╝ "
msg "  ██╔══╝  ██║   ██║╚════██║██║██║   ██║██║╚██╗██║██╔══██╗██║   ██║ ██╔██╗ "
msg "  ██║     ╚██████╔╝███████║██║╚██████╔╝██║ ╚████║██████╔╝╚██████╔╝██╔╝ ██╗"
msg "  ╚═╝      ╚═════╝ ╚══════╝╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
msg "${RESET}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FB_VERSION="unknown"
if [[ -r "$SCRIPT_DIR/version.txt" ]]; then
  FB_VERSION="$(tr -d '[:space:]' < "$SCRIPT_DIR/version.txt")"
fi
msg "$(L MSG_INST_0003 "${GREEN}" "${FB_VERSION}" "${RESET}")"
msg "$(L MSG_INST_0004 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0005 "${YELLOW}" "${RESET}")"
msg ""

msg_info "$(L MSG_INST_0006 "$OS" "$ARCH")"

INSTALL_HAD_CONFIG=0
[[ -e "${HOME:-/root}/.config/fusionbox/config.yaml" || -L "${HOME:-/root}/.config/fusionbox/config.yaml" ]] && INSTALL_HAD_CONFIG=1

# Shared finisher: tighten permissions, create symlink, seed default config
_finalize_install() {
  local source="$1"
  [[ -f "$source/src/lib/deploy.sh" && ! -L "$source/src/lib/deploy.sh" ]] || return 1
  bash -n "$source/src/lib/deploy.sh" || return 1
  source "$source/src/lib/deploy.sh"
  fusion_deploy "$source" "$FUSION_BASE" "$FUSION_BIN"
}

_finish_install_telemetry() {
  local common="$FUSION_BASE/src/lib/common.sh"
  [[ -f "$common" && ! -L "$common" ]] || return 0
  FUSION_SRC="$FUSION_BASE/src"
  source "$common" || return 0
  FUSION_VER="$FB_VERSION"
  if [[ -r "$FUSION_BASE/version.txt" ]]; then
    FUSION_VER="$(tr -d '[:space:]' < "$FUSION_BASE/version.txt")"
  fi
  F_OS="$OS"
  _load_config
  if ! _telemetry_install_consent "$INSTALL_HAD_CONFIG"; then
    msg "$(L MSG_INST_0007 "${YELLOW}" "${RESET}")"
    CONFIG_general_stats=false
  fi
  _telemetry_event install || true
}

# Offline fallback: install from the directory this script lives in
_do_local_install() {
  _il_load_from "$SCRIPT_DIR/src/i18n" || true
_finalize_install "$SCRIPT_DIR"
  msg ""
  msg_ok "$(L MSG_INST_0008)"
  _finish_install_telemetry
  msg "$(L MSG_INST_0009)"
  exit 0
}

_json_string() {
  local key="$1"
  tr -d '\r\n' < "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

_validate_archive() {
  local archive="$1" root="$2" entry target type line
  local listing="$TMPDIR/archive.list" verbose="$TMPDIR/archive.verbose"

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

_download_release() {
  local metadata="$TMPDIR/latest-release.json"
  local tag asset checksum_url expected actual

  if ! curl -fsSL --connect-timeout 10 --retry 2 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      "$FUSION_API/releases/latest" -o "$metadata"; then
    return 2
  fi

  tag="$(_json_string tag_name "$metadata")"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 2
  asset="FusionBox-$tag.tar.gz"
  checksum_url="$FUSION_REPO/releases/download/$tag/SHA256SUMS"

  msg_info "$(L MSG_INST_0010 "$tag")"
  curl -fsSL --connect-timeout 10 --retry 2 \
    "$FUSION_REPO/releases/download/$tag/$asset" -o "$TMPDIR/fusionbox.tar.gz" || return 1
  curl -fsSL --connect-timeout 10 --retry 2 \
    "$checksum_url" -o "$TMPDIR/SHA256SUMS" || return 1

  expected="$(while read -r sum name rest; do
    name="${name#\*}"
    if [[ "$name" == "$asset" && -z "$rest" && "$sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
      printf '%s\n' "${sum,,}"
    fi
  done < "$TMPDIR/SHA256SUMS")"
  [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || return 1
  actual="$(sha256sum "$TMPDIR/fusionbox.tar.gz" | cut -d ' ' -f 1)"
  [[ "$actual" == "$expected" ]] || return 1

  DOWNLOAD_ROOT="FusionBox"
  DOWNLOAD_SOURCE="release $tag"
}

_download_main_fallback() {
  msg "$(L MSG_INST_0011 "${YELLOW}" "${RESET}")"
  msg "$(L MSG_INST_0012 "${YELLOW}" "${RESET}")"
  curl -fsSL --connect-timeout 10 --retry 2 \
    "$FUSION_REPO/archive/refs/heads/$FUSION_BRANCH.tar.gz" -o "$TMPDIR/fusionbox.tar.gz" || return 1
  DOWNLOAD_ROOT="FusionBox-$FUSION_BRANCH"
  DOWNLOAD_SOURCE="main branch fallback (no release checksum)"
}

if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
  if [[ -f "$SCRIPT_DIR/fusion.sh" ]]; then
    _do_local_install
  fi
  msg_err "$(L MSG_INST_0013)"
  exit 1
fi

for dep in curl tar sha256sum sed grep; do
  command -v "$dep" &>/dev/null && continue
  msg_info "$(L MSG_INST_0014 "$dep")"
  case "$OS" in
    ubuntu|debian) apt-get install -y curl tar coreutils sed grep ;;
    centos|rhel|fedora) yum install -y curl tar coreutils sed grep ;;
    alpine) apk add curl tar coreutils sed grep ;;
    *) msg_err "$(L MSG_INST_0015 "$dep" "$OS")"; exit 1 ;;
  esac
  command -v "$dep" &>/dev/null || { msg_err "$(L MSG_INST_0016 "$dep")"; exit 1; }
done

# 先下载解压到临时目录，全部成功后才替换现有安装（避免"先删后下"失败导致两空）
msg_info "$(L MSG_INST_0017)"
TMPDIR=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
DOWNLOAD_ROOT=""
DOWNLOAD_SOURCE=""
if _download_release; then
  :
else
  download_status=$?
  if [[ $download_status -eq 2 ]]; then
    _download_main_fallback || { msg_err "$(L MSG_INST_0018)"; exit 1; }
  else
    msg_err "$(L MSG_INST_0019)"
    exit 1
  fi
fi

_validate_archive "$TMPDIR/fusionbox.tar.gz" "$DOWNLOAD_ROOT" || {
  msg_err "$(L MSG_INST_0020)"
  exit 1
}
tar xzf "$TMPDIR/fusionbox.tar.gz" -C "$TMPDIR"
_il_load_from "$TMPDIR/$DOWNLOAD_ROOT/src/i18n" || true
[[ -f "$TMPDIR/$DOWNLOAD_ROOT/fusion.sh" && -f "$TMPDIR/$DOWNLOAD_ROOT/src/lib/deploy.sh" ]] || {
  msg_err "$(L MSG_INST_0021)"
  exit 1
}
msg_info "$(L MSG_INST_0022 "$DOWNLOAD_SOURCE")"

msg_info "$(L MSG_INST_0023 "$FUSION_BASE")"
_finalize_install "$TMPDIR/$DOWNLOAD_ROOT"

rm -rf "$TMPDIR"

msg ""
msg_ok "$(L MSG_INST_0024)"
_finish_install_telemetry
msg ""
msg "$(L MSG_INST_0025 "${BOLD}" "${RESET}")"
msg "$(L MSG_INST_0026 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0027 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0028 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0029 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0030 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0031 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0032 "${CYAN}" "${RESET}")"
msg "$(L MSG_INST_0033 "${CYAN}" "${RESET}")"
msg ""
exit 0
