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
msg "  ${GREEN}FusionBox 安装程序 v1.0.0${RESET}"
msg "  ${CYAN}Linux 全能管理工具箱${RESET}"
msg "  ${YELLOW}一站式 Linux 服务器管理解决方案${RESET}"
msg ""

msg_info "检测到: $OS ($ARCH)"

if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
  if [[ -f "fusion.sh" ]]; then
    msg_info "本地安装模式"
    _do_local_install
    exit 0
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

msg_info "正在安装 FusionBox 到 $FUSION_BASE..."
rm -rf "$FUSION_BASE"
mkdir -p "$FUSION_BASE"

msg_info "正在下载 FusionBox..."
TMPDIR=$(mktemp -d)
curl -fsSL "$FUSION_REPO/archive/$FUSION_BRANCH.tar.gz" -o "$TMPDIR/fusionbox.tar.gz" || {
  msg_err "下载失败"
  rm -rf "$TMPDIR"
  exit 1
}

tar xzf "$TMPDIR/fusionbox.tar.gz" -C "$TMPDIR"
cp -rf "$TMPDIR/fusionbox-$FUSION_BRANCH/"* "$FUSION_BASE/" 2>/dev/null || \
cp -rf "$TMPDIR/fusionbox-main/"* "$FUSION_BASE/" 2>/dev/null || {
  msg_err "解压失败"
  rm -rf "$TMPDIR"
  exit 1
}

chmod -R 755 "$FUSION_BASE"
chmod +x "$FUSION_BASE/fusion.sh"
ln -sf "$FUSION_BASE/fusion.sh" "$FUSION_BIN"

mkdir -p "$HOME/.config/fusionbox"
[[ ! -f "$HOME/.config/fusionbox/config.yaml" ]] && \
  cp "$FUSION_BASE/configs/config.yaml" "$HOME/.config/fusionbox/" 2>/dev/null || true

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
