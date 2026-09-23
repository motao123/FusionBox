#!/usr/bin/env python3
"""发布链路加固棘轮：随产品交付的 compose 编排里，端口与凭据不许有"隐式默认"。

两类断言：
1. 已发布端口（`- "HOST:CONTAINER"`）要么绑回环地址，要么在同一行或上一行写
   `# fb-expose: <理由>`。裸写 `8088:80` 等于绑 0.0.0.0，云主机上就是公网可达。
2. 口令/密钥类环境变量（键名含 PASSWORD/PASSWD/PWD/SECRET/TOKEN/KEY）的值必须是
   运行时展开（`${...}`、`$var`）或 `.env` 注入，不许是字面量；确实需要字面量的写
   `# fb-cred-ok: <理由>`。

扫描范围只覆盖会随安装交付的文件（src/**.sh、templates/、configs/、install.sh、
fusion.sh），测试资产与 .scratch 不参与。
"""
from __future__ import annotations

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EXPOSE_MARK = re.compile(r"#\s*fb-expose\s*:")
CRED_MARK = re.compile(r"#\s*fb-cred-ok\s*:")
PORT_LINE = re.compile(r'^\s*-\s*"?(?P<host>[0-9.]+|\[?::[0-9a-f]*\]?|localhost|::1)??:?(?P<pub>\d+):(?P<target>\d+)(?:/(?:tcp|udp))?/?')
# 不锚行尾：引号被写坏的畸形行同样要算端口映射，否则格式一错本检查就瞎掉
PORT_BARE = re.compile(r'^\s*-\s*"?(?P<binding>\d+:\d+(?:/(?:tcp|udp))?)')
UNBALANCED_QUOTE = re.compile(r'^\s*-\s*"[^"\n]*$')
LOOPBACK = re.compile(r'^(?:127\.\d{1,3}\.\d{1,3}\.\d{1,3}|::1|\[::1\]|localhost)$')
ENV_LINE = re.compile(r'^\s*(?:-\s*)?(?P<key>[A-Z][A-Z0-9_]{2,})\s*[:=]\s*"?(?P<value>[^"\n]*?)"?\s*$')
CRED_KEY = re.compile(r"(?:PASSWORD|PASSWD|PWD|SECRET|TOKEN|_KEY)$|^(?:KEY|SECRET)")
RUNTIME_VALUE = re.compile(r"^(?:\$[{(]?[A-Za-z_]|[A-Za-z0-9_.-]+\s*[:=]|<|\{\{|%s|\$\{)")

SCAN_ROOTS = ("src", "templates", "configs")
SCAN_FILES = ("install.sh", "fusion.sh")


def candidates():
    for name in SCAN_FILES:
        path = os.path.join(ROOT, name)
        if os.path.isfile(path):
            yield path
    for base in SCAN_ROOTS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, base)):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith((".sh", ".yml", ".yaml", ".conf")):
                    yield os.path.join(dirpath, fn)


def marked(lines, index, pattern):
    for offset in (0, -1):
        position = index + offset
        if 0 <= position < len(lines) and pattern.search(lines[position]):
            return True
    return False


def audit(path):
    problems = []
    try:
        lines = io.open(path, encoding="utf-8").read().splitlines()
    except (UnicodeDecodeError, OSError):
        return problems
    for number, line in enumerate(lines):
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if UNBALANCED_QUOTE.match(line.rstrip()):
            problems.append("%s:%d 该行的引号不成对，渲染进 compose 就不是合法 YAML：%s"
                            % (rel, number + 1, line.strip()[:60]))
            continue
        stripped = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
        if PORT_BARE.match(stripped):
            if not marked(lines, number, EXPOSE_MARK):
                problems.append("%s:%d 端口 %s 未指定绑定地址（Docker 会绑到所有网卡）；"
                                "改 127.0.0.1: 前缀或注明 # fb-expose: <理由>"
                                % (rel, number + 1, PORT_BARE.match(stripped).group("binding")))
        elif PORT_LINE.match(stripped) and stripped.lstrip().startswith("-"):
            host = PORT_LINE.match(stripped).group("host")
            if host and not LOOPBACK.match(host) and not marked(lines, number, EXPOSE_MARK):
                problems.append("%s:%d 端口绑定到 %s 且未注明 # fb-expose: <理由>"
                                % (rel, number + 1, host))
        match = ENV_LINE.match(stripped)
        if match and CRED_KEY.search(match.group("key")):
            value = match.group("value").strip()
            if value and not RUNTIME_VALUE.match(value) and not marked(lines, number, CRED_MARK):
                problems.append("%s:%d %s 是写死的字面量凭据；改运行时取值或注明 # fb-cred-ok: <理由>"
                                % (rel, number + 1, match.group("key")))
    return problems


def main():
    problems = []
    scanned = 0
    for path in sorted(candidates()):
        scanned += 1
        problems.extend(audit(path))
    if problems:
        for item in problems:
            print("  " + item)
        print("FAIL  端口/凭据棘轮：%d 处需要显式绑定或注明理由（扫描 %d 个交付文件）"
              % (len(problems), scanned))
        return 1
    print("PASS  端口/凭据棘轮：交付的 compose 编排里没有隐式全网卡端口，也没有写死的凭据（扫描 %d 个文件）" % scanned)
    return 0


if __name__ == "__main__":
    sys.exit(main())
