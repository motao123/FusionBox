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

[[ $EUID -ne 0 ]] && msg_err "Please run as root" && exit 1

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) msg_err "Unsupported architecture: $ARCH"; exit 1 ;;
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
msg "  ${GREEN}FusionBox Installer v1.0.0${RESET}"
msg "  ${CYAN}Ultimate Linux Management Script${RESET}"
msg "  ${YELLOW}The Ultimate Linux Server Management Solution${RESET}"
msg ""

msg_info "Detected: $OS ($ARCH)"

if ! curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
  if [[ -f "fusion.sh" ]]; then
    msg_info "Local install mode"
    _do_local_install
    exit 0
  fi
  msg_err "Network unavailable and no local files found"
  exit 1
fi

for dep in curl tar; do
  command -v "$dep" &>/dev/null || {
    msg_info "Installing $dep..."
    case "$OS" in
      ubuntu|debian) apt-get install -y "$dep" ;;
      centos|rhel|fedora) yum install -y "$dep" ;;
      alpine) apk add "$dep" ;;
    esac
  }
done

msg_info "Installing FusionBox to $FUSION_BASE..."
rm -rf "$FUSION_BASE"
mkdir -p "$FUSION_BASE"

msg_info "Downloading FusionBox..."
TMPDIR=$(mktemp -d)
curl -fsSL "$FUSION_REPO/archive/$FUSION_BRANCH.tar.gz" -o "$TMPDIR/fusionbox.tar.gz" || {
  msg_err "Download failed"
  rm -rf "$TMPDIR"
  exit 1
}

tar xzf "$TMPDIR/fusionbox.tar.gz" -C "$TMPDIR"
cp -rf "$TMPDIR/fusionbox-$FUSION_BRANCH/"* "$FUSION_BASE/" 2>/dev/null || \
cp -rf "$TMPDIR/fusionbox-main/"* "$FUSION_BASE/" 2>/dev/null || {
  msg_err "Extraction failed"
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
msg_ok "FusionBox installed successfully!"
msg ""
msg "  ${BOLD}Usage:${RESET}"
msg "  fusionbox              ${CYAN}Main menu${RESET}"
msg "  fusionbox help         ${CYAN}Show help${RESET}"
msg "  fusionbox proxy        ${CYAN}Proxy management${RESET}"
msg "  fusionbox system       ${CYAN}System management${RESET}"
msg "  fusionbox network      ${CYAN}Network tools${RESET}"
msg "  fusionbox web          ${CYAN}Web/LNMP deployment${RESET}"
msg "  fusionbox panels       ${CYAN}Panels & Docker${RESET}"
msg "  fusionbox market       ${CYAN}App market${RESET}"
msg ""
exit 0
