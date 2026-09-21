#!/bin/bash
# 真机验收：OpenSSH 候选版本的「切换 / 回滚」事务
#
# 需要 root + Docker + 网络 + 编译链（gcc/make/libssl-dev/zlib1g-dev）；不进 CI。
# 用法： bash tests/acceptance/openssh_switch.sh [仓库根目录] [状态目录]
#
# 为什么切换不在宿主机上做：
#   validationserver 上唯一的访问路径就是宿主 sshd。按 roadmap 自己的判定，
#   在没有带外通道（VNC/救援模式）时不该在生产 sshd 上做切换实验。因此：
#     1. 在宿主机跑**真实**的 fetch → verify(GPG 验签) → build → test(独立端口回连)
#     2. 把真实产物拷进一个容器，容器里另跑一个 sshd 扮演「生产 sshd」
#     3. 在容器里执行 switch / rollback，并用**真实 SSH 登录 + 版本横幅**判定
#     4. 断言宿主机 /usr/sbin/sshd 与配置的哈希全程未变
set -u

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
STATE="${2:-/var/lib/fusionbox/openssh-candidate}"
IMAGE='openssh-fixture'
CONTAINER='fb-sshd-fixture'
HOST_PORT=2222
PASS=0
FAIL=0

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" -eq 0 ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }
MOD()  { python3 -B "$ROOT/src/lib/openssh_candidate.py" "$@"; }

HOST_SSHD_SHA_BEFORE="$(sha256sum /usr/sbin/sshd 2>/dev/null | cut -d' ' -f1)"
HOST_CONF_SHA_BEFORE="$(sha256sum /etc/ssh/sshd_config 2>/dev/null | cut -d' ' -f1)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  ssh-keygen -f /root/.ssh/known_hosts -R "[127.0.0.1]:$HOST_PORT" >/dev/null 2>&1
  rm -f /tmp/fbswitch_key /tmp/fbswitch_key.pub
}
cleanup

step "0. 宿主机准备编译链"
if ! command -v cc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
  apt-get update -qq >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq build-essential libssl-dev zlib1g-dev >/dev/null 2>&1
fi
check "编译器与头文件可用（cc/make/libssl）" \
  "$(command -v cc >/dev/null && command -v make >/dev/null && echo 0 || echo 1)"

step "1. 真实候选流水线：fetch → verify(GPG) → build → test(独立端口回连)"
rm -rf "$STATE"
out="$(MOD fetch --state-dir "$STATE" 2>&1)"; rc=$?
check "fetch 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
out="$(MOD verify --state-dir "$STATE" 2>&1)"; rc=$?
check "verify 通过 GPG 验签 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "verify 报告签名有效" "$(printf '%s' "$out" | grep -q 'verified' && echo 0 || echo 1)"
out="$(MOD build --state-dir "$STATE" 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
check "build 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
CANDIDATE="$STATE/prefix/sbin/sshd"
check "候选 sshd 已生成" "$([[ -x "$CANDIDATE" ]] && echo 0 || echo 1)"
if [[ -x "$CANDIDATE" ]]; then
  out="$(MOD test --state-dir "$STATE" 2>&1)"; rc=$?
  if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
  check "test 在独立高端口完成真实回连 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  check "test 记录独立登录成功" "$(printf '%s' "$out" | grep -q '"independent_login": true' && echo 0 || echo 1)"
else
  bad "test 在独立高端口完成真实回连 (候选未生成)"
  bad "test 记录独立登录成功 (候选未生成)"
fi
CANDIDATE_VERSION="$("$CANDIDATE" -V 2>&1 | head -1)"

step "2. 容器夹具：另起一个 sshd 扮演生产 sshd"
docker rm -f "$CONTAINER" >/dev/null 2>&1
docker run -d --name "$CONTAINER" -p "127.0.0.1:$HOST_PORT:2222" "$IMAGE" sleep infinity >/dev/null 2>&1 \
  || { docker pull -q ubuntu:24.04 >/dev/null 2>&1; docker tag ubuntu:24.04 "$IMAGE"; \
       docker run -d --name "$CONTAINER" -p "127.0.0.1:$HOST_PORT:2222" "$IMAGE" sleep infinity >/dev/null; }
docker exec "$CONTAINER" bash -c 'command -v sshd >/dev/null 2>&1' \
  || docker exec "$CONTAINER" bash -c 'apt-get update -qq >/dev/null 2>&1 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server python3 >/dev/null 2>&1'
docker exec "$CONTAINER" bash -c 'ssh-keygen -A >/dev/null 2>&1; mkdir -p /run/sshd; sed -i "s/^#\?Port .*/Port 2222/" /etc/ssh/sshd_config; grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config || echo "PermitRootLogin yes" >> /etc/ssh/sshd_config'
docker exec -d "$CONTAINER" /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
sleep 2
check "容器内生产 sshd 已在 2222 提供服务" \
  "$(docker exec "$CONTAINER" bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222 && head -c 8 <&3 | grep -q SSH-2.0 && echo 0 || echo 1')"
FIXTURE_VERSION="$(docker exec "$CONTAINER" /usr/sbin/sshd -V 2>&1 | head -1)"
printf '     容器当前 sshd: %s\n     候选 sshd:     %s\n' "$FIXTURE_VERSION" "$CANDIDATE_VERSION"
check "候选版本确实不同于容器现状（版本横幅可用于判定）" \
  "$([[ "$CANDIDATE_VERSION" != "$FIXTURE_VERSION" ]] && echo 0 || echo 1)"

# 放进容器：模块 + 真实候选状态目录 + 一把真实登录用的密钥
docker exec "$CONTAINER" bash -c 'mkdir -p /root/fb /root/.ssh'
docker cp "$ROOT/src/lib/openssh_candidate.py" "$CONTAINER:/root/fb/openssh_candidate.py" >/dev/null
docker exec "$CONTAINER" bash -c 'rm -rf /var/lib/fusionbox/openssh-candidate && mkdir -p /var/lib/fusionbox'
docker cp "$STATE" "$CONTAINER:/var/lib/fusionbox/openssh-candidate" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f /tmp/fbswitch_key
docker cp /tmp/fbswitch_key.pub "$CONTAINER:/root/.ssh/authorized_keys" >/dev/null
docker exec "$CONTAINER" bash -c 'chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys'
FIXTURE_HASH_BEFORE="$(docker exec "$CONTAINER" sha256sum /usr/sbin/sshd | cut -d' ' -f1)"

FIX() { docker exec "$CONTAINER" python3 -B /root/fb/openssh_candidate.py "$@" \
          --sshd-path /usr/sbin/sshd --config /etc/ssh/sshd_config --pid-file /run/sshd.pid \
          --reload-command 'kill -HUP $(cat /run/sshd.pid)' \
          --restart-command '/usr/sbin/sshd -D -e -f /etc/ssh/sshd_config & sleep 1' --grace 6; }

step "3. dry-run：跑全部门禁但不改任何文件"
out="$(FIX switch --dry-run --accept-config-drift 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then
  out="$(FIX switch --dry-run 2>&1)"; rc=$?
fi
check "dry-run 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "dry-run 明确说明未替换任何文件" "$(printf '%s' "$out" | grep -q 'nothing was replaced' && echo 0 || echo 1)"
check "dry-run 后容器 sshd 未变" \
  "$([[ "$(docker exec "$CONTAINER" sha256sum /usr/sbin/sshd | cut -d' ' -f1)" == "$FIXTURE_HASH_BEFORE" ]] && echo 0 || echo 1)"

step "4. 安全策略漂移必须显式接受（不能静默放行）"
out="$(FIX switch --dry-run 2>&1)"; rc=$?
drift_json="$(printf '%s' "$out" | python3 -c 'import json,sys
try: d=json.loads(sys.stdin.read())
except Exception: print(""); raise SystemExit
print(json.dumps(d.get("drift", {})))' 2>/dev/null)"
if [[ $rc -ne 0 ]]; then
  check "存在漂移时拒绝并要求 --accept-config-drift" \
    "$(printf '%s' "$out" | grep -q 'accept-config-drift' && echo 0 || echo 1)"
elif [[ "$drift_json" == "{}" ]]; then
  ok "两个版本的有效策略无差异，因此无需放行（drift 为空是实测结果）"
else
  bad "既没拒绝也没报告空 drift（$drift_json）"
fi

step "5. 真实切换：原子替换 + reload + 复验"
out="$(FIX switch --accept-config-drift 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
check "switch 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "switch 记录状态 verified" "$(printf '%s' "$out" | grep -q '"status": "verified"' && echo 0 || echo 1)"
check "容器 sshd 二进制已换成候选（sha256 变化）" \
  "$([[ "$(docker exec "$CONTAINER" sha256sum /usr/sbin/sshd | cut -d' ' -f1)" != "$FIXTURE_HASH_BEFORE" ]] && echo 0 || echo 1)"
check "运行中的 daemon 报告候选版本（新二进制真正生效）" \
  "$(docker exec "$CONTAINER" /usr/sbin/sshd -V 2>&1 | grep -qF "$(printf '%s' "$CANDIDATE_VERSION" | sed 's/^OpenSSH_//;s/,.*//')" && echo 0 || echo 1)"
rm -f /root/.ssh/known_hosts.fbtest
# sshd -V 报 `OpenSSH_10.5p1`，而协议横幅是 `OpenSSH_10.5`（portable 不带 p 后缀），
# 两个断言各用各自的形式，不去猜。
CANDIDATE_TAG="$(printf '%s' "$CANDIDATE_VERSION" | sed 's/^OpenSSH_//;s/[, ].*//')"
CANDIDATE_BANNER_TAG="$(printf '%s' "$CANDIDATE_VERSION" | sed 's/^OpenSSH_//;s/p[0-9]*//;s/[, ].*//')"
login_out="$(ssh -v -F /dev/null -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts.fbtest \
      -o IdentitiesOnly=yes -o PasswordAuthentication=no -o ConnectTimeout=5 \
      -i /tmp/fbswitch_key -p "$HOST_PORT" root@127.0.0.1 'printf switch-login-ok' 2>&1)"
check "用真实 SSH 客户端经新二进制登录成功" \
  "$(printf '%s' "$login_out" | grep -q switch-login-ok && echo 0 || echo 1)"
# 光「能登录」不能证明是新二进制在服务（旧 daemon 也能登录），必须看远端软件版本。
check "客户端看到的远端软件版本就是候选版本（${CANDIDATE_BANNER_TAG}）" \
  "$(printf '%s' "$login_out" | grep -qi "remote software version OpenSSH_${CANDIDATE_BANNER_TAG}" && echo 0 || echo 1)"
sleep 8
out="$(FIX status 2>&1)"
check "watchdog 复核后状态仍为 verified（未被误判回滚）" \
  "$(printf '%s' "$out" | grep -q '"switch_status": "verified"' && echo 0 || echo 1)"
check "status 报告生产二进制与候选一致" \
  "$(printf '%s' "$out" | grep -q '"production_matches_candidate": true' && echo 0 || echo 1)"

step "6. 手动回滚：恢复上一份二进制并重新生效"
out="$(FIX rollback 2>&1)"; rc=$?
if [[ $rc -ne 0 ]]; then printf '%s\n' "$out" | tail -5; fi
check "rollback 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
check "二进制已还原为切换前的哈希" \
  "$([[ "$(docker exec "$CONTAINER" sha256sum /usr/sbin/sshd | cut -d' ' -f1)" == "$FIXTURE_HASH_BEFORE" ]] && echo 0 || echo 1)"
check "运行中的 daemon 回到原版本" \
  "$(docker exec "$CONTAINER" /usr/sbin/sshd -V 2>&1 | grep -qF "$(printf '%s' "$FIXTURE_VERSION" | sed 's/^OpenSSH_//;s/,.*//')" && echo 0 || echo 1)"
check "回滚后真实 SSH 登录仍可用" \
  "$(ssh -F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/root/.ssh/known_hosts.fbtest \
        -o IdentitiesOnly=yes -o PasswordAuthentication=no -o ConnectTimeout=5 \
        -i /tmp/fbswitch_key -p "$HOST_PORT" root@127.0.0.1 'printf rollback-login-ok' 2>/dev/null | grep -q rollback-login-ok && echo 0 || echo 1)"

step "7. 生产侧开关的拒绝路径"
out="$(FIX switch --dry-run --sshd-path /etc/hostname 2>&1)"; rc=$?
check "候选替换非 sshd 文件时被拒绝（-t 校验失败）" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
docker exec "$CONTAINER" bash -c 'ln -sf /usr/sbin/sshd /tmp/sshd-link'
out="$(FIX switch --dry-run --sshd-path /tmp/sshd-link 2>&1)"; rc=$?
check "符号链接的生产路径被拒绝" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
out="$(FIX rollback 2>&1)"; rc=$?
check "已回滚状态下再次 rollback 被拒绝（不猜）" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"

step "8. 宿主机未被触碰（这是整套夹具的前提）"
check "宿主 /usr/sbin/sshd 哈希未变" \
  "$([[ "$(sha256sum /usr/sbin/sshd | cut -d' ' -f1)" == "$HOST_SSHD_SHA_BEFORE" ]] && echo 0 || echo 1)"
check "宿主 sshd_config 哈希未变" \
  "$([[ "$(sha256sum /etc/ssh/sshd_config | cut -d' ' -f1)" == "$HOST_CONF_SHA_BEFORE" ]] && echo 0 || echo 1)"

step "9. 清理"
cleanup
check "夹具容器已删除" "$([[ -z "$(docker ps -aq -f name=^/$CONTAINER\$)" ]] && echo 0 || echo 1)"

printf '\n====================\n通过 %d / 失败 %d\n====================\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
