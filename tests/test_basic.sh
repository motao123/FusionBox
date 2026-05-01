#!/bin/bash
# FusionBox Basic Tests
# Run: bash tests/test_basic.sh

FUSION_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

test() {
  local name="$1"
  local result="$2"
  if [[ "$result" -eq 0 ]]; then
    echo "  PASS: $name"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL+1))
  fi
}

echo "FusionBox Test Suite"
echo "===================="
echo ""

# Test 1: All source files exist
echo "--- File Structure ---"
test "fusion.sh exists" $([ -f "$FUSION_DIR/fusion.sh" ]; echo $?)
test "install.sh exists" $([ -f "$FUSION_DIR/install.sh" ]; echo $?)
test "init.sh exists" $([ -f "$FUSION_DIR/src/init.sh" ]; echo $?)
test "common.sh exists" $([ -f "$FUSION_DIR/src/lib/common.sh" ]; echo $?)
test "proxy.sh exists" $([ -f "$FUSION_DIR/src/modules/proxy.sh" ]; echo $?)
test "system.sh exists" $([ -f "$FUSION_DIR/src/modules/system.sh" ]; echo $?)
test "network.sh exists" $([ -f "$FUSION_DIR/src/modules/network.sh" ]; echo $?)
test "web.sh exists" $([ -f "$FUSION_DIR/src/modules/web.sh" ]; echo $?)
test "panels.sh exists" $([ -f "$FUSION_DIR/src/modules/panels.sh" ]; echo $?)
test "market.sh exists" $([ -f "$FUSION_DIR/src/modules/market.sh" ]; echo $?)
test "i18n/en.sh exists" $([ -f "$FUSION_DIR/src/i18n/en.sh" ]; echo $?)
test "i18n/zh_CN.sh exists" $([ -f "$FUSION_DIR/src/i18n/zh_CN.sh" ]; echo $?)
test "config.yaml exists" $([ -f "$FUSION_DIR/configs/config.yaml" ]; echo $?)

# Test 2: Shell syntax check
echo ""
echo "--- Syntax Check ---"
for f in fusion.sh install.sh src/init.sh src/lib/common.sh src/modules/*.sh src/i18n/*.sh; do
  if [[ -f "$FUSION_DIR/$f" ]]; then
    bash -n "$FUSION_DIR/$f" 2>/dev/null
    test "bash syntax: $f" $?
  fi
done

# Test 3: Module entry points
echo ""
echo "--- Module Entry Points ---"
test "proxy_main function exists" $(grep -q "^proxy_main()" "$FUSION_DIR/src/modules/proxy.sh"; echo $?)
test "system_main function exists" $(grep -q "^system_main()" "$FUSION_DIR/src/modules/system.sh"; echo $?)
test "network_main function exists" $(grep -q "^network_main()" "$FUSION_DIR/src/modules/network.sh"; echo $?)
test "web_main function exists" $(grep -q "^web_main()" "$FUSION_DIR/src/modules/web.sh"; echo $?)
test "panels_main function exists" $(grep -q "^panels_main()" "$FUSION_DIR/src/modules/panels.sh"; echo $?)
test "market_main function exists" $(grep -q "^market_main()" "$FUSION_DIR/src/modules/market.sh"; echo $?)

# Test 4: Main router
echo ""
echo "--- Router ---"
test "route command handler exists" $(grep -q "^route()" "$FUSION_DIR/fusion.sh"; echo $?)
test "main_menu exists" $(grep -q "^main_menu()" "$FUSION_DIR/fusion.sh"; echo $?)
test "show_help exists" $(grep -q "^show_help()" "$FUSION_DIR/fusion.sh"; echo $?)

# Test 5: i18n keys
echo ""
echo "--- i18n ---"
test "en.sh has MSG_WELCOME" $(grep -q "MSG_WELCOME=" "$FUSION_DIR/src/i18n/en.sh"; echo $?)
test "zh_CN.sh has MSG_WELCOME" $(grep -q "MSG_WELCOME=" "$FUSION_DIR/src/i18n/zh_CN.sh"; echo $?)
test "en.sh has MOD_PROXY" $(grep -q "MOD_PROXY=" "$FUSION_DIR/src/i18n/en.sh"; echo $?)
test "zh_CN.sh has MOD_PROXY" $(grep -q "MOD_PROXY=" "$FUSION_DIR/src/i18n/zh_CN.sh"; echo $?)

# Summary
echo ""
echo "===================="
echo "Results: $PASS passed, $FAIL failed"
echo "===================="
exit $FAIL
