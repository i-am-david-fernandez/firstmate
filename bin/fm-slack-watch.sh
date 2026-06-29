#!/usr/bin/env bash
# Watch the captain's Slack attention channel for a new human reply.
# Blocks (sleeping FM_SLACK_POLL seconds between polls, zero tokens while idle)
# until a new non-bot message arrives, prints it, advances the seen marker, and
# exits 0 - which re-invokes the firstmate session. Re-launch it after handling
# to keep watching, exactly like the crew watcher's arm chain.
#
# Output on a hit (oldest-first):
#   SLACK_NEW:
#   <ts>\t<<user>> <text>
#
# Marker: state/.slack-last-ts. On first run with no marker, it seeds from the
# current latest ts so only genuinely new replies wake firstmate.
# Usage: fm-slack-watch.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-slack-lib.sh
. "$SCRIPT_DIR/fm-slack-lib.sh"

fm_slack_require || exit 1

INTERVAL="${FM_SLACK_POLL:-45}"
MARKER="${FM_SLACK_MARKER:-$STATE/.slack-last-ts}"
mkdir -p "$STATE"

if [ ! -f "$MARKER" ]; then
  fm_slack_latest_ts > "$MARKER"
fi
LAST=$(cat "$MARKER")

while true; do
  NEW=$(fm_slack_new_since "$LAST")
  if [ -n "$NEW" ]; then
    echo "SLACK_NEW:"
    echo "$NEW"
    echo "$NEW" | tail -1 | cut -f1 > "$MARKER"
    exit 0
  fi
  sleep "$INTERVAL"
done
