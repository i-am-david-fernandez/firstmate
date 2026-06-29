#!/usr/bin/env bash
# Slack notification provider (see the provider contract in fm-notify-lib.sh).
# Posts one attention message to the captain's Slack attention channel.
#
# Uniform CLI: [-p PRIORITY] [-h HEADING] [-t TAGS] "<message>". Slack's
# chat.postMessage has no native priority or tags, so HEADING is prefixed to the
# text and PRIORITY/TAGS are accepted (for a uniform surface across providers)
# but not rendered. Configure with SLACK_API_KEY (environment, secret) plus
# FM_SLACK_CHANNEL or config/slack-channel.
#
# SILENT NO-OP (exit 0) when Slack is not configured (no token or channel) or
# curl/jq are absent - never an error. Exits 2 only on a usage error. (The
# watcher, fm-slack-watch.sh, keeps the fail-fast fm_slack_require instead,
# because watching for replies is an explicit, must-be-configured action.)
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-notify-lib.sh
. "$SCRIPT_DIR/fm-notify-lib.sh"
# shellcheck source=bin/fm-slack-lib.sh
. "$SCRIPT_DIR/fm-slack-lib.sh"

fm_notify_parse_args "$@" || exit 2

# Not configured -> silent no-op (uniform provider behavior).
if ! fm_slack_configured; then
  echo "fm-slack-notify: Slack not configured; skipping (no-op)" >&2
  exit 0
fi
# Required tools absent -> skip rather than fail.
if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  echo "fm-slack-notify: curl/jq not found; skipping (no-op)" >&2
  exit 0
fi

# Slack has no native priority/tags: fold a non-default heading into the text.
text="$FM_N_MESSAGE"
[ "$FM_N_HEADING" = firstmate ] || text="*${FM_N_HEADING}*: ${text}"

FM_SLACK_CH=$(fm_slack_channel)
fm_slack_post "$text"
