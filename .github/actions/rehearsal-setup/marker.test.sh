#!/bin/sh
# Tests for marker.sh. Run: sh marker.test.sh
#
# marker.sh is called from steps that also run during a real release, so the inactive
# branch is as load-bearing as the active one: if it ever printed or wrote anything, a
# real release's log would differ from today's, which specs/72 "Global constraints"
# forbids. Both branches are asserted here.
set -u

SCRIPT="$(dirname "$0")/marker.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

check() {
  description="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$description"
  else
    fail "$description"
    printf '       expected: %s\n' "$expected"
    printf '       actual:   %s\n' "$actual"
  fi
}

# Each case gets its own RUNNER_TEMP so the markers file starts absent.
fresh() {
  case_dir="$TMP/$1"
  mkdir -p "$case_dir"
  RUNNER_TEMP="$case_dir"
  GITHUB_STEP_SUMMARY="$case_dir/summary.md"
  export RUNNER_TEMP GITHUB_STEP_SUMMARY
}

# --- inactive: a real release ------------------------------------------------------

fresh inactive
RH_ACTIVE=''; export RH_ACTIVE
out="$(sh "$SCRIPT" merge-to-master 'push the merge of v0.3.0 to master' 2>&1)"
rc=$?
check "inactive prints nothing on stdout or stderr" "" "$out"
check "inactive exits 0" "0" "$rc"
check "inactive writes no markers file" "absent" \
  "$( [ -e "$RUNNER_TEMP/rehearsal-markers" ] && echo present || echo absent )"
check "inactive writes no step summary" "absent" \
  "$( [ -s "$GITHUB_STEP_SUMMARY" ] && echo present || echo absent )"

# --- active ------------------------------------------------------------------------

fresh active
RH_ACTIVE=1; export RH_ACTIVE
out="$(sh "$SCRIPT" merge-to-master 'push the merge of v0.3.0 to master' 2>&1)"
rc=$?
check "active prints the marker line" \
  "REHEARSAL merge-to-master: would push the merge of v0.3.0 to master" "$out"
check "active exits 0" "0" "$rc"
check "active records the id" "merge-to-master" \
  "$(cat "$RUNNER_TEMP/rehearsal-markers" 2>/dev/null)"
check "active names the id in the step summary" "1" \
  "$(grep -c 'merge-to-master' "$GITHUB_STEP_SUMMARY" 2>/dev/null)"

# --- active, several calls ---------------------------------------------------------

fresh appends
RH_ACTIVE=1; export RH_ACTIVE
sh "$SCRIPT" release-prepare 'commit, tag and push the release' >/dev/null 2>&1
sh "$SCRIPT" site-deploy 'publish the site to gh-pages' >/dev/null 2>&1
check "ids append in call order, one per line" "release-prepare site-deploy" \
  "$(tr '\n' ' ' < "$RUNNER_TEMP/rehearsal-markers" | sed 's/ $//')"

# --- usage errors ------------------------------------------------------------------
#
# A malformed call site is a workflow bug, and the marker set it produces would be a
# lie. It fails in both modes on purpose: catching it only under RH_ACTIVE would mean
# the inactive path silently tolerates the same bug in every real release.

fresh noargs
RH_ACTIVE=1; export RH_ACTIVE
sh "$SCRIPT" >/dev/null 2>&1
check "active: no arguments fails" "1" "$?"

fresh oneargactive
sh "$SCRIPT" only-an-id >/dev/null 2>&1
check "active: a missing description fails" "1" "$?"

fresh noargsinactive
RH_ACTIVE=''; export RH_ACTIVE
sh "$SCRIPT" >/dev/null 2>&1
check "inactive: no arguments fails too" "1" "$?"

fresh emptyid
RH_ACTIVE=1; export RH_ACTIVE
sh "$SCRIPT" '' 'a description' >/dev/null 2>&1
check "active: an empty id fails" "1" "$?"

# --- RUNNER_TEMP is mandatory when active ------------------------------------------
#
# Without it the id goes nowhere and the completeness check in rehearsal-verify would
# report a missing marker for a site that did emit one. Fail at the call site instead.

fresh norunnertemp
RH_ACTIVE=1; export RH_ACTIVE
unset RUNNER_TEMP
sh "$SCRIPT" some-id 'do a thing' >/dev/null 2>&1
check "active: an unset RUNNER_TEMP fails" "1" "$?"

# --- GITHUB_STEP_SUMMARY is optional -----------------------------------------------

fresh nosummary
RH_ACTIVE=1; export RH_ACTIVE
unset GITHUB_STEP_SUMMARY
out="$(sh "$SCRIPT" some-id 'do a thing' 2>&1)"
check "active: an unset GITHUB_STEP_SUMMARY still emits the marker" \
  "REHEARSAL some-id: would do a thing" "$out"
check "active: an unset GITHUB_STEP_SUMMARY still records the id" "some-id" \
  "$(cat "$RUNNER_TEMP/rehearsal-markers" 2>/dev/null)"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
