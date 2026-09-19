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

[[ $EUID -ne 0 ]] && msg_err "请以 root 身份运行" && exit 1

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) msg_err "不支持的架构: $ARCH"; exit 1 ;;
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
msg "  ${GREEN}FusionBox 安装程序 ${FB_VERSION}${RESET}"
msg "  ${CYAN}Linux 全能管理工具箱${RESET}"
msg "  ${YELLOW}一站式 Linux 服务器管理解决方案${RESET}"
msg ""

msg_info "检测到: $OS ($ARCH)"

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
    msg "${YELLOW}[WARN]${RESET} 无法保存匿名统计选择，统计保持关闭。"
    CONFIG_general_stats=false
  fi
  _telemetry_event install || true
}

# Offline fallback: install from the directory this script lives in
_do_local_install() {
  _finalize_install "$SCRIPT_DIR"
  msg ""
  msg_ok "FusionBox 本地安装成功！"
  _finish_install_telemetry
  msg "  用法: fusionbox   （主菜单）   fusionbox help   （帮助）"
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

  msg_info "发现最新稳定版本 $tag，正在下载已校验的 Release 包..."
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
  msg "${YELLOW}[WARN]${RESET} GitHub latest Release API 不可用或受限，回退到 main 分支快照。"
  msg "${YELLOW}[WARN]${RESET} main 快照没有 Release SHA256SUMS，无法提供发布资产级完整性校验。"
  curl -fsSL --connect-timeout 10 --retry 2 \
    "$FUSION_REPO/archive/refs/heads/$FUSION_BRANCH.tar.gz" -o "$TMPDIR/fusionbox.tar.gz" || return 1
  DOWNLOAD_ROOT="FusionBox-$FUSION_BRANCH"
  DOWNLOAD_SOURCE="main branch fallback (no release checksum)"
}

if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
  if [[ -f "$SCRIPT_DIR/fusion.sh" ]]; then
    _do_local_install
  fi
  msg_err "网络不可用且未找到本地文件"
  exit 1
fi

for dep in curl tar sha256sum sed grep; do
  command -v "$dep" &>/dev/null && continue
  msg_info "正在安装缺少的依赖: $dep..."
  case "$OS" in
    ubuntu|debian) apt-get install -y curl tar coreutils sed grep ;;
    centos|rhel|fedora) yum install -y curl tar coreutils sed grep ;;
    alpine) apk add curl tar coreutils sed grep ;;
    *) msg_err "无法自动安装依赖 $dep（未知系统: $OS）"; exit 1 ;;
  esac
  command -v "$dep" &>/dev/null || { msg_err "依赖安装失败: $dep"; exit 1; }
done

# 先下载解压到临时目录，全部成功后才替换现有安装（避免"先删后下"失败导致两空）
msg_info "正在下载 FusionBox..."
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
    _download_main_fallback || { msg_err "main 分支快照下载失败"; exit 1; }
  else
    msg_err "Release 资产下载或 SHA256 校验失败；为避免降级安装未校验内容，安装已停止"
    exit 1
  fi
fi

_validate_archive "$TMPDIR/fusionbox.tar.gz" "$DOWNLOAD_ROOT" || {
  msg_err "归档结构或路径安全检查失败"
  exit 1
}
tar xzf "$TMPDIR/fusionbox.tar.gz" -C "$TMPDIR"
[[ -f "$TMPDIR/$DOWNLOAD_ROOT/fusion.sh" && -f "$TMPDIR/$DOWNLOAD_ROOT/src/lib/deploy.sh" ]] || {
  msg_err "解压后的 Release 结构无效"
  exit 1
}
msg_info "下载来源: $DOWNLOAD_SOURCE"

msg_info "正在安装 FusionBox 到 $FUSION_BASE..."
_finalize_install "$TMPDIR/$DOWNLOAD_ROOT"

rm -rf "$TMPDIR"

msg ""
msg_ok "FusionBox 安装成功！"
_finish_install_telemetry
msg ""
msg "  ${BOLD}用法:${RESET}"
msg "  fusionbox              ${CYAN}主菜单${RESET}"
msg "  fusionbox help         ${CYAN}显示帮助${RESET}"
msg "  fusionbox proxy        ${CYAN}代理管理${RESET}"
msg "  fusionbox system       ${CYAN}系统管理${RESET}"
msg "  fusionbox network      ${CYAN}网络工具${RESET}"
msg "  fusionbox web          ${CYAN}网站部署${RESET}"
msg "  fusionbox panels       ${CYAN}面板与工具${RESET}"
msg "  fusionbox market       ${CYAN}应用市场${RESET}"
msg ""
exit 0
