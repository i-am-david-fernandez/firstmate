#!/usr/bin/env bash
# Local, offline secret scan run before any commit / push / PR / local-only merge
# / handoff - for project work and firstmate self-improvement alike. The point is
# to catch credentials *before* they leave the machine (see AGENTS.md hard rule
# HR4 and CONTRIBUTING.md).
#
# It wraps `betterleaks` (a pure-local scanner; no network egress) and always
# runs redacted, so the scanner itself never echoes a raw secret. When
# `betterleaks` is not on PATH it degrades to a built-in high-signal prefix grep
# and warns loudly - it never silently passes.
#
# Usage:
#   fm-secret-scan.sh                 # scan the working tree of the cwd repo
#   fm-secret-scan.sh --staged        # scan only staged changes (pre-commit gate)
#   fm-secret-scan.sh <path>          # scan an arbitrary dir (a worktree / clone)
#   fm-secret-scan.sh --since <ref>   # scan the diff from <ref>..HEAD (branch review)
#   fm-secret-scan.sh --help
#
# Exit codes: 0 = clean; 1 = findings (block the caller); 2 = usage/internal error.
#
# Env knobs (see docs/configuration.md):
#   FM_ENABLE_SECRET_SCAN  master on/off switch (default: on); off|false|no|0 disable the gate
#   FM_SECRET_SCAN_BIN     override the scanner binary (default: betterleaks on PATH)
#   FM_SECRET_SCAN_CONFIG  override the config file (default: <repo-root>/.betterleaks.toml)
#   FM_SECRET_SCAN_STRICT  1 = treat "binary absent" as a hard failure (default: degrade+warn)
set -eu

usage() {
  sed -n '12,17p' "$0" | sed 's/^# \{0,1\}//'
}

# --help works regardless of the master switch.
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac

# Master switch (the single chokepoint; callers do not re-check). Default ENABLED
# (fail-safe): only an explicit off|false|no|0 disables the gate. When disabled,
# print one notice so the off state is visible, and exit 0 BEFORE any binary
# resolution, config, or degraded-mode logic - never a silent skip.
case "$(printf '%s' "${FM_ENABLE_SECRET_SCAN:-}" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off)
    echo "secret scan: disabled via FM_ENABLE_SECRET_SCAN" >&2
    exit 0
    ;;
esac

MODE=tree   # tree | staged | path | since
TARGET=""   # path for `path` mode
REF=""      # ref for `since` mode

case "${1:-}" in
  --staged)
    MODE=staged
    [ $# -eq 1 ] || { echo "error: --staged takes no further arguments" >&2; exit 2; }
    ;;
  --since)
    MODE=since
    REF=${2:-}
    [ -n "$REF" ] || { echo "error: --since requires a <ref>" >&2; exit 2; }
    [ $# -eq 2 ] || { echo "error: --since takes exactly one <ref>" >&2; exit 2; }
    ;;
  -*)
    echo "error: unknown option '$1'" >&2
    usage >&2
    exit 2
    ;;
  '')
    MODE=tree
    ;;
  *)
    MODE=path
    TARGET=$1
    [ $# -eq 1 ] || { echo "error: only one <path> may be given" >&2; exit 2; }
    [ -d "$TARGET" ] || { echo "error: not a directory: $TARGET" >&2; exit 2; }
    ;;
esac

# Resolve the repo root of the scan target, used to locate the config file and to
# anchor git-based scans. Falls back to the raw target / cwd when not in a repo.
case "$MODE" in
  path) SCAN_DIR=$TARGET ;;
  *)    SCAN_DIR=. ;;
esac
ROOT=$(git -C "$SCAN_DIR" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || ROOT=$(cd "$SCAN_DIR" && pwd)

# High-signal credential prefixes for degraded mode and for documentation. These
# are deliberately credential-shaped (tokens/keys), not low-entropy identifiers -
# the latter are covered by the fake-placeholders / hermetic-tests hard rules.
PATTERN='xoxb-|xoxp-|sk-ant-|sk-[A-Za-z0-9]{20,}|github_pat_|ghp_|gho_|ghs_|ATATT|sntryu_|NRAK-|bkua_|AIza[0-9A-Za-z_-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PGP|PRIVATE) '
# Inline allow markers honored in degraded mode (betterleaks honors them itself).
ALLOW='gitleaks:allow|betterleaks:allow'

# --- config resolution ------------------------------------------------------
CONFIG_ARGS=()
if [ -n "${FM_SECRET_SCAN_CONFIG:-}" ]; then
  [ -f "$FM_SECRET_SCAN_CONFIG" ] || { echo "error: FM_SECRET_SCAN_CONFIG set but not a file: $FM_SECRET_SCAN_CONFIG" >&2; exit 2; }
  CONFIG_ARGS=(--config "$FM_SECRET_SCAN_CONFIG")
elif [ -f "$ROOT/.betterleaks.toml" ]; then
  CONFIG_ARGS=(--config "$ROOT/.betterleaks.toml")
elif [ -f "$ROOT/.gitleaks.toml" ]; then
  CONFIG_ARGS=(--config "$ROOT/.gitleaks.toml")
fi

# --- degraded fallback ------------------------------------------------------
# Built-in prefix grep. Never prints raw matched content (only file:line or a
# redacted count), so the fallback itself cannot become a leak vector.
degraded_scan() {
  echo "DEGRADED: betterleaks not on PATH; ran built-in prefix scan only" >&2
  local hits=0
  case "$MODE" in
    path|tree)
      local line file lineno rest
      while IFS= read -r line; do
        case "$line" in
          *gitleaks:allow*|*betterleaks:allow*) continue ;;
        esac
        file=${line%%:*}
        rest=${line#*:}
        lineno=${rest%%:*}
        echo "DEGRADED finding: $file:$lineno" >&2
        hits=$((hits + 1))
      done < <(grep -rnIE --exclude-dir=.git -- "$PATTERN" "$ROOT" 2>/dev/null || true)
      ;;
    staged|since)
      local blob n
      if [ "$MODE" = staged ]; then
        blob=$(git -C "$ROOT" diff --cached -U0 2>/dev/null || true)
      else
        blob=$(git -C "$ROOT" diff -U0 "$REF..HEAD" 2>/dev/null || true)
      fi
      n=$(printf '%s\n' "$blob" | grep -vE -- "$ALLOW" | grep -cE -- "$PATTERN" || true)
      if [ "$n" -gt 0 ]; then
        echo "DEGRADED finding: $n match(es) in ${MODE} diff (redacted)" >&2
        hits=$n
      fi
      ;;
  esac
  if [ "$hits" -gt 0 ]; then
    echo "secret scan: FINDINGS (degraded mode) - blocking" >&2
    return 1
  fi
  echo "secret scan: clean (degraded mode)" >&2
  return 0
}

# --- full scan via betterleaks ----------------------------------------------
BIN=${FM_SECRET_SCAN_BIN:-betterleaks}
if ! command -v "$BIN" >/dev/null 2>&1; then
  if [ "${FM_SECRET_SCAN_STRICT:-}" = 1 ]; then
    echo "error: secret scanner '$BIN' not on PATH and FM_SECRET_SCAN_STRICT=1" >&2
    exit 2
  fi
  rc=0
  degraded_scan || rc=$?
  exit "$rc"
fi

COMMON=(--no-banner --redact --exit-code 1 "${CONFIG_ARGS[@]}")
rc=0
case "$MODE" in
  staged) "$BIN" git --staged "${COMMON[@]}" "$ROOT" || rc=$? ;;
  since)  "$BIN" git --log-opts="$REF..HEAD" "${COMMON[@]}" "$ROOT" || rc=$? ;;
  path)   "$BIN" dir "$TARGET" "${COMMON[@]}" || rc=$? ;;
  tree)   "$BIN" dir "$ROOT" "${COMMON[@]}" || rc=$? ;;
esac

case "$rc" in
  0) echo "secret scan: clean" >&2; exit 0 ;;
  1) echo "secret scan: FINDINGS - blocking (output redacted above)" >&2; exit 1 ;;
  *) echo "error: secret scanner '$BIN' exited $rc (internal error)" >&2; exit 2 ;;
esac
