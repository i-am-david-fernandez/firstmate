#!/usr/bin/env bash
# Post one message to the captain's configured Slack attention channel.
# Use this to mirror an attention-needing event (a needed decision, a blocker,
# or completion of a long task) to Slack in addition to the chat interface.
# Routine chatter does NOT belong here; the channel is for getting the captain.
# Usage: fm-slack-notify.sh "<message>"
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-slack-lib.sh
. "$SCRIPT_DIR/fm-slack-lib.sh"

[ "$#" -ge 1 ] || { echo "usage: fm-slack-notify.sh \"<message>\"" >&2; exit 2; }

fm_slack_require
fm_slack_post "$*"
