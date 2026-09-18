#!/bin/bash
# Safe by default: no installation, system modification or external downloads.
set -e
cd "$(dirname "$0")/.."
bash tests/test_basic.sh
if command -v python >/dev/null 2>&1; then
  python tests/test_safety.py
else
  python3 tests/test_safety.py
fi
