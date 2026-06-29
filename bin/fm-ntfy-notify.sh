#!/usr/bin/env bash
# ntfy notification provider (see the provider contract in fm-notify-lib.sh).
# Pushes one attention message to the captain's optional ntfy server via ntfy's
# HTTP API: Title/Priority/Tags headers and a timestamped body.
#
# Uniform CLI: [-p PRIORITY] [-h HEADING] [-t TAGS] "<message>" - ntfy maps all
# three onto its native Title/Priority/Tags.
#
# Configuration (environment wins, else a local, gitignored file):
#   FM_NTFY_HOST   full base URL, e.g. http://hostname:port (else config/ntfy-host)
#   FM_NTFY_TOPIC  ntfy topic           (else config/ntfy-topic; default: firstmate)
# The push carries no credentials (matching a tokenless ntfy server).
#
# SILENT NO-OP (exit 0) when no host is configured or when curl is absent -
# never an error. Exits 2 only on a usage error.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-${FM_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
# shellcheck source=bin/fm-notify-lib.sh
. "$SCRIPT_DIR/fm-notify-lib.sh"

fm_notify_parse_args "$@" || exit 2

HOST=$(fm_notify_resolve "${FM_NTFY_HOST:-}" "$CONFIG/ntfy-host")
HOST=${HOST%/}   # tolerate a trailing slash in the configured base URL
TOPIC=$(fm_notify_resolve "${FM_NTFY_TOPIC:-}" "$CONFIG/ntfy-topic")
[ -n "$TOPIC" ] || TOPIC=firstmate

# No host configured -> silent no-op: ntfy is optional and off by default.
[ -n "$HOST" ] || { echo "fm-ntfy-notify: FM_NTFY_HOST not configured; skipping (no-op)" >&2; exit 0; }
# curl absent -> cannot push; skip rather than fail the caller.
command -v curl >/dev/null 2>&1 || { echo "fm-ntfy-notify: curl not found; skipping (no-op)" >&2; exit 0; }

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -s \
  -H "Title: $FM_N_HEADING" \
  -H "Priority: $FM_N_PRIORITY" \
  -H "Tags: $FM_N_TAGS" \
  -d "$TS: $FM_N_MESSAGE" \
  "$HOST/$TOPIC" >/dev/null 2>&1 || true
