#!/usr/bin/env python3
"""FusionBox i18n 抽取器：把硬编码文案改写成键式调用，并产出语言包条目。

用法：
    python3 scripts/i18n_extract.py --dry-run src/lib/common.sh fusion.sh
    python3 scripts/i18n_extract.py --apply   src/lib/common.sh fusion.sh
    python3 scripts/i18n_extract.py --report  # 全仓扫描，只看统计不改文件

约定（与 src/lib/i18n.sh 一致）：
  * 每个文件一个键前缀（见 KEY_PREFIX），键名 <PREFIX><NNNN>，按首次出现顺序编号。
  * 相同模板文本在同一文件内复用同一个键（去重）。
  * 颜色转义（${F_XXX}）留在调用点，不进语言包。
  * 含 $( ) / ${x:+ } / ${x:- } / ${x# } 等复杂展开的行**不改写**，只报告，交人工处理。
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
# 需要人工处理的表达式：命令替换、带修饰的参数展开、位置参数等
COMPLEX_RE = re.compile(r'\$\(|\$\{[A-Za-z_][A-Za-z0-9_]*[:#%/^,]|\$#|\$[0-9@*?!]')
# 变量：$name / ${name} / ${name[*]} / ${name[@]}——一律按参数传入，语言包内不留变量
VAR_RE = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?:\[[*@]\])?\}|\$([A-Za-z_][A-Za-z0-9_]*)')

# 调用点：msg/msg_* / echo / printf（保留前导空白与前置语句片段）
CALL_RE = re.compile(
    r'(?P<pre>(?:^|[;{}|]|\s)*)'
    r'(?P<fn>msg(?:_ok|_err|_warn|_info|_tip|_title)?|echo|printf)'
    r'(?P<sp>\s+)'
    r'(?P<opt>-e\s+|-n\s+)?'
    r'(?P<q>"|\')(?P<txt>(?:[^"\'\\]|\\.)*)(?P=q)'
)


def is_translatable(txt: str) -> bool:
    return bool(CJK_RE.search(txt))


class Extractor:
    def __init__(self, relpath: str, dry: bool):
        self.rel = relpath
        self.dry = dry
        self.prefix = KEY_PREFIX.get(relpath, 'TXT_')
        self.counter = 0
        self.by_text = {}          # 模板文本 → 键
        self.entries = {}          # 键 → {'zh':..., 'args':n, 'printf':bool}
        self.rewritten = []
        self.skipped = []
        self.unchanged = []

    def _key_for(self, text: str, nargs: int, is_printf: bool):
        key = self.by_text.get(text)
        if key is None:
            self.counter += 1
            key = '%s%04d' % (self.prefix, self.counter)
            self.by_text[text] = key
            self.entries[key] = {'zh': text, 'args': nargs, 'printf': is_printf}
        return key

    def process_line(self, lineno: int, line: str) -> str:
        stripped = line.lstrip()
        if stripped.startswith('#') or '<<' in line:
            return line
        if not CALL_RE.search(line):
            return line
        out = line
        offset = 0
        changed = False
        while True:
            m = CALL_RE.search(out, offset)
            if not m:
                break
            txt = m.group('txt')
            if not is_translatable(txt):
                offset = m.end()
                continue
            raw = txt
            if COMPLEX_RE.search(raw):
                self.skipped.append((lineno, line.strip(), 'complex-expansion'))
                offset = m.end()
                continue
            is_printf = m.group('fn') == 'printf'
            if is_printf and '$' in raw:
                self.skipped.append((lineno, line.strip(), 'printf-with-vars'))
                offset = m.end()
                continue
            args = []

            def _sub(mm):
                args.append('"%s"' % mm.group(0))
                return '\x00'          # 占位符哨兵，稍后换成 %s

            if is_printf:
                # printf 调用点：格式串原样进语言包（保留 %s/%d），后续参数保持不动
                template = raw
            else:
                # 先把变量换成哨兵，再转义文本里原有的字面 %，最后才落成 %s——
                # 顺序反了会把占位符自己转义掉（printf 会打印字面 "%s"）。
                with_sentinel = VAR_RE.sub(_sub, raw)
                template = with_sentinel.replace('%', '%%').replace('\x00', '%s')
                # 自检 1：源码里每个变量都必须被换成参数，数量不符说明有形式没识别（宁可交人工）
                if len(VAR_RE.findall(raw)) != len(args):
                    self.skipped.append((lineno, line.strip(), 'var-count-mismatch'))
                    offset = m.end()
                    continue
                # 自检 2：模板里不允许残留任何 $（残留即会漏变量）
                if '$' in template:
                    self.skipped.append((lineno, line.strip(), 'residual-dollar'))
                    offset = m.end()
                    continue
            key = self._key_for(template, len(args), is_printf)
            argstr = (' ' + ' '.join(args)) if args else ''
            replacement = '%s%s "$(L %s%s)"' % (m.group('pre'), m.group('fn'), key, argstr)
            out = out[:m.start()] + replacement + out[m.end():]
            changed = True
            offset = m.start() + len(replacement)
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
    print('%-34s %8s %8s' % ('文件', '中文文案', '可自动改写'))
    total = auto = 0
    for rel in KEY_PREFIX:
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            continue
        lines = io.open(path, encoding='utf-8').read().split('\n')
        ex = Extractor(rel, True)
        n = 0
        for i, l in enumerate(lines, 1):
            before = len(ex.rewritten)
            ex.process_line(i, l)
            if len(ex.rewritten) > before:
                n += 1
        cnt = sum(1 for l in lines if not l.lstrip().startswith('#') and CALL_RE.search(l)
                  and is_translatable(CALL_RE.search(l).group('txt')))
        print('%-34s %8d %8d' % (rel, cnt, n))
        total += cnt
        auto += n
    print('%-34s %8d %8d' % ('合计', total, auto))


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
        for ln, text, why in r['skipped'][:8]:
            print('   SKIP %-5d [%s] %s' % (ln, why, text[:100]))
    if args.json:
        data = {r['file']: r['entries'] for r in results}
        io.open(args.json, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=1))
        print('\n键表已写入 %s' % args.json)
    return 0


if __name__ == '__main__':
    sys.exit(main())
