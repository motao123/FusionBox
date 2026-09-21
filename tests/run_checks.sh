#!/usr/bin/env bash
# FusionBox v1.35.0 regression checks.
#
# These checks lock in the shipped UX fixes: dependency preflight, backup scope
# skipping, Chinese help for raw passthrough subcommands, i18n coverage, CPU
# accounting, numbered workspace slots, update changelog display, long-task
# stage progress and the SSH-resident workspace. They must run without root,
# without Docker and without network access so CI stays deterministic.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/src"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED_NAMES=()

ok()   { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

# check <name> <expected-substring> <command...>
check_contains() {
  local name="$1" needle="$2"; shift 2
  local out
  out="$("$@" 2>&1)"
  if grep -qF -- "$needle" <<<"$out"; then
    ok "$name"
  else
    bad "$name (期望包含: $needle)"
    printf '%s\n' "$out" | sed 's/^/       | /' | head -15
  fi
}

check_absent() {
  local name="$1" needle="$2"; shift 2
  local out
  out="$("$@" 2>&1)"
  if grep -qF -- "$needle" <<<"$out"; then
    bad "$name (不应包含: $needle)"
    printf '%s\n' "$out" | sed 's/^/       | /' | head -15
  else
    ok "$name"
  fi
}

check_exit() {
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then ok "$name"; else bad "$name (exit=$got, 期望 $want)"; fi
}

section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# ---------------------------------------------------------------------------
section "1. 语法 / 导入"
# ---------------------------------------------------------------------------
for f in "$REPO_ROOT/fusion.sh" "$REPO_ROOT/install.sh" "$SRC/init.sh" \
         "$SRC/lib/common.sh" "$SRC/lib/deploy.sh" "$SRC"/modules/*.sh "$SRC"/i18n/*.sh; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n $(basename "$f")"; else bad "bash -n $f"; fi
done
if PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile "$SRC"/lib/*.py "$REPO_ROOT"/scripts/*.py 2>/dev/null; then
  ok "python 语法编译"
else
  bad "python 语法编译"
fi

# ---------------------------------------------------------------------------
section "2. P2: 裸透传入口无参输出中文帮助"
# ---------------------------------------------------------------------------
check_contains "market_apps.py 无参 -> 中文" "受管应用生命周期" \
  python3 "$SRC/lib/market_apps.py"
check_absent "market_apps.py 无参不暴露 argparse 英文" "the following arguments are required" \
  python3 "$SRC/lib/market_apps.py"
check_contains "compose_backup.py 无参 -> 中文" "受管 Compose 备份" \
  python3 "$SRC/lib/compose_backup.py"
check_absent "compose_backup.py 无参不暴露 argparse 英文" "the following arguments are required" \
  python3 "$SRC/lib/compose_backup.py"
check_contains "docker_migration.py 无参 -> 中文" "Docker 离线迁移" \
  python3 "$SRC/lib/docker_migration.py"
check_absent "docker_migration.py 无参不暴露 argparse 英文" "the following arguments are required" \
  python3 "$SRC/lib/docker_migration.py"
check_contains "market_apps.py 非法参数 -> 中文" "参数有误" \
  python3 "$SRC/lib/market_apps.py" bogus-action

# ---------------------------------------------------------------------------
section "3. P2: docker / compose 前置检查给中文原因"
# ---------------------------------------------------------------------------
STUB="$WORK/stub"
mkdir -p "$STUB"
# docker CLI present, daemon OK, compose subcommand missing.
cat > "$STUB/docker" <<'DOCKER'
#!/usr/bin/env bash
if [[ "$1" == "--host" && "$3" == "info" ]]; then exit 0; fi
if [[ "$1" == "--host" && "$3" == "compose" ]]; then exit 1; fi
exit 0
DOCKER
chmod +x "$STUB/docker"
check_contains "缺 compose v2 -> 中文说明" "Docker Compose v2" \
  env PATH="$STUB:/usr/bin:/bin" python3 "$SRC/lib/market_apps.py" install nginx
check_absent "缺 compose 不出现「输出已隐藏」" "output withheld" \
  env PATH="$STUB:/usr/bin:/bin" python3 "$SRC/lib/market_apps.py" install nginx

# No docker at all.
EMPTY="$WORK/emptypath"
mkdir -p "$EMPTY"
for b in python3 env sh bash grep cat; do
  p="$(command -v "$b" 2>/dev/null)" && ln -sf "$p" "$EMPTY/$b"
done
check_contains "缺 docker -> 中文说明" "未检测到 docker" \
  env PATH="$EMPTY" python3 "$SRC/lib/market_apps.py" install nginx
check_contains "catalog 无需 docker 即可用" "nginx:" \
  env PATH="$EMPTY" python3 "$SRC/lib/market_apps.py" catalog

# ---------------------------------------------------------------------------
section "4. P1: 备份空 scope 跳过 + 全空中文报错"
# ---------------------------------------------------------------------------
ROOT="$WORK/root"
mkdir -p "$ROOT/var/www"
echo "fusionbox-check" > "$ROOT/var/www/marker.txt"
OUT="$WORK/out"
mkdir -p "$OUT"
check_contains "部分 scope 缺失 -> 跳过并成功" "Created scopes: web" \
  python3 "$SRC/lib/archive.py" create fusion,web,docker "$OUT/partial.tar" --root "$ROOT"
check_contains "skip 报告为中文" "已跳过 scope fusion" \
  python3 "$SRC/lib/archive.py" create fusion,web,docker "$OUT/partial2.tar" --root "$ROOT"
[[ -f "$OUT/partial.tar" ]] && ok "跳过后仍产出备份文件" || bad "跳过后仍产出备份文件"

EMPTYROOT="$WORK/emptyroot"
mkdir -p "$EMPTYROOT"
check_contains "全部 scope 缺失 -> 中文报错" "没有任何可备份范围" \
  python3 "$SRC/lib/archive.py" create fusion,docker "$OUT/empty.tar" --root "$EMPTYROOT"
check_absent "全空时不说英文 No backup sources" "No backup sources" \
  python3 "$SRC/lib/archive.py" create fusion,docker "$OUT/empty.tar" --root "$EMPTYROOT"
[[ ! -f "$OUT/empty.tar" ]] && ok "全空失败不产出半成品备份" || bad "全空失败不产出半成品备份"

# strict mode still fails hard
check_exit "--require-all-scopes 保持严格失败" 1 \
  python3 "$SRC/lib/archive.py" create fusion,web,docker "$OUT/strict.tar" \
  --root "$EMPTYROOT" --require-all-scopes

# 用户可触达的错误必须是中文且可执行（v1.35.1 补齐）
check_contains "未知 scope -> 中文报错" "未知备份范围" \
  python3 "$SRC/lib/archive.py" create bogus "$OUT/bad-scope.tar" --root "$ROOT"
check_contains "严格模式 -> 中文报错" "没有可备份源" \
  python3 "$SRC/lib/archive.py" create fusion,web "$OUT/strict2.tar" \
  --root "$EMPTYROOT" --require-all-scopes
check_exit "备份重名 -> 失败" 1 \
  python3 "$SRC/lib/archive.py" create web "$OUT/partial.tar" --root "$ROOT"
check_contains "备份重名 -> 中文提示" "备份文件已存在" \
  python3 "$SRC/lib/archive.py" create web "$OUT/partial.tar" --root "$ROOT"
check_contains "恢复缺范围 -> 中文提示" "请求的范围不在该备份中" \
  python3 "$SRC/lib/archive.py" verify docker "$OUT/partial.tar"
check_contains "abort 冲突 -> 中文提示" "恢复时发现目标已存在" \
  python3 "$SRC/lib/archive.py" preview web "$OUT/partial.tar" --root "$ROOT" --conflict abort
check_absent "顶层报错前缀为中文" "Backup operation failed" \
  python3 "$SRC/lib/archive.py" create bogus "$OUT/bad-scope2.tar" --root "$ROOT"

# ---------------------------------------------------------------------------
section "5. 备份 -> 校验 -> 预览 -> 恢复 往返"
# ---------------------------------------------------------------------------
check_contains "verify 往返" "Verified scopes" \
  python3 "$SRC/lib/archive.py" verify web "$OUT/partial.tar"
PREVIEW_ROOT="$WORK/preview-target"
mkdir -p "$PREVIEW_ROOT"
check_contains "preview 往返" "var/www" \
  python3 "$SRC/lib/archive.py" preview web "$OUT/partial.tar" --root "$PREVIEW_ROOT"
RESTORE="$WORK/restore"
mkdir -p "$RESTORE"
python3 "$SRC/lib/archive.py" restore web "$OUT/partial.tar" --root "$RESTORE" --conflict replace >/dev/null 2>&1
if [[ -f "$RESTORE/var/www/marker.txt" ]] && \
   [[ "$(cat "$RESTORE/var/www/marker.txt")" == "fusionbox-check" ]]; then
  ok "恢复内容字节一致"
else
  bad "恢复内容字节一致"
fi

# ---------------------------------------------------------------------------
section "6. P3: 菜单数量动态读取 catalog"
# ---------------------------------------------------------------------------
CATALOG_COUNT="$(python3 "$SRC/lib/market_apps.py" catalog 2>/dev/null | grep -c '^[a-z0-9][a-z0-9_-]*:')"
if [[ "$CATALOG_COUNT" =~ ^[0-9]+$ ]] && (( CATALOG_COUNT >= 10 )); then
  ok "catalog 计数可动态读取 ($CATALOG_COUNT)"
else
  bad "catalog 计数可动态读取 (got=$CATALOG_COUNT)"
fi
if grep -q '受管 Nginx / ntfy' "$SRC/modules/market.sh"; then
  bad "菜单文案不再写死 Nginx/ntfy"
else
  ok "菜单文案不再写死 Nginx/ntfy"
fi
check_contains "菜单文案改为「受管应用生命周期」" "受管应用生命周期" \
  grep -F "受管应用生命周期" "$SRC/modules/market.sh"

# ---------------------------------------------------------------------------
section "7. P3: i18n 英文环境无中文依赖自检"
# ---------------------------------------------------------------------------
EN_OUT="$(FUSION_SRC="$SRC" LANG=en_US.UTF-8 bash -c '
  source "'"$SRC"'/lib/common.sh"
  F_PKG_MGR=apt
  _load_lang en
  show_dependency_status
' 2>&1)"
# strip ANSI colour codes first: they are non-ASCII but not Chinese.
EN_TEXT="$(printf '%s' "$EN_OUT" | sed $'s/\033\\[[0-9;]*m//g')"
if grep -qF "Dependencies:" <<<"$EN_TEXT"; then ok "英文环境依赖自检为英文"; else
  bad "英文环境依赖自检为英文"; printf '%s\n' "$EN_TEXT" | sed 's/^/       | /'; fi
if python3 -c 'import sys; sys.exit(0 if any("\u4e00" <= c <= "\u9fff" for c in sys.stdin.read()) else 1)' <<<"$EN_TEXT"; then
  bad "英文环境依赖自检不含中文"; printf '%s\n' "$EN_TEXT" | sed 's/^/       | /'
else
  ok "英文环境依赖自检不含中文"
fi
check_contains "en.sh 鸣谢已翻译" "Mianhua Cloud" \
  grep -F 'MSG_ACKNOWLEDGEMENT=' "$SRC/i18n/en.sh"

# ---------------------------------------------------------------------------
section "8. P3: CPU 核数口径"
# ---------------------------------------------------------------------------
CPU_OUT="$(FUSION_SRC="$SRC" bash -c 'source "'"$SRC"'/lib/common.sh"; _cpu_cores_display' 2>&1)"
if grep -qE '[0-9]+' <<<"$CPU_OUT"; then ok "CPU 口径可显示 ($CPU_OUT)"; else
  bad "CPU 口径可显示 ($CPU_OUT)"; fi
if grep -q '_cpu_cores_display' "$SRC/modules/system.sh" && \
   grep -q '_cpu_cores_display' "$REPO_ROOT/fusion.sh"; then
  ok "status / system info 使用可用核口径"
else
  bad "status / system info 使用可用核口径"
fi

# ---------------------------------------------------------------------------
section "9. A 档: 编号工作区槽位归一化"
# ---------------------------------------------------------------------------
check_contains "槽位 3 -> w3" "w3" \
  bash -c 'source "'"$SRC"'/lib/common.sh"; source "'"$SRC"'/modules/workspace.sh"; _ws_work_name 3'
check_contains "槽位 w3 -> w3" "w3" \
  bash -c 'source "'"$SRC"'/lib/common.sh"; source "'"$SRC"'/modules/workspace.sh"; _ws_work_name w3'
check_contains "槽位 work3 -> w3" "w3" \
  bash -c 'source "'"$SRC"'/lib/common.sh"; source "'"$SRC"'/modules/workspace.sh"; _ws_work_name work3'
check_contains "槽位 11 越界被拒" "1-10" \
  bash -c 'source "'"$SRC"'/lib/common.sh"; source "'"$SRC"'/modules/workspace.sh"; _ws_work_name 11'

# ---------------------------------------------------------------------------
section "10. 依赖守卫存在性覆盖"
# ---------------------------------------------------------------------------
for mod in system panels market; do
  if grep -q '_require_python3' "$SRC/modules/$mod.sh"; then
    ok "$mod.sh 接入 python3 守卫"
  else
    bad "$mod.sh 接入 python3 守卫"
  fi
done
check_contains "系统 backup 入口有守卫" "_require_python3" \
  grep -F '_require_python3' "$SRC/modules/system.sh"
if grep -q '2>/dev/null | grep -q' "$SRC/modules/market.sh"; then
  bad "market.sh 不再用 2>/dev/null 吞错误"
else
  ok "market.sh 不再用 2>/dev/null 吞错误"
fi

# ---------------------------------------------------------------------------
section "11. A/B 档新入口"
# ---------------------------------------------------------------------------
check_contains "fusion.sh 路由 log" "show_logs" grep -F 'show_logs' "$REPO_ROOT/fusion.sh"
check_contains "system_rescue 存在" "system_rescue()" grep -F 'system_rescue()' "$SRC/modules/system.sh"
check_contains "cluster alias 速查表入口" "cluster_k_alias()" grep -F 'cluster_k_alias()' "$SRC/modules/cluster.sh"
check_contains "help 补充依赖说明" "依赖" grep -F '依赖:' "$REPO_ROOT/fusion.sh"

# ---------------------------------------------------------------------------
section "12. C 档: 更新后展示本次变更"
# ---------------------------------------------------------------------------
check_contains "fusion.sh 定义 _update_show_notes" "_update_show_notes" \
  grep -F '_update_show_notes()' "$REPO_ROOT/fusion.sh"
check_contains "更新成功后调用 _update_show_notes" "_update_show_notes \"\$tmpdir/\$archive_root\"" \
  grep -F '_update_show_notes "$tmpdir/$archive_root"' "$REPO_ROOT/fusion.sh"

# _update_changelog_section extracts only the requested version's body.
mkdir -p "$WORK/notes/docs"
{
  printf '# 变更历史\n\n'
  printf '## v1.99.0 目标版本\n'
  printf -- '- 这是目标版本的条目 A\n\n'
  printf '## v1.98.0 旧版本\n'
  printf -- '- 这是旧版本的条目 B\n'
} > "$WORK/notes/docs/CHANGELOG.md"
sed -n '/^_update_changelog_section()/,/^}/p' "$REPO_ROOT/fusion.sh" > "$WORK/fn.sh"
have_section="$(bash -c 'source "'"$WORK"'/fn.sh"; _update_changelog_section "'"$WORK"'/notes/docs/CHANGELOG.md" 1.99.0' 2>/dev/null)"
if grep -qF '条目 A' <<<"$have_section" && ! grep -qF '条目 B' <<<"$have_section"; then
  ok "_update_changelog_section 只取目标版本段落"
else
  bad "_update_changelog_section 只取目标版本段落"
  printf '%s\n' "$have_section" | sed 's/^/       | /' | head -10
fi

# ---------------------------------------------------------------------------
section "13. B 档: 长任务阶段进度"
# ---------------------------------------------------------------------------
check_contains "common.sh 提供 progress_begin" "progress_begin()" \
  grep -F 'progress_begin()' "$SRC/lib/common.sh"
check_contains "common.sh 提供 progress_step" "progress_step()" \
  grep -F 'progress_step()' "$SRC/lib/common.sh"
check_contains "LNMP 安装接入阶段计数" "progress_begin 4" \
  grep -F 'progress_begin 4' "$SRC/modules/web.sh"
check_contains "受管安装提示阶段流程" "MSG_MARKET_STAGES" \
  grep -F 'MSG_MARKET_STAGES' "$SRC/modules/market.sh"
check_contains "Docker 安装接入阶段计数" "MSG_DOCKER_STAGES_1" \
  grep -F 'MSG_DOCKER_STAGES_1' "$SRC/modules/panels.sh"
check_contains "Docker 安装阶段结束复位" "progress_end" \
  grep -F 'progress_end' "$SRC/modules/panels.sh"
check_contains "代理安装接入阶段计数" "MSG_PROXY_STAGES_1" \
  grep -F 'MSG_PROXY_STAGES_1' "$SRC/modules/proxy.sh"
check_contains "代理安装阶段结束复位" "progress_end" \
  grep -F 'progress_end' "$SRC/modules/proxy.sh"

step_out="$(bash -c 'source "'"$SRC"'/lib/common.sh"; progress_begin 3; progress_step "阶段甲"; progress_step "阶段乙"' 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g')"
if grep -qF '[1/3] 阶段甲' <<<"$step_out" && grep -qF '[2/3] 阶段乙' <<<"$step_out"; then
  ok "progress_step 输出 [n/total] 形式"
else
  bad "progress_step 输出 [n/total] 形式"
  printf '%s\n' "$step_out" | sed 's/^/       | /'
fi

# 新增阶段文案中英同步
for key in MSG_DOCKER_STAGES_1 MSG_DOCKER_STAGES_2 MSG_DOCKER_STAGES_3 MSG_DOCKER_STAGES_4 \
           MSG_PROXY_STAGES_1 MSG_PROXY_STAGES_2 MSG_PROXY_STAGES_3 MSG_PROXY_STAGES_4; do
  zh="$(grep -c "^$key=" "$SRC/i18n/zh_CN.sh")"
  en="$(grep -c "^$key=" "$SRC/i18n/en.sh")"
  if [[ "$zh" == "1" && "$en" == "1" ]]; then
    ok "i18n 中英同步 $key"
  else
    bad "i18n 中英同步 $key (zh=$zh en=$en)"
  fi
done

# ---------------------------------------------------------------------------
section "14. A 档: 工作区 SSH 常驻"
# ---------------------------------------------------------------------------
check_contains "workspace.sh 提供 _ws_slot_ensure" "_ws_slot_ensure()" \
  grep -F '_ws_slot_ensure()' "$SRC/modules/workspace.sh"
check_contains "ws 支持 ensure 动作" "ensure|resume)" \
  grep -F 'ensure|resume)' "$SRC/modules/workspace.sh"
check_contains "ws 支持 ssh 动作" "ssh)" \
  grep -F '    ssh)' "$SRC/modules/workspace.sh"
if grep -q '不存在，正在创建' "$SRC/modules/workspace.sh"; then
  ok "直接 ws w<n> 不存在时自动创建"
else
  bad "直接 ws w<n> 不存在时自动创建"
fi

# ---------------------------------------------------------------------------
section "15. CNB 流水线：镜像显式指定 + tag_push 脚本 POSIX 兼容"
# ---------------------------------------------------------------------------
CNB_YML="$REPO_ROOT/.cnb.yml"
check_contains "CI 显式指定 python 镜像" "image: python:3.11" \
  grep -F 'image: python:3.11' "$CNB_YML"
# 默认 Runner shell 是 sh（dash）；tag_push 脚本内出现 [[ ]] 会在 dash 下报错。
# 只审查 tag_push 段落：CI 段落通过 bash -n / bash tests 显式调用 bash，不受影响。
if awk '/^  tag_push:/{f=1} /^main:/{f=0} f' "$CNB_YML" | grep -qF '[['; then
  bad "tag_push 脚本不含 bashism [[ ]]"
else
  ok "tag_push 脚本不含 bashism [[ ]]"
fi
check_contains "tag_push 版本校验用 POSIX case" 'case "$CNB_BRANCH" in' \
  grep -F 'case "$CNB_BRANCH" in' "$CNB_YML"
# 附件插件按 Tag 查 Release，Release 不存在会 404；必须先建 Release 再上传。
tag_block="$(awk '/^  tag_push:/{f=1} /^main:/{f=0} f' "$CNB_YML")"
rel_line="$(printf '%s\n' "$tag_block" | grep -n 'type: git:release' | head -1 | cut -d: -f1)"
att_line="$(printf '%s\n' "$tag_block" | grep -n 'upload-release-attachments' | head -1 | cut -d: -f1)"
if [ -n "$rel_line" ] && [ -n "$att_line" ] && [ "$rel_line" -lt "$att_line" ]; then
  ok "tag_push 先建 Release 再上传附件"
else
  bad "tag_push 先建 Release 再上传附件 (release=$rel_line attach=$att_line)"
fi

# ---------------------------------------------------------------------------
section "16. 帮助分发 / 未知子命令 / 配置键闭环（v1.36.3）"
# ---------------------------------------------------------------------------
# `help` 是只读入口，不需要 root，因此可以直接走真实 CLI。
FUSION_CLI=(bash "$REPO_ROOT/fusion.sh")
MODULES="proxy system network web panels market warp workspace cluster"

# 16.1 help <模块> 必须真的分发：输出该模块命令清单 + 本机安装状态
for m in $MODULES; do
  out="$("${FUSION_CLI[@]}" help "$m" < /dev/null 2>&1)"
  state="$(awk '/本机状态/ { getline; print; exit }' <<<"$out")"
  if grep -qF -- "fusionbox $m" <<<"$out" && grep -qF "本机状态" <<<"$out" \
     && [[ -n "${state//[[:space:]]/}" ]]; then
    ok "fusionbox help $m 输出模块命令清单 + 本机状态"
  else
    bad "fusionbox help $m 输出模块命令清单 + 本机状态"
  fi
done

# 16.2 help <模块> 与 <模块> help 必须一致（route 层归一化）
#
# 「本机状态」那一行是实时探测（docker 守护进程响应快慢、nginx/php 是否存在），
# 两次调用之间可以合法地不同，因此先把这一行归一化再比对；状态行本身已在 16.1
# 断言非空。曾因直接比对原始输出在 CI 上出现过 flake（同一提交一次通过一次失败）。
help_normalized() {
  awk '/本机状态/ { print; getline; print "    <本机状态>"; next } { print }'
}
for m in proxy system network web panels market warp workspace cluster; do
  a="$("${FUSION_CLI[@]}" help "$m" < /dev/null 2>&1 | help_normalized)"
  b="$("${FUSION_CLI[@]}" "$m" help < /dev/null 2>&1 | help_normalized)"
  if [[ "$a" == "$b" ]]; then
    ok "help $m 与 $m help 输出一致"
  else
    bad "help $m 与 $m help 输出一致"
  fi
done

# 16.3 别名必须命中规范模块
for pair in "p:proxy" "sys:system" "s:system" "net:network" "n:network" "w:web"\
            "lnmp:web" "panels:panels" "tools:panels" "m:market" "apps:market"\
            "ws:workspace" "cl:cluster"; do
  alias_name="${pair%%:*}"
  canonical="${pair##*:}"
  out="$("${FUSION_CLI[@]}" help "$alias_name" < /dev/null 2>&1)"
  if grep -qF -- "fusionbox $canonical" <<<"$out"; then
    ok "别名 help $alias_name -> $canonical"
  else
    bad "别名 help $alias_name -> $canonical"
  fi
done

# 16.4 模块帮助条目数不能再退化成「空头支票」
help_total=0
for m in $MODULES; do
  n="$("${FUSION_CLI[@]}" help "$m" < /dev/null 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -cE '^  +fusionbox ')"
  help_total=$((help_total + n))
done
if (( help_total >= 100 )); then
  ok "模块帮助命令条目 $help_total >= 100"
else
  bad "模块帮助命令条目 $help_total >= 100"
fi

# 16.5 未知模块 -> 退出码 1 + 列出可用模块
check_exit "help <未知模块> 退出码 1" 1 "${FUSION_CLI[@]}" help no-such-module
check_contains "help <未知模块> 列出可用模块" "可用模块" \
  "${FUSION_CLI[@]}" help no-such-module

# 16.6 未知子命令：退出码 2、明确报错、且不进交互菜单
# 函数层验证，避免 fusion.sh 对非 help 命令的 root 门禁（本脚本必须能非 root 运行）。
for m in $MODULES; do
  out="$(bash -c "export HOME='$WORK' FUSION_BASE='$REPO_ROOT' FUSION_SRC='$SRC'; \
    . \"$SRC/init.sh\" >/dev/null 2>&1; _load_module '$m' >/dev/null 2>&1; \
    ${m}_main definitely-not-a-command" 2>&1)"
  rc=$?
  if [[ "$rc" == "2" ]] && grep -qF "未知子命令" <<<"$out" && ! grep -qF "返回主菜单" <<<"$out"; then
    ok "$m 未知子命令 rc=2 且不渲染菜单"
  else
    bad "$m 未知子命令 rc=2 且不渲染菜单 (rc=$rc)"
  fi
done

# 16.7 help 参数不能被未知子命令守卫误伤
for m in $MODULES; do
  out="$(bash -c "export HOME='$WORK' FUSION_BASE='$REPO_ROOT' FUSION_SRC='$SRC'; \
    . \"$SRC/init.sh\" >/dev/null 2>&1; _load_module '$m' >/dev/null 2>&1; \
    ${m}_main help" 2>&1)"
  if grep -qF -- "fusionbox $m" <<<"$out"; then
    ok "$m help 仍输出命令清单"
  else
    bad "$m help 仍输出命令清单"
  fi
done

# 16.8 配置文件里的每个键都必须有真实读取点（禁止「装饰性开关」）
CFG="$REPO_ROOT/configs/config.yaml"
src_text="$(cat "$REPO_ROOT/fusion.sh" "$SRC/init.sh" "$SRC"/lib/*.sh "$SRC"/modules/*.sh 2>/dev/null)"
cfg_keys="$(awk '
  /^[[:space:]]*#/ { next }
  /^[a-zA-Z_][A-Za-z0-9_]*:[[:space:]]*$/ { s=$1; sub(/:$/, "", s); next }
  /^[[:space:]]+[a-zA-Z_][A-Za-z0-9_]*:/ { k=$1; sub(/:$/, "", k); if (s != "") print s "_" k }
' "$CFG")"
cfg_missing=0
while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  if ! grep -qF -- "CONFIG_$key" <<<"$src_text"; then
    bad "配置键 $key 无读取点（写了不生效）"
    cfg_missing=1
  fi
done <<<"$cfg_keys"
if (( cfg_missing == 0 )); then
  ok "config.yaml 全部键都有读取点"
fi
check_contains "config.yaml 声明了不受本文件控制的设置" "不由本文件控制" cat "$CFG"
check_absent "config.yaml 不再含装饰性的 auto_update" "auto_update" cat "$CFG"

# 16.9 general.color=false 必须真正关闭 ANSI
color_out="$(bash -c "export HOME='$WORK' FUSION_BASE='$REPO_ROOT' FUSION_SRC='$SRC'; \
  mkdir -p \"\$HOME/.config/fusionbox\"; \
  printf 'general:\n  color: false\n' > \"\$HOME/.config/fusionbox/config.yaml\"; \
  . \"$SRC/init.sh\" >/dev/null 2>&1; printf 'RED=[%s] BOLD=[%s]\\n' \"\$F_RED\" \"\$F_BOLD\"" 2>&1)"
if grep -qE 'RED=\[\] BOLD=\[\]' <<<"$color_out"; then
  ok "general.color=false 清空 ANSI 变量"
else
  bad "general.color=false 清空 ANSI 变量"
fi

# 16.10 G07 时区预设
tz_count="$(sed -n '/^SYSTEM_TZ_PRESETS=(/,/^)/p' "$SRC/modules/system.sh" | grep -cE '^  "[^|]+\|[^|]+\|[^|]+"$')"
if (( tz_count >= 20 )); then
  ok "时区预设 $tz_count >= 20"
else
  bad "时区预设 $tz_count >= 20"
fi
check_contains "时区校验函数存在（防路径穿越）" "_system_tz_apply()" \
  grep -n '^_system_tz_apply()' "$SRC/modules/system.sh"

# 16.11 发布版本号在五处保持一致
ver="$(tr -d '[:space:]' < "$REPO_ROOT/version.txt")"
ver_bad=0
grep -Fqx "export FUSION_VER=\"$ver\"" "$SRC/init.sh" || ver_bad=1
grep -Fq "version-$ver" "$REPO_ROOT/README.md" || ver_bad=1
grep -Fq "v$ver" "$REPO_ROOT/docs/index.html" || ver_bad=1
grep -Fq "v$ver" "$REPO_ROOT/docs/implementation-status.md" || ver_bad=1
if (( ver_bad == 0 )); then
  ok "version.txt / init.sh / README / Pages / 实施状态 版本一致 ($ver)"
else
  bad "version.txt / init.sh / README / Pages / 实施状态 版本一致 ($ver)"
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m== 结果 ==\033[0m\n'
printf '通过 %d / 失败 %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '失败项:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
echo "全部回归检查通过"
