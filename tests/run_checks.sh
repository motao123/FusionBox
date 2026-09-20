#!/usr/bin/env bash
# FusionBox v1.34.0 regression checks.
#
# These checks lock in the first-run UX fixes: dependency preflight, backup
# scope skipping, Chinese help for raw passthrough subcommands, i18n coverage,
# CPU accounting and numbered workspace slots. They must run without root,
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
printf '\n\033[1m== 结果 ==\033[0m\n'
printf '通过 %d / 失败 %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf '失败项:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
echo "全部回归检查通过"
