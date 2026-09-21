#!/bin/bash
# B4 真机验收（v1.41.0）：Cloudflare 联动真实凭据验证（G44），
# 不进 CI。需要环境变量提供最小权限凭据（只给测试 Zone 的
# Zone Settings Edit + Firewall Services Edit），脚本会：
#   - 临时写入 /etc/fusionbox/cloudflare.conf（原有文件先备份、退出时恢复）
#   - 用真实 API 验证 fusionbox-cf-ban 封禁/解封与幂等
#   - 用真实 API 验证 fusionbox-cf-guard 负载自适应开盾与恢复
#   - 任何退出路径都把 security_level 恢复为基线并清理测试规则
# 用法: CF_API_TOKEN=... CF_ZONE_ID=... bash tests/acceptance/cloudflare_guard.sh
# 可选: CF_TEST_IP（默认 192.0.2.1，TEST-NET-1，绝不误伤真实用户）
#       CF_BAN_SCRIPT / CF_GUARD_SCRIPT（默认 /usr/local/bin/fusionbox-cf-{ban,guard}）
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1

TEST_IP="${CF_TEST_IP:-192.0.2.1}"
BAN_SCRIPT="${CF_BAN_SCRIPT:-/usr/local/bin/fusionbox-cf-ban}"
GUARD_SCRIPT="${CF_GUARD_SCRIPT:-/usr/local/bin/fusionbox-cf-guard}"
CONF="/etc/fusionbox/cloudflare.conf"
API="https://api.cloudflare.com/client/v4"
STATE_DIR="/var/lib/fusionbox"

PASS=0
FAIL=0
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
check_fail(){ if [[ "$2" -ne 0 ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

# ---- curl 封装：token 不进进程命令行 ----
CURL_CFG=$(mktemp)
chmod 600 "$CURL_CFG"
printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\n' "${CF_API_TOKEN:-}" > "$CURL_CFG"

cf_api() { # cf_api <method> <path> [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -fsS --max-time 25 -X "$method" "$API$path" -K "$CURL_CFG" -d "$body" 2>/dev/null
  else
    curl -fsS --max-time 25 -X "$method" "$API$path" -K "$CURL_CFG" 2>/dev/null
  fi
}
sec_level() { # 读当前 security_level
  cf_api GET "/zones/$CF_ZONE_ID/settings/security_level" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"]["value"] if d.get("success") else "")' 2>/dev/null
}
rule_id() { # 提取 TEST_IP 的 block 规则 id（兼容紧凑/pretty JSON）
  cf_api GET "/zones/$CF_ZONE_ID/firewall/access_rules/rules?mode=block&configuration%5Bvalue%5D=$TEST_IP&per_page=10" 2>/dev/null \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([a-f0-9]\{32\}\)".*/\1/p' | head -1
}
rule_exists() {
  cf_api GET "/zones/$CF_ZONE_ID/firewall/access_rules/rules?mode=block&configuration%5Bvalue%5D=$TEST_IP&per_page=10" \
    | grep -Eq "\"value\"[[:space:]]*:[[:space:]]*\"$TEST_IP\""
}
CONF_BACKUP=""
cleanup() {
  # 兜底：恢复 security_level、删除测试规则、恢复配置
  local now base rid
  base="$(cat /tmp/fb-cf-baseline 2>/dev/null || true)"
  now="$(sec_level 2>/dev/null || true)"
  if [[ -n "$base" && -n "$now" && "$now" != "$base" ]]; then
    cf_api PATCH "/zones/$CF_ZONE_ID/settings/security_level" "{\"value\":\"$base\"}" >/dev/null 2>&1
  fi
  rid="$(rule_id)"
  if [[ -n "$rid" ]]; then
    cf_api DELETE "/zones/$CF_ZONE_ID/firewall/access_rules/rules/$rid" >/dev/null 2>&1
  fi
  if [[ -n "$CONF_BACKUP" ]]; then
    mv -T "$CONF_BACKUP" "$CONF" 2>/dev/null
  else
    rm -f "$CONF" 2>/dev/null
  fi
  rm -f "$STATE_DIR"/cf-guard.*.state "$STATE_DIR"/cf-guard.*.state.original "$STATE_DIR"/cf-guard.*.state.lock 2>/dev/null
  rm -f "$CURL_CFG"
}
trap 'cleanup' EXIT

step "0. 前置"
[[ -n "${CF_API_TOKEN:-}" && -n "${CF_ZONE_ID:-}" ]] || { echo "需要环境变量 CF_API_TOKEN 与 CF_ZONE_ID"; exit 1; }
[[ $EUID -eq 0 ]] || { echo "需要 root（写 $CONF 与 $STATE_DIR）"; exit 1; }
[[ -x "$BAN_SCRIPT" ]] || { echo "缺少 $BAN_SCRIPT（先在 web 防护菜单安装）"; exit 1; }
[[ -x "$GUARD_SCRIPT" ]] || { echo "缺少 $GUARD_SCRIPT（先在 web 防护菜单安装）"; exit 1; }
mkdir -p "$STATE_DIR"

step "1. 凭据与基线"
vfy=$(cf_api GET "/user/tokens/verify" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("ok" if (d.get("success") and d.get("result",{}).get("status")=="active") else "no")' 2>/dev/null)
check "Token verify 端点确认 active" "$([[ "$vfy" == "ok" ]] && echo 0 || echo 1)"
baseline=$(sec_level)
case "$baseline" in off|essentially_off|low|medium|high|under_attack) check "security_level 基线可读（$baseline）" 0;; *) bad "security_level 基线不可读"; exit 1;; esac
printf '%s' "$baseline" > /tmp/fb-cf-baseline
# 备份原配置
if [[ -f "$CONF" ]]; then
  CONF_BACKUP=$(mktemp)
  cp "$CONF" "$CONF_BACKUP"
fi
umask 077
printf 'CF_API_TOKEN=%s\nCF_ZONE_ID=%s\n' "$CF_API_TOKEN" "$CF_ZONE_ID" > "$CONF"
chmod 600 "$CONF"
[[ "$(stat -c %a "$CONF")" == "600" ]]; check "临时 conf 已写入（600）" "$?"

step "2. 缺凭据显式拒绝"
# 注意：环境变量可作为 conf 缺项的合法回退，这里用 env -u 隔离，确保测的是「纯 conf 缺失」路径
mv -T "$CONF" "$CONF.moved" 2>/dev/null
env -u CF_API_TOKEN -u CF_ZONE_ID "$BAN_SCRIPT" ban "$TEST_IP" >/dev/null 2>&1
check_fail "conf 缺失 → cf-ban 退出 1" "$?"
mv -T "$CONF.moved" "$CONF" 2>/dev/null
printf 'CF_ZONE_ID=%s\n' "$CF_ZONE_ID" > "$CONF"
env -u CF_API_TOKEN -u CF_ZONE_ID "$BAN_SCRIPT" ban "$TEST_IP" >/dev/null 2>&1
check_fail "CF_API_TOKEN 缺失 → cf-ban 退出 1" "$?"
printf 'CF_API_TOKEN=%s\nCF_ZONE_ID=%s\n' "$CF_API_TOKEN" "$CF_ZONE_ID" > "$CONF"

step "3. IP 封禁/解封（真实 API）"
"$BAN_SCRIPT" ban 'not-an-ip' >/dev/null 2>&1
check_fail "非法 IP 格式拒绝" "$?"
"$BAN_SCRIPT" ban "$TEST_IP" >/dev/null 2>&1
check "ban $TEST_IP 退出 0" "$?"
rule_exists; check "API 侧确认 block 规则已存在" "$?"
"$BAN_SCRIPT" ban "$TEST_IP" >/dev/null 2>&1
check "重复 ban 幂等退出 0" "$?"
"$BAN_SCRIPT" unban "$TEST_IP" >/dev/null 2>&1
check "unban $TEST_IP 退出 0" "$?"
if rule_exists; then bad "API 侧确认规则已消失"; else ok "API 侧确认规则已消失"; fi

step "4. 负载自适应开盾（真实 API）"
load1=$(awk '{print $1}' /proc/loadavg)
load1="${load1:-0}"
th_open=$(python3 -c "print(float('$load1')-1)")
th_close=$(python3 -c "print(float('$load1')+100)")
printf 'CF_API_TOKEN=%s\nCF_ZONE_ID=%s\nLOAD_THRESHOLD=%s\n' "$CF_API_TOKEN" "$CF_ZONE_ID" "$th_open" > "$CONF"
zid_lower=${CF_ZONE_ID,,}
rm -f "$STATE_DIR/cf-guard.$zid_lower.state" "$STATE_DIR/cf-guard.$zid_lower.state.original" 2>/dev/null
"$GUARD_SCRIPT" >/tmp/fb-cf-guard-open.log 2>&1
check "高负载档运行退出 0" "$?"
[[ "$(sec_level)" == "under_attack" ]]; check "security_level 真实切到 under_attack（基线 $baseline）" "$?"
[[ "$(cat "$STATE_DIR/cf-guard.$zid_lower.state" 2>/dev/null)" == "under_attack" ]]; check "state 文件记录 under_attack" "$?"
"$GUARD_SCRIPT" >/dev/null 2>&1
check "重复运行幂等退出 0（不再调 API）" "$?"
[[ "$(sec_level)" == "under_attack" ]]; check "幂等运行后级别不变" "$?"
printf 'CF_API_TOKEN=%s\nCF_ZONE_ID=%s\nLOAD_THRESHOLD=%s\n' "$CF_API_TOKEN" "$CF_ZONE_ID" "$th_close" > "$CONF"
"$GUARD_SCRIPT" >/tmp/fb-cf-guard-close.log 2>&1
check "负载回落档运行退出 0" "$?"
[[ "$(sec_level)" == "$baseline" ]]; check "security_level 真实恢复为基线 $baseline" "$?"
[[ "$(cat "$STATE_DIR/cf-guard.$zid_lower.state" 2>/dev/null)" == "$baseline" ]]; check "state 文件记录恢复值" "$?"

step "5. 清理与终态"
[[ "$(sec_level)" == "$baseline" ]]; check "终态 security_level == 基线" "$?"
if rule_exists; then bad "终态无测试封禁规则残留"; else ok "终态无测试封禁规则残留"; fi
rm -f /tmp/fb-cf-baseline
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
