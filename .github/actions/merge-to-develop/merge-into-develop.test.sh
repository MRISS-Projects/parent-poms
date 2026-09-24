#!/bin/sh
# Tests for merge-into-develop.sh. Run: sh merge-into-develop.test.sh
#
# Case 4 is the one that matters most. A real conflict must STOP the merge-back and leave the
# development branch exactly where it was, rather than being resolved by picking a side, which
# is what the `-X ours` in #65's issue body would have done. See
# specs/65-merge-release-back-into-develop.md §2.2.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/merge-into-develop.sh"
. "$HERE/test-fixture.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# run_merge [args...] — in $REPO; sets $out and $rc. Defaults to the fixture's own names.
run_merge() {
  if [ "$#" -eq 0 ]; then set -- v1.0 merge-back/v1.0 DEVELOP; fi
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

# expect_file <description> <path> <expected-content> — compared against HEAD.
expect_file() {
  actual="$(g show "HEAD:$2" 2>/dev/null)"
  expected="$(printf '%b' "$3")"
  if [ "$actual" = "$expected" ]; then pass "$1"
  else
    fail "$1"
    printf '       expected %s:\n%s\n       actual:\n%s\n' "$2" "$expected" "$actual"
  fi
}

# --- 1. an RC-only fix reaches the development branch ---------------------------------

new_repo "$TMP/rc-fix"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
release 1.0; align 1.0; on_develop
run_merge
expect_rc "an RC-only fix merges" 0
expect_file "the RC fix is on the development branch" a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'
expect_says "it prints the evidence line" \
  "merge-to-develop: carried 1 path(s) from v1.0 into DEVELOP; 0 lost"

parents="$(g rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')"
if [ "$parents" -eq 3 ]; then pass "the merge is a two-parent commit, even though it could fast-forward"
else fail "the merge is a two-parent commit (got $((parents - 1)) parent(s))"; fi

subject="$(g log -1 --format=%s)"
if [ "$subject" = "[maven-release-plugin] merge release v1.0 into DEVELOP" ]; then
  pass "the merge commit carries the §3.3 message"
else fail "the merge commit carries the §3.3 message (got: $subject)"; fi

if g show HEAD:pom.xml | grep -qF '<version>2.0-SNAPSHOT</version>' &&
   g show HEAD:pom.xml | grep -qF '<tag>HEAD</tag>' &&
   g show HEAD:mod/pom.xml | grep -qF '<version>2.0-SNAPSHOT</version>'; then
  pass "the POMs keep the development version and SCM tag"
else fail "the POMs keep the development version and SCM tag"; fi

# --- 2. a development-only change survives --------------------------------------------

new_repo "$TMP/dev-change"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
g checkout -q DEVELOP
put b.txt 'alpha\nbeta\ngamma-dev\n'; commit "dev change"
release 1.0; align 1.0; on_develop
run_merge
expect_rc "an RC fix and a development change to different files merge" 0
expect_file "the development change survives" b.txt 'alpha\nbeta\ngamma-dev\n'
expect_file "and so does the RC fix" a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'

# --- 3. edits to different lines of one file both survive ------------------------------

new_repo "$TMP/same-file"
put a.txt 'ONE-rc\ntwo\nthree\nfour\nfive\n'; commit "rc fix"
g checkout -q DEVELOP
put a.txt 'one\ntwo\nthree\nfour\nFIVE-dev\n'; commit "dev change"
release 1.0; align 1.0; on_develop
run_merge
expect_rc "edits to different lines of one file merge" 0
expect_file "both edits survive" a.txt 'ONE-rc\ntwo\nthree\nfour\nFIVE-dev\n'
expect_says "a path both sides changed still counts as carried" "carried 1 path(s)"

# --- 4. a real conflict stops the merge-back ------------------------------------------

new_repo "$TMP/conflict"
put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
g checkout -q DEVELOP
put a.txt 'one\nTWO-dev\nthree\nfour\nfive\n'; commit "dev change"
release 1.0; align 1.0; on_develop
before="$(g rev-parse HEAD)"
run_merge
expect_rc "a real conflict fails" 1
expect_says "it names the conflicted path" "a.txt"
expect_says "it names the tag to merge by hand" "v1.0"
expect_says "it says the release itself is complete" "release itself is complete"

if [ "$(g rev-parse HEAD)" = "$before" ]; then pass "the development branch is unchanged"
else fail "the development branch is unchanged"; fi

if g rev-parse -q --verify MERGE_HEAD >/dev/null; then fail "no merge is left in progress"
else pass "no merge is left in progress"; fi

if [ -z "$(g status --porcelain)" ]; then pass "the working tree is clean"
else fail "the working tree is clean"; g status --short; fi

# --- 5. a POM conflict is a real conflict too ------------------------------------------
# A module declaring its own <scm><tag>, or a mis-set version, leaves the aligned commit
# disagreeing with the development branch on a POM. That must fail, not be resolved.

new_repo "$TMP/pom-conflict"
release 1.0
g checkout -q -b merge-back/v1.0 v1.0
set_poms 9.9-SNAPSHOT HEAD
commit "align v1.0 to the wrong version"
on_develop
run_merge
expect_rc "an alignment that disagrees with the development branch's POMs fails" 1
expect_says "it names the POM" "pom.xml"

# --- 6. misuse ------------------------------------------------------------------------

new_repo "$TMP/misuse"
release 1.0; align 1.0
g checkout -q rc
run_merge
expect_rc "run on a branch other than the named one, it fails" 1
expect_says "and says which branch it is on" "on 'rc'"

on_develop
run_merge v1.0 merge-back/v1.0
expect_rc "two arguments instead of three fails" 1
expect_says "misuse prints a usage line" "usage:"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
