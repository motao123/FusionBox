#!/bin/bash
# FusionBox One-Click Installer

set -e

FUSION_BASE="/etc/fusionbox"
FUSION_REPO="https://github.com/motao123/FusionBox"
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
FB_VERSION="$(tr -d '[:space:]' < "$(cd "$(dirname "$0")" && pwd)/version.txt" 2>/dev/null)"
msg "  ${GREEN}FusionBox 安装程序 ${FB_VERSION}${RESET}"
msg "  ${CYAN}Linux 全能管理工具箱${RESET}"
msg "  ${YELLOW}一站式 Linux 服务器管理解决方案${RESET}"
msg ""

msg_info "检测到: $OS ($ARCH)"

# Shared finisher: tighten permissions, create symlink, seed default config
_finalize_install() {
  # Do not change permissions of existing credentials or business state.
  find "$FUSION_BASE/src" "$FUSION_BASE/templates" -type d -exec chmod 755 {} +
  find "$FUSION_BASE/src" "$FUSION_BASE/templates" -type f -exec chmod 644 {} +
  chmod 755 "$FUSION_BASE/fusion.sh" "$FUSION_BASE/install.sh" 2>/dev/null || true
  ln -sf "$FUSION_BASE/fusion.sh" "$FUSION_BIN"

  mkdir -p "$HOME/.config/fusionbox"
  [[ ! -f "$HOME/.config/fusionbox/config.yaml" ]] && \
    cp "$FUSION_BASE/configs/config.yaml" "$HOME/.config/fusionbox/" 2>/dev/null || true
}

# Offline fallback: install from the directory this script lives in
_do_local_install() {
  local src_dir
  src_dir="$(cd "$(dirname "$0")" && pwd)"
  if [[ "$src_dir" != "$FUSION_BASE" ]]; then
    msg_info "本地安装模式: $src_dir -> $FUSION_BASE"
    mkdir -p "$FUSION_BASE"
    cp -rf "$src_dir/"* "$FUSION_BASE/" || { msg_err "复制文件失败"; exit 1; }
  else
    msg_info "源目录即安装目录，就地修复权限与软链接"
  fi
  _finalize_install
  msg ""
  msg_ok "FusionBox 本地安装成功！"
  msg "  用法: fusionbox   （主菜单）   fusionbox help   （帮助）"
  exit 0
}

if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
  if [[ -f "$(cd "$(dirname "$0")" && pwd)/fusion.sh" ]]; then
    _do_local_install
  fi
  msg_err "网络不可用且未找到本地文件"
  exit 1
fi

for dep in curl tar; do
  command -v "$dep" &>/dev/null || {
    msg_info "正在安装 $dep..."
    case "$OS" in
      ubuntu|debian) apt-get install -y "$dep" ;;
      centos|rhel|fedora) yum install -y "$dep" ;;
      alpine) apk add "$dep" ;;
    esac
  }
done

# 先下载解压到临时目录，全部成功后才替换现有安装（避免"先删后下"失败导致两空）
msg_info "正在下载 FusionBox..."
TMPDIR=$(mktemp -d)
curl -fsSL "$FUSION_REPO/archive/$FUSION_BRANCH.tar.gz" -o "$TMPDIR/fusionbox.tar.gz" || {
  msg_err "下载失败"
  rm -rf "$TMPDIR"
  exit 1
}

tar xzf "$TMPDIR/fusionbox.tar.gz" -C "$TMPDIR"
ls "$TMPDIR/FusionBox-$FUSION_BRANCH/fusion.sh" >/dev/null 2>&1 || \
ls "$TMPDIR/FusionBox-main/fusion.sh" >/dev/null 2>&1 || {
  msg_err "解压失败"
  rm -rf "$TMPDIR"
  exit 1
}

msg_info "正在安装 FusionBox 到 $FUSION_BASE..."
mkdir -p "$FUSION_BASE"
cp -rf "$TMPDIR/FusionBox-$FUSION_BRANCH/"* "$FUSION_BASE/" 2>/dev/null || \
cp -rf "$TMPDIR/FusionBox-main/"* "$FUSION_BASE/" 2>/dev/null || {
  msg_err "复制文件失败"
  rm -rf "$TMPDIR"
  exit 1
}

_finalize_install

rm -rf "$TMPDIR"

msg ""
msg_ok "FusionBox 安装成功！"
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
