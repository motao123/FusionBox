#!/usr/bin/env python3
"""README 中英同步闸门：保证 README.en.md 不会悄悄落后于 README.md。

用法：
    python3 scripts/docs_readme_gate.py            # 全量检查
    python3 scripts/docs_readme_gate.py --verbose  # 追加逐节结构对照

退出码：0 通过；1 存在硬性漂移（结构 / 命令 / 版本 / 链接 / 中文残留）。

设计口径：文档翻译不追求逐字对等，追求**可验证的结构性对等**——读者能照做的
每一行命令、每一个表格、每一个链接都必须两边同时存在。
"""
import argparse
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ZH = ROOT / "README.md"
EN = ROOT / "README.en.md"

FENCE_RE = re.compile(r"^```(\S*)\s*$")
TABLE_RE = re.compile(r"^\s*\|")
LINK_RE = re.compile(r"\]\(([^)\s]+)")
IMG_RE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)")
INLINE_CODE_RE = re.compile(r"`[^`\n]+`")
VERSION_BADGE_RE = re.compile(r"version-(\d+\.\d+\.\d+)")
# 英文版允许出现的中文：仅品牌 / 面板等专有名词原名
CJK_RE = re.compile("[　-〿一-鿿＀-￯‘’“”—…]")
CJK_ALLOW = {"棉花云", "哪吒监控", "宝塔"}
# 命令块里必须逐字一致的起始词
CMD_RE = re.compile(
    r"^\s*(fusionbox|bash|curl|sudo|systemctl|scp|ssh|git|python3?|k)\b.*"
)
# 命令行尾注是散文，允许翻译；命令本体必须逐字一致
TRAILING_COMMENT_RE = re.compile(r"\s+#.*$")
# 两份 README 互链的语言切换器：链接目标天然不对称，单独校验其存在性
SELF_LINKS = {"README.md", "README.en.md"}
# 命令操作数占位符按设计原样镜像（<端口> / <应用> …），不计入中文残留
PLACEHOLDER_RE = re.compile(r"<[^<>\n]{1,24}>")


def strip_tables_and_fences(lines):
    """返回 (逐行, 是否在代码块内) 的标记序列，便于分区域统计。"""
    in_fence = False
    for raw in lines:
        m = FENCE_RE.match(raw.strip())
        if m:
            yield raw, in_fence
            in_fence = not in_fence
        else:
            yield raw, in_fence


def blocks(lines):
    """按 H2 切节：返回 [(title, [lines]), ...]，首项为前言（无 H2 的头部）。"""
    out, cur, buf = [], "(preamble)", []
    for raw, in_code in strip_tables_and_fences(lines):
        if not in_code and raw.startswith("## "):
            out.append((cur, buf))
            cur, buf = raw[3:].strip(), [raw]
        else:
            buf.append(raw)
    out.append((cur, buf))
    return out


def fingerprint(lines):
    """一节 structural fingerprint。"""
    fences, langs, tables, rows, cells = 0, [], 0, 0, []
    in_code = False
    for raw, was_code in strip_tables_and_fences(lines):
        if FENCE_RE.match(raw.strip()) and not was_code:
            fences += 1
            langs.append(FENCE_RE.match(raw.strip()).group(1))
        in_code = was_code
        if not in_code and TABLE_RE.match(raw):
            tables += 1
            rows += 1
            cells.append(raw.count("|"))
    links = [l for l in LINK_RE.findall("\n".join(lines))
             if not l.startswith("#")
             and Path(l.split("#")[0]).name not in SELF_LINKS]
    return {
        "fences": fences,
        "langs": langs,
        "table_rows": rows,
        "cells": cells,
        "inline_spans": sorted(x for l in lines for x in INLINE_CODE_RE.findall(l)),
        "links": sorted(links),
        "images": sorted(IMG_RE.findall("\n".join(lines))),
    }


def commands(lines):
    """代码块内的可执行命令本体（注释译文不计，命令本身必须逐字一致）。"""
    out = []
    for raw, in_code in strip_tables_and_fences(lines):
        if in_code and CMD_RE.match(raw):
            out.append(TRAILING_COMMENT_RE.sub("", raw).strip())
    return out


def github_anchor(title):
    a = title.strip().lower()
    a = re.sub(r"[^\w \-]", "", a)
    return re.sub(r"\s", "-", a)


def cjk_residue(lines):
    """英文版中文残留：跳过语言切换器一行，并放过原样镜像的命令占位符。"""
    bad = Counter()
    for raw in lines:
        if "](README.md)" in raw or "](./README.md)" in raw:
            continue
        text = PLACEHOLDER_RE.sub("", raw)
        for m in CJK_RE.finditer(text):
            ctx = text[max(0, m.start() - 4): m.start() + 5]
            if any(tok in ctx for tok in CJK_ALLOW):
                continue
            bad[m.group(0)] += 1
    return bad


def unclosed_comment(text):
    """返回首个未配对 `<!--` 的起始行号，全部闭合则返回 None。

    Markdown 渲染器会把未闭合注释之后的整篇正文当注释吞掉，而两份文件同病时
    结构对比恒等相等、本闸门原本看不见（v1.43.1 的发布槽位就是这么坏掉的）。
    """
    pos = 0
    while True:
        start = text.find("<!--", pos)
        if start < 0:
            return None
        end = text.find("-->", start + 4)
        if end < 0:
            return text.count("\n", 0, start) + 1
        pos = end + 3


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true", help="打印逐节结构对照")
    ap.add_argument("--zh", default=str(ZH), help="中文版路径（自测用）")
    ap.add_argument("--en", default=str(EN), help="英文版路径（自测用）")
    args = ap.parse_args()

    zh_path, en_path = Path(args.zh), Path(args.en)
    for path in (zh_path, en_path):
        if not path.exists():
            print(f"FAIL  缺少文件: {path.name}")
            return 1

    zh_lines = zh_path.read_text(encoding="utf-8").splitlines()
    en_lines = en_path.read_text(encoding="utf-8").splitlines()
    zh_sec, en_sec = blocks(zh_lines), blocks(en_lines)

    fails, notes = [], []

    # 1) 版本一致性：两份 README 必须声明同一版本
    zv = set(VERSION_BADGE_RE.findall("\n".join(zh_lines)))
    ev = set(VERSION_BADGE_RE.findall("\n".join(en_lines)))
    if not zv:
        fails.append("README.md 里找不到 version-X.Y.Z 徽章，闸门失去版本锚点")
    if zv and ev != zv:
        fails.append(f"版本徽章不一致 zh={sorted(zv)} en={sorted(ev)}")

    # 2) 分节数量一致
    if len(zh_sec) != len(en_sec):
        fails.append(f"H2 节数不一致：zh={len(zh_sec)} en={len(en_sec)}")
    else:
        notes.append(f"H2 节数一致: {len(zh_sec)}")

    # 3) 逐节结构对等
    for idx, ((zt, zl), (et, el)) in enumerate(zip(zh_sec, en_sec)):
        zf, ef = fingerprint(zl), fingerprint(el)
        for key in ("fences", "table_rows"):
            if zf[key] != ef[key]:
                fails.append(
                    f"[{idx}] 「{zt}」↔「{et}」 {key} 不一致: zh={zf[key]} en={ef[key]}"
                )
        if zf["inline_spans"] != ef["inline_spans"]:
            only_zh = sorted(set(zf["inline_spans"]) - set(ef["inline_spans"]))
            only_en = sorted(set(ef["inline_spans"]) - set(zf["inline_spans"]))
            fails.append(
                f"[{idx}] 「{zt}」行内代码不一致 仅中文有={only_zh[:5]}"
                f" 仅英文有={only_en[:5]}"
            )
        if zf["langs"] != ef["langs"]:
            fails.append(f"[{idx}] 「{zt}」代码块语言标注不一致: {zf['langs']} vs {ef['langs']}")
        if zf["links"] != ef["links"]:
            only_zh = sorted(set(zf["links"]) - set(ef["links"]))
            only_en = sorted(set(ef["links"]) - set(zf["links"]))
            fails.append(
                f"[{idx}] 「{zt}」链接目标不一致 仅中文有={only_zh} 仅英文有={only_en}"
            )
        zc, ec = Counter(commands(zl)), Counter(commands(el))
        if zc != ec:
            miss = sorted((zc - ec).elements())
            extra = sorted((ec - zc).elements())
            fails.append(
                f"[{idx}] 「{zt}」命令行不一致 英文缺失={miss[:6]}"
                f"{'…' if len(miss) > 6 else ''} 英文多出={extra[:6]}"
                f"{'…' if len(extra) > 6 else ''}"
            )
        if args.verbose:
            print(
                f"  [{idx}] {zt[:22]:<24} | {et[:28]:<30} fences={zf['fences']}/{ef['fences']} "
                f"rows={zf['table_rows']}/{ef['table_rows']} cmds={sum(zc.values())}/{sum(ec.values())}"
            )

    # 4) 英文版中文残留（语言切换器与命令占位符除外）
    bad = cjk_residue(en_lines)
    if bad:
        preview = "、".join(f"{c}×{n}" for c, n in bad.most_common(8))
        fails.append(f"README.en.md 含未白名单化的中文 {sum(bad.values())} 处: {preview}")

    # 5) 两份 README 的目录锚点都必须能落到本节标题
    for name, secs, lns in (("README.md", zh_sec, zh_lines),
                            ("README.en.md", en_sec, en_lines)):
        anchors = {github_anchor(t) for t, _ in secs}
        toc = "\n".join(lns[:90])
        dead = sorted(a for a in set(re.findall(r"\]\(#([^)]+)\)", toc))
                      if a not in anchors)
        if dead:
            fails.append(f"{name} 目录锚点失效: {dead}")

    # 6) 语言切换器必须双向可达
    if not re.search(r"\]\((\./)?README\.en\.md\)", "\n".join(zh_lines)):
        fails.append("README.md 缺少指向 README.en.md 的语言切换链接")
    if not re.search(r"\]\((\./)?README\.md\)", "\n".join(en_lines)):
        fails.append("README.en.md 缺少指向 README.md 的语言切换链接")

    broken = []
    for name, lines in ((zh_path.name, zh_lines), (en_path.name, en_lines)):
        at = unclosed_comment("\n".join(lines))
        if at:
            broken.append(f"{name}:{at} 有未闭合的 HTML 注释，其后的正文在渲染时会被整体吞掉")
    if broken:
        fails.extend(broken)
    else:
        notes.append("两份 README 的 HTML 注释成对闭合")

    for n in notes:
        print(f"  ok  {n}")
    if fails:
        print(f"\nFAIL  README 中英同步闸门：{len(fails)} 项漂移")
        for f in fails:
            print(f"  - {f}")
        return 1
    print("PASS  README 中英结构 / 命令 / 版本 / 链接 / 锚点全部对齐")
    return 0


if __name__ == "__main__":
    sys.exit(main())
