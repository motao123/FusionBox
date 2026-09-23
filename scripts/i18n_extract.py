#!/usr/bin/env python3
"""FusionBox i18n 抽取器：把硬编码文案改写成键式调用，并产出语言包条目。

用法：
    python3 scripts/i18n_extract.py --dry-run src/lib/common.sh fusion.sh
    python3 scripts/i18n_extract.py --apply   src/lib/common.sh fusion.sh
    python3 scripts/i18n_extract.py --report  # 全仓扫描，只看统计不改文件

约定（与 src/lib/i18n.sh 一致）：
  * 每个文件一个键前缀（见 KEY_PREFIX），键名 <PREFIX><NNNN>，按首次出现顺序编号。
  * 相同模板文本在同一文件内复用同一个键（去重）。
  * 颜色转义（${F_XXX}）与所有值表达式都**作为参数传入**，语言包内不留变量、不留转义码。
  * 支持的值表达式形态：$name / ${name} / ${name[*]} / ${name[@]} / ${name:-默认} /
    ${name^^} / ${#name[@]} / ${name[$i]} / $((算术)) / $(命令) / $1 / $# / $@ / $* / $? 等。
    这些整体作为「一个值」透传，语义与原先在字符串内展开等价。
  * 只有无法安全解析的行（引号不配平、printf 格式串混变量）才 SKIP，交人工处理。
  * 输出：改写后的文件（--apply）+ 语言包条目到 stdout（JSON），供合包脚本使用。
"""
import argparse
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 文件 → 键前缀（统一 MSG_ 家族，与既有键名不冲突）
KEY_PREFIX = {
    'fusion.sh': 'MSG_MAIN_',
    'install.sh': 'MSG_INST_',
    'src/init.sh': 'MSG_INIT_',
    'src/lib/common.sh': 'MSG_COMMON_',
    'src/lib/deploy.sh': 'MSG_DEPLOY_',
    'src/modules/proxy.sh': 'MSG_PROXY_',
    'src/modules/system.sh': 'MSG_SYS_',
    'src/modules/network.sh': 'MSG_NET_',
    'src/modules/web.sh': 'MSG_WEB_',
    'src/modules/panels.sh': 'MSG_PANEL_',
    'src/modules/market.sh': 'MSG_MARKET_',
    'src/modules/warp.sh': 'MSG_WARP_',
    'src/modules/workspace.sh': 'MSG_WS_',
    'src/modules/cluster.sh': 'MSG_CL_',
}

CJK = '\u3000-\u303f\u4e00-\u9fff\uff00-\uffef\u2018\u2019\u201c\u201d\u2014\u2026\u3001\u3002'
CJK_RE = re.compile('[' + CJK + ']')

# 调用点开头：语句边界 + 函数名 + 空白 + 可选 -e/-n + 引号
CALL_START_RE = re.compile(
    r'(?P<pre>(?:^|[;{}|&]|\s)*)'
    r'(?P<fn>msg(?:_ok|_err|_warn|_info|_tip|_title)?|echo|printf)'
    r'(?P<sp>\s+)'
    r'(?P<opt>-e\s+|-n\s+)?'
    r'(?P<q>"|\')'
)

SENTINEL = '\x00'

# 用户可见文案的其它出口：辅助函数（提示语 / 确认语 / 日志 / 功能名）
AUX_FUNCS = [
    'read', 'confirm', 'read_input', 'progress_step', '_log_write',
    'select_option', '_fb_user_read_password', 'shutdown',
    '_require_python3', '_require_docker_compose', '_require_docker_daemon',
    '_require_docker', '_require_cmd', '_require_optional_cmd', '_require_root',
    '_system_mirror_apply_apt', '_system_mirror_apply_yum', '_system_dns_apply',
    '_panels_docker_mirror_apply', '_network_bench_execute', '_notify_send',
]
AUX_RE = re.compile(r'(?<![A-Za-z0-9_/])(?P<fn>' +
                    '|'.join(re.escape(f) for f in AUX_FUNCS) + r')(?P<sp>\s+)')

# 变量赋值（含 local/declare/export 前缀、+= 累加、数组追加 +=( ），用于抽取右侧文案
DEF_ASSIGN_RE = re.compile(
    r'(?:^|[\s;(])(?:(?:local|declare|export)\s+(?:-\S+\s+)*)?'
    r'[A-Za-z_][A-Za-z0-9_]*(?:\+?=\(?["\'])'
)


def _segment_end(text, start):
    """返回从 start 起的“单条命令”结尾（顶层 ; | & { } 或行尾）。"""
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c == '\\':
            i += 2
            continue
        if c in '"\'':
            j = _skip_quoted(text, i)
            if j is None:
                return n
            i = j
            continue
        if c == '$' and i + 1 < n and text[i + 1] in '({':
            j = _match(text, i + 1)
            if j is None:
                return n
            i = j + 1
            continue
        if c in ';|&{}':
            return i
        i += 1
    return n


def _established_keys():
    """读取已发布的语言包，返回 {前缀: 最大编号}，保证新键不与既有键冲突。"""
    path = os.path.join(ROOT, 'src', 'i18n', 'zh_CN.sh')
    maxima = {}
    if not os.path.isfile(path):
        return maxima
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*?)(\d{4})="', io.open(path, encoding='utf-8').read(), re.M):
        pre, num = m.group(1), int(m.group(2))
        maxima[pre] = max(maxima.get(pre, 0), num)
    return maxima


_ESTABLISHED = None


def _existing_max(prefix: str) -> int:
    global _ESTABLISHED
    if _ESTABLISHED is None:
        _ESTABLISHED = _established_keys()
    # 前缀在 KEY_PREFIX 里带尾下划线（如 MSG_SYS_），既有键同样形如 MSG_SYS_0001
    return _ESTABLISHED.get(prefix, 0)


def _skip_quoted(text, i):
    """i 指向引号字符；返回配对引号之后的位置；失败返回 None。

    双引号内遇到 $( 或 ${ 会按配平跳过内部（内部允许出现引号）。
    """
    q = text[i]
    n = len(text)
    j = i + 1
    while j < n:
        c = text[j]
        if c == '\\':
            j += 2
            continue
        if q == '"' and c == '$' and j + 1 < n and text[j + 1] in '({':
            k = _match(text, j + 1)
            if k is None:
                return None
            j = k + 1
            continue
        if c == q:
            return j + 1
        j += 1
    return None


def _match(text, start):
    """text[start] 为 ( 或 {；返回与之配平的闭括号位置；失败返回 None。"""
    open_ch = text[start]
    close_ch = ')' if open_ch == '(' else '}'
    depth = 0
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c == '\\':
            i += 2
            continue
        if c in '\'"':
            j = _skip_quoted(text, i)
            if j is None:
                return None
            i = j
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def split_value_exprs(text):
    """把字符串内容切成「静态文本 + 值表达式」序列。

    返回 (template, exprs)；template 用 %s 占位，exprs 为原样表达式列表。
    遇到无法安全解析的内容返回 None（调用方 SKIP）。
    """
    lit = []
    exprs = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '\\' and i + 1 < n:
            lit.append(text[i:i + 2])
            i += 2
            continue
        if c == '$' and i + 1 < n:
            nxt = text[i + 1]
            if nxt in '({':
                j = _match(text, i + 1)
                if j is None:
                    return None
                exprs.append(text[i:j + 1])
                i = j + 1
                lit.append(SENTINEL)
                continue
            m = re.match(r'\$[A-Za-z_][A-Za-z0-9_]*', text[i:])
            if m:
                exprs.append(m.group(0))
                i += m.end()
                lit.append(SENTINEL)
                continue
            m = re.match(r'\$\d+', text[i:])
            if m:
                exprs.append(m.group(0))
                i += m.end()
                lit.append(SENTINEL)
                continue
            if nxt in '#@*?!':
                exprs.append(text[i:i + 2])
                i += 2
                lit.append(SENTINEL)
                continue
        lit.append(c)
        i += 1
    return ''.join(lit), exprs


class Extractor:
    def __init__(self, relpath: str, dry: bool):
        self.rel = relpath
        self.dry = dry
        self.prefix = KEY_PREFIX.get(relpath, 'TXT_')
        self.counter = _existing_max(self.prefix)
        self.by_text = {}          # (模板, is_printf) → 键
        self.entries = {}          # 键 → {'zh':..., 'args':n, 'printf':bool}
        self.rewritten = []
        self.skipped = []

    def _key_for(self, text: str, nargs: int, is_printf: bool):
        sig = (text, is_printf)
        key = self.by_text.get(sig)
        if key is None:
            self.counter += 1
            key = '%s%04d' % (self.prefix, self.counter)
            self.by_text[sig] = key
            self.entries[key] = {'zh': text, 'args': nargs, 'printf': is_printf}
        return key

    def _make_call(self, raw: str, is_printf: bool):
        """把字符串内容转成 $(L KEY args...)；无法安全处理时返回 None。"""
        # 串内已含本地化调用 → 不重复抽键
        if re.search(r'\$\((?:L|_tr)\s+[A-Z]', raw):
            return None
        parsed = split_value_exprs(raw)
        if parsed is None:
            return None
        template, exprs = parsed
        if is_printf:
            if exprs:
                return None
            key = self._key_for(template, 0, True)
            args = []
        else:
            if exprs:
                template = template.replace('%', '%%').replace(SENTINEL, '%s')
            # 整串只是一个表达式（去掉占位符后没有实质文本）→ 无意义，跳过
            if not template.replace('%s', '').replace('%%', '').strip():
                return None
            key = self._key_for(template, len(exprs), False)
            args = ['"%s"' % e for e in exprs]
        argstr = (' ' + ' '.join(args)) if args else ''
        return '$(L %s%s)' % (key, argstr)

    def _apply_aux(self, lineno, orig, out):
        """辅助函数参数：read -p / confirm / _log_write / _require_* 等。"""
        if out.lstrip()[:1] in ('"', "'"):
            return out, False          # 整行是数据条目，交给 _apply_data_row
        changed = False
        pos = 0
        while True:
            m = AUX_RE.search(out, pos)
            if not m:
                break
            seg_start = m.end()
            seg_end = _segment_end(out, seg_start)
            i = seg_start
            while i < seg_end:
                ch = out[i]
                if ch in '"\'':
                    j = _skip_quoted(out, i)
                    if j is None:
                        break
                    raw = out[i + 1:j - 1]
                    if CJK_RE.search(raw):
                        call = self._make_call(raw, False)
                        if call:
                            new = '"' + call + '"'
                            out = out[:i] + new + out[j:]
                            seg_end += len(new) - (j - i)
                            i += len(new)
                            changed = True
                            continue
                    i = j
                    continue
                if ch == '$' and i + 1 < len(out) and out[i + 1] in '({':
                    k = _match(out, i + 1)
                    if k is None:
                        break
                    i = k + 1
                    continue
                i += 1
            pos = seg_end
        return out, changed

    def _apply_msg(self, lineno, orig, out):
        """msg/msg_* / echo / printf 的字符串参数。"""
        if out.lstrip()[:1] in ('"', "'"):
            return out, False          # 整行是数据条目，交给 _apply_data_row
        changed = False
        pos = 0
        while True:
            m = CALL_START_RE.search(out, pos)
            if not m:
                break
            q_start = m.end() - 1
            q_end = _skip_quoted(out, q_start)
            if q_end is None:
                self.skipped.append((lineno, orig.strip(), 'unbalanced-quote'))
                pos = m.end()
                continue
            raw = out[q_start + 1:q_end - 1]
            if not CJK_RE.search(raw):
                pos = q_end
                continue
            # 串内已含本地化调用（如 $(_tr MSG_X "默认值") 的默认值）→ 不重复抽键
            if re.search(r'\$\((?:L|_tr)\s+[A-Z]', raw):
                pos = q_end
                continue
            is_printf = m.group('fn') == 'printf'
            call = self._make_call(raw, is_printf)
            if call is None:
                self.skipped.append((lineno, orig.strip(),
                                     'printf-with-vars' if is_printf else 'unparsable-expression'))
                pos = q_end
                continue
            new = '"' + call + '"'
            out = out[:q_start] + new + out[q_end:]
            changed = True
            pos = q_start + len(new)
        return out, changed

    def _apply_assign(self, lineno, orig, out):
        """赋值右侧的整体字符串（含一行多个赋值，如 a="$1" b="中文"）。"""
        changed = False
        pos = 0
        while True:
            m = DEF_ASSIGN_RE.search(out, pos)
            if not m:
                break
            q_start = m.end() - 1
            q_end = _skip_quoted(out, q_start)
            if q_end is None:
                pos = m.end()
                continue
            rest = out[q_end:]
            if '"' in rest or "'" in rest:
                pos = q_end           # 行内还有引号：多串/嵌套，交人工
                continue
            raw = out[q_start + 1:q_end - 1]
            if not CJK_RE.search(raw):
                pos = q_end
                continue
            call = self._make_call(raw, False)
            if call is None:
                pos = q_end
                continue
            new = '"' + call + '"'
            out = out[:q_start] + new + out[q_end:]
            pos = q_start + len(new)
            changed = True
        return out, changed

    def _apply_data_row(self, lineno, orig, out):
        """数组条目：行首即为字符串字面量（如 market/network 的数据表）。"""
        indent = len(out) - len(out.lstrip())
        if out.lstrip()[:1] not in ('"', "'"):
            return out, False
        q_start = indent
        q_end = _skip_quoted(out, q_start)
        if q_end is None:
            return out, False
        rest = out[q_end:]
        if '"' in rest or "'" in rest:
            return out, False          # 行内还有引号：多串/嵌套，交人工
        raw = out[q_start + 1:q_end - 1]
        if not CJK_RE.search(raw):
            return out, False
        call = self._make_call(raw, False)
        if call is None:
            return out, False
        return out[:q_start] + '"' + call + '"' + out[q_end:], True

    def process_line(self, lineno: int, line: str) -> str:
        stripped = line.lstrip()
        # heredoc（<< 或 <<-）内部内容不在本行；here-string（<<<）不影响
        if stripped.startswith('#') or re.search(r'(?<!<)<<-?(?!<)', line):
            return line
        out = line
        changed = False
        # 顺序很关键：**先整行（数据行 / 赋值），再内层调用**。
        # 反过来的话，像 "a 'b' c" 这种「单行数据里嵌了引号串」的条目会被内层先改坏
        # 引号配对（单引号串被换成双引号），整串随即被当成半截串抽走——
        # v1.43.0 修复（CLUSTER_TASKS 的 swap1g 条目曾因此被拆坏）。
        for fn in (self._apply_data_row, self._apply_assign, self._apply_aux, self._apply_msg):
            out, c = fn(lineno, line, out)
            changed = changed or c
        if changed:
            self.rewritten.append((lineno, line, out))
        return out


def process_file(relpath: str, apply: bool, dry: bool):
    path = os.path.join(ROOT, relpath)
    if not os.path.isfile(path):
        print('!! 文件不存在: %s' % relpath, file=sys.stderr)
        return None
    src = io.open(path, encoding='utf-8').read()
    lines = src.split('\n')
    ex = Extractor(relpath, dry)
    new_lines = [ex.process_line(i, l) for i, l in enumerate(lines, 1)]
    if apply:
        io.open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(new_lines))
    return {
        'file': relpath,
        'rewritten': ex.rewritten,
        'skipped': ex.skipped,
        'entries': ex.entries,
    }


def report_only():
    """全仓扫描：统计每个文件的待抽取文案量（不写文件）"""
    print('%-34s %8s %8s %8s' % ('文件', '中文文案', '可自动改写', '需人工'))
    total = auto = skipped = 0
    for rel in KEY_PREFIX:
        path = os.path.join(ROOT, rel.replace('/', os.sep))
        if not os.path.isfile(path):
            continue
        lines = io.open(path, encoding='utf-8').read().split('\n')
        ex = Extractor(rel, True)
        for i, l in enumerate(lines, 1):
            ex.process_line(i, l)
        # 注：同一行多语句只算一次改写
        seen = set()
        n = 0
        for ln, _a, _b in ex.rewritten:
            if ln not in seen:
                seen.add(ln)
                n += 1
        print('%-34s %8d %8d %8d' % (rel, len(ex.rewritten), n, len(ex.skipped)))
        total += len(ex.rewritten)
        auto += n
        skipped += len(ex.skipped)
    print('%-34s %8d %8d %8d' % ('合计', total, auto, skipped))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('files', nargs='*')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--report', action='store_true')
    ap.add_argument('--json', default='')
    args = ap.parse_args()

    if args.report:
        report_only()
        return 0

    results = []
    for rel in args.files:
        res = process_file(rel, args.apply, args.dry_run)
        if res:
            results.append(res)

    for r in results:
        print('== %s ==  改写 %d 行，需人工 %d 处，新增键 %d 个'
              % (r['file'], len(r['rewritten']), len(r['skipped']), len(r['entries'])))
        for ln, old, new in r['rewritten'][:3]:
            print('   %-5d - %s' % (ln, old.strip()[:110]))
            print('         + %s' % new.strip()[:110])
        if len(r['rewritten']) > 3:
            print('   ... 其余 %d 行' % (len(r['rewritten']) - 3))
        for ln, text, why in r['skipped'][:12]:
            print('   SKIP %-5d [%s] %s' % (ln, why, text[:100]))
    if args.json:
        data = {r['file']: r['entries'] for r in results}
        io.open(args.json, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=1))
        print('\n键表已写入 %s' % args.json)
    return 0


if __name__ == '__main__':
    sys.exit(main())
