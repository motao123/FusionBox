#!/bin/bash
# FusionBox i18n 核心 —— 两个**完整**语言包 + 键式查询
#
# 设计要点（详见 docs/i18n.md）：
#   1) 两套语言包地位对等：src/i18n/zh_CN.sh 与 src/i18n/en.sh，键名一一对应；
#      tests/test_i18n.py 与 run_checks.sh 第 22 节会强制校验键集合完全一致。
#   2) 查询走 L <key> [args...]：无参数返回原文，有参数按 printf 模板插值；
#      语言包缺失某键时**回退到另一语言**（绝不把裸键名打到用户脸上），并登记缺失。
#   3) EN 缺中文（或反之）由 tests/i18n_audit.py 统计，覆盖率只能涨不能跌。
#   4) 本文件被 common.sh 与 fusion.sh（根权限门禁之前）共同加载，必须自包含。

: "${FUSION_SRC:=${FUSION_BASE:-/etc/fusionbox}/src}"
FUSION_I18N_DIR="${FUSION_I18N_DIR:-$FUSION_SRC/i18n}"

F_LANG="${F_LANG:-auto}"

# 两包各自的键值表
declare -gA _LANG_ZH=()
declare -gA _LANG_EN=()
# 查询未命中登记（测试与审计用；正常运行不影响输出）
declare -ga _I18N_MISSES=()

_I18N_KEY_RE='^(MSG_|MOD_|SYS_|NET_|WEB_|PANEL_|MARKET_|BBR_|PROXY_|CL_|WS_|MAIN_|INST_|INIT_|TXT_)[A-Z0-9_]*$'

# 清掉上一份包留下的同名变量，避免「包 A 有、包 B 无」时读到脏值
_i18n_clear_pack_vars() {
  local v
  while IFS= read -r v; do
    [[ -n "$v" ]] && unset "$v"
  done < <(compgen -v | grep -E "$_I18N_KEY_RE")
}

_i18n_load_packs() {
  local f v
  _LANG_ZH=(); _LANG_EN=()
  for f in zh_CN en; do
    [[ -f "$FUSION_I18N_DIR/$f.sh" ]] || continue
    _i18n_clear_pack_vars
    # shellcheck disable=SC1090
    . "$FUSION_I18N_DIR/$f.sh"
    while IFS= read -r v; do
      [[ -n "$v" ]] || continue
      if [[ "$f" == "zh_CN" ]]; then _LANG_ZH["$v"]="${!v}"; else _LANG_EN["$v"]="${!v}"; fi
    done < <(compgen -v | grep -E "$_I18N_KEY_RE")
  done
}

# 兼容旧接口：切换语言并（重新）加载语言包
_load_lang() {
  F_LANG="${1:-zh_CN}"
  _i18n_load_packs
}

# 依据 F_LANG（auto 时看 $LANG）决定实际语言
# auto 规则：显式英文 locale（en*）用英文；其余（zh_*、C、POSIX、未设置、其他语言）
# 一律用中文——项目主语言是中文，而服务器常见 C.UTF-8（Ubuntu 云镜像默认），
# 不能因为没设 LANG 就把中文用户的界面变成英文。要英文请显式指定：
#   fusionbox lang en   /   FUSION_LANG=en fusionbox ...
_i18n_resolve_auto() {
  case "${LANG:-}" in
    en*|EN*) printf 'en' ;;
    *)       printf 'zh_CN' ;;
  esac
}

_i18n_init() {
  local want="$F_LANG"
  if [[ -z "$want" || "$want" == "auto" ]]; then
    want="$(_i18n_resolve_auto)"
  fi
  [[ -f "$FUSION_I18N_DIR/$want.sh" ]] || want="zh_CN"
  _load_lang "$want"
}

# 兼容旧名（common.sh 老版本与 init.sh 都用过 _init_lang）
_init_lang() { _i18n_init; }

# 当前是否需要按英文取值（auto 视为已解析，避免调用点拿到 auto 而回落到中文）
_i18n_is_en() { [[ "${F_LANG:-}" == "en" ]]; }

# 取当前语言下的原始模板 → 写入全局 _I18N_VALUE
# 注意：不要用命令替换调用本函数（子 shell 会让 _I18N_MISSES 的登记丢失，
# v1.42.0 就踩过这个坑：缺失统计恒为 0）。需要取值的调用点直接用 _I18N_VALUE。
_I18N_VALUE=""
_i18n_get() {
  local key="$1" v=""
  # F_LANG 仍是 auto（配置里写的 auto / 尚未初始化）时按环境即时判定，
  # 否则会一律落到中文分支——英文包就形同虚设（v1.42.0 修复过这个坑）。
  if [[ -z "${F_LANG:-}" || "$F_LANG" == "auto" ]]; then
    F_LANG="$(_i18n_resolve_auto)"
  fi
  if _i18n_is_en; then
    v="${_LANG_EN[$key]:-}"
    [[ -n "$v" ]] || v="${_LANG_ZH[$key]:-}"
  else
    v="${_LANG_ZH[$key]:-}"
    [[ -n "$v" ]] || v="${_LANG_EN[$key]:-}"
  fi
  if [[ -z "$v" ]]; then
    _I18N_MISSES+=("$key")
    _I18N_VALUE="$key"
    return 0
  fi
  _I18N_VALUE="$v"
}

# 需要字符串结果的地方（如 printf 调用点的格式串）
_i18n_text() { _i18n_get "$1"; printf '%s' "$_I18N_VALUE"; }

_i18n_has() { [[ -n "${_LANG_ZH[$1]:-}${_LANG_EN[$1]:-}" ]]; }

# L <key> [args...] —— 无参数取原文；有参数按 printf 模板插值
L() {
  local key="$1"; shift || true
  _i18n_get "$key"
  if (( $# )); then printf -- "$_I18N_VALUE" "$@"; else printf '%s' "$_I18N_VALUE"; fi
}

# 兼容旧接口：_tr <key> <中文默认值> [args...]
_tr() {
  local key="$1"; shift || true
  local fallback="${1:-}"; shift || true
  _i18n_get "$key"
  local fmt="$_I18N_VALUE"
  [[ "$fmt" == "$key" && -n "$fallback" ]] && fmt="$fallback"
  if (( $# )); then printf -- "$fmt" "$@"; else printf '%s' "$fmt"; fi
}

# 语言显示名（用于 `fusionbox lang` 回显）
_i18n_display_name() {
  case "${1:-}" in
    zh_CN|zh) printf 'zh_CN (中文)' ;;
    en)       printf 'en (English)' ;;
    auto)     printf 'auto' ;;
    *)        printf '%s' "${1:-unknown}" ;;
  esac
}
