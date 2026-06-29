#!/usr/bin/env bash
# Behavior tests for the notification-provider pattern: fm-notify-lib.sh (shared
# config resolve + uniform arg parse) and fm-notify.sh (the fan-out dispatcher).
# Fakes curl so nothing touches the network; all hosts/tokens/channels are
# obviously-fake placeholders (HR2), and ambient provider config is unset (HR3).
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Hermetic (HR3): drop any provider config the captain's shell may export.
unset SLACK_API_KEY FM_SLACK_CHANNEL FM_NTFY_HOST FM_NTFY_TOPIC

TMP=$(fm_test_tmproot fm-notify)
FAKEBIN=$(fm_fakebin "$TMP")
CURL_LOG="$TMP/curl.log"
CONFIG="$TMP/config"; mkdir -p "$CONFIG"

# --- fm-notify-lib.sh: shared resolve + parse (sourced) ---------------------
# shellcheck source=bin/fm-notify-lib.sh
. "$ROOT/bin/fm-notify-lib.sh"

got=$(fm_notify_resolve "envval" "$CONFIG/none"); [ "$got" = envval ] || fail "resolve: env wins (got '$got')"
printf '# comment\n\nfileval\n' > "$CONFIG/r"
got=$(fm_notify_resolve "" "$CONFIG/r"); [ "$got" = fileval ] || fail "resolve: file fallback (got '$got')"
got=$(fm_notify_resolve "" "$CONFIG/missing"); [ -z "$got" ] || fail "resolve: empty when neither (got '$got')"
pass "fm_notify_resolve: env wins, file fallback (comments/blanks skipped), else empty"

fm_notify_parse_args "hello world"
{ [ "$FM_N_PRIORITY" = 3 ] && [ "$FM_N_HEADING" = firstmate ] && [ -z "$FM_N_TAGS" ] && [ "$FM_N_MESSAGE" = "hello world" ]; } || fail "parse defaults"
pass "fm_notify_parse_args: defaults (priority 3, heading firstmate, no tags)"

fm_notify_parse_args -p 5 -h "Title X" -t "a,b" -- "the msg"
{ [ "$FM_N_PRIORITY" = 5 ] && [ "$FM_N_HEADING" = "Title X" ] && [ "$FM_N_TAGS" = "a,b" ] && [ "$FM_N_MESSAGE" = "the msg" ]; } || fail "parse flags"
pass "fm_notify_parse_args: maps -p/-h/-t and honors the -- terminator"

set +e; fm_notify_parse_args -z x 2>/dev/null; rc=$?; set -e; expect_code 2 "$rc" "unknown flag -> 2"
set +e; fm_notify_parse_args 2>/dev/null;       rc=$?; set -e; expect_code 2 "$rc" "empty message -> 2"
set +e; fm_notify_parse_args -p 2>/dev/null;    rc=$?; set -e; expect_code 2 "$rc" "missing flag value -> 2"
pass "fm_notify_parse_args: usage errors (unknown flag, empty message, missing value) return 2"

# --- fm-notify.sh dispatcher fan-out ----------------------------------------
# Fake curl: record argv; answer Slack's chat.postMessage with an ok payload,
# swallow everything else (ntfy discards output).
cat > "$FAKEBIN/curl" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CURL_LOG"
case "\$*" in
  *chat.postMessage*) echo '{"ok":true,"ts":"1.1"}' ;;
  *) : ;;
esac
SH
chmod +x "$FAKEBIN/curl"

# Each provider runs as a subprocess whose non-interactive bash re-sources
# BASH_ENV (~/.bash_env sources ~/.secrets.env etc.), which would re-inject the
# operator's REAL Slack/ntfy config and defeat the unset above - leaking real
# values into the test (HR3). So every child runs with BASH_ENV neutralized and
# the provider vars explicitly cleared; each case re-sets only its fake config.
HERMETIC=(env BASH_ENV=/dev/null
  SLACK_API_KEY= FM_SLACK_CHANNEL= FM_NTFY_HOST= FM_NTFY_TOPIC=
  FM_SLACK_API="http://slack.example/api" FM_CONFIG_OVERRIDE="$CONFIG" PATH="$FAKEBIN:$PATH")

# 1. Nothing configured -> dispatcher is a no-op (exit 0, no provider posts).
: > "$CURL_LOG"
set +e
"${HERMETIC[@]}" "$ROOT/bin/fm-notify.sh" -h "x" "all quiet"; rc=$?
set -e
expect_code 0 "$rc" "dispatcher exits 0 with no providers configured"
[ ! -s "$CURL_LOG" ] || fail "no provider may post when unconfigured"
pass "dispatcher: no-op (exit 0, no curl) when no provider is configured"

# 2. Only ntfy configured -> only ntfy fires; Slack self-skips.
: > "$CURL_LOG"
"${HERMETIC[@]}" FM_NTFY_HOST="http://ntfy.example:8080" \
  "$ROOT/bin/fm-notify.sh" -p 4 -h "Build broke" -t "warning" "the build is red"
got=$(cat "$CURL_LOG")
assert_contains "$got" "http://ntfy.example:8080/firstmate" "ntfy provider fired"
assert_not_contains "$got" "chat.postMessage" "Slack provider skipped (unconfigured)"
pass "dispatcher: fans out only to the configured provider (ntfy)"

# 3. Both configured -> both fire.
: > "$CURL_LOG"
"${HERMETIC[@]}" SLACK_API_KEY="xoxb-test" FM_SLACK_CHANNEL="CEXAMPLE001" FM_NTFY_HOST="http://ntfy.example:8080" \
  "$ROOT/bin/fm-notify.sh" -h "Heads up" "both fire"
got=$(cat "$CURL_LOG")
assert_contains "$got" "chat.postMessage" "Slack provider fired"
assert_contains "$got" "http://ntfy.example:8080/firstmate" "ntfy provider fired"
pass "dispatcher: fans out to all configured providers (Slack + ntfy)"

# 4. Empty message is a usage error (exit 2).
set +e; "${HERMETIC[@]}" "$ROOT/bin/fm-notify.sh" 2>/dev/null; rc=$?; set -e
expect_code 2 "$rc" "dispatcher empty message -> exit 2"
pass "dispatcher: empty message is a usage error (exit 2)"

echo "# fm-notify: all assertions passed"
