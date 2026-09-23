#!/usr/bin/env python3
"""i18n 审计：语言包一致性、英文包纯净度、覆盖进度、install.sh 内置表漂移、数据数组字面量。

用法：
    python3 scripts/i18n_audit.py            # 全部检查（一致性/纯净度/内置表/数据数组）
    python3 scripts/i18n_audit.py --coverage # 追加：各文件未抽取文案计数（信息性）
    python3 scripts/i18n_audit.py --max-untranslated N   # 覆盖率棘轮（超过 N 视为失败）

退出码：0 全部通过；1 有硬性失败（键不一致 / 英文含中文 / 内置表漂移 /
        数据数组含未走语言包的中文条目 / 超棘轮）。
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
# bash 数组字面量：NAME=(\n ... \n) —— 用于扫描数据表里的未抽取条目
ARRAY_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=\(\n(.*?)^\)', re.M | re.S)

# 约定「条目 100% 走语言包」的数据表（棘轮基线：2026-09-23 实测全部 100% 键式）。
# 往这些数组里加字面量条目即为未抽取文案。标识符型数组（P_PROTOCOLS / P_BACKENDS /
# CLUSTER_GAMES 的纯 ASCII 条目）不在此列——它们本来就不该有键。
KEYED_ARRAYS = {
    'MARKET_APPS', 'SYSTEM_TZ_PRESETS', 'PANELS_DOCKER_MIRRORS',
    'CLUSTER_TASKS', 'NETWORK_BENCH_ITEMS',
}

# 英文包里允许保留的中文（仅有「语言自称」这类必须写原名的场景）
EN_CJK_ALLOW = set()

# 已抽取完成的文件（核心层）；模块层见 ALL_FILES
CORE_FILES = ['fusion.sh', 'install.sh', 'src/init.sh', 'src/lib/common.sh']

# 全仓需要抽取的脚本（v1.43.0 起模块层也已收口，未抽取数必须为 0）
ALL_FILES = CORE_FILES + ['src/modules/%s.sh' % m for m in
                          ('system', 'web', 'panels', 'cluster', 'network',
                           'market', 'workspace', 'proxy', 'warp')]

# 提取器使用的消息调用形态（保留供参考；实际计数走 i18n_extract.Extractor）
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
    """统计仍未抽取的文案行数（复用 i18n_extract 的抽取器，覆盖全部出口形态）。"""
    sys.path.insert(0, os.path.join(ROOT, 'scripts'))
    import i18n_extract as ie
    total = 0
    rows = []
    for rel in files:
        p = os.path.join(ROOT, rel.replace('/', os.sep))
        if not os.path.isfile(p):
            continue
        lines = io.open(p, encoding='utf-8').read().split('\n')
        ex = ie.Extractor(rel, True)
        seen = set()
        for i, line in enumerate(lines, 1):
            before = len(ex.rewritten)
            ex.process_line(i, line)
            if len(ex.rewritten) > before:
                seen.add(i)
        rows.append((rel, len(seen)))
        total += len(seen)
    return rows, total


def check_data_arrays(files, problems):
    """数据数组的抽取检查。

    `count_untranslated()` 只扫 msg/echo/printf 这类**文案出口**，看不见数组里的条目，
    所以 v1.43.0 的 `MARKET_APPS` Warp 条目（英文说明、未走语言包）能一路混过 --coverage
    报 0。这里补两条正交的规矩：

    1. 棘轮：`KEYED_ARRAYS` 里的数组今天 100% 走语言包，出现任何非 `$(L ...)` 条目即为
       未抽取文案——**与语种无关**（那条漏网的正是纯英文，只查中文会再次放过它）。
    2. 兜底：任何数组条目里出现中文字面量且未走语言包，一律失败。
       标识符型数组（P_PROTOCOLS 的 `"VLESS-TCP" "vless" "tcp"`、CLUSTER_GAMES 的
       `minecraft-java|Minecraft Java|...`）不含中文，天然不受影响。
    """
    arrays = entries = 0
    for rel in files:
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        src = io.open(p, encoding='utf-8').read()
        for m in ARRAY_RE.finditer(src):
            name, body, base = m.group(1), m.group(2), m.start(2)
            rows = [(i, l.strip()) for i, l in enumerate(body.split('\n'))
                    if l.strip().startswith('"')]
            if not rows:
                continue
            arrays += 1
            entries += len(rows)
            for i, row in rows:
                if '$(L ' in row:
                    continue
                ln = src[:base].count('\n') + i + 1
                if name in KEYED_ARRAYS:
                    problems.append('%s:%d 数组 %s 约定全量走语言包，出现字面量条目: %s'
                                    % (rel, ln, name, row[:60]))
                elif CJK_RE.search(row):
                    problems.append('%s:%d 数组 %s 的条目含中文却未走语言包: %s'
                                    % (rel, ln, name, row[:60]))
    return arrays, entries


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
    arrays, entries = check_data_arrays(ALL_FILES, problems)

    if args.coverage:
        # 全仓覆盖进度
        rows, total = count_untranslated(ALL_FILES)
        print('%-34s %8s' % ('文件', '未抽取'))
        for rel, n in rows:
            mark = '✓' if n == 0 else ' '
            print('%-34s %8d %s' % (rel, n, mark))
        print('%-34s %8d' % ('合计', total))
        if total:
            problems.append('仍有 %d 处未抽取文案' % total)
        if args.max_untranslated is not None and total > args.max_untranslated:
            problems.append('未抽取文案 %d > 棘轮上限 %d' % (total, args.max_untranslated))

    if problems:
        print('!! i18n 审计失败 %d 项：' % len(problems))
        for p in problems[:40]:
            print('   - %s' % p)
        return 1
    if not args.quiet:
        print('i18n 审计通过：zh_CN %d 键 / en %d 键，键与占位符完全一致，英文包无中文，'
              'install.sh 内置表与语言包同步；数据数组扫描 %d 个 / %d 条目，'
              '棘轮数组 %s 保持全量键式'
              % (len(zh), len(en), arrays, entries, '/'.join(sorted(KEYED_ARRAYS))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
