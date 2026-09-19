#!/bin/bash
# FusionBox reference policy (anti-plagiarism, attribution-aware)
#
# 目的：确保仓库不含未署名的第三方工具箱代码/标识。
#
# 禁止：kejilion / BlueSkyXN / SKY-BOX / Neo-TOWeR 等同类工具箱的项目名，
#       不允许出现在源码或文档的任何位置。
# 例外：233boy/sing-box 是本项目明确授权的集成（fusionbox proxy sb，见 README），
#       允许在下列文件与任意文件的注释行中署名；其余位置出现即视为违规。
#
# 用法: bash tests/reference_policy.sh   （退出码 0 = 通过）

cd "$(dirname "$0")/.." || exit 1

AUTHORIZED_233BOY_FILES="./README.md ./docs/CHANGELOG.md ./fusion.sh ./src/modules/proxy.sh"
FORBIDDEN_PATTERNS="kejilion BlueSkyXN SKY-BOX Neo-TOWeR"

rc=0
auth_files=0

while IFS= read -r f; do
  # 1) 禁止类项目名：任何位置命中即失败
  for pat in $FORBIDDEN_PATTERNS; do
    if grep -q "$pat" "$f" 2>/dev/null; then
      echo "  FAIL: unauthorized reference '$pat' in $f"
      grep -n "$pat" "$f" | head -3 | sed 's/^/    /'
      rc=1
    fi
  done

  # 2) 233boy：仅允许授权文件，或任意文件中的注释行（署名）
  if grep -q "233boy" "$f" 2>/dev/null; then
    case " $AUTHORIZED_233BOY_FILES " in
      *" $f "*)
        auth_files=$((auth_files + 1))
        ;;
      *)
        bad=$(grep -n "233boy" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l)
        if [[ "$bad" -gt 0 ]]; then
          echo "  FAIL: 233boy referenced in $f outside comments"
          echo "        (authorized files: $AUTHORIZED_233BOY_FILES)"
          grep -n "233boy" "$f" | grep -vE '^[0-9]+:[[:space:]]*#' | head -3 | sed 's/^/    /'
          rc=1
        fi
        ;;
    esac
  fi
done < <(if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git ls-files -- '*.sh' '*.md' '*.yaml' '*.yml' '*.txt' '*.json' | grep -v '^tests/' | sed 's|^|./|'
else
  find . -path ./tests -prune -o -type f \( -name '*.sh' -o -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name '*.txt' -o -name '*.json' \) -print
fi)

if [[ $rc -eq 0 ]]; then
  echo "  PASS: no unauthorized project references"
  [[ $auth_files -gt 0 ]] && \
    echo "  INFO: authorized 233boy/sing-box attribution found in $auth_files file(s)"
fi
exit $rc