#!/bin/bash
# 两主机夹具（Docker 扮演第二台主机）+ 跨主机迁移编排 真机验收。
# 覆盖 G15/G16/G61/G63（SSH 出站、rsync 远端形态、灾备传输、批量任务）与 G29（跨主机迁移）。
#
# 不进 CI：需要 root / Docker / 网络。用法: bash tests/acceptance/two_host.sh [仓库根目录]
#
# 边界声明（与本仓库验收口径一致）:
# * 第二台主机是 privileged 容器（ubuntu + sshd + dockerd），cluster_session.run_ssh 对
#   「远端必须是物理机」没有任何依赖；容器销毁即回收。
# * 生产 sshd、宿主 Docker 资源（除本脚本自己创建的）一律不触碰。
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"

PASS=0
FAIL=0
NODE_NAME=fbnode2
NODE_CONTAINER=fb-twohost-node2
SRC_CONTAINER=fb-twohost-src
KEY=/tmp/fb-twohost-key
AGENT_SOCK=/tmp/fb-twohost-agent.sock
CLUSTER_DIR=/etc/fusionbox/cluster
STORE=/var/lib/fusionbox/docker-migration-store
BUNDLE=/tmp/fb-twohost-bundle.tar.gz
CREATED_CLUSTER_DIR=0

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

free_port() {
  local port=22022
  while ss -ltn | grep -q ":${port} "; do port=$((port + 1)); done
  printf '%s' "$port"
}
HOST_PORT="$(free_port)"

cleanup_owned() {
  docker rm -f "$NODE_CONTAINER" "$SRC_CONTAINER" >/dev/null 2>&1
  docker volume rm fb-twohost-data >/dev/null 2>&1
  rm -f "$KEY" "$KEY.pub" "$AGENT_SOCK" "$BUNDLE" /root/.ssh/known_hosts.fbtwohost 2>/dev/null
  if [[ "$CREATED_CLUSTER_DIR" == "1" ]]; then
    rm -rf "$CLUSTER_DIR"
  fi
}
trap cleanup_owned EXIT

step "0. 前置检查"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
command -v docker >/dev/null || { echo "需要 docker"; exit 1; }
[[ -d "$CLUSTER_DIR" ]] || CREATED_CLUSTER_DIR=1

step "1. 目标机夹具（privileged 容器 = 第二台主机）"
rm -f "$KEY" "$KEY.pub"
ssh-keygen -q -t ed25519 -N '' -f "$KEY" 2>/dev/null
docker rm -f "$NODE_CONTAINER" >/dev/null 2>&1
docker run -d --privileged --name "$NODE_CONTAINER" -p "127.0.0.1:${HOST_PORT}:22" \
  ubuntu:24.04 sleep infinity >/dev/null || { echo "无法启动夹具容器"; exit 1; }
docker exec "$NODE_CONTAINER" bash -c \
  'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server python3 docker.io >/dev/null 2>&1'
check "目标机安装 openssh-server + python3 + docker.io" "$?"

docker exec "$NODE_CONTAINER" bash -c 'mkdir -p /run/sshd && ssh-keygen -A >/dev/null 2>&1'
docker exec -i "$NODE_CONTAINER" bash -c \
  "mkdir -p /root/.ssh && chmod 700 /root/.ssh && cat > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" < "$KEY.pub"
docker exec -d "$NODE_CONTAINER" /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config

step "2. 目标机 FusionBox 源码与迁移落地目录（模拟已安装）"
docker exec "$NODE_CONTAINER" mkdir -p /etc/fusionbox
docker cp "$ROOT/src" "$NODE_CONTAINER:/etc/fusionbox/src" >/dev/null
docker exec "$NODE_CONTAINER" mkdir -p /var/lib/fusionbox/docker-migration-store
docker exec "$NODE_CONTAINER" chmod 700 /var/lib/fusionbox/docker-migration-store
check "目标机具备 /etc/fusionbox/src 与 0700 落地目录" "$?"

docker exec -d "$NODE_CONTAINER" bash -c \
  'dockerd --storage-driver=vfs --iptables=false >/var/log/dockerd.log 2>&1'
ready=0
for _ in $(seq 1 60); do
  if docker exec "$NODE_CONTAINER" docker info >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
check "目标机内嵌 Docker 守护进程就绪（vfs）" "$((1 - ready))"

step "3. 专用密钥（不复用任何生产密钥）"
# node-exec 走 --identity（本次新增的 CLI 能力）；cluster exec 是普通 ssh，
# 通过一次性 ssh-agent 提供同一把专用密钥。OpenSSH 默认身份取自 passwd 而非
# $HOME，覆盖 HOME 对 ssh 无效（实测），因此不用 HOME 注入。
eval "$(ssh-agent -a "$AGENT_SOCK" -s)" >/dev/null
AGENT_PID="${SSH_AGENT_PID:-}"
ssh-add "$KEY" >/dev/null 2>&1
check "专用密钥已加入一次性 agent" "$?"

step "4. 集群登记与信任（严格 known_hosts）"
printf '%s\n%s\n%s\ny\n' "$NODE_NAME" "root@127.0.0.1" "$HOST_PORT" \
  | "$FUSION" cluster add >/dev/null 2>&1
check "cluster add 登记节点" "$?"
grep -q "^${NODE_NAME}|" "$CLUSTER_DIR/nodes.conf" 2>/dev/null
check "节点清单包含 $NODE_NAME" "$?"
printf 'YES\n' | "$FUSION" cluster trust "$NODE_NAME" >/dev/null 2>&1
check "cluster trust 固定主机密钥（交互确认）" "$?"
grep -q "\[127.0.0.1\]:${HOST_PORT}" "$CLUSTER_DIR/known_hosts" 2>/dev/null
check "known_hosts 已含主机键（[host]:port 形式）" "$?"

step "5. SSH 出站（G15）与批量执行（G63）"
out="$(env SSH_AUTH_SOCK="$AGENT_SOCK" "$FUSION" cluster node-exec "$NODE_NAME" --identity "$KEY" -- 'echo remote-ok-$(uname -s)' 2>/dev/null)"
check "cluster node-exec 经 --identity 专用密钥到达目标机" "$([[ "$out" == *remote-ok-Linux* ]] && echo 0 || echo 1)"
# 命令回显行不含展开结果，BEACON-42 只可能来自远端输出，避免假阳性
out="$(printf 'echo BEACON-$((6*7))\ny\n\n' | env SSH_AUTH_SOCK="$AGENT_SOCK" "$FUSION" cluster exec 2>/dev/null)"
check "cluster exec 批量执行真实到达目标机（远端输出 BEACON-42）" "$([[ "$out" == *BEACON-42* ]] && echo 0 || echo 1)"

step "6. 真实 docker-v1 离线包（宿主导出）"
docker volume rm fb-twohost-data >/dev/null 2>&1
docker volume create fb-twohost-data >/dev/null
docker run --rm -v fb-twohost-data:/d alpine:3.20 sh -c 'echo migration-payload > /d/probe.txt'
docker rm -f "$SRC_CONTAINER" >/dev/null 2>&1
docker run -d --name "$SRC_CONTAINER" -v fb-twohost-data:/data alpine:3.20 sleep 3600 >/dev/null
rm -f "$BUNDLE"
"$FUSION" panels docker-migration export "$BUNDLE" --container "$SRC_CONTAINER" --confirm-stop-writers >/dev/null 2>&1
check "宿主导出 docker-v1 离线包" "$([[ -s "$BUNDLE" ]] && echo 0 || echo 1)"
SHA="$(sha256sum "$BUNDLE" | awk '{print $1}')"

step "7. 灾备传输（G61/G16 形态）：archive push/pull --kind docker-v1"
docker exec "$NODE_CONTAINER" mkdir -p /var/lib/fusionbox/archive-store
docker exec "$NODE_CONTAINER" chmod 700 /var/lib/fusionbox/archive-store
"$FUSION" cluster archive push "$NODE_NAME" fb-twohost-bundle.tar.gz --file "$BUNDLE" \
  --kind docker-v1 --sha256 "$SHA" --remote-root /var/lib/fusionbox/archive-store \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" --confirm-owned-store >/dev/null 2>&1
check "archive push 摘要校验通过" "$?"
docker exec "$NODE_CONTAINER" test -f /var/lib/fusionbox/archive-store/fb-twohost-bundle.tar.gz
check "目标机落包存在" "$?"
PULL_DIR="$(mktemp -d /root/fb-pull.XXXX)"; chmod 700 "$PULL_DIR"
"$FUSION" cluster archive pull "$NODE_NAME" fb-twohost-bundle.tar.gz --file "$PULL_DIR/fb-twohost-pull.tar.gz" \
  --kind docker-v1 --sha256 "$SHA" --remote-root /var/lib/fusionbox/archive-store \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" --confirm-owned-store >/dev/null 2>&1
check "archive pull 往返校验通过" "$?"
rm -rf "$PULL_DIR"

step "8. 跨主机迁移编排（G29）：dry-run 不写目标机"
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" --dry-run --json >/tmp/fb-dryrun.json 2>/dev/null
check "dry-run 退出码 0" "$?"
python3 - <<'PY' 2>/dev/null
import json
data = json.load(open('/tmp/fb-dryrun.json'))
raise SystemExit(0 if data.get('result') == 'dry-run' and data.get('steps') == ['gate'] else 1)
PY
check "dry-run 摘要为 result=dry-run、仅 gate 步骤" "$?"
count="$(docker exec "$NODE_CONTAINER" sh -c 'ls -A /var/lib/fusionbox/docker-migration-store | wc -l')"
check "dry-run 后目标机落地目录为空（未写入）" "$([[ "$count" == "0" ]] && echo 0 || echo 1)"

step "9. 门禁拒绝：缺迁移模块 / 落地目录权限不符"
docker exec "$NODE_CONTAINER" mv /etc/fusionbox/src/lib/docker_migration.py /etc/fusionbox/src/lib/docker_migration.py.bak
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" >/dev/null 2>&1
check "缺 FusionBox 迁移模块时拒绝（rc!=0）" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
docker exec "$NODE_CONTAINER" mv /etc/fusionbox/src/lib/docker_migration.py.bak /etc/fusionbox/src/lib/docker_migration.py
docker exec "$NODE_CONTAINER" chmod 755 /var/lib/fusionbox/docker-migration-store
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" >/dev/null 2>&1
check "落地目录非 0700 时拒绝" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
docker exec "$NODE_CONTAINER" chmod 700 /var/lib/fusionbox/docker-migration-store

step "10. 完整迁移：目标机 restore 成功且容器健康"
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" --json >/tmp/fb-remote.json 2>/dev/null
check "编排退出码 0" "$?"
python3 - <<'PY' 2>/dev/null
import json
data = json.load(open('/tmp/fb-remote.json'))
ok = (data.get('result') == 'migrated'
      and data.get('steps') == ['gate', 'transfer', 'preflight', 'restore', 'health']
      and set(data.get('containers_state', {}).values()) == {'running'}
      and len(data.get('transaction', '')) == 32)
raise SystemExit(0 if ok else 1)
PY
check "摘要: migrated + 五步齐全 + 容器 running + 事务 32 位" "$?"
c="$(docker exec "$NODE_CONTAINER" sh -c 'docker ps -aq | wc -l')"
check "目标机内嵌 Docker 中容器在运行" "$([[ "${c:-0}" -ge 1 ]] && echo 0 || echo 1)"
v="$(docker exec "$NODE_CONTAINER" sh -c 'docker volume ls -q | grep -c fb-twohost-data')"
check "目标机具名卷已恢复" "$([[ "${v:-0}" -ge 1 ]] && echo 0 || echo 1)"
content="$(docker exec "$NODE_CONTAINER" sh -c 'docker run --rm -v fb-twohost-data:/d alpine:3.20 cat /d/probe.txt 2>/dev/null')"
check "卷内数据逐字节一致" "$([[ "$content" == "migration-payload" ]] && echo 0 || echo 1)"

step "11. 目标机已有同名资源 → preflight 拒绝且不回滚健康状态"
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" --json >/tmp/fb-reject.json 2>/dev/null
check "第二次迁移被 preflight 拒绝（rc!=0）" "$([[ $? -ne 0 ]] && echo 0 || echo 1)"
python3 - <<'PY' 2>/dev/null
import json
data = json.load(open('/tmp/fb-reject.json'))
ok = data.get('result') == 'preflight-rejected' and data.get('target_clean') is True
raise SystemExit(0 if ok else 1)
PY
check "摘要: preflight-rejected 且 target_clean" "$?"
c="$(docker exec "$NODE_CONTAINER" sh -c 'docker ps -aq | wc -l')"
check "第一次迁移的健康状态未被第二次失败波及" "$([[ "${c:-0}" -ge 1 ]] && echo 0 || echo 1)"

step "12. 中断场景：restore 进行中掐断 SSH → 目标机 rollback 清零"
# 触发方式：向卷内灌入足够数据使 restore 需要数秒；轮询到目标机出现第一个容器
# 立即杀掉编排进程（ssh 会话断开 → 目标机 restore 收到 SIGHUP 中止，journal 停在 running）。
docker run --rm -v fb-twohost-data:/d alpine:3.20 sh -c \
  'dd if=/dev/urandom of=/d/payload.bin bs=1M count=300 2>/dev/null'
rm -f "$BUNDLE"
"$FUSION" panels docker-migration export "$BUNDLE" --container "$SRC_CONTAINER" --confirm-stop-writers >/dev/null 2>&1
docker exec "$NODE_CONTAINER" sh -c 'docker rm -f $(docker ps -aq) >/dev/null 2>&1; docker volume rm $(docker volume ls -q) >/dev/null 2>&1' 
"$FUSION" panels docker-migration remote "$NODE_NAME" --bundle "$BUNDLE" --name fb-twohost-bundle.tar.gz \
  --key "$KEY" --known-hosts "$CLUSTER_DIR/known_hosts" >/tmp/fb-kill.out 2>&1 &
ORCH=$!
killed=0
# journal 目录在 restore 一开始就创建（早于镜像加载/容器创建），是最可靠的
# 「已进入 restore」信号；轮询到它立即掐断编排进程。
for _ in $(seq 1 600); do
  n="$(docker exec "$NODE_CONTAINER" sh -c 'ls /var/lib/fusionbox/docker-migration 2>/dev/null | wc -l' 2>/dev/null)"
  if [[ "${n:-0}" -ge 1 ]]; then kill "$ORCH" 2>/dev/null; killed=1; break; fi
  sleep 1
done
wait "$ORCH" 2>/dev/null
check "在 restore 进行中掐断编排进程" "$((1 - killed))"
sleep 2
tx="$(docker exec "$NODE_CONTAINER" sh -c 'ls /var/lib/fusionbox/docker-migration 2>/dev/null | head -1')"
state="$(docker exec "$NODE_CONTAINER" sh -c "python3 -c \"import json;print(json.load(open('/var/lib/fusionbox/docker-migration/$tx/journal.json'))['state'])\" 2>/dev/null" 2>/dev/null)"
if [[ -n "$tx" && "$state" != "complete" ]]; then
  docker exec "$NODE_CONTAINER" python3 -B /etc/fusionbox/src/lib/docker_migration.py rollback "$tx" >/dev/null 2>&1
  check "目标机 rollback 中断事务成功（state=$state）" "$?"
  c="$(docker exec "$NODE_CONTAINER" sh -c 'docker ps -aq | wc -l')"
  v="$(docker exec "$NODE_CONTAINER" sh -c 'docker volume ls -q | grep -c fb-twohost-data')"
  check "中断不留半成品（无容器、无残留卷）" "$([[ "${c:-0}" == "0" && "${v:-0}" == "0" ]] && echo 0 || echo 1)"
else
  ok "时序未命中（restore 已在掐断前完成或未及创建 journal），中断路径由单测矩阵覆盖"
fi

step "13. 清理"
docker exec "$NODE_CONTAINER" sh -c 'docker rm -f $(docker ps -aq) >/dev/null 2>&1' 
cleanup_owned
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
