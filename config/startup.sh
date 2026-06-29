# config/startup.sh - fleet startup/auth hook (LOCAL, gitignored skeleton).
#
# Put this file at <firstmate-home>/config/startup.sh. It is the single, harness-
# agnostic seam where the captain's fleet-wide startup and authentication steps run.
#
# WHERE IT RUNS (it is SOURCED, not executed, so any env it exports persists):
#   - bin/fm-bootstrap.sh sources it into the firstmate session at every session
#     start, before the auth checks - so a token login it performs here suppresses
#     a false NEEDS_GH_AUTH.
#   - bin/fm-spawn.sh sources it into every ship/scout crewmate pane right before
#     the agent launches - crewmates are not firstmate instances and never run
#     bootstrap, so this is their only startup seam.
#   - Secondmates are firstmate instances in their own homes: each runs its own
#     bootstrap, which sources THAT home's own config/startup.sh. So a secondmate
#     gets its home's copy, not the main home's - keep per-home copies in sync if
#     you want identical fleet auth everywhere.
#
# CONTRACT (read before editing):
#   - POSIX sh ONLY. It is sourced under /bin/sh (crewmate panes) and bash
#     (bootstrap). No bashisms (no [[ ]], no arrays, no `local` outside functions).
#   - Must be FAST, NON-INTERACTIVE, and IDEMPOTENT. It runs on every session
#     start and every spawn; a slow or blocking step stalls the whole fleet.
#   - NEVER call `exit`. That would kill bootstrap or the crewmate pane. Use
#     `return` to bail early instead.
#   - OAuth/device-code logins (`gh auth login`, `acli auth login` interactive)
#     CANNOT run here - they need a human. Do TOKEN-BASED, non-interactive auth
#     only; perform the one-time interactive login by hand.
#   - Keep secrets OUT of git. This file is gitignored, but still read tokens from
#     env vars or files OUTSIDE the repo (e.g. ~/.config/fleet/), never inline.
#
# ---------------------------------------------------------------------------
# EXAMPLES (commented out - uncomment/adapt the ones you need):
#
# # GitHub: non-interactive re-auth from a token file, only if not already authed.
# if ! gh auth status >/dev/null 2>&1; then
#   if [ -r "$HOME/.config/fleet/gh-token" ]; then
#     gh auth login --with-token < "$HOME/.config/fleet/gh-token" >/dev/null 2>&1 || true
#   fi
# fi
#
# # Some tools read a token straight from the environment - just export it.
# if [ -r "$HOME/.config/fleet/gh-token" ]; then
#   GH_TOKEN=$(cat "$HOME/.config/fleet/gh-token")
#   export GH_TOKEN
# fi
#
# # Atlassian acli (Jira): API-token auth is scriptable; interactive OAuth is not.
# # Check acli's own flags for the exact non-interactive form your version supports.
# # if ! acli jira auth status >/dev/null 2>&1; then
# #   ATLASSIAN_API_TOKEN=$(cat "$HOME/.config/fleet/acli-token" 2>/dev/null) || true
# #   export ATLASSIAN_API_TOKEN
# #   # acli jira auth login --email "you@example.com" --token "$ATLASSIAN_API_TOKEN" >/dev/null 2>&1 || true
# # fi
#
# # Generic env exports for the fleet (PATH additions, region, etc.).
# # export AWS_REGION=ap-southeast-2
# ---------------------------------------------------------------------------

# Add your fleet startup/auth steps above this line.
# The trailing no-op keeps an all-commented file a valid sourced script.
:
