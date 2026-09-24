#!/bin/sh
# Tests for push-merge-back.sh. Run: sh push-merge-back.test.sh
#
# The remote is a local bare repository. A second clone of it plays whoever pushes to the
# development branch while the release is running. That is PR #82's review finding, and the
# common way to hit it is not a concurrent hotfix but an ordinary PR merge into DEVELOP during
# the minutes a release takes. Case 2 is the regression test for it. Cases 3 and 4 are the
# reasons a retry must NOT go ahead: POMs that moved under the alignment, and a new conflict.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/push-merge-back.sh"
. "$HERE/test-fixture.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

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

# setup <name> — the fixture with an RC fix, released, aligned and merged into DEVELOP locally,
# and a bare remote holding DEVELOP at its tip from BEFORE that merge: the state push-merge-back.sh
# starts from. $REMOTE is the bare repository; $OTHER is a second clone of it.
setup() {
  new_repo "$TMP/$1"
  put a.txt 'one\nTWO-rc\nthree\nfour\nfive\n'; commit "rc fix"
  release 1.0; align 1.0; on_develop
  REMOTE="$TMP/$1-remote.git"
  git clone -q --bare "$REPO" "$REMOTE"
  (cd "$REPO" && sh "$HERE/merge-into-develop.sh" v1.0 merge-back/v1.0 DEVELOP >/dev/null) ||
    fail "fixture: the initial merge-back failed"
  OTHER="$TMP/$1-other"
  git clone -q -b DEVELOP "$REMOTE" "$OTHER"
  git -C "$OTHER" config user.name other
  git -C "$OTHER" config user.email other@example.invalid
  git -C "$OTHER" config core.autocrlf false
}

# concurrent_push <path> <content> — someone else pushes to DEVELOP first.
concurrent_push() {
  printf '%b' "$2" > "$OTHER/$1"
  git -C "$OTHER" add -A && git -C "$OTHER" commit -q -m "concurrent change to $1" &&
    git -C "$OTHER" push -q origin DEVELOP
}

# run_push [dry-run-flag] — in $REPO, against $REMOTE; sets $out and $rc.
run_push() {
  out="$(cd "$REPO" && RH_GIT_PUSH_DRYRUN="${1:-}" \
    sh "$SCRIPT" "$REMOTE" v1.0 merge-back/v1.0 DEVELOP 2>&1)"
  rc=$?
}

remote_tip() { git -C "$REMOTE" rev-parse DEVELOP; }

# --- 1. nothing moved: one push ----------------------------------------------------------

setup quiet
run_push
expect_rc "with no concurrent push, it pushes" 0
if [ "$(remote_tip)" = "$(g rev-parse HEAD)" ]; then pass "the remote is at the merge"
else fail "the remote is at the merge"; fi

# --- 2. the review finding: DEVELOP advanced by a non-POM commit --------------------------

setup advanced
concurrent_push b.txt 'alpha\nbeta\ngamma-concurrent\n'
concurrent="$(git -C "$OTHER" rev-parse HEAD)"
run_push
expect_rc "a push rejected because DEVELOP advanced is merged again and retried" 0
expect_says "it says why it is retrying" "merging again"
if git -C "$REMOTE" merge-base --is-ancestor "$concurrent" DEVELOP; then
  pass "the concurrent commit is kept"
else fail "the concurrent commit is kept"; fi
if git -C "$REMOTE" show DEVELOP:a.txt | grep -q TWO-rc &&
   git -C "$REMOTE" show DEVELOP:b.txt | grep -q gamma-concurrent; then
  pass "the remote has both the release fix and the concurrent change"
else fail "the remote has both the release fix and the concurrent change"; fi
expect_says "the retried merge is proven again" "carried 1 path(s) from v1.0 into DEVELOP; 0 lost"

# --- 3. DEVELOP advanced with a POM change: the alignment no longer holds -------------------

setup pom-moved
concurrent_push mod/pom.xml '<project>\n    <artifactId>mod</artifactId>\n    <!-- moved -->\n</project>\n'
concurrent="$(git -C "$OTHER" rev-parse HEAD)"
run_push
expect_rc "a POM change on DEVELOP stops the retry" 1
expect_says "it names the POM" "mod/pom.xml"
expect_says "it gives the whole reason, not its first half" "may no longer match it"
expect_says "it says the release itself is complete" "release itself is complete"
if [ "$(remote_tip)" = "$concurrent" ]; then pass "the remote is left at the concurrent commit"
else fail "the remote is left at the concurrent commit"; fi

# --- 4. DEVELOP advanced with a change that now conflicts ----------------------------------

setup conflict
concurrent_push a.txt 'one\nTWO-concurrent\nthree\nfour\nfive\n'
concurrent="$(git -C "$OTHER" rev-parse HEAD)"
run_push
expect_rc "a concurrent change that conflicts with the release stops the retry" 1
expect_says "it names the conflicted path" "a.txt"
if [ "$(remote_tip)" = "$concurrent" ]; then pass "the remote is left at the concurrent commit"
else fail "the remote is left at the concurrent commit"; fi

# --- 5. rejected for another reason: no retry --------------------------------------------

setup refused
mkdir -p "$REMOTE/hooks"
printf '#!/bin/sh\necho "branch protected" >&2\nexit 1\n' > "$REMOTE/hooks/update"
chmod +x "$REMOTE/hooks/update"
before="$(remote_tip)"
run_push
expect_rc "a push refused for a reason other than DEVELOP advancing fails at once" 1
expect_says "it says the branch did not advance" "other than"
expect_says "it gives the recovery" "release itself is complete"
if [ "$(remote_tip)" = "$before" ]; then pass "the remote is unchanged"
else fail "the remote is unchanged"; fi

# --- 6. a rehearsal pushes nothing ---------------------------------------------------------

setup dry
before="$(remote_tip)"
run_push --dry-run
expect_rc "with --dry-run it succeeds" 0
if [ "$(remote_tip)" = "$before" ]; then pass "and the remote is unchanged"
else fail "and the remote is unchanged"; fi

# --- 7. misuse -----------------------------------------------------------------------------

out="$(cd "$REPO" && RH_GIT_PUSH_DRYRUN='' sh "$SCRIPT" "$REMOTE" v1.0 2>&1)"; rc=$?
expect_rc "two arguments instead of four fails" 1
expect_says "misuse prints a usage line" "usage:"

out="$(cd "$REPO" && env -u RH_GIT_PUSH_DRYRUN sh "$SCRIPT" "$REMOTE" v1.0 merge-back/v1.0 DEVELOP 2>&1)"
rc=$?
expect_rc "RH_GIT_PUSH_DRYRUN unset fails rather than pushing for real" 1
expect_says "and says rehearsal-setup must run first" "rehearsal-setup"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
