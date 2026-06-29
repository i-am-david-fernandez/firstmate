#!/usr/bin/env bash
# Shared Slack helpers: post to and read from the captain's attention channel.
# Sourced by fm-slack-notify.sh and fm-slack-watch.sh; usable standalone in tests.
#
# Configuration (all LOCAL, never the shared template's business):
#   SLACK_API_KEY        bot token (xoxb-...); required, taken from the environment
#   FM_SLACK_CHANNEL     channel id override; else read from config/slack-channel
#   config/slack-channel local, gitignored file holding one channel id (first
#                        non-blank, non-comment line)
# The token is a secret and is read only from the environment, never a tracked file.

FM_SLACK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$(cd "$FM_SLACK_LIB_DIR/.." && pwd)}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-${STATE:-$FM_HOME/state}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"

SLACK_TOKEN="${SLACK_API_KEY:-}"
FM_SLACK_API="${FM_SLACK_API:-https://slack.com/api}"

# Resolve the channel: explicit override wins, else the local config file.
fm_slack_channel() {
  if [ -n "${FM_SLACK_CHANNEL:-}" ]; then
    printf '%s\n' "$FM_SLACK_CHANNEL"
    return 0
  fi
  local f="$CONFIG/slack-channel"
  [ -f "$f" ] || return 1
  grep -vE '^[[:space:]]*(#|$)' "$f" | head -1 | tr -d '[:space:]'
}

# Fail fast unless token, channel, and required tools are all present.
fm_slack_require() {
  local missing=
  command -v curl >/dev/null 2>&1 || missing="$missing curl"
  command -v jq >/dev/null 2>&1 || missing="$missing jq"
  [ -n "$missing" ] && { echo "error: missing required tools:$missing" >&2; return 1; }
  [ -n "$SLACK_TOKEN" ] || { echo "error: SLACK_API_KEY is not set in the environment" >&2; return 1; }
  FM_SLACK_CH=$(fm_slack_channel) || true
  [ -n "${FM_SLACK_CH:-}" ] || { echo "error: no Slack channel configured (set FM_SLACK_CHANNEL or $CONFIG/slack-channel)" >&2; return 1; }
  return 0
}

# Post a message to the configured channel. Args: the message text.
# Prints "ts=<ts>" on success; prints the Slack error to stderr and returns 1 otherwise.
fm_slack_post() {
  local text="$*"
  [ -n "$text" ] || { echo "error: refusing to post an empty message" >&2; return 1; }
  local payload
  payload=$(jq -nc --arg ch "$FM_SLACK_CH" --arg t "$text" '{channel:$ch, text:$t}')
  local resp
  resp=$(curl -s -X POST \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-type: application/json; charset=utf-8" \
    --data "$payload" "$FM_SLACK_API/chat.postMessage")
  if [ "$(echo "$resp" | jq -r '.ok')" = "true" ]; then
    echo "ts=$(echo "$resp" | jq -r '.ts')"
    return 0
  fi
  echo "error: slack post failed: $(echo "$resp" | jq -r '.error // "unknown"')" >&2
  return 1
}

# Print the ts of the latest message in the channel, or 0 if none.
fm_slack_latest_ts() {
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    "$FM_SLACK_API/conversations.history?channel=$FM_SLACK_CH&limit=1" \
    | jq -r '.messages[0].ts // "0"'
}

# Print real human messages strictly newer than the given ts, oldest-first,
# one per line as "<ts>\t<<user>> <text>". Skips bot messages and join/leave
# and other subtype events. No output means nothing new.
fm_slack_new_since() {
  local last="$1"
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    "$FM_SLACK_API/conversations.history?channel=$FM_SLACK_CH&oldest=$last&limit=50" \
    | jq -r --arg last "$last" '
      [ .messages[]?
        | select(.subtype == null)
        | select(.bot_id == null)
        | select((.ts|tonumber) > ($last|tonumber)) ]
      | sort_by(.ts|tonumber)
      | .[] | "\(.ts)\t<\(.user)> \(.text)"'
}
