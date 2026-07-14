---
name: difit-review
description: Agent-only procedure for presenting code to the captain for review with difit - a local, deterministic, GitHub-style git-diff viewer. Use whenever showing the captain a diff to review, partial (a code option best seen in-situ, a proposed change) or complete (a finished branch before it is pushed / merged). difit renders the actual git diff (no LLM in the content path), unlike a hand-built Lavish artifact; prefer it for any real code-diff review.
user-invocable: false
---

# difit-review

Present code to the captain for review as a real, browser-viewable git diff via `difit`.

## Why difit (and when NOT Lavish)

difit spins up a local web server that renders the **actual `git diff`** in a GitHub-style Files-changed view, with per-line commenting. The diff bytes come from git, not from an LLM, so the representation is **deterministic and faithful** - the captain's stated reason for preferring it over a Lavish diff, whose content is LLM-constructed and carries a (small but non-zero) misrepresentation risk.

- **Code / diff review → difit** (this skill). Faithful reproduction of a diff.
- **Synthesis, plans, comparisons, decision surfaces → Lavish.** Interpretive by nature; cross-check load-bearing claims against source.

The only LLM-chosen input to difit is the **diff range** (which refs/commits to show). That is transparent and verifiable, not a content risk - always tell the captain the exact range you served so scope is clear.

## When to use

- **Complete review:** a crewmate branch is done and needs overall review before it is pushed to the local remote / handed to the captain. Serve the branch vs its base.
- **Partial review:** you want the captain to see a specific code option, a proposed change, or uncommitted work in-situ rather than describe it in prose.
- As the standard presentation step wherever firstmate would otherwise relay a diff summary alone.

## Requirements (verified: difit 5.0.8, Node v24)

- `difit` on PATH (`command -v difit`); Node >= 21.
- The captain sets the port via the **`DIFIT_PORT` environment variable**. NEVER hardcode the port - read it dynamically every time: `--port "$DIFIT_PORT"`. If `$DIFIT_PORT` is somehow unset, stop and ask the captain rather than guessing a port.

## Invocation

difit operates on the **current directory's** git repo, so `cd` into the target repo or worktree first. Run it as a **harness-tracked background task** (it is a long-running server, same pattern as the watcher / Lavish), then verify it responds before handing the captain the URL.

Standard command:

```sh
cd <repo-or-worktree-dir>
difit <RANGE> --no-open --host 0.0.0.0 --port "$DIFIT_PORT" --keep-alive
```

- `--no-open` - required: there is no browser inside the container to open.
- `--host 0.0.0.0` - REQUIRED in this environment. A default/localhost-only bind is NOT reachable from the captain's side (verified 2026-07-13: without `--host` the captain could not open the page), so all-interfaces binding is necessary for the diff to reach them. difit prints a loud "accessible from external network" warning on `0.0.0.0`; that is expected and unavoidable here - do not drop `--host` to silence it.
- `--port "$DIFIT_PORT"` - the captain's configured port, read dynamically. Note `--port` is a *preferred* port ("auto-assigned if occupied"), so confirm the actual bound port from difit's startup line / a `curl` check rather than assuming.
- `--keep-alive` - required: keep the server up after the browser disconnects, so it survives until (and after) the captain connects.

### `<RANGE>` forms

**Argument order matters:** `difit <subject> [<baseline>]` - the FIRST ref is the subject under review (the *new* state), the SECOND is the baseline compared against (the *old* state). Get it backwards and additions render as red removals (verified). So a finished branch reviewed against master is `difit <branch> master` (branch first), NOT `difit master <branch>`.

- `difit <branch> <base>` - a finished branch's changes vs its base, e.g. `difit david/fm/<id> master` (**complete review**). Branch (subject) first.
- `difit --merge-base <branch> <base>` - resolve the base with `git merge-base` first (use when the branch may not be freshly rebased onto base).
- `difit .` - all uncommitted changes (staged + unstaged). `difit working` - unstaged only. `difit staged` - staged only.
- `difit <commit>` / `difit HEAD~n` - a single commit.
- `difit --pr <github-pr-url>` - a GitHub PR (needs `gh`); not the usual firstmate path (firstmate does not drive GitHub).

Other useful options: `--context <lines>` (context around each hunk), `--include-untracked` (fold in untracked files), `--clean` (start with no prior comments), `--comment <json>` (inject initial review comments, repeatable).

## Verify before handing over (HR1)

Do not tell the captain it is ready without confirming the server actually serves the diff:

```sh
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:${DIFIT_PORT}/"        # expect 200
curl -s "http://localhost:${DIFIT_PORT}/api/diff" | head -c 200                    # expect real diff JSON (file paths)
```

Optionally sanity-check that the served file list matches `git diff --stat <RANGE>` - a cheap faithfulness confirmation.

Then give the captain the URL: `http://localhost:$DIFIT_PORT` (or the host's address + `:$DIFIT_PORT` if localhost does not map for them), and state the exact range you served.

## Getting the captain's feedback

Two paths:

1. **"Copy Prompt" (captain-driven):** the captain comments on lines/ranges in the UI, clicks **Copy Prompt** (or Copy All Prompt), and pastes the formatted result back into chat. Comments persist in browser localStorage per commit.
2. **`difit comment` (firstmate-driven retrieval):** difit exposes a `comment` subcommand to add / retrieve / resolve comments on a *running* server. This lets firstmate pull the captain's comments programmatically instead of relying on copy-paste. Confirm the exact retrieval invocation with `difit comment --help` the first time you use it in a session before relying on it.

Treat returned comments as review feedback: act on each, and re-present (a fresh difit of the updated diff) when you have addressed them.

## Teardown

The server is a background task. When the review is done (captain merged / approved / moved on), stop it - kill that background task. Do not leave difit servers running across unrelated work; one server holds the port. For several reviews at once, run them on distinct ports (not the single `$DIFIT_PORT`) or serve sequentially.

## Gotchas

- Port already in use → difit auto-reassigns; always read the real port from startup output / verify with `curl`, do not assume `$DIFIT_PORT` was honored.
- `--host 0.0.0.0` exposes the server on all interfaces (the external-network warning). Fine within the trusted container/host; drop `--host` for localhost-only if that reaches the captain.
- difit has no "point at an arbitrary repo path" flag - always `cd` into the repo/worktree first.
- Never interpolate untrusted text into the difit command line; the range args are refs/paths you control.
