#!/usr/bin/env bash
# Behavior tests for bin/fm-secret-scan.sh.
#
# Covers BOTH execution paths without depending on the real scanner:
#   - binary-present: a fake `betterleaks` (via fm_fakebin) records its argv and
#     reports clean/findings on demand, so we assert mode->invocation mapping,
#     exit-code mapping, --redact, and that no raw planted value is printed.
#   - binary-absent: the built-in degraded grep, with a high-entropy fake token.
#
# Fake secrets are high-entropy random (per the token-efficiency caveat: a
# low-entropy fake like "aaaa..." would be filtered by the real scanner and make
# a real detection look like a miss). No real secret ever appears here.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCAN="$ROOT/bin/fm-secret-scan.sh"

# Hermetic (HR3): unset any ambient knobs the code under test reads, so an
# operator's configured environment can neither change results nor leak values.
unset FM_ENABLE_SECRET_SCAN FM_SECRET_SCAN_BIN FM_SECRET_SCAN_CONFIG FM_SECRET_SCAN_STRICT

TMP=$(fm_test_tmproot fm-secret-scan)
FAKEBIN=$(fm_fakebin "$TMP")

# A high-entropy fake credential: ghp_ + 36 random alnum chars.
FAKE_TOKEN="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"

# --- fake betterleaks --------------------------------------------------------
# Records argv to FAKE_BL_LOG; clean (exit 0) or findings (exit 1) per
# FAKE_BL_RESULT. In findings mode it prints only a REDACTED line, mirroring the
# real --redact behavior, so we can assert the raw token never reaches output.
export FAKE_BL_LOG="$TMP/bl.log"
cat > "$FAKEBIN/betterleaks" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_BL_LOG"
case "${FAKE_BL_RESULT:-clean}" in
  findings) echo "Finding: secret REDACTED in fixture.txt"; exit 1 ;;
  *)        echo "no leaks found"; exit 0 ;;
esac
SH
chmod +x "$FAKEBIN/betterleaks"

# A repo to scan, with a root .betterleaks.toml so config resolution is exercised.
REPO="$TMP/repo"
fm_git_init_commit "$REPO"
printf 'extend.useDefault = true\n' > "$REPO/.betterleaks.toml"
git -C "$REPO" add .betterleaks.toml
git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm cfg

run() {  # run <result> -- <args...>  : run the wrapper with the fake on PATH
  local result=$1; shift; [ "$1" = -- ] && shift
  : > "$FAKE_BL_LOG"
  ( cd "$REPO" && PATH="$FAKEBIN:$PATH" FAKE_BL_RESULT="$result" "$SCAN" "$@" ) 2>"$TMP/err" >"$TMP/out"
}

# 1. clean tree -> exit 0
set +e; run clean -- ; rc=$?; set -e
expect_code 0 "$rc" "clean tree exits 0"
assert_grep "dir" "$FAKE_BL_LOG" "default mode invokes the dir subcommand"
pass "clean working-tree scan exits 0 via dir subcommand"

# 2. findings -> exit 1, redacted, raw token never printed
printf 'token=%s\n' "$FAKE_TOKEN" > "$REPO/fixture.txt"
set +e; run findings -- ; rc=$?; set -e
expect_code 1 "$rc" "findings exit 1"
out=$(cat "$TMP/out" "$TMP/err")
assert_not_contains "$out" "$FAKE_TOKEN" "raw planted token must not appear in output"
assert_contains "$out" "REDACTED" "redacted finding surfaced"
rm -f "$REPO/fixture.txt"
pass "findings exit 1 and never print the raw secret"

# 3. --redact is always passed to the scanner
run clean --
assert_grep "--redact" "$FAKE_BL_LOG" "wrapper always passes --redact"
pass "wrapper always runs the scanner redacted"

# 4. config resolution: root .betterleaks.toml passed via --config
assert_grep "--config" "$FAKE_BL_LOG" "wrapper passes --config"
assert_grep "$REPO/.betterleaks.toml" "$FAKE_BL_LOG" "config path is the repo-root .betterleaks.toml"
pass "config resolves to the repo-root .betterleaks.toml"

# 5. --staged maps to the git --staged subcommand
run clean -- --staged
assert_grep "git --staged" "$FAKE_BL_LOG" "staged mode invokes git --staged"
pass "--staged invokes the staged git scan"

# 6. --since maps to git --log-opts=<ref>..HEAD
run clean -- --since HEAD~0
assert_grep "--log-opts=HEAD~0..HEAD" "$FAKE_BL_LOG" "since mode passes the log range"
pass "--since scans the ref..HEAD diff"

# 7. <path> maps to dir <path>
SUB="$TMP/elsewhere"; mkdir -p "$SUB"
run clean -- "$SUB"
assert_grep "dir $SUB" "$FAKE_BL_LOG" "path mode invokes dir <path>"
pass "<path> scans the given directory"

# 8. scanner internal error (exit !=0,1) -> wrapper exit 2
cat > "$TMP/boom" <<'SH'
#!/usr/bin/env bash
exit 7
SH
chmod +x "$TMP/boom"
set +e; ( cd "$REPO" && FM_SECRET_SCAN_BIN="$TMP/boom" "$SCAN" ) 2>/dev/null; rc=$?; set -e
expect_code 2 "$rc" "scanner internal error maps to exit 2"
pass "scanner non-clean/non-findings exit maps to exit 2"

# --- degraded mode (binary absent) ------------------------------------------
# Point the wrapper at a binary that does not exist; no betterleaks on PATH here.

# 9. degraded clean dir -> exit 0, warns DEGRADED
CLEAN="$TMP/clean"; mkdir -p "$CLEAN"; printf 'nothing to see\n' > "$CLEAN/a.txt"
set +e; FM_SECRET_SCAN_BIN="$TMP/absent-xyz" "$SCAN" "$CLEAN" 2>"$TMP/err"; rc=$?; set -e
expect_code 0 "$rc" "degraded clean dir exits 0"
assert_grep "DEGRADED:" "$TMP/err" "degraded mode warns loudly"
pass "degraded mode: clean dir exits 0 with a DEGRADED warning"

# 10. degraded finding -> exit 1, DEGRADED, raw token never printed
DIRTY="$TMP/dirty"; mkdir -p "$DIRTY"; printf 'key=%s\n' "$FAKE_TOKEN" > "$DIRTY/leak.txt"
set +e; FM_SECRET_SCAN_BIN="$TMP/absent-xyz" "$SCAN" "$DIRTY" 2>"$TMP/err" >"$TMP/out"; rc=$?; set -e
expect_code 1 "$rc" "degraded finding exits 1"
out=$(cat "$TMP/out" "$TMP/err")
assert_contains "$out" "DEGRADED:" "degraded warning present on a finding"
assert_not_contains "$out" "$FAKE_TOKEN" "degraded mode must not print the raw token"
pass "degraded mode: catches a planted token, exits 1, never prints it"

# 11. degraded mode honors inline allow comments
ALLOWED="$TMP/allowed"; mkdir -p "$ALLOWED"
printf 'key=%s # gitleaks:allow\n' "$FAKE_TOKEN" > "$ALLOWED/ok.txt"
set +e; FM_SECRET_SCAN_BIN="$TMP/absent-xyz" "$SCAN" "$ALLOWED" 2>/dev/null; rc=$?; set -e
expect_code 0 "$rc" "degraded mode skips gitleaks:allow lines"
pass "degraded mode honors inline gitleaks:allow comments"

# 12. FM_SECRET_SCAN_STRICT=1 with no binary -> hard fail (exit 2)
set +e; FM_SECRET_SCAN_BIN="$TMP/absent-xyz" FM_SECRET_SCAN_STRICT=1 "$SCAN" "$CLEAN" 2>/dev/null; rc=$?; set -e
expect_code 2 "$rc" "strict + absent binary hard-fails"
pass "FM_SECRET_SCAN_STRICT=1 hard-fails when the binary is absent"

# 13. --help exits 0 and prints usage
set +e; "$SCAN" --help >"$TMP/help" 2>&1; rc=$?; set -e
expect_code 0 "$rc" "--help exits 0"
assert_grep "fm-secret-scan.sh --staged" "$TMP/help" "help lists the modes"
pass "--help prints usage and exits 0"

# --- master switch FM_ENABLE_SECRET_SCAN ------------------------------------
# A dir with a planted high-entropy fake secret: an enabled scan would block it.
PLANTED="$TMP/planted"; mkdir -p "$PLANTED"; printf 'key=%s\n' "$FAKE_TOKEN" > "$PLANTED/leak.txt"

# 14. disabled values exit 0 (do NOT block) even with a secret present, and say so.
for v in 0 false no off OFF False No Off; do
  set +e
  out=$(FM_ENABLE_SECRET_SCAN="$v" FM_SECRET_SCAN_BIN="$TMP/absent-xyz" "$SCAN" "$PLANTED" 2>&1); rc=$?
  set -e
  expect_code 0 "$rc" "FM_ENABLE_SECRET_SCAN=$v must exit 0 (gate off)"
  assert_contains "$out" "disabled via FM_ENABLE_SECRET_SCAN" "disabled notice for $v"
  assert_not_contains "$out" "$FAKE_TOKEN" "disabled path must not print the token ($v)"
done
pass "FM_ENABLE_SECRET_SCAN off-values disable the gate (exit 0, notice, no block)"

# 15. enabled values still scan: a planted secret in degraded mode blocks (exit 1).
for v in '' 1 true yes on TRUE Yes ON; do
  set +e
  ( if [ -n "$v" ]; then export FM_ENABLE_SECRET_SCAN="$v"; else unset FM_ENABLE_SECRET_SCAN; fi
    FM_SECRET_SCAN_BIN="$TMP/absent-xyz" "$SCAN" "$PLANTED" ) >/dev/null 2>"$TMP/err"; rc=$?
  set -e
  expect_code 1 "$rc" "FM_ENABLE_SECRET_SCAN='$v' must still scan and block"
  assert_no_grep "disabled via FM_ENABLE_SECRET_SCAN" "$TMP/err" "no disabled notice when enabled ('$v')"
done
pass "FM_ENABLE_SECRET_SCAN on-values (incl. unset) keep the gate active"

# 16. --help works even when the gate is disabled.
set +e; FM_ENABLE_SECRET_SCAN=0 "$SCAN" --help >"$TMP/help2" 2>&1; rc=$?; set -e
expect_code 0 "$rc" "--help exits 0 even when disabled"
assert_grep "fm-secret-scan.sh --staged" "$TMP/help2" "--help still prints usage when disabled"
pass "--help works regardless of the master switch"

echo "# fm-secret-scan: all assertions passed"
