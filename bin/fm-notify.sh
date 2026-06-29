#!/usr/bin/env bash
# Fan one attention message out to every configured notification provider.
# This is the single command firstmate calls to mirror an attention-needing
# event (a needed decision, a blocker, or completion of a long task) to its
# external notification tools, in addition to the chat interface. Each provider
# self-skips when unconfigured, so this is safe to call unconditionally: an
# unconfigured fleet sends nothing and sees no behavior change. Routine chatter
# does NOT belong here.
#
# Usage: fm-notify.sh [-p PRIORITY] [-h HEADING] [-t TAGS] "<message>"
#
# To integrate a new notification tool: write bin/fm-<tool>-notify.sh to the
# provider contract (see fm-notify-lib.sh) and add its short name to PROVIDERS.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-notify-lib.sh
. "$SCRIPT_DIR/fm-notify-lib.sh"

# Registered providers, each implemented by bin/fm-<name>-notify.sh.
PROVIDERS="slack ntfy"

# Validate the shared CLI once, up front (each provider re-parses its own args).
fm_notify_parse_args "$@" || exit 2

rc=0
for p in $PROVIDERS; do
  prov="$SCRIPT_DIR/fm-$p-notify.sh"
  [ -x "$prov" ] || continue
  # Providers are best-effort and self-skip when unconfigured; a non-zero here
  # is an unexpected provider error, surfaced but not fatal to the fan-out.
  "$prov" -p "$FM_N_PRIORITY" -h "$FM_N_HEADING" -t "$FM_N_TAGS" "$FM_N_MESSAGE" || {
    rc=$?
    echo "fm-notify: provider '$p' exited $rc" >&2
  }
done
exit "$rc"
