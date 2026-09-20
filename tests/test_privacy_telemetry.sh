#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
PASS=0
FAIL=0

ok() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
assert_eq() { [[ "$2" == "$3" ]] && ok "$1" || { fail "$1 (expected=$2 actual=$3)"; }; }
assert_match() { [[ "$3" =~ $2 ]] && ok "$1" || { fail "$1 (actual=$3)"; }; }

reset_consent_fixture() {
  rm -f -- "$FUSION_TELEMETRY_ID_FILE" "$FUSION_TELEMETRY_CONSENT_FILE"
  cat > "$FUSION_CONFIG" <<'YAML'
general:
  stats: false
YAML
  CONFIG_general_stats=false
}

export HOME="$TMP/home"
export FUSION_BASE="$ROOT"
export FUSION_SRC="$ROOT/src"
mkdir -p "$HOME/.config/fusionbox"
source "$ROOT/src/lib/common.sh"

cat > "$FUSION_CONFIG" <<'YAML'
# retained heading
general:
  lang: "en" # retained language
  stats: false                # opt in only
  color: true
proxy:
  core_dir: /custom/core
  auto_tls: true
YAML
_load_config
assert_eq 'nested YAML lang parsed' en "${CONFIG_general_lang:-}"
assert_eq 'nested YAML stats parsed' false "${CONFIG_general_stats:-}"
assert_eq 'later section parsed' /custom/core "${CONFIG_proxy_core_dir:-}"

_config_set_general stats true
assert_eq 'stats updated once' 1 "$(grep -c '^[[:space:]]*stats:' "$FUSION_CONFIG")"
assert_match 'inline comment retained' '# opt in only$' "$(grep '^[[:space:]]*stats:' "$FUSION_CONFIG")"
assert_match 'unrelated content retained' '^  core_dir: /custom/core$' "$(grep 'core_dir:' "$FUSION_CONFIG")"

CONFIG_general_stats=false
before="$(find "$FUSION_CONFIG_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)"
_telemetry_event heartbeat
sleep 0.1
after="$(find "$FUSION_CONFIG_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)"
assert_eq 'disabled telemetry creates no identifier' "$before" "$after"

CONFIG_general_stats=true
id1="$(_telemetry_id)"
id2="$(_telemetry_id)"
mode="$(stat -c '%a' "$FUSION_TELEMETRY_ID_FILE")"
# Git Bash on Windows reports host ACL projection as 0644; Linux enforces 0600.
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
  [[ "$mode" == 600 || "$mode" == 644 ]] && ok 'identifier mode requested as 0600' || fail "identifier mode requested as 0600 (actual=$mode)"
else
  assert_eq 'identifier mode is 0600' 600 "$mode"
fi
assert_match 'random UUID format' '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' "$id1"
assert_eq 'identifier is stable' "$id1" "$id2"

privacy_command reset-id >/dev/null
id3="$(< "$FUSION_TELEMETRY_ID_FILE")"
[[ "$id3" != "$id1" ]] && ok 'reset-id rotates identifier' || fail 'reset-id rotates identifier'

_telemetry_event arbitrary-event >/dev/null 2>&1
assert_eq 'event whitelist rejects unknown event' 2 "$?"

privacy_command off >/dev/null
assert_match 'off persisted atomically' '^[[:space:]]*stats: false' "$(grep '^[[:space:]]*stats:' "$FUSION_CONFIG")"
old_id="$(< "$FUSION_TELEMETRY_ID_FILE")"
privacy_command reset-id >/dev/null 2>&1
assert_eq 'reset-id rejected while disabled' 1 "$?"
assert_eq 'disabled reset preserves identifier' "$old_id" "$(< "$FUSION_TELEMETRY_ID_FILE")"

reset_consent_fixture
_telemetry_install_consent 0
assert_eq 'non-TTY install defaults stats off' false "${CONFIG_general_stats:-}"
assert_eq 'non-TTY install records decision' disabled "$(< "$FUSION_TELEMETRY_CONSENT_FILE")"
consent_mode="$(stat -c '%a' "$FUSION_TELEMETRY_CONSENT_FILE")"
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
  [[ "$consent_mode" == 600 || "$consent_mode" == 644 ]] && ok 'consent marker mode requested as 0600' || fail "consent marker mode requested as 0600 (actual=$consent_mode)"
else
  assert_eq 'consent marker mode is 0600' 600 "$consent_mode"
fi
[[ ! -e "$FUSION_TELEMETRY_ID_FILE" ]] && ok 'non-TTY install creates no identifier' || fail 'non-TTY install creates no identifier'

reset_consent_fixture
_telemetry_consent_is_interactive() { return 0; }
printf 'y\n' | _telemetry_install_consent 0
assert_match 'interactive opt-in persists true' '^[[:space:]]*stats: true' "$(grep '^[[:space:]]*stats:' "$FUSION_CONFIG")"
assert_eq 'interactive opt-in records decision' enabled "$(< "$FUSION_TELEMETRY_CONSENT_FILE")"
assert_match 'interactive opt-in creates UUID' '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' "$(< "$FUSION_TELEMETRY_ID_FILE")"

reset_consent_fixture
original_config="$(< "$FUSION_CONFIG")"
printf 'y\n' | _telemetry_install_consent 1
assert_eq 'existing config is not overwritten' "$original_config" "$(< "$FUSION_CONFIG")"
[[ ! -e "$FUSION_TELEMETRY_CONSENT_FILE" ]] && ok 'existing config is not marked or prompted' || fail 'existing config is not marked or prompted'
[[ ! -e "$FUSION_TELEMETRY_ID_FILE" ]] && ok 'existing config creates no identifier' || fail 'existing config creates no identifier'

reset_consent_fixture
printf 'n\n' | _telemetry_install_consent 0
assert_eq 'interactive opt-out records decision' disabled "$(< "$FUSION_TELEMETRY_CONSENT_FILE")"
[[ ! -e "$FUSION_TELEMETRY_ID_FILE" ]] && ok 'interactive opt-out creates no identifier' || fail 'interactive opt-out creates no identifier'

if command -v curl >/dev/null; then
  MOCK="$TMP/bin"
  mkdir -p "$MOCK"
  cat > "$MOCK/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$TELEMETRY_ARGS"
for arg in "$@"; do
  [[ "$arg" == --data-binary ]] && want_payload=1 && continue
  if [[ "${want_payload:-0}" == 1 ]]; then printf '%s' "$arg" > "$TELEMETRY_BODY"; break; fi
done
SH
  chmod +x "$MOCK/curl"
  export TELEMETRY_ARGS="$TMP/curl.args" TELEMETRY_BODY="$TMP/body.json"
  export FUSION_TELEMETRY_TEST_MODE=1
  export FUSION_TELEMETRY_TEST_ENDPOINT='http://127.0.0.1:18080/v1/event'
  CONFIG_general_stats=true FUSION_VER=1.24.2 F_OS=ubuntu PATH="$MOCK:$PATH" _telemetry_event heartbeat
  for _ in {1..20}; do [[ -f "$TELEMETRY_BODY" ]] && break; sleep 0.05; done
  payload="$(< "$TELEMETRY_BODY")"
  assert_match 'payload uses fixed schema' '^\{"schema_version":1,"event":"heartbeat","installation_id":"[0-9a-f]{32}","version":"1.24.2","os":"ubuntu","arch":"(x86_64|aarch64|armv7l|other)"\}$' "$payload"
  assert_match 'short connect timeout' '^2$' "$(grep -A1 -- '--connect-timeout' "$TELEMETRY_ARGS" | tail -1)"
  assert_match 'short total timeout' '^3$' "$(grep -A1 -- '--max-time' "$TELEMETRY_ARGS" | tail -1)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
exit "$FAIL"
