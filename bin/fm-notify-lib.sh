#!/usr/bin/env bash
# Shared helpers for firstmate's notification providers - the common surface
# every external notification tool integrates through. See AGENTS.md (attention
# mirrors) and docs/configuration.md ("Notification providers").
#
# THE PROVIDER CONTRACT. A provider is bin/fm-<tool>-notify.sh and:
#   - takes the uniform CLI:  [-p PRIORITY] [-h HEADING] [-t TAGS] "<message>"
#     (parse it with fm_notify_parse_args, which fills FM_N_PRIORITY/FM_N_HEADING/
#      FM_N_TAGS/FM_N_MESSAGE);
#   - resolves its own config with fm_notify_resolve (environment wins, else a
#     local, gitignored file);
#   - is a SILENT NO-OP (exit 0, with one stderr notice) when it is not
#     configured or a required tool is absent - never an error;
#   - exits 2 only on a usage error (unknown flag, missing flag value, empty
#     message);
#   - maps PRIORITY/HEADING/TAGS onto the underlying tool as far as that tool
#     allows (some tools have no native priority/tags - fold them into the text).
# Register a new provider by adding its short name to PROVIDERS in bin/fm-notify.sh,
# the fan-out dispatcher.
#
# This library is sourced (by the providers, the dispatcher, and tests) and is
# safe to source more than once.
[ -n "${FM_NOTIFY_LIB_LOADED:-}" ] && return 0
FM_NOTIFY_LIB_LOADED=1

# Resolve a config value: the environment value ($1) wins; else the first
# non-blank, non-comment line of the file ($2). Prints empty when neither is
# set. Always returns 0 (callers test the printed value for emptiness).
fm_notify_resolve() {  # fm_notify_resolve <env-value> <config-file>
  if [ -n "${1:-}" ]; then printf '%s\n' "$1"; return 0; fi
  [ -f "${2:-}" ] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$2" | head -1 | tr -d '[:space:]'
}

# Parse the uniform provider CLI into FM_N_PRIORITY / FM_N_HEADING / FM_N_TAGS /
# FM_N_MESSAGE. Defaults: priority 3, heading "firstmate", tags empty. Returns 2
# (and prints a usage line) on an unknown flag, a missing flag value, or an empty
# message; the caller should `exit 2`. Returns (does not exit) so it stays
# testable when the library is sourced.
# FM_N_* are consumed by the sourcing provider/dispatcher, not within this file.
# shellcheck disable=SC2034
fm_notify_parse_args() {
  FM_N_PRIORITY=3
  FM_N_HEADING=firstmate
  FM_N_TAGS=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -p) [ "$#" -ge 2 ] || { echo "error: -p needs a value" >&2; return 2; }; FM_N_PRIORITY=$2; shift 2 ;;
      -h) [ "$#" -ge 2 ] || { echo "error: -h needs a value" >&2; return 2; }; FM_N_HEADING=$2; shift 2 ;;
      -t) [ "$#" -ge 2 ] || { echo "error: -t needs a value" >&2; return 2; }; FM_N_TAGS=$2;     shift 2 ;;
      --) shift; break ;;
      -*) echo "error: unknown option '$1'" >&2; return 2 ;;
      *)  break ;;
    esac
  done
  FM_N_MESSAGE="$*"
  [ -n "$FM_N_MESSAGE" ] || {
    echo "usage: $(basename "${0:-fm-<tool>-notify.sh}") [-p PRIORITY] [-h HEADING] [-t TAGS] \"<message>\"" >&2
    return 2
  }
  return 0
}
