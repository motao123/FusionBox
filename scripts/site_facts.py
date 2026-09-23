#!/usr/bin/env python3
"""Pages 主页事实闸门：主页上的每个数字都必须能从入库文件派生。

用法：
    python3 scripts/site_facts.py             # 校验（CI 用），漂移则退出码 1
    python3 scripts/site_facts.py --json      # 打印派生结果
    python3 scripts/site_facts.py --write     # 把派生值写回 docs/index.html

口径与项目一致：**只声明能被读取、能被校验的数**。主页里带 data-fact 标记的数字
由本脚本从源码派生；派生不了的数（如 tests/ 的验收计数——测试资产不入库）不允许
挂 data-fact，只能作为「本地测试资产结论」在文案里注明口径。
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE = os.path.join(ROOT, "docs", "index.html")
I18N_DIR = os.path.join(ROOT, "src", "i18n")
CATALOG_JSON = os.path.join(ROOT, "src", "lib", "market-catalog.v1.json")

KEY_RE = re.compile(r'^([A-Z][A-Z0-9_]*)="((?:[^"\\]|\\.)*)"', re.M)
ARRAY_RE = r"^{name}=\((.*?)^\)"


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def array_body(src, name):
    m = re.search(ARRAY_RE.format(name=re.escape(name)), src, re.S | re.M)
    return m.group(1) if m else ""


def array_rows(src, name):
    """数组里的条目数。"""
    return len(_array_rows(src, name))


def load_langpack():
    zh = {}
    for line in read(os.path.join(I18N_DIR, "zh_CN.sh")).splitlines():
        m = KEY_RE.match(line)
        if m:
            zh[m.group(1)] = m.group(2)
    return zh


def fact_market_categories(market_src, lang):
    """MARKET_APPS 数组每条目格式为 `分类:名称:包名:说明`，多数经语言包取值。"""
    cats = set()
    for row in _array_rows(market_src, "MARKET_APPS"):
        m = re.search(r"L (MSG_MARKET_\d+)", row)
        value = lang.get(m.group(1), "") if m else row.strip().strip('"')
        if ":" in value:
            cats.add(value.split(":", 1)[0].strip())
    return len(cats), len(_array_rows(market_src, "MARKET_APPS"))


def _array_rows(src, name):
    return [l.strip() for l in array_body(src, name).splitlines() if l.strip().startswith('"')]


def fact_managed_templates():
    """内建受管模板 = 运行时目录 − 声明式 JSON 目录条目。"""
    sys.path.insert(0, os.path.join(ROOT, "src", "lib"))
    import market_apps  # noqa: E402  与 CI 的 catalog 检查同源
    market_apps.configure_catalog()
    merged = set(market_apps.catalog_apps())
    declared = {a["id"] for a in json.loads(read(CATALOG_JSON))["apps"]}
    return len(merged - declared), len(declared)


def fact_web_apps(web_src):
    return len(set(re.findall(r"^\s*\d+\)\s+(_deploy_\w+)", web_src, re.M)))


def derive():
    modules = len([f for f in os.listdir(os.path.join(ROOT, "src", "modules"))
                   if f.endswith(".sh")])
    market_src = read(os.path.join(ROOT, "src", "modules", "market.sh"))
    proxy_src = read(os.path.join(ROOT, "src", "modules", "proxy.sh"))
    system_src = read(os.path.join(ROOT, "src", "modules", "system.sh"))
    web_src = read(os.path.join(ROOT, "src", "modules", "web.sh"))
    lang = load_langpack()
    zh_keys = len(lang)
    en_keys = len([1 for line in read(os.path.join(I18N_DIR, "en.sh")).splitlines()
                   if KEY_RE.match(line)])
    builtin, declared = fact_managed_templates()
    cats, _ = fact_market_categories(market_src, lang)
    return {
        "modules": modules,
        "market_apps": array_rows(market_src, "MARKET_APPS"),
        "market_categories": cats,
        "managed_builtin": builtin,
        "managed_declared": declared,
        "proxy_protocols": array_rows(proxy_src, "P_PROTOCOLS"),
        "proxy_backends": array_rows(proxy_src, "P_BACKENDS"),
        "web_apps": fact_web_apps(web_src),
        "tz_presets": array_rows(system_src, "SYSTEM_TZ_PRESETS"),
        "i18n_keys": zh_keys,
        "_i18n_keys_en": en_keys,
    }


MARK_RE = re.compile(r'(data-fact="([^"]+)"[^>]*>)([^<]*)(<)')


def check(facts):
    src = read(PAGE)
    marks = [(m.group(2), m.group(3)) for m in MARK_RE.finditer(src)]
    bad = []
    for name, shown in marks:
        if name not in facts:
            bad.append(f'data-fact="{name}" 无法派生（该数字不该出现在主页上）')
        elif shown != str(facts[name]):
            bad.append(f'data-fact="{name}" 主页写 {shown!r}，源码派生 {facts[name]!r}')
    names = {n for n, _ in marks}
    missing = sorted(set(facts) - names - {k for k in facts if k.startswith("_")})
    if i18n_mismatch(facts):
        bad.append(i18n_mismatch(facts))
    return names, bad, missing


def i18n_mismatch(facts):
    if facts["i18n_keys"] != facts["_i18n_keys_en"]:
        return (f"语言包键数不对等：zh_CN {facts['i18n_keys']} / "
                f"en {facts['_i18n_keys_en']}")
    return None


def write_back(facts):
    src = read(PAGE)

    def sub(m):
        name = m.group(2)
        val = facts.get(name)
        return m.group(1) + (str(val) if val is not None else m.group(3)) + m.group(4)

    new = MARK_RE.sub(sub, src)
    if new != src:
        with open(PAGE, "w", encoding="utf-8", newline="") as fh:
            fh.write(new)
    return sum(1 for a, b in zip(src.splitlines(), new.splitlines()) if a != b)


def main():
    global PAGE
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true", help="打印派生结果")
    ap.add_argument("--write", action="store_true", help="把派生值写回主页")
    ap.add_argument("--page", default=PAGE, help="主页路径（自测用）")
    args = ap.parse_args()

    PAGE = args.page
    facts = derive()
    if args.json:
        print(json.dumps(facts, ensure_ascii=False, indent=2, sort_keys=True))
        return 0
    if args.write:
        n = write_back(facts)
        print(f"PASS  已按源码派生值回写主页，更新 {n} 行")
        return 0

    found, bad, missing = check(facts)
    if not found:
        print("FAIL  主页里没有任何 data-fact 标记，闸门空转")
        return 1
    if bad:
        print(f"FAIL  主页事实闸门：{len(bad)} 项不成立")
        for b in bad:
            print(f"  - {b}")
        return 1
    print(f"PASS  主页 {len(found)} 处声明数字全部由源码派生并对齐："
          + "、".join(f"{k}={facts[k]}" for k in sorted(found)))
    if missing:
        print(f"  note  已派生但主页未展示的数：{', '.join(missing)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
