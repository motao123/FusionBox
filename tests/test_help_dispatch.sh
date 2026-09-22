#!/bin/bash
# FusionBox 帮助分发 / 未知子命令 / 配置生效 / 时区预设 回归测试
#
# 设计原则：
#   * 不需要 root，不修改系统，不联网（匿名统计默认关闭，测试 HOME 也没有 config）；
#   * 帮助分发走真实 CLI（`fusion.sh help <模块>`），未知子命令在函数层验证，
#     避免 fusion.sh 对非 help 命令的 root 门禁；
#   * 每个模块只调用一次 CLI，控制子进程数量；
#   * 只断言真实存在的行为，不为“看起来通过”放宽条件。
#
# 运行: bash tests/test_help_dispatch.sh
set -u

FUSION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$FUSION_DIR" || exit 1
PASS=0
FAIL=0

test() {
  local name="$1" result="$2"
  if [[ "$result" -eq 0 ]]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

_strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# 帮助末尾的「本机状态」是实时探测（docker 守护进程响应快慢等），两次调用之间
# 可以合法地不同。所有「两种写法输出一致」的断言都必须先归一化这一行，
# 否则会得到与真实行为无关的假失败（CI 上已出现过）。
_help_normalized() {
  sed 's/\x1b\[[0-9;]*m//g' | awk '/本机状态/ { print; getline; print "    <本机状态>"; next } { print }'
}

# 真实入口：优先直接执行；若可执行位在传输中丢失（如 SFTP 拷贝），退回 `bash fusion.sh`，
# 这样测试校验的始终是同一份脚本逻辑，而不是文件权限。
if [[ -x ./fusion.sh ]]; then
  FUSION_CLI=(./fusion.sh)
else
  FUSION_CLI=(bash ./fusion.sh)
fi

# 隔离 HOME：避免读写真实用户配置，也避免匿名统计被意外打开
TMP_HOME="$(mktemp -d)"
trap 'rm -rf -- "$TMP_HOME" 2>/dev/null || true' EXIT
export HOME="$TMP_HOME"
export FUSION_BASE="$FUSION_DIR"
export FUSION_SRC="$FUSION_DIR/src"

echo "FusionBox Help / Subcommand / Config Tests"
echo "========================================="

MODULES="proxy system network web panels market warp workspace cluster"

# ------------------------------------------------- 1. 帮助分发（端到端，走真实 CLI）
echo ""
echo "--- 1. 模块帮助分发 ---"
CMD_LINES=0
for m in $MODULES; do
  out="$("${FUSION_CLI[@]}" help "$m" < /dev/null 2>&1)"
  rc=$?
  clean="$(printf '%s' "$out" | _strip_ansi)"
  test "help $m 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  test "help $m 打印 $m 命令清单" "$(printf '%s\n' "$clean" | grep -qE "^  +fusionbox $m" && echo 0 || echo 1)"
  test "help $m 附本机状态行" "$(printf '%s\n' "$clean" | grep -q "本机状态" && echo 0 || echo 1)"
  n="$(printf '%s\n' "$clean" | grep -cE "^  +fusionbox ")"
  CMD_LINES=$((CMD_LINES + n))
done
test "模块帮助命令条目 >= 100 (实际 $CMD_LINES)" "$([[ "$CMD_LINES" -ge 100 ]] && echo 0 || echo 1)"

# 别名：每组别名必须与规范名命中同一份帮助
ALIAS_CASES="
p:proxy:代理管理
sys:system:系统管理
s:system:系统管理
net:network:网络工具
n:network:网络工具
w:web:网站部署
lnmp:web:网站部署
panels:panels:面板与工具
tools:panels:面板与工具
market:market:应用市场
apps:market:应用市场
warp:warp:WARP
ws:workspace:后台工作区
cl:cluster:集群控制
"
while IFS=: read -r alias canonical title; do
  [[ -n "$alias" ]] || continue
  out="$("${FUSION_CLI[@]}" help "$alias" < /dev/null 2>&1)"
  rc=$?
  clean="$(printf '%s' "$out" | _strip_ansi)"
  test "help $alias -> $canonical (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  test "help $alias 命中「$title」" "$(printf '%s\n' "$clean" | grep -q "$title" && echo 0 || echo 1)"
done <<< "$ALIAS_CASES"

# 未知模块必须非零退出并给出可用模块列表
out="$("${FUSION_CLI[@]}" help no-such-module < /dev/null 2>&1)"
rc=$?
test "help <未知模块> 退出码非零 (rc=$rc)" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
test "help <未知模块> 提示可用模块" "$(printf '%s' "$out" | grep -q "可用模块" && echo 0 || echo 1)"

# 两种写法必须一致（route 层归一化，而不是让 9 个模块各自调用 show_help）。
# 帮助末尾的「本机状态」是实时探测，两次调用之间可以合法地不同，因此先归一化该行；
# 该行本身在下面单独断言非空，避免「归一化把问题一起抹掉」。
for m in $MODULES; do
  a="$("${FUSION_CLI[@]}" help "$m" < /dev/null 2>&1)"
  ra=$?
  b="$("${FUSION_CLI[@]}" "$m" help < /dev/null 2>&1)"
  rb=$?
  test "$m: help <模块> 与 <模块> help 输出一致" \
    "$([[ "$(printf '%s' "$a" | _help_normalized)" == "$(printf '%s' "$b" | _help_normalized)" ]] && echo 0 || echo 1)"
  test "$m: 本机状态行非空" \
    "$(printf '%s' "$a" | awk '/本机状态/ { getline; if (length($0) > 0) found = 1 } END { exit !found }' && echo 0 || echo 1)"
  test "$m: 两种写法退出码均为 0 (ra=$ra rb=$rb)" \
    "$([[ $ra -eq 0 && $rb -eq 0 ]] && echo 0 || echo 1)"
done

# 本机状态是实时探测：两次调用之间可能合法地不同（首次超时、第二次成功）。
# 这正是曾在 CI 上真实出现的 flake（同一提交一次通过一次失败），因此在这里固定下来：
# 即使探测结果不同，两种写法归一化后也必须一致。
echo ""
echo "--- 1b. 探测结果变动时两种写法仍一致（flake 回归）---"
if command -v timeout >/dev/null 2>&1; then
  SHIM_DIR="$TMP_HOME/shim"; mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/docker" <<'SHIM'
#!/bin/sh
count_file="${FUSION_TEST_DOCKER_COUNT:-/tmp/fusionbox-docker-count}"
seen=$(cat "$count_file" 2>/dev/null || echo 0); seen=$((seen + 1)); printf '%s' "$seen" > "$count_file"
[ "$seen" -le 1 ] && sleep 10    # 第一次调用故意超过探测超时
printf '29.8.1\n'
SHIM
  chmod +x "$SHIM_DIR/docker"
  export FUSION_TEST_DOCKER_COUNT="$TMP_HOME/docker-count"
  rm -f "$FUSION_TEST_DOCKER_COUNT"
  a_raw="$(PATH="$SHIM_DIR:$PATH" "${FUSION_CLI[@]}" help panels < /dev/null 2>&1)"
  b_raw="$(PATH="$SHIM_DIR:$PATH" "${FUSION_CLI[@]}" panels help < /dev/null 2>&1)"
  test "夹具有效：探测结果在两次调用间确实不同" \
    "$([[ "$a_raw" != "$b_raw" ]] && echo 0 || echo 1)"
  test "探测结果变动时两种写法归一化后仍一致" \
    "$([[ "$(printf '%s' "$a_raw" | _help_normalized)" == "$(printf '%s' "$b_raw" | _help_normalized)" ]] && echo 0 || echo 1)"
  test "探测超时时给出诚实的「未响应」而不是「未安装」" \
    "$(printf '%s' "$a_raw" | grep -q "守护进程未响应" && echo 0 || echo 1)"
else
  echo "  SKIP: 未找到 timeout，跳过探测超时夹具（不影响其他断言）"
fi

# panels docker 子命令也应能取到帮助
out="$("${FUSION_CLI[@]}" panels docker help < /dev/null 2>&1)"
rc=$?
test "panels docker help 退出码 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
test "panels docker help 输出命令清单" \
  "$(printf '%s' "$out" | grep -q "fusionbox panels docker" && echo 0 || echo 1)"

# 总帮助仍可用，并指引到模块帮助
out="$("${FUSION_CLI[@]}" help < /dev/null 2>&1)"
test "help 指向模块详细帮助" "$(printf '%s' "$out" | grep -q "fusionbox help <模块>" && echo 0 || echo 1)"

# ------------------------------------------------- 2. 未知子命令
echo ""
echo "--- 2. 未知子命令守卫 ---"
# shellcheck disable=SC1090
. "$FUSION_SRC/init.sh" >/dev/null 2>&1

for m in $MODULES; do
  _load_module "$m" >/dev/null 2>&1
  test "模块 $m 可加载" "$(declare -F "${m}_main" >/dev/null && echo 0 || echo 1)"
done

for m in $MODULES; do
  out="$("${m}_main" definitely-not-a-command 2>&1)"
  rc=$?
  test "$m 未知子命令返回非零 (rc=$rc)" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  test "$m 未知子命令输出明确报错" "$(printf '%s' "$out" | grep -q "未知子命令" && echo 0 || echo 1)"
  test "$m 未知子命令给出 help 提示" "$(printf '%s' "$out" | grep -q "help" && echo 0 || echo 1)"
done

# help 参数不能被守卫误伤
for m in $MODULES; do
  out="$("${m}_main" help 2>&1)"
  rc=$?
  test "$m <help> 仍返回 0 (rc=$rc)" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  test "$m <help> 输出命令清单" "$(printf '%s' "$out" | grep -q "fusionbox $m" && echo 0 || echo 1)"
done

# 菜单函数仍然存在（无参路径未被破坏）
test "所有模块菜单入口函数存在" \
  "$(for m in $MODULES; do declare -F "${m}_menu" >/dev/null || exit 1; done; echo 0)"

# ------------------------------------------------- 3. 时区预设 (G07)
echo ""
echo "--- 3. 时区预设 ---"
PRESET_BLOCK="$(sed -n '/^SYSTEM_TZ_PRESETS=(/,/^)/p' src/modules/system.sh)"
# 文案已走语言包：源码数调用点，三字段格式在语言包里校验
TZ_COUNT="$(printf '%s\n' "$PRESET_BLOCK" | grep -cE '^  "\$\(L MSG_SYS_[0-9]+\)"$')"
test "时区预设数量 >= 20 (实际 $TZ_COUNT)" "$([[ "$TZ_COUNT" -ge 20 ]] && echo 0 || echo 1)"
TZ_PACK="$(grep -cE '^MSG_SYS_[0-9]+="[^|]+\|[^|]+\|[^|]+"$' src/i18n/zh_CN.sh)"
test "时区预设全部为 区域|标识|名称 三字段 (语言包 $TZ_PACK 条)" "$([[ "$TZ_PACK" -ge 20 ]] && echo 0 || echo 1)"
test "存在 _system_tz_apply 校验函数" \
  "$(grep -q '^_system_tz_apply()' src/modules/system.sh && echo 0 || echo 1)"

# ------------------------------------------------- 4. 配置键真实生效
echo ""
echo "--- 4. 配置键生效 ---"
CFG_CONF="$TMP_HOME/.config/fusionbox/config.yaml"
mkdir -p "$(dirname "$CFG_CONF")"
cp configs/config.yaml "$CFG_CONF"

_load_config
test "general.lang 被读取" "$([[ -n "${CONFIG_general_lang:-}" ]] && echo 0 || echo 1)"
test "general.stats 被读取" "$([[ -n "${CONFIG_general_stats:-}" ]] && echo 0 || echo 1)"
test "system.monitor_interval 被读取" \
  "$([[ "${CONFIG_system_monitor_interval:-}" == "5" ]] && echo 0 || echo 1)"
test "system.backup_dir 被读取" \
  "$([[ "${CONFIG_system_backup_dir:-}" == "/root/backups" ]] && echo 0 || echo 1)"
test "network.speedtest_server 被读取" \
  "$([[ "${CONFIG_network_speedtest_server:-}" == "auto" ]] && echo 0 || echo 1)"

test "general.color=true 保留 ANSI 颜色" "$([[ -n "$F_RED" ]] && echo 0 || echo 1)"

# 关闭彩色 -> 所有 ANSI 变量清空（写临时文件再替换，避免 sed -i 的跨平台差异）
sed 's/^  color: true/  color: false/' "$CFG_CONF" > "$CFG_CONF.new" && mv "$CFG_CONF.new" "$CFG_CONF"
_load_config
test "general.color=false 清空 ANSI 颜色" \
  "$([[ -z "$F_RED" && -z "$F_GREEN" && -z "$F_BOLD" && -z "$F_RESET" ]] && echo 0 || echo 1)"
test "general.color=false 时 F_COLOR=0" "$([[ "$F_COLOR" -eq 0 ]] && echo 0 || echo 1)"

echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================="
exit $FAIL
