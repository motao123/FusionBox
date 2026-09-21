#!/bin/bash
# ACME 路线 A：本地 Pebble（协议级，无外部依赖）真机验收，不进 CI。
# 覆盖：preflight → webroot 签发（Pebble 证书）→ status → renew 触发（指纹变化）
#       → 失败路径（不可达目录 URL）签发失败后无证书、challenge 配置恢复。
# 用法: bash tests/acceptance/acme_pebble.sh [仓库根目录]
#
# 边界声明：Pebble 配合 PEBBLE_VA_ALWAYS_VALID=1 时所有 challenge 直接判有效，
# 因此本脚本验证的是 FusionBox 的 certbot 调用链、证书落盘、nginx 装配、续期与
# 失败回滚——不含真实 challenge 传输；后者由 acme_staging.sh（真实 CA + 真实
# HTTP-01）覆盖。
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"

PASS=0
FAIL=0
DOMAIN=fbtest.acme.invalid
EMAIL=ops@fbtest.example
PEBBLE=fb-acme-pebble
LE_DIR=/tmp/fb-acme-le
STATE_DIR=/tmp/fb-acme-state
CA_BUNDLE=/tmp/fb-pebble-minica.pem
SERVER_URL=https://127.0.0.1:14000/dir
HTTP_PORT=8080

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

cleanup_owned() {
  docker rm -f "$PEBBLE" >/dev/null 2>&1
  rm -rf "$LE_DIR" "$STATE_DIR" "$CA_BUNDLE" /tmp/fb-acme-fp.*
}
trap cleanup_owned EXIT

step "0. 前置"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
command -v docker >/dev/null || { echo "需要 docker"; exit 1; }
if ! command -v certbot >/dev/null 2>&1; then
  echo "安装 certbot..."
  apt-get update -qq >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null 2>&1
fi
command -v certbot >/dev/null 2>&1; check "certbot 可用" "$?"
systemctl is-active --quiet nginx || { systemctl start nginx >/dev/null 2>&1; }
systemctl is-active --quiet nginx; check "nginx 运行中" "$?"

step "1. Pebble + PEBBLE_VA_ALWAYS_VALID（challenge 直接判有效）"
docker rm -f "$PEBBLE" >/dev/null 2>&1
docker run -d --name "$PEBBLE" -e PEBBLE_VA_ALWAYS_VALID=1 \
  -p 127.0.0.1:14000:14000 ghcr.io/letsencrypt/pebble >/dev/null 2>&1
check "Pebble 容器启动" "$?"
ready=0
for _ in $(seq 1 30); do
  if curl -sk -m 5 "$SERVER_URL" | grep -q newNonce; then ready=1; break; fi
  sleep 1
done
check "ACME 目录可访问（newNonce 字段）" "$((1 - ready))"
docker cp "$PEBBLE:/test/certs/pebble.minica.pem" "$CA_BUNDLE" >/dev/null 2>&1
[[ -s "$CA_BUNDLE" ]]; check "Pebble CA 证书已导出" "$?"

export WEB_ACME_SERVER="$SERVER_URL"
export WEB_ACME_LE_DIR="$LE_DIR"
export WEB_ACME_STATE_DIR="$STATE_DIR"
export WEB_ACME_HTTP_PORT="$HTTP_PORT"
export REQUESTS_CA_BUNDLE="$CA_BUNDLE"
export SSL_CERT_FILE="$CA_BUNDLE"
ACME_ENV=(env "WEB_ACME_SERVER=$SERVER_URL" "WEB_ACME_LE_DIR=$LE_DIR" "WEB_ACME_STATE_DIR=$STATE_DIR"
          "WEB_ACME_HTTP_PORT=$HTTP_PORT" "REQUESTS_CA_BUNDLE=$CA_BUNDLE" "SSL_CERT_FILE=$CA_BUNDLE")

step "2. preflight（域名校验/端口/冲突只读检查）"
"${ACME_ENV[@]}" "$FUSION" web ssl preflight --domain "$DOMAIN" --email "$EMAIL" >/tmp/fb-acme-preflight.log 2>&1
check "preflight 退出码 0" "$?"
grep -q "8080" /tmp/fb-acme-preflight.log; check "端口报告使用覆盖端口 8080" "$?"

step "3. issue：真实签发 Pebble 证书并启用受管 TLS"
"${ACME_ENV[@]}" "$FUSION" web ssl issue --domain "$DOMAIN" --email "$EMAIL" >/tmp/fb-acme-issue.log 2>&1
check "issue 退出码 0" "$?"
[[ -s "$LE_DIR/live/$DOMAIN/fullchain.pem" ]]; check "证书落盘 live/$DOMAIN/fullchain.pem" "$?"
issuer="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -issuer 2>/dev/null)"
printf '%s' "$issuer" | grep -qi pebble; check "签发者确实是 Pebble（$issuer）" "$?"
subject="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -subject 2>/dev/null)"
san="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -ext subjectAltName 2>/dev/null)"
printf '%s' "$san" | grep -q "$DOMAIN"; check "SAN 含 $DOMAIN" "$?"
endate="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -enddate 2>/dev/null | cut -d= -f2)"
days_left=$(( ($(date -d "$endate" +%s) - $(date +%s)) / 86400 ))
check "证书有效期短（${days_left} 天 ≤ 30，测试 CA）" "$(( days_left <= 30 && days_left >= 0 ? 0 : 1 ))"
ls "$LE_DIR/live/$DOMAIN/privkey.pem" >/dev/null 2>&1; check "私钥落盘" "$?"
nginx -t >/dev/null 2>&1; check "受管 TLS 配置通过 nginx -t" "$?"
[[ -f /etc/nginx/conf.d/fusionbox-tls-"$DOMAIN".conf ]]; check "TLS 配置文件存在" "$?"

step "4. status"
"${ACME_ENV[@]}" "$FUSION" web ssl status --domain "$DOMAIN" >/tmp/fb-acme-status.log 2>&1
check "status 退出码 0" "$?"
grep -q "$DOMAIN" /tmp/fb-acme-status.log; check "status 列出证书" "$?"

step "5. renew --days 30：Pebble 5 天证书必然到期，触发真实续期"
before_fp="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -fingerprint -sha256 2>/dev/null)"
"${ACME_ENV[@]}" "$FUSION" web ssl renew --days 30 >/tmp/fb-acme-renew.log 2>&1
check "renew 退出码 0" "$?"
after_fp="$(openssl x509 -in "$LE_DIR/live/$DOMAIN/fullchain.pem" -noout -fingerprint -sha256 2>/dev/null)"
check "证书指纹已变化（真实续期）" "$([[ "$before_fp" != "$after_fp" ]] && echo 0 || echo 1)"
nginx -t >/dev/null 2>&1; check "续期后 nginx 配置仍有效" "$?"

step "6. 失败路径：ACME 目录不可达 → 签发失败、无证书、challenge 配置恢复"
BAD_DOMAIN=fbfail.acme.invalid
"${ACME_ENV[@]}" "$FUSION" web ssl issue --domain "$BAD_DOMAIN" --email "$EMAIL" \
  --server https://127.0.0.1:19999/dir >/tmp/fb-acme-fail.log 2>&1
check "不可达目录 URL 时 issue 失败（rc!=0）" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
[[ ! -e "$LE_DIR/live/$BAD_DOMAIN/fullchain.pem" ]]; check "失败域无证书落盘" "$?"
[[ ! -f /etc/nginx/conf.d/fusionbox-acme-"$BAD_DOMAIN".conf ]]; check "challenge 临时配置已回滚" "$?"
nginx -t >/dev/null 2>&1; check "回滚后 nginx 配置仍有效" "$?"

step "7. 清理"
rm -f /etc/nginx/conf.d/fusionbox-tls-"$DOMAIN".conf /etc/nginx/conf.d/fusionbox-acme-"$DOMAIN".conf 2>/dev/null
nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1
cleanup_owned
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
