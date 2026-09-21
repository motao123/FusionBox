#!/bin/bash
# A6 目录扩容真机验收（v1.40.0）：vocechat 单容器应用全生命周期，不进 CI。
# 安装 → 健康 + HTTP → 卸载保留卷 → reuse-data 重装 → HTTP 与数据复核。
# 用法: bash tests/acceptance/market_app_expansion.sh [仓库根目录]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"
APP='vocechat'
PROJECT='fb-market-vocechat'
PORT=3009
BASE=/var/lib/fusionbox/compose-projects
DB_DIR="$BASE/$PROJECT"

PASS=0
FAIL=0
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

wait_http() {
  for _ in $(seq 1 45); do
    code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/" 2>/dev/null)"
    [[ "$code" == "200" ]] && return 0
    sleep 2
  done
  return 1
}
healthy() {
  for _ in $(seq 1 45); do
    s="$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null)"
    [[ "$s" == "healthy" ]] && return 0
    sleep 2
  done
  return 1
}

cleanup_owned() {
  docker rm -f "$PROJECT-app" >/dev/null 2>&1
  docker volume rm "${PROJECT}_data" >/dev/null 2>&1
  rm -f "$BASE/${PROJECT}".json "$BASE/${PROJECT}".compose.json 2>/dev/null
}
trap cleanup_owned EXIT

step "0. 前置与清理"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
docker version >/dev/null 2>&1 || { echo "需要可用 Docker"; exit 1; }
cleanup_owned

step "1. 安装（market managed install vocechat）"
"$FUSION" market managed install "$APP" --confirm >/dev/null 2>&1
check "install 退出码 0" "$?"
healthy "$PROJECT-app"; check "容器 healthy（自检端点）" "$?"
if wait_http; then ok "真实 HTTP 200（localhost:$PORT）"; else bad "真实 HTTP 200（localhost:$PORT）"; fi

step "2. 卸载（保留具名卷）"
docker exec "$PROJECT-app" sh -c 'echo probe > /home/vocechat-server/data/fb-probe.txt' 2>/dev/null
"$FUSION" market managed uninstall "$APP" --confirm >/dev/null 2>&1
check "uninstall 退出码 0" "$?"
n="$(docker ps -aq --filter "name=$PROJECT" | wc -l)"
check "容器已移除" "$([[ "${n:-0}" == "0" ]] && echo 0 || echo 1)"
docker volume inspect "${PROJECT}_data" >/dev/null 2>&1
check "具名卷保留" "$?"
content="$(docker run --rm -v "${PROJECT}_data":/d alpine:3.20 cat /d/fb-probe.txt 2>/dev/null)"
check "卷内数据仍在（含探针文件）" "$([[ "$content" == "probe" ]] && echo 0 || echo 1)"

step "3. reuse-data 重装"
"$FUSION" market managed reinstall "$APP" --confirm --reuse-data >/dev/null 2>&1
check "reinstall --reuse-data 退出码 0" "$?"
healthy "$PROJECT-app"; check "重装后 healthy" "$?"
if wait_http; then ok "重装后 HTTP 200"; else bad "重装后 HTTP 200"; fi
content="$(docker exec "$PROJECT-app" cat /home/vocechat-server/data/fb-probe.txt 2>/dev/null)"
check "重装未新建替代卷（探针文件仍在）" "$([[ "$content" == "probe" ]] && echo 0 || echo 1)"

step "4. 清理"
"$FUSION" market managed uninstall "$APP" --confirm >/dev/null 2>&1
cleanup_owned
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
