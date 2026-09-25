#!/usr/bin/env python3
"""上游 URL 存活巡检：评测矩阵/工具类第三方 URL 全量探活。

背景（同类聚合工具箱"失联作品"教训）：聚合类功能的死因是上游 URL 腐烂无人知。
用户照着评测矩阵执行的每个地址都必须活着，本闸门在 CI 逐个探活。

用法：
    python3 scripts/upstream_url_audit.py          # 在线探活全部第三方 URL
    python3 scripts/upstream_url_audit.py --list   # 离线列出提取到的 URL（快闸门用，
                                                   # run_checks 承诺无网络可跑，不做探活）

提取口径：src/i18n/zh_CN.sh、src/i18n/en.sh、install.sh 中的全部 https URL。
排除口径：本项目自有地址（motao123 仓库、api.github.com 同仓库、cnb.cool/code_free、
Pages、遥测 Worker）不巡检；src/modules/ 内的工具类 URL（宝塔/1Panel/reinstall 等）
暂不纳入——其中部分域名按地域可达性波动大，纳入会产生假红，待有分位观测再议。

探活口径：GET + 跟随重定向，最终 2xx/3xx 即存活；每地址超时 15s、瞬时错误重试 1 次。
仅在 GitHub Actions（海外出口）运行；CNB 出口对部分域名不稳定，不接入。
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ("src/i18n/zh_CN.sh", "src/i18n/en.sh", "install.sh")
SELF_PATTERNS = (
    "github.com/motao123",
    "api.github.com/repos/motao123",
    "raw.githubusercontent.com/motao123",
    "cnb.cool/code_free",
    "motao123.github.io",
    "fusionbox-telemetry",
)
URL_RE = re.compile(r"https://[A-Za-z0-9./_?=#%-]+")
TIMEOUT = 15


def extract():
    urls = set()
    for rel in SOURCES:
        text = (ROOT / rel).read_text(encoding="utf-8")
        urls.update(URL_RE.findall(text))
    return sorted(u for u in urls if not any(p in u for p in SELF_PATTERNS))


def probe(url):
    rc = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-L",
         "--max-time", str(TIMEOUT), "--retry", "1", url],
        capture_output=True, text=True, timeout=TIMEOUT + 15)
    code = rc.stdout.strip()
    return code.startswith(("2", "3")), code


def main():
    offline = "--list" in sys.argv[1:]
    urls = extract()
    if len(urls) < 15:
        print(f"FAIL 提取到 {len(urls)} 个 URL，低于基线 15——提取口径可能坏了")
        return 1
    print(f"提取到 {len(urls)} 个第三方 URL")
    if offline:
        for u in urls:
            print(f"  [list] {u}")
        print("PASS 提取口径正常（--list 离线模式，不做探活）")
        return 0
    fails = []
    for u in urls:
        ok, code = probe(u)
        print(f"  [{'ok ' if ok else 'FAIL'}] {code or 'ERR'}  {u}")
        if not ok:
            fails.append(u)
    if fails:
        print(f"FAIL {len(fails)}/{len(urls)} 个第三方地址不可达：")
        for u in fails:
            print(f"  - {u}")
        return 1
    print(f"PASS 全部 {len(urls)} 个第三方 URL 存活")
    return 0


if __name__ == "__main__":
    sys.exit(main())
