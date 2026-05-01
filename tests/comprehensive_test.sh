#!/bin/bash
# FusionBox Comprehensive Test Suite

cd /root/FusionBox 2>/dev/null || cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0; ERR_LIST=()

test() {
  local name="$1"; local result="$2"
  if [[ "$result" -eq 0 ]]; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL+1))
    ERR_LIST+=("$name")
  fi
}

echo "===== FusionBox Comprehensive Test Suite ====="
echo ""

echo "--- 1. Basic Existence & Syntax ---"
test "fusion.sh exists"  $([ -f fusion.sh ]; echo $?)
test "install.sh exists" $([ -f install.sh ]; echo $?)
for f in fusion.sh install.sh src/init.sh src/lib/common.sh src/modules/*.sh src/i18n/*.sh; do
  bash -n "$f" 2>/dev/null
  test "bash syntax: $f" $?
done

echo ""
echo "--- 2. Module Entry Points ---"
for mod in proxy system network web panels market; do
  grep -q "^${mod}_main()" "src/modules/${mod}.sh"
  test "${mod}_main function" $?
done

echo ""
echo "--- 3. Command Routing ---"
for fn in route main_menu show_help self_update show_status; do
  grep -q "^${fn}()" fusion.sh
  test "${fn} exists" $?
done

echo ""
echo "--- 4. Runtime Commands ---"
OUTPUT=$(bash fusion.sh version 2>&1)
test "version shows FusionBox v1" $(echo "$OUTPUT" | grep -q "FusionBox v1"; echo $?)

OUTPUT=$(bash fusion.sh help 2>&1)
test "help shows Proxy Management" $(echo "$OUTPUT" | grep -qi "代理管理\|Proxy Management"; echo $?)
test "help shows System Management" $(echo "$OUTPUT" | grep -qi "系统管理\|System Management"; echo $?)
test "help shows Network Tools" $(echo "$OUTPUT" | grep -qi "网络工具\|Network Tools"; echo $?)
test "help shows App Market" $(echo "$OUTPUT" | grep -qi "应用市场\|App Market"; echo $?)

echo ""
echo "--- 5. Module Routing ---"
for mod_pair in "proxy|代理" "system|BBR" "network|IP" "web|LNMP" "panels|Docker" "market|应用"; do
  cmd="${mod_pair%%|*}"
  expected="${mod_pair##*|}"
  OUTPUT=$(bash fusion.sh "$cmd" help 2>&1)
  test "route to $cmd shows $expected" $(echo "$OUTPUT" | grep -qi "$expected"; echo $?)
done

echo ""
echo "--- 6. System Module Functions ---"
OUTPUT=$(bash fusion.sh system info 2>&1)
test "system info shows CPU" $(echo "$OUTPUT" | grep -qi "CPU"; echo $?)
test "system info shows Memory" $(echo "$OUTPUT" | grep -qi "内存\|Memory"; echo $?)
test "system info shows Kernel" $(echo "$OUTPUT" | grep -qi "内核\|Kernel"; echo $?)

OUTPUT=$(bash fusion.sh system bbr 2>&1)
test "system bbr shows status" $(echo "$OUTPUT" | grep -qiE "BBR|拥塞控制|congestion|CUBIC"; echo $?)

OUTPUT=$(bash fusion.sh system benchmark 2>&1)
test "system benchmark shows CPU" $(echo "$OUTPUT" | grep -qi "CPU"; echo $?)
test "system benchmark shows Disk I/O" $(echo "$OUTPUT" | grep -qi "磁盘\|Disk I/O\|Read\|Write\|读取\|写入"; echo $?)

OUTPUT=$(bash fusion.sh system monitor 2>&1 & sleep 2 && kill %1 2>/dev/null)
test "system monitor starts" $?

echo ""
echo "--- 7. Network Module Functions ---"
OUTPUT=$(bash fusion.sh network ip 2>&1)
test "network ip shows IPv4" $(echo "$OUTPUT" | grep -qi "IPv4\|IPv6"; echo $?)

OUTPUT=$(bash fusion.sh network streaming 2>&1)
test "network streaming checks services" $(echo "$OUTPUT" | grep -qiE "Netflix|YouTube|ChatGPT|TikTok|流媒体"; echo $?)

OUTPUT=$(bash fusion.sh network dns 2>&1)
test "network dns shows system DNS" $(echo "$OUTPUT" | grep -qi "系统 DNS\|System DNS\|resolv"; echo $?)

OUTPUT=$(bash fusion.sh network ping google.com 2>&1)
test "network ping works" $(echo "$OUTPUT" | grep -qi "ping\|64 bytes\|from"; echo $?)

echo ""
echo "--- 8. Web Module Functions ---"
OUTPUT=$(bash fusion.sh web help 2>&1)
test "web help shows LNMP" $(echo "$OUTPUT" | grep -qi "LNMP\|lnmp"; echo $?)
test "web help shows SSL" $(echo "$OUTPUT" | grep -qi "SSL\|ssl"; echo $?)

OUTPUT=$(bash fusion.sh web nginx status 2>&1)
test "web nginx status" $(echo "$OUTPUT" | grep -qiE "Nginx|nginx|未安装\|not installed"; echo $?)

echo ""
echo "--- 9. Panels Module Functions ---"
OUTPUT=$(bash fusion.sh panels help 2>&1)
test "panels help shows Docker" $(echo "$OUTPUT" | grep -qi "Docker\|docker"; echo $?)
test "panels help shows Baota" $(echo "$OUTPUT" | grep -qi "宝塔\|Baota"; echo $?)
test "panels help shows X-UI" $(echo "$OUTPUT" | grep -qi "X-UI\|x-ui"; echo $?)

OUTPUT=$(bash fusion.sh panels docker 2>&1 & sleep 2 && kill %1 2>/dev/null)
test "panels docker menu" $?

echo ""
echo "--- 10. Market Module Functions ---"
OUTPUT=$(bash fusion.sh market help 2>&1)
test "market help shows list" $(echo "$OUTPUT" | grep -qi "list\|列出"; echo $?)
test "market help shows install" $(echo "$OUTPUT" | grep -qi "install\|安装"; echo $?)

echo ""
echo "--- 11. Install Script ---"
OUTPUT=$(bash install.sh 2>&1)
test "install.sh detects environment" $(echo "$OUTPUT" | grep -qi "检测到\|Detected\|Installer\|安装"; echo $?)

echo ""
echo "--- 12. Config & Templates ---"
test "config.yaml exists" $([ -f configs/config.yaml ]; echo $?)
test "nginx template exists" $([ -f templates/nginx/fusionbox.conf ]; echo $?)
test "docker template exists" $([ -f templates/docker/nginx-proxy.yml ]; echo $?)

echo ""
echo "--- 13. i18n ---"
for lang in en zh_CN; do
  test "i18n/$lang.sh MSG_WELCOME" $(grep -q "MSG_WELCOME=" "src/i18n/$lang.sh"; echo $?)
  test "i18n/$lang.sh MOD_PROXY" $(grep -q "MOD_PROXY=" "src/i18n/$lang.sh"; echo $?)
  test "i18n/$lang.sh SYS_INFO" $(grep -q "SYS_INFO=" "src/i18n/$lang.sh"; echo $?)
  test "i18n/$lang.sh has welcome message" $(grep -q "Welcome\|欢迎" "src/i18n/$lang.sh"; echo $?)
done

echo ""
echo "--- 14. No External Project References ---"
refs=0
for pattern in "233boy" "kejilion" "BlueSkyXN" "SKY-BOX" "Neo-TOWeR"; do
  count=$(grep -r "$pattern" . --exclude-dir=tests --include="*.sh" --include="*.md" --include="*.yaml" --include="*.yml" --include="*.txt" --include="*.json" 2>/dev/null | grep -v "node_modules\|\.git" | wc -l)
  refs=$((refs + count))
done
test "no external project references ($refs found, expect 0)" $([ "$refs" -eq 0 ]; echo $?)

echo ""
echo "--- 15. File Integrity ---"
test "version.txt is 1.0.0" $(grep -q "1.0.0" version.txt; echo $?)
test "fusion.sh is executable" $([ -x fusion.sh ]; echo $?)
test "install.sh is executable" $([ -x install.sh ]; echo $?)

total_files=$(find . -name "*.sh" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.conf" -o -name "*.txt" -o -name "*.md" 2>/dev/null | grep -v ".git/" | wc -l)
test "minimum 20 source files" $([ "$total_files" -ge 20 ]; echo $?)

echo ""
echo "======= RESULTS ======="
echo "  Total:  $((PASS+FAIL))  Passed: $PASS  Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo "  Failed tests:"
  for e in "${ERR_LIST[@]}"; do echo "    - $e"; done
  exit 1
else
  echo "  All tests passed!"
fi
