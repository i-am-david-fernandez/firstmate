#!/usr/bin/env bash
# Resolve the crewmate branch name for a task id, the single source of truth for
# branch naming across fm-brief, fm-merge-local, fm-review-diff, and fm-promote.
#
# Honors the optional FM_BRANCH_PREFIX environment variable: when set and
# non-empty, the branch is <FM_BRANCH_PREFIX>/fm/<id> (e.g. FM_BRANCH_PREFIX=foo
# yields foo/fm/fix-login-k3); when unset or empty, the legacy fm/<id> form is
# used so default behavior is unchanged. These helpers run in firstmate's own
# session, so the variable is resolved from firstmate's environment - export it in
# the firstmate launch profile to make it persistent across restarts.
# Usage: fm-branch.sh <task-id>
set -u

ID=${1:?usage: fm-branch.sh <task-id>}

PREFIX="${FM_BRANCH_PREFIX:-}"
if [ -n "$PREFIX" ]; then
  echo "$PREFIX/fm/$ID"
else
  echo "fm/$ID"
fi
