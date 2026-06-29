#!/usr/bin/env bash
# Behavior tests for the Slack attention module (fm-slack-lib.sh and CLIs).
# Fakes `curl` so nothing touches the network; jq runs for real.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot fm-slack)
FAKEBIN=$(fm_fakebin "$TMP")
PATH="$FAKEBIN:$PATH"

# Canned channel history: newest-first, mixing a human reply, our bot's own
# message, and a channel_join subtype event. ts values straddle the marker.
cat > "$TMP/history.json" <<'JSON'
{"ok":true,"messages":[
  {"type":"message","ts":"300.0","user":"UHUMAN","text":"second human reply"},
  {"type":"message","ts":"250.0","bot_id":"B1","user":"UBOT","text":"bot noise"},
  {"type":"message","ts":"200.0","user":"UHUMAN","text":"first human reply"},
  {"type":"message","subtype":"channel_join","ts":"150.0","user":"UHUMAN","text":"joined"},
  {"type":"message","ts":"100.0","user":"UHUMAN","text":"old reply"}
]}
JSON

# Fake curl: history GET -> canned file; chat.postMessage -> echo args + ok.
cat > "$FAKEBIN/curl" <<SH
#!/usr/bin/env bash
args="\$*"
case "\$args" in
  *conversations.history*limit=1*) echo '{"ok":true,"messages":[{"ts":"300.0"}]}' ;;
  *conversations.history*) cat "$TMP/history.json" ;;
  *chat.postMessage*)
    # capture the JSON payload for assertion
    payload=""; while [ "\$#" -gt 0 ]; do [ "\$1" = "--data" ] && { payload="\$2"; }; shift; done
    printf '%s' "\$payload" > "$TMP/last-post.json"
    echo '{"ok":true,"ts":"999.9"}' ;;
  *) echo '{"ok":false,"error":"unexpected"}' ;;
esac
SH
chmod +x "$FAKEBIN/curl"

# Hermetic env: ignore any ambient Slack config from the captain's real shell,
# so the test neither breaks in a configured environment nor echoes a real
# channel id into failure output / CI logs.
unset FM_SLACK_CHANNEL FM_SLACK_POLL FM_SLACK_MARKER
export SLACK_API_KEY="xoxb-test"
export FM_CONFIG_OVERRIDE="$TMP/config"
mkdir -p "$FM_CONFIG_OVERRIDE"

# shellcheck source=bin/fm-slack-lib.sh
. "$ROOT/bin/fm-slack-lib.sh"

# 1. channel resolves from the config file
printf '# comment\n\nCEXAMPLE001\n' > "$FM_CONFIG_OVERRIDE/slack-channel"
got=$(fm_slack_channel)
[ "$got" = "CEXAMPLE001" ] || fail "channel from config file (got '$got')"
pass "channel resolves from config file, skipping comments/blanks"

# 2. FM_SLACK_CHANNEL env overrides the file
got=$(FM_SLACK_CHANNEL=COVERRIDE fm_slack_channel)
[ "$got" = "COVERRIDE" ] || fail "FM_SLACK_CHANNEL override (got '$got')"
pass "FM_SLACK_CHANNEL overrides the config file"

# 3. require passes with token + channel present
fm_slack_require || fail "fm_slack_require should pass with token and channel"
pass "fm_slack_require passes when token and channel present"

# 4. new_since filters bots + subtypes, keeps only strictly-newer humans, oldest-first
out=$(fm_slack_new_since "150.0")
assert_contains "$out" "first human reply" "keeps human msg newer than marker"
assert_contains "$out" "second human reply" "keeps later human msg"
assert_not_contains "$out" "bot noise" "drops bot message"
assert_not_contains "$out" "joined" "drops channel_join subtype"
assert_not_contains "$out" "old reply" "drops msg at/under marker"
first=$(echo "$out" | head -1)
assert_contains "$first" "200.0" "output is oldest-first"
pass "new_since filters bots/subtypes/old and sorts oldest-first"

# 5. nothing newer than the latest -> empty
out=$(fm_slack_new_since "300.0")
[ -z "$out" ] || fail "new_since should be empty when nothing is newer (got '$out')"
pass "new_since is empty when no newer messages"

# 6. post builds correct payload and reports ts
res=$(fm_slack_require && fm_slack_post "hello there")
[ "$res" = "ts=999.9" ] || fail "post should report ts (got '$res')"
assert_grep '"channel":"CEXAMPLE001"' "$TMP/last-post.json" "post payload carries channel"
assert_grep '"text":"hello there"' "$TMP/last-post.json" "post payload carries text"
pass "post sends channel+text and reports ts"

# 7. empty message is refused
if fm_slack_post "" 2>/dev/null; then fail "empty post should be refused"; fi
pass "post refuses an empty message"

echo "# fm-slack: all assertions passed"
