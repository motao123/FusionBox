#!/bin/bash
# B1 真实容器生命周期验收（真机，不进 CI）：部署(真实 HTTP) → 停止/启动 →
# compose 备份 → 卸载(保留卷) → 备份恢复 → 数据与 HTTP 复核。
# 用法: bash tests/acceptance/container_lifecycle.sh [仓库根目录]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"
PROJECT='fb-market-umami'
APP='umami'
PORT=8090
BASE=/var/lib/fusionbox/compose-projects
ARCHIVE=/tmp/fb-lifecycle-backup.tar.gz
DB="${PROJECT}-db"
WEB="${PROJECT}-app"

PASS=0
FAIL=0
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

wait_http() {
  for _ in $(seq 1 60); do
    code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/api/heartbeat" 2>/dev/null)"
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
  docker rm -f "$DB" "$WEB" >/dev/null 2>&1
  docker volume rm "${PROJECT}_data" >/dev/null 2>&1
  rm -f "$BASE/${PROJECT}".json "$BASE/${PROJECT}".compose.json "$ARCHIVE" 2>/dev/null
}
trap cleanup_owned EXIT

step "0. 前置与清理"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
docker version >/dev/null 2>&1 || { echo "需要可用 Docker"; exit 1; }
cleanup_owned

step "1. 部署（market managed install umami）"
"$FUSION" market managed install "$APP" --confirm >/dev/null 2>&1
check "install 退出码 0" "$?"
healthy "$DB"; check "postgres 容器 healthy" "$?"
healthy "$WEB"; check "umami 容器 healthy" "$?"
if wait_http; then ok "真实 HTTP: /api/heartbeat 200"; else bad "真实 HTTP: /api/heartbeat 200"; fi

step "2. 写入业务数据（后续恢复的比对基准）"
docker exec "$DB" psql -U umami -d umami -c \
  "CREATE TABLE IF NOT EXISTS fb_probe(id int primary key); INSERT INTO fb_probe VALUES (42);" >/dev/null 2>&1
check "数据行写入成功" "$?"

step "3. 停止/启动往返"
docker stop "$WEB" "$DB" >/dev/null 2>&1
s="$(docker inspect -f '{{.State.Running}}' "$WEB" 2>/dev/null)"
check "两容器已停止（Go 模板布尔为小写）" "$([[ "$s" == "false" ]] && echo 0 || echo 1)"
docker start "$DB" "$WEB" >/dev/null 2>&1
healthy "$DB" && healthy "$WEB"; check "启动后恢复 healthy" "$?"
if wait_http; then ok "启动后 HTTP 200"; else bad "启动后 HTTP 200"; fi

step "4. compose 备份（G28；market 安装已自动登记 compose-backup）"
"$FUSION" panels compose-backup backup "$PROJECT" "$ARCHIVE" --confirm-stop-writers >/dev/null 2>&1
check "backup 生成归档" "$([[ -s "$ARCHIVE" ]] && echo 0 || echo 1)"
sha_a="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
"$FUSION" panels compose-backup backup "$PROJECT" "$ARCHIVE" --confirm-stop-writers >/dev/null 2>&1
sha_b="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
check "重复备份内容确定（同一数据同一摘要）" "$([[ "$sha_a" == "$sha_b" ]] && echo 0 || echo 1)"

step "5. 模拟数据全损（容器与卷销毁，登记与 compose 保留）"
docker compose -p "$PROJECT" -f "$BASE/${PROJECT}.compose.json" down -v >/dev/null 2>&1
n="$(docker ps -aq --filter "name=${PROJECT}" | wc -l)"
check "容器已全部移除" "$([[ "${n:-0}" == "0" ]] && echo 0 || echo 1)"
docker volume inspect "${PROJECT}_data" >/dev/null 2>&1
check "数据卷已销毁（模拟最坏情况）" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"

step "6. 重建空壳并从备份恢复数据"
# compose-backup restore 的语义是向已登记且已重建的项目灌回卷数据（G28 边界），
# 不是从零引导：先按同一 compose 重建空容器与空卷。
docker compose -p "$PROJECT" -f "$BASE/${PROJECT}.compose.json" up -d >/dev/null 2>&1
for _ in $(seq 1 30); do
  n="$(docker ps -aq --filter "name=${PROJECT}" | wc -l)"
  [[ "${n:-0}" -ge 2 ]] && break
  sleep 2
done
check "空壳容器已重建" "$([[ "${n:-0}" -ge 2 ]] && echo 0 || echo 1)"
"$FUSION" panels compose-backup restore "$PROJECT" "$ARCHIVE" --confirm-stop-writers >/dev/null 2>&1
"$FUSION" panels compose-backup restore "$PROJECT" "$ARCHIVE" --confirm-stop-writers >/dev/null 2>&1
check "restore 退出码 0" "$?"
healthy "$DB" && healthy "$WEB"; check "恢复后两容器 healthy" "$?"
if wait_http; then ok "恢复后 HTTP 200"; else bad "恢复后 HTTP 200"; fi
row="$(docker exec "$DB" psql -U umami -d umami -t -A -c 'SELECT id FROM fb_probe WHERE id=42;' 2>/dev/null)"
check "备份数据行完整恢复（id=42）" "$([[ "$row" == "42" ]] && echo 0 || echo 1)"

step "7. 清理"
docker exec "$DB" psql -U umami -d umami -c 'DROP TABLE IF EXISTS fb_probe;' >/dev/null 2>&1
"$FUSION" market managed uninstall "$APP" --confirm >/dev/null 2>&1
cleanup_owned
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
