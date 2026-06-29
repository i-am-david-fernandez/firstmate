#!/usr/bin/env bash
# Behavior tests for bin/fm-ntfy-notify.sh - the optional ntfy attention push.
# Fakes `curl` so nothing touches the network; records its argv for assertions.
# All hosts/topics here are obviously-fake placeholders (HR2); the ambient
# NTFY_* are unset so an operator's real config can neither change results nor
# leak into output (HR3).
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$ROOT/bin/fm-ntfy-notify.sh"

# Hermetic (HR3): drop any ambient ntfy config the captain's shell may export.
unset FM_NTFY_HOST FM_NTFY_TOPIC

TMP=$(fm_test_tmproot fm-ntfy)
FAKEBIN=$(fm_fakebin "$TMP")
CURL_LOG="$TMP/curl.log"
CONFIG="$TMP/config"
mkdir -p "$CONFIG"

# Fake curl: record the full argv (one invocation per line); succeed silently.
cat > "$FAKEBIN/curl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CURL_LOG"
exit 0
SH
chmod +x "$FAKEBIN/curl"

# run <args...> : invoke the script with the fake curl on PATH and an isolated
# config dir. Per-call NTFY_* must be set by the caller via the environment.
# BASH_ENV is neutralized so the provider subprocess cannot re-source the
# operator's real config (~/.bash_env -> ~/.secrets.env etc.) and leak/skew the
# test (HR3); NTFY_* are passed through explicitly (empty when the caller unset).
run() {
  : > "$CURL_LOG"
  env BASH_ENV=/dev/null FM_NTFY_HOST="${FM_NTFY_HOST:-}" FM_NTFY_TOPIC="${FM_NTFY_TOPIC:-}" \
      FM_CONFIG_OVERRIDE="$CONFIG" PATH="$FAKEBIN:$PATH" "$SCRIPT" "$@"
}

# 1. Unconfigured -> silent no-op: exit 0 and curl never invoked.
set +e; run "nothing configured"; rc=$?; set -e
expect_code 0 "$rc" "unconfigured push exits 0 (no-op)"
[ ! -s "$CURL_LOG" ] || fail "unconfigured push must not call curl"
pass "no-op when no host configured (exit 0, no curl)"

# 2. Host from env, default topic 'firstmate', flags mapped to headers.
set +e; FM_NTFY_HOST="http://ntfy.example:8080" run -p 4 -h "Build broke" -t "warning,skull" "the build is red"; rc=$?; set -e
expect_code 0 "$rc" "configured push exits 0"
got=$(cat "$CURL_LOG")
assert_contains "$got" "http://ntfy.example:8080/firstmate" "posts to host/<default topic>"
assert_contains "$got" "Title: Build broke" "maps -h to the Title header"
assert_contains "$got" "Priority: 4" "maps -p to the Priority header"
assert_contains "$got" "Tags: warning,skull" "maps -t to the Tags header"
assert_contains "$got" ": the build is red" "body carries the timestamped message"
pass "env host + default topic + flag->header mapping"

# 3. Host and topic from local config files (no env).
printf '# my server\nhttp://cfg.example:9000\n' > "$CONFIG/ntfy-host"
printf 'ops-alerts\n' > "$CONFIG/ntfy-topic"
set +e; run "from config files"; rc=$?; set -e
expect_code 0 "$rc" "config-file push exits 0"
assert_contains "$(cat "$CURL_LOG")" "http://cfg.example:9000/ops-alerts" "resolves host+topic from config files"
pass "host/topic resolve from config files (comments/blanks skipped)"

# 4. Environment wins over the config files.
set +e; FM_NTFY_HOST="http://env.example:1234" FM_NTFY_TOPIC="env-topic" run "env precedence"; rc=$?; set -e
assert_contains "$(cat "$CURL_LOG")" "http://env.example:1234/env-topic" "env overrides config files"
pass "environment overrides config files"

# 5. A trailing slash on the host does not double up before the topic.
rm -f "$CONFIG/ntfy-host" "$CONFIG/ntfy-topic"
set +e; FM_NTFY_HOST="http://slash.example:7/" run "trailing slash"; rc=$?; set -e
got=$(cat "$CURL_LOG")
assert_contains "$got" "http://slash.example:7/firstmate" "single slash between host and topic"
assert_not_contains "$got" "slash.example:7//firstmate" "no doubled slash"
pass "trailing slash on host is tolerated"

# 6. Defaults: no flags -> Title 'firstmate', Priority 3.
set +e; FM_NTFY_HOST="http://def.example:80" run "defaults"; rc=$?; set -e
got=$(cat "$CURL_LOG")
assert_contains "$got" "Title: firstmate" "default heading is firstmate"
assert_contains "$got" "Priority: 3" "default priority is 3"
pass "default heading and priority"

# 7. Empty message is a usage error (exit 2), even when configured.
set +e; FM_NTFY_HOST="http://x.example:1" run; rc=$?; set -e
expect_code 2 "$rc" "empty message is a usage error"
pass "empty message refused with exit 2"

echo "# fm-ntfy: all assertions passed"
