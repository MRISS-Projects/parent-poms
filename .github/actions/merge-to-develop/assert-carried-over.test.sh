#!/bin/sh
# Tests for assert-carried-over.sh. Run: sh assert-carried-over.test.sh
#
# Two cases are load-bearing and neither is optional:
#
#   - Case 2 is the regression test the assertion exists for. `-X ours` over a conflicting RC
#     fix is what #65's issue body proposed, and it merges green having dropped the fix. It is
#     also the case that showed the first design of this check was wrong: the fixture has to be
#     a conflict, a conflict means both sides changed the path, and that design skipped every
#     path both sides changed. See specs/65-merge-release-back-into-develop.md §3.3.
#   - Case 5 is the one check 1 cannot see. It compares HEAD against the plain merge of the
#     ALIGNED commit, so an alignment step that rewrites a non-POM file passes it. Only a
#     comparison against the tag catches that.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/assert-carried-over.sh"
. "$HERE/test-fixture.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# run_assert <tag> <branch-before> <aligned-ref> <branch> — in $REPO; sets $out and $rc.
run_assert() {
  out="$(cd "$REPO" && sh "$SCRIPT" "$@" 2>&1)"
  rc=$?
}

expect_rc() {
  if [ "$rc" -eq "$2" ]; then pass "$1"
  else
    fail "$1 (expected exit $2, got $rc)"
    printf '       output:\n%s\n' "$out"
  fi
}

expect_says() {
  if printf '%s' "$out" | grep -qF -- "$2"; then pass "$1"
  else
    fail "$1"
    printf '       expected output to contain: %s\n' "$2"
    printf '       actual output:\n%s\n' "$out"
  fi
}

# A conflicting fix: rc and DEVELOP both rewrite line two of a.txt.
conflicting_fix() {
  new_repo "$TMP/$1"
  put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
  g checkout -q DEVELOP
  put a.txt 'one\nTWO-dev\nthree\nfour\nfive\n'; commit "dev change"
  release 1.0; align 1.0; on_develop
  BEFORE="$(g rev-parse HEAD)"
}

# --- 1. a clean plain merge ----------------------------------------------------------

new_repo "$TMP/clean"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
release 1.0; align 1.0; on_develop
BEFORE="$(g rev-parse HEAD)"
g merge -q --no-ff --no-edit merge-back/v1.0
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "a clean plain merge passes" 0
expect_says "it prints the evidence line" \
  "merge-to-develop: carried 1 path(s) from v1.0 into DEVELOP; 0 lost"

# --- 2. the regression: -X ours drops the RC fix ---------------------------------------

conflicting_fix xours
g merge -q --no-ff --no-edit -X ours merge-back/v1.0 >/dev/null
if g show HEAD:a.txt | grep -q TWO-rc; then
  fail "fixture: -X ours should have dropped the rc fix, and did not"
fi
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "a merge resolved with -X ours fails" 1
expect_says "it names the path whose release change was at risk" "a.txt"

# --- 3. and -X theirs ------------------------------------------------------------------

conflicting_fix xtheirs
g merge -q --no-ff --no-edit -X theirs merge-back/v1.0 >/dev/null
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "a merge resolved with -X theirs fails" 1
expect_says "it names the conflicted path" "a.txt"

# --- 4. a merge commit edited after the fact ------------------------------------------

new_repo "$TMP/amended"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
release 1.0; align 1.0; on_develop
BEFORE="$(g rev-parse HEAD)"
g merge -q --no-ff --no-edit merge-back/v1.0
put b.txt 'alpha\nbeta\ngamma\n'
g add -A && g commit -q --amend --no-edit
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "HEAD differing from the plain merge fails" 1
expect_says "it names the path that differs" "b.txt"

# --- 5. alignment that rewrote a non-POM file -------------------------------------------

new_repo "$TMP/misaligned"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
release 1.0; align 1.0
put b.txt 'alpha\nBETA-by-alignment\n'
g add -A && g commit -q --amend --no-edit
on_develop
BEFORE="$(g rev-parse HEAD)"
g merge -q --no-ff --no-edit merge-back/v1.0
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "an aligned commit that changed a non-POM file fails" 1
expect_says "it names the file the alignment changed" "b.txt"

# --- 6. a deletion on the release is carried and counted -------------------------------

new_repo "$TMP/deletion"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'
g rm -q b.txt
commit "rc fix and removal"
release 1.0; align 1.0; on_develop
BEFORE="$(g rev-parse HEAD)"
g merge -q --no-ff --no-edit merge-back/v1.0
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "a release that deletes a file passes when the deletion arrives" 0
expect_says "the deletion is counted" "carried 2 path(s)"

# --- 7. POMs are not counted as carried -----------------------------------------------

new_repo "$TMP/poms-only"
release 1.0; align 1.0; on_develop
BEFORE="$(g rev-parse HEAD)"
g merge -q --no-ff --no-edit merge-back/v1.0
run_assert v1.0 "$BEFORE" merge-back/v1.0 DEVELOP
expect_rc "a release that changed only POMs passes" 0
expect_says "and carries zero paths" "carried 0 path(s)"

# --- 8. misuse ------------------------------------------------------------------------

run_assert v1.0 "$BEFORE" merge-back/v1.0
expect_rc "three arguments instead of four fails" 1
expect_says "misuse prints a usage line" "usage:"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
