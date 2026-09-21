#!/bin/bash
# 真机验收：多容器应用（声明式目录）的完整生命周期
#
# 需要 root + Docker + Python 3；不进 CI（CI 契约是不依赖 root/Docker/网络）。
# 用法： bash tests/acceptance/market_multicontainer.sh [仓库根目录]
#
# 覆盖：
#   1. install（依赖 db 先健康，app 才启动）
#   2. status
#   3. update 无改动 → 明确提示不做任何事
#   4. update 真换镜像 → 健康
#   5. update 换到必然起不来的镜像 → 必须失败并自动回滚（不留半成品）
#   6. 新字段（shm_size/tmpfs/read_only/sysctls/entrypoint）在真机 Docker 上
#      既被正确落地、也被 resources() 反向校验（漂移必须被抓到）
#   7. uninstall 保留数据
#   8. reinstall --reuse-data 后数据仍在（真实插入的行还在）
set -u

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"
PROJECT='fb-market-umami'
BASE='/var/lib/fusionbox/compose-projects'
PASS=0
FAIL=0

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

# 每次从干净状态开始：只清理本脚本自己拥有的资源
cleanup_owned() {
  for name in "$PROJECT-db" "$PROJECT-app" 'fb-market-fieldprobe-app'; do
    docker rm -f "$name" >/dev/null 2>&1
  done
  docker volume rm "${PROJECT}_data" fb-market-fieldprobe_data >/dev/null 2>&1
  rm -f "$BASE/$PROJECT".json "$BASE/$PROJECT".compose.json "$BASE/$PROJECT".update.json 2>/dev/null
  rm -f "$BASE/fb-market-fieldprobe".json "$BASE/fb-market-fieldprobe".compose.json 2>/dev/null
}
cleanup_owned

PY=python3
FB() { "$FUSION" "$@" < /dev/null 2>&1; }

step "0. 内置目录包含 umami（多服务）"
out="$(FB market managed catalog)"
check "catalog 列出 umami" "$(printf '%s' "$out" | grep -q '^umami:' && echo 0 || echo 1)"
check "catalog 显示 2 个服务" "$(printf '%s' "$out" | grep -q '^umami:.*services=2' && echo 0 || echo 1)"

step "1. install"
out="$(FB market managed install umami --confirm)"
rc=$?
if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
check "install 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "install 报告 healthy" "$(printf '%s' "$out" | grep -q 'healthy' && echo 0 || echo 1)"

step "2. 依赖顺序与健康（真实容器状态）"
db_started="$(docker inspect -f '{{.State.StartedAt}}' "$PROJECT-db" 2>/dev/null)"
app_started="$(docker inspect -f '{{.State.StartedAt}}' "$PROJECT-app" 2>/dev/null)"
check "两个容器都在运行" "$([[ -n "$db_started" && -n "$app_started" ]] && echo 0 || echo 1)"
check "db 先于 app 启动（depends_on 生效）" "$([[ -n "$db_started" && -n "$app_started" && "$db_started" < "$app_started" ]] && echo 0 || echo 1)"
check "db 健康" "$([[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-db" 2>/dev/null)" == healthy ]] && echo 0 || echo 1)"
check "app 健康" "$([[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-app" 2>/dev/null)" == healthy ]] && echo 0 || echo 1)"
check "localhost:8090 真实响应 200" "$([[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/api/heartbeat)" == 200 ]] && echo 0 || echo 1)"
check "shm_size 已落地（64MiB）" "$([[ "$(docker inspect -f '{{.HostConfig.ShmSize}}' "$PROJECT-db" 2>/dev/null)" == 67108864 ]] && echo 0 || echo 1)"
check "宿主未暴露 8090 之外端口" "$([[ "$(docker inspect -f '{{range $p, $c := .HostConfig.PortBindings}}{{$p}} {{end}}' "$PROJECT-app" 2>/dev/null | tr -d ' ')" == '3000/tcp' ]] && echo 0 || echo 1)"

step "3. status"
out="$(FB market managed status umami)"
check "status 报告 healthy" "$(printf '%s' "$out" | grep -q 'healthy' && echo 0 || echo 1)"

step "4. update 无改动"
out="$(FB market managed update umami --confirm)"
check "无改动时明确提示 nothing to do" "$(printf '%s' "$out" | grep -q 'nothing to do' && echo 0 || echo 1)"
check "无改动不改动容器（仍在运行）" "$([[ -n "$(docker ps -q -f name=^/$PROJECT-app\$)" ]] && echo 0 || echo 1)"

step "5. update 真换镜像（umami 2.11.3 → latest 摘要）"
NEW_APP='ghcr.io/umami-software/umami@sha256:85909afc45bdcda1917394594a087421fdbb05610fded0fa9f6fb861abb2f367'
out="$(FB market managed update umami --confirm --service-image "app=$NEW_APP")"
rc=$?
check "update 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "报告只改了 app 服务" "$(printf '%s' "$out" | grep -q 'changed services: app' && echo 0 || echo 1)"
check "容器镜像已换成新摘要" "$(docker inspect -f '{{.Image}}' "$PROJECT-app" 2>/dev/null | grep -q . && [[ "$(docker inspect -f '{{index .Config.Image}}' "$PROJECT-app" 2>/dev/null)" == "$NEW_APP" ]] && echo 0 || echo 1)"
check "换镜像后仍健康" "$([[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-app" 2>/dev/null)" == healthy ]] && echo 0 || echo 1)"

step "6. update 换成必然起不来的镜像 → 必须失败并回滚"
BAD_APP="$(docker inspect --format '{{index .RepoDigests 0}}' alpine:3.20 2>/dev/null)"
if [[ -z "$BAD_APP" ]]; then
  printf '  SKIP  未找到 alpine 摘要，无法构造失败场景\n'
else
  out="$(FB market managed update umami --confirm --service-image "app=$BAD_APP")"
  rc=$?
  check "失败场景退出码非零 (rc=$rc)" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  check "失败信息说明已回滚" "$(printf '%s' "$out" | grep -qE '回滚|restored' && echo 0 || echo 1)"
  sleep 3
  check "回滚后 app 仍健康" "$([[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-app" 2>/dev/null)" == healthy ]] && echo 0 || echo 1)"
  check "回滚后 app 镜像回到上一个（不是 alpine）" "$([[ "$(docker inspect -f '{{index .Config.Image}}' "$PROJECT-app" 2>/dev/null)" == "$NEW_APP" ]] && echo 0 || echo 1)"
  check "失败已就地恢复（记录为 healthy）" "$(FB market managed status umami | grep -q healthy && echo 0 || echo 1)"
  check "update 日志已清除（无遗留 journal）" "$([[ ! -f "$BASE/$PROJECT.update.json" ]] && echo 0 || echo 1)"
fi

step "7. 新字段在真机 Docker 上的落地与漂移检测"
$PY -B - "$ROOT" <<'PYEOF'
import json
import sys

root = sys.argv[1]
sys.path.insert(0, root + '/src/lib')
import market_apps as apps  # noqa: E402

PROJECT = 'fb-market-fieldprobe'


def fixture(spec_app):
    record = {'owner': apps.cb.OWNER, 'project': PROJECT,
              'compose': str(apps.cb.BASE / (PROJECT + '.compose.json')),
              'market': {'owner': apps.OWNER, 'app': 'fieldprobe', 'token': 'b' * 32,
                         'state': 'installing', 'catalog_app': spec_app,
                         'catalog_digest': __import__('market_catalog').app_digest(spec_app)}}
    return record


SPEC = {'id': 'fieldprobe', 'name': 'field probe', 'description': 'fixture', 'revoked': False,
        'high_privilege': False, 'domain': False, 'bytes': 536870912, 'nas_path': False,
        'services': [{'id': 'app', 'image': 'alpine:3.20@sha256:' + '0' * 64,
                      'entrypoint': ['/bin/sh', '-c', 'sleep 600'],
                      'ports': [], 'volumes': [], 'binds': [], 'devices': [],
                      'network_mode': 'bridge', 'docker_socket': False, 'memory': '64m',
                      'cpus': '0.50', 'pids_limit': 32, 'health': ['CMD', 'true'],
                      'health_retries': 5, 'shm_size': '128m', 'tmpfs': ['/run/probe'],
                      'read_only': True, 'sysctls': {'net.core.somaxconn': '1024'}}]}

failures = []


def report(label, ok):
    print(('  PASS  ' if ok else '  FAIL  ') + label)
    if not ok:
        failures.append(label)


# 用真实 alpine 摘要替换占位（fixture 必须能拉得动才能真跑）
real = apps.cb.js('image', 'inspect', 'alpine:3.20')[0]
SPEC['services'][0]['image'] = real['RepoDigests'][0]
record = fixture(SPEC)
apps.write_compose(record)
apps.cb.docker('compose', '-p', PROJECT, '-f', record['compose'], 'up', '-d', '--wait', '--wait-timeout', '60')
inspect = apps.cb.js('inspect', PROJECT + '-app')[0]
host = inspect['HostConfig']
report('shm_size 落地为 128MiB', host.get('ShmSize') == 128 * 1024 * 1024)
report('tmpfs 落地 /run/probe', set((host.get('Tmpfs') or {}).keys()) == {'/run/probe'})
report('read_only 根文件系统生效', bool(host.get('ReadonlyRootfs')) is True)
report('sysctls 落地', (host.get('Sysctls') or {}) == {'net.core.somaxconn': '1024'})
report('entrypoint 落地', inspect['Config'].get('Entrypoint') == ['/bin/sh', '-c', 'sleep 600'])
report('resources() 接受一致的声明', bool(apps.resources(record)) is True)

# 声明与实际不一致时，resources() 必须拒绝（否则校验形同虚设）
drifted = json.loads(json.dumps(record))
drifted['market']['catalog_app']['services'][0]['shm_size'] = '256m'
drifted['market']['catalog_digest'] = __import__('market_catalog').app_digest(drifted['market']['catalog_app'])
try:
    apps.resources(drifted)
    report('shm_size 漂移被抓到', False)
except ValueError:
    report('shm_size 漂移被抓到', True)

apps.cb.docker('compose', '-p', PROJECT, '-f', record['compose'], 'down', '-v')
print('  FAILURES=%d' % len(failures))
sys.exit(1 if failures else 0)
PYEOF
check "新字段真机落地与漂移检测全部通过" "$?"

step "8. uninstall 保留数据"
docker exec "$PROJECT-db" psql -U umami -d umami -c 'create table fb_retention(x int); insert into fb_retention values (42);' >/dev/null 2>&1
check "探针数据已写入" "$([[ "$(docker exec "$PROJECT-db" psql -U umami -d umami -tAc 'select count(*) from fb_retention' 2>/dev/null | tr -d ' ')" == 1 ]] && echo 0 || echo 1)"
out="$(FB market managed uninstall umami --confirm)"
rc=$?
check "uninstall 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "容器已删除" "$([[ -z "$(docker ps -aq -f name=^/$PROJECT-app\$)" && -z "$(docker ps -aq -f name=^/$PROJECT-db\$)" ]] && echo 0 || echo 1)"
check "具名卷被保留" "$(docker volume ls -q | grep -qx "${PROJECT}_data" && echo 0 || echo 1)"

step "9. reinstall --reuse-data 后数据仍在"
out="$(FB market managed reinstall umami --confirm --reuse-data)"
rc=$?
if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
check "reinstall 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "重建后健康" "$([[ "$(docker inspect -f '{{.State.Health.Status}}' "$PROJECT-app" 2>/dev/null)" == healthy ]] && echo 0 || echo 1)"
check "复用数据仍在（第 42 行还在）" "$([[ "$(docker exec "$PROJECT-db" psql -U umami -d umami -tAc 'select count(*) from fb_retention' 2>/dev/null | tr -d ' ')" == 1 ]] && echo 0 || echo 1)"
check "服务仍可用（heartbeat 200）" "$([[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/api/heartbeat)" == 200 ]] && echo 0 || echo 1)"

step "10. 收尾清理"
FB market managed uninstall umami --confirm >/dev/null 2>&1
docker volume rm "${PROJECT}_data" >/dev/null 2>&1
cleanup_owned
check "已卸载且数据卷已清理（验收环境不残留）" "$([[ -z "$(docker ps -aq -f name=^/$PROJECT-)" ]] && echo 0 || echo 1)"

printf '\n====================\n通过 %d / 失败 %d\n====================\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
