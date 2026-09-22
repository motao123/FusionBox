#!/usr/bin/env python3
"""i18n 审计：语言包一致性、英文包纯净度、覆盖进度、install.sh 内置表漂移。

用法：
    python3 scripts/i18n_audit.py            # 全部检查（一致性/纯净度/内置表）
    python3 scripts/i18n_audit.py --coverage # 追加：各文件未抽取文案计数（信息性）
    python3 scripts/i18n_audit.py --max-untranslated N   # 覆盖率棘轮（超过 N 视为失败）

退出码：0 全部通过；1 有硬性失败（键不一致 / 英文含中文 / 内置表漂移 / 超棘轮）。
"""
import argparse
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
I18N = os.path.join(ROOT, 'src', 'i18n')
KEY_RE = re.compile(r'^([A-Z][A-Z0-9_]*)="((?:[^"\\]|\\.)*)"', re.M)
CJK_RE = re.compile('[\u3000-\u303f\u4e00-\u9fff\uff00-\uffef\u2018\u2019\u201c\u201d\u2014\u2026\u3001\u3002]')
SPEC_RE = re.compile(r'%(?:s|d|i|f|x|X|o|e|g|u|c)')

# 英文包里允许保留的中文（仅有「语言自称」这类必须写原名的场景）
EN_CJK_ALLOW = set()

# 已抽取完成的文件（核心层）；其余为待推进的模块层
CORE_FILES = ['fusion.sh', 'install.sh', 'src/init.sh', 'src/lib/common.sh']

# 提取器使用的消息调用形态（与 scripts/i18n_extract.py 保持一致）
CALL_RE = re.compile(
    r'(?:msg(?:_ok|_err|_warn|_info|_tip|_title)?|echo|printf)\s+(?:-e\s+|-n\s+)?'
    r'(?:"([^"]*)"|\'([^\']*)\')')


def load_pack(lang):
    p = os.path.join(I18N, lang + '.sh')
    if not os.path.isfile(p):
        return None
    return dict(KEY_RE.findall(io.open(p, encoding='utf-8').read()))


def check_parity(zh, en, problems):
    only_zh = sorted(set(zh) - set(en))
    only_en = sorted(set(en) - set(zh))
    for k in only_zh:
        problems.append('en.sh 缺键: %s' % k)
    for k in only_en:
        problems.append('zh_CN.sh 缺键: %s' % k)
    for k in sorted(set(zh) & set(en)):
        zs, es = SPEC_RE.findall(zh[k]), SPEC_RE.findall(en[k])
        if zs != es:
            problems.append('占位符不一致 %s: zh=%s en=%s' % (k, zs, es))
        if not zh[k].strip():
            problems.append('zh_CN 空值: %s' % k)
        if not en[k].strip():
            problems.append('en 空值: %s' % k)


def check_en_purity(en, problems):
    for k, v in sorted(en.items()):
        if k in EN_CJK_ALLOW:
            continue
        if CJK_RE.search(v):
            problems.append('en.sh 含中文: %s=%s' % (k, v[:60]))


def check_install_table(zh, en, problems):
    p = os.path.join(ROOT, 'install.sh')
    src = io.open(p, encoding='utf-8').read()
    for lang, table in (('_IL_ZH', zh), ('_IL_EN', en)):
        for m in re.finditer(r'^%s\[([A-Z][A-Z0-9_]*)\]="((?:[^"\\]|\\.)*)"' % lang, src, re.M):
            key, val = m.group(1), m.group(2)
            want = table.get(key)
            if want is None:
                problems.append('install.sh %s[%s] 在语言包中不存在' % (lang, key))
            elif want != val:
                problems.append('install.sh %s[%s] 与语言包漂移: %r != %r' % (lang, key, val, want))


def count_untranslated(files):
    total = 0
    rows = []
    for rel in files:
        p = os.path.join(ROOT, rel.replace('/', os.sep))
        if not os.path.isfile(p):
            continue
        n = 0
        for line in io.open(p, encoding='utf-8').read().split('\n'):
            if line.lstrip().startswith('#'):
                continue
            for m in CALL_RE.finditer(line):
                txt = m.group(1) or m.group(2) or ''
                if CJK_RE.search(txt):
                    n += 1
        rows.append((rel, n))
        total += n
    return rows, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--coverage', action='store_true')
    ap.add_argument('--max-untranslated', type=int, default=None)
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    problems = []
    zh, en = load_pack('zh_CN'), load_pack('en')
    if zh is None or en is None:
        print('!! 语言包缺失（src/i18n/zh_CN.sh 或 en.sh）')
        return 1
    check_parity(zh, en, problems)
    check_en_purity(en, problems)
    check_install_table(zh, en, problems)

    if args.coverage:
        # 全仓覆盖进度（信息性）
        mods = ['src/modules/%s.sh' % m for m in
                ('proxy', 'system', 'network', 'web', 'panels', 'market', 'warp', 'workspace', 'cluster')]
        rows, total = count_untranslated(CORE_FILES + mods)
        print('%-34s %8s' % ('文件', '未抽取'))
        for rel, n in rows:
            mark = '✓' if n == 0 else ' '
            print('%-34s %8d %s' % (rel, n, mark))
        print('%-34s %8d' % ('合计', total))
        core_rows, core_total = count_untranslated(CORE_FILES)
        if core_total:
            problems.append('核心层仍有 %d 处未抽取文案' % core_total)
        if args.max_untranslated is not None and total > args.max_untranslated:
            problems.append('未抽取文案 %d > 棘轮上限 %d' % (total, args.max_untranslated))

    if problems:
        print('!! i18n 审计失败 %d 项：' % len(problems))
        for p in problems[:40]:
            print('   - %s' % p)
        return 1
    if not args.quiet:
        print('i18n 审计通过：zh_CN %d 键 / en %d 键，键与占位符完全一致，英文包无中文，'
              'install.sh 内置表与语言包同步' % (len(zh), len(en)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
