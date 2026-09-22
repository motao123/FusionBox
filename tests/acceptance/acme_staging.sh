#!/bin/bash
# ACME 路线 B：Let's Encrypt staging + 含 IP 的公共域名（sslip.io），不进 CI。
# 真实 CA、真实 HTTP-01 传输：LE staging 的 VA 会从公网访问 http://<域名>/.well-known/
# acme-challenge/<token>（80 端口必须对公网开放）。
# 覆盖：真实 DNS 解析报告 → 真实签发（staging 中间证书）→ status →
#       失败路径（DNS 无法解析的域名 → 签发失败、无证书、配置回滚）。
# 用法: bash tests/acceptance/acme_staging.sh [仓库根目录]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"

PASS=0
FAIL=0
DOMAIN="$(curl -s -m 8 ifconfig.me 2>/dev/null | tr -d '[:space:]').sslip.io"
EMAIL=netyc@vip.qq.com
LE_DIR=/tmp/fb-acme-staging-le
STATE_DIR=/tmp/fb-acme-staging-state
STAGING=https://acme-staging-v02.api.letsencrypt.org/directory

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

cleanup_owned() {
  rm -rf "$LE_DIR" "$STATE_DIR"
  rm -f /etc/nginx/conf.d/fusionbox-tls-"$DOMAIN".conf /etc/nginx/conf.d/fusionbox-acme-"$DOMAIN".conf 2>/dev/null
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1
}
trap cleanup_owned EXIT

step "0. 前置"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
command -v certbot >/dev/null 2>&1 || { echo "需要 certbot"; exit 1; }
systemctl is-active --quiet nginx; check "nginx 运行中" "$?"
[[ -n "$DOMAIN" && "$DOMAIN" != ".sslip.io" ]]; check "公网 IP 可获取（$DOMAIN）" "$?"
resolved="$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)"
check "sslip.io 域名解析到本机公网 IP（$resolved）" "$([[ "$resolved" == "$(curl -s -m 8 ifconfig.me 2>/dev/null)" ]] && echo 0 || echo 1)"

export WEB_ACME_SERVER="$STAGING"
export WEB_ACME_LE_DIR="$LE_DIR"
export WEB_ACME_STATE_DIR="$STATE_DIR"
ACME_ENV=(env "WEB_ACME_SERVER=$STAGING" "WEB_ACME_LE_DIR=$LE_DIR" "WEB_ACME_STATE_DIR=$STATE_DIR")

step "1. preflight：真实 DNS 解析报告"
"${ACME_ENV[@]}" "$FUSION" web ssl preflight --domain "$DOMAIN" --email "$EMAIL" >/tmp/fb-staging-preflight.log 2>&1
check "preflight 退出码 0" "$?"
grep -qi "$DOMAIN" /tmp/fb-staging-preflight.log; check "报告包含域名" "$?"

step "2. issue：真实 CA（staging）+ 真实 HTTP-01 签发"
# LE staging 会间歇性返回 "too many requests / Service busy"（外部限流，与产品无关）。
# 对这类瞬时错误退避重试；重试耗尽仍如实 FAIL，不掩盖真实问题。
issue_rc=1
attempts=0
for attempt in 1 2 3; do
  attempts=$attempt
  "${ACME_ENV[@]}" "$FUSION" web ssl issue --domain "$DOMAIN" --email "$EMAIL" >/tmp/fb-staging-issue.log 2>&1
  issue_rc=$?
  [[ $issue_rc -eq 0 ]] && break
  if grep -qiE "too many requests|service busy|rate ?limit" /tmp/fb-staging-issue.log && [[ $attempt -lt 3 ]]; then
    echo "    （第 $attempt 次遇到 LE staging 限流，90s 后重试）"
    sleep 90
    continue
  fi
  break
done
if [[ $issue_rc -ne 0 ]] && grep -qiE "too many requests|service busy|rate ?limit" /tmp/fb-staging-issue.log; then
  echo "    注意: $attempts 次尝试均被 Let's Encrypt staging 限流（外部环境问题，非 FusionBox 缺陷）"
fi
check "issue 退出码 0（尝试 $attempts 次）" "$issue_rc"
[[ -s "$LE_DIR/live/$DOMAIN/fullchain.pem" ]]; check "证书落盘" "$?"
issuer="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -issuer 2>/dev/null)"
printf '%s' "$issuer" | grep -qi "STAGING"; check "签发者为 Let's Encrypt staging（${issuer:0:60}）" "$?"
san="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -ext subjectAltName 2>/dev/null)"
printf '%s' "$san" | grep -q "$DOMAIN"; check "SAN 含 $DOMAIN" "$?"
[[ -f /etc/nginx/conf.d/fusionbox-tls-"$DOMAIN".conf ]]; check "受管 TLS 配置启用" "$?"

step "3. status"
"${ACME_ENV[@]}" "$FUSION" web ssl status --domain "$DOMAIN" >/tmp/fb-staging-status.log 2>&1
check "status 退出码 0" "$?"
grep -q "$DOMAIN" /tmp/fb-staging-status.log; check "status 列出证书" "$?"

step "4. 失败路径：DNS 无法解析的域名 → LE 拒绝、无证书、配置回滚"
BAD_DOMAIN="fb-nonexistent-$RANDOM.invalid.example.com"
"${ACME_ENV[@]}" "$FUSION" web ssl issue --domain "$BAD_DOMAIN" --email "$EMAIL" >/tmp/fb-staging-fail.log 2>&1
check "DNS 失败时 issue 失败（rc!=0）" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
[[ ! -e "$LE_DIR/live/$BAD_DOMAIN/fullchain.pem" ]]; check "失败域无证书落盘" "$?"
[[ ! -f /etc/nginx/conf.d/fusionbox-acme-"$BAD_DOMAIN".conf ]]; check "challenge 临时配置已回滚" "$?"
nginx -t >/dev/null 2>&1; check "回滚后 nginx 配置仍有效" "$?"

step "5. 清理"
cleanup_owned
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
