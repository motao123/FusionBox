#!/bin/bash
# B5 真机验收（v1.40.0）：网络参数优化真实改值 + 快照恢复（G18/G67 的真实执行），
# 不进 CI。验证服务器是专用环境（roadmap B5 的判定），本脚本执行真实 sysctl
# 改动并从快照恢复，任何中断路径都恢复原值。
# 用法: bash tests/acceptance/netopt_sysctl.sh [仓库根目录]
set -u
ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" || exit 1
FUSION="$ROOT/fusion.sh"
FILE=/etc/sysctl.d/99-fusionbox-netopt.conf
SNAP=/etc/fusionbox/netopt-original.conf
KEYS=(net.core.rmem_max net.core.wmem_max net.core.somaxconn net.ipv4.tcp_fastopen net.ipv4.netdev_max_backlog)

PASS=0
FAIL=0
ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check(){ if [[ "$2" == "0" ]]; then ok "$1"; else bad "$1"; fi; }
step() { printf '\n== %s ==\n' "$1"; }

cur() { sysctl -n "$1" 2>/dev/null; }

restore_hard() {
  # 与 _system_netopt_reset 相同语义的兜底：按快照回写运行值并清理文件
  if [[ -f "$SNAP" ]]; then
    while IFS= read -r line; do
      k="${line%% =*}"; k="${k// /}"
      v="${line##*= }"
      [[ -n "$k" && -n "$v" ]] && sysctl -w "$k=$v" >/dev/null 2>&1
    done < "$SNAP"
  fi
  rm -f "$FILE"
}
trap 'restore_hard' EXIT

step "0. 前置"
[[ $EUID -eq 0 ]] || { echo "需要 root"; exit 1; }
[[ ! -f "$FILE" ]] || { echo "已存在优化文件（$FILE），请先手动恢复后再跑"; exit 1; }
[[ ! -f "$SNAP" ]] || { echo "已存在快照（$SNAP），请先手动恢复后再跑"; exit 1; }

step "1. 基线记录"
for k in net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default \
         net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.somaxconn net.core.netdev_max_backlog \
         net.ipv4.ip_local_port_range net.ipv4.tcp_fastopen net.ipv4.tcp_tw_reuse; do
  cur "$k" > /tmp/fb-netopt-base-"$k" 2>/dev/null || { echo "无法读取 $k"; exit 1; }
done
base_somaxconn="$(cur net.core.somaxconn)"
ok "11 个键的运行值已记录（somaxconn=$base_somaxconn）"

# sysctl -n 对多值键用 tab 分隔，比较前统一归一化空白
norm() { cur "$1" | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//'; }

# 100M-1G 档的目标值（必须与 src/modules/system.sh 的档位 2 一致）
declare -A TIER2=(
  [net.core.rmem_max]=16777216 [net.core.wmem_max]=16777216
  [net.core.rmem_default]=1048576 [net.core.wmem_default]=1048576
  [net.ipv4.tcp_rmem]='4096 87380 16777216' [net.ipv4.tcp_wmem]='4096 65536 16777216'
  [net.core.somaxconn]=4096 [net.core.netdev_max_backlog]=4096
  [net.ipv4.ip_local_port_range]='1024 65535'
  [net.ipv4.tcp_fastopen]=3 [net.ipv4.tcp_tw_reuse]=1
)

step "2. 真实应用 100M-1G 档"
printf '2\ny\n\n0\n' | "$FUSION" system netopt >/tmp/fb-netopt-apply.log 2>&1
check "菜单应用退出" "$?"
[[ -f "$FILE" ]]; check "优化文件已生成" "$?"
# 强断言：运行时值必须等于档位目标（不看基线，任何系统默认值下都成立）
target_bad=0
for k in "${!TIER2[@]}"; do
  if [[ "$(norm "$k")" != "${TIER2[$k]}" ]]; then
    target_bad=1
    echo "    未生效: $k=$(norm "$k") 目标=${TIER2[$k]}"
  fi
done
check "11 个键运行时值全部等于档位目标（真实生效）" "$target_bad"
# 弱断言：至少一个键相对基线发生变化（证明确有可观测改动，兼容默认值恰好相同的键）
changed=0
for k in "${!TIER2[@]}"; do
  [[ "$(norm "$k")" != "$(cat /tmp/fb-netopt-base-"$k" | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//')" ]] && changed=$((changed + 1))
done
check "至少一个键相对基线真实改变（实测 $changed/11 个）" \
  "$([[ $changed -gt 0 ]] && echo 0 || echo 1)"
[[ -f "$SNAP" ]]; check "首次应用前快照已保存" "$?"
snap_ok=0
while IFS= read -r line; do
  k="${line%% =*}"; k="${k// /}"; v="${line##*= }"
  [[ "$v" == "$(cat /tmp/fb-netopt-base-"$k")" ]] || { snap_ok=1; break; }
done < "$SNAP"
check "快照内容与基线逐键一致" "$snap_ok"

step "3. 真实恢复默认"
printf '4\ny\n\n0\n' | "$FUSION" system netopt >/tmp/fb-netopt-reset.log 2>&1
check "菜单恢复退出" "$?"
[[ ! -f "$FILE" ]]; check "优化文件已删除" "$?"
[[ ! -f "$SNAP" ]]; check "快照已清理" "$?"
diff_ok=0
for k in net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default \
         net.ipv4.tcp_rmem net.ipv4.tcp_wmem net.core.somaxconn net.core.netdev_max_backlog \
         net.ipv4.ip_local_port_range net.ipv4.tcp_fastopen net.ipv4.tcp_tw_reuse; do
  [[ "$(cur "$k")" == "$(cat /tmp/fb-netopt-base-"$k")" ]] || { diff_ok=1; echo "    漂移: $k=$(cur "$k") 基线=$(cat /tmp/fb-netopt-base-"$k")"; }
done
check "恢复后 11 个键与基线逐键一致（无漂移）" "$diff_ok"

step "4. 清理"
rm -f /tmp/fb-netopt-base-* 2>/dev/null
printf '\n== 结果 ==\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
