#!/bin/sh
# Tests for assert-no-writes.sh. Run: sh assert-no-writes.test.sh
#
# specs/72 §3 originally called this script "thin enough that its verification is the
# demonstration run". PR #77's review disproved that: a failed `git ls-remote` read as "the ref
# is absent", so an auth or network error produced a clean bill of health — exit 0, "the remote
# is byte-for-byte as it was before the run". A script whose whole job is to fail closed needs
# its failure paths tested, and a demonstration run only ever exercises the happy one.
#
# `git` is replaced by a stub on PATH so each case controls exactly which remote reads succeed.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/assert-no-writes.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# --- the stub git ------------------------------------------------------------------
#
# Serves `ls-remote --heads|--tags origin [pattern]` from STUB_HEADS / STUB_TAGS. STUB_FAIL
# names the kinds whose reads fail, as an auth error would — every read of that kind, whether
# the whole listing or one ref, so the stub behaves like a remote that is actually unreachable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/git" <<'STUB'
#!/bin/sh
[ "$1" = "ls-remote" ] || { echo "stub git: unexpected: $*" >&2; exit 99; }
kind="${2#--}"
pattern="${4:-}"
case " ${STUB_FAIL:-} " in
  *" $kind "*) echo "fatal: Authentication failed for 'https://github.com/x/y.git/'" >&2; exit 128 ;;
esac
if [ "$kind" = heads ]; then data="$STUB_HEADS"; else data="$STUB_TAGS"; fi
[ -n "$data" ] || exit 0
if [ -n "$pattern" ]; then
  printf '%s\n' "$data" | awk -v p="$pattern" '$2 == p || $2 == p "^{}"'
else
  printf '%s\n' "$data"
fi
STUB
chmod +x "$TMP/bin/git"

HEADS_BEFORE='aaa	refs/heads/DEVELOP
bbb	refs/heads/master
ccc	refs/heads/staging-0.3.0-SNAPSHOT-RC'
TAGS_BEFORE='ddd	refs/tags/dsh-0.2.4
eee	refs/tags/dsh-0.2.4^{}'

# Each case gets a RUNNER_TEMP holding the 'before' snapshots rehearsal-setup would have
# written, plus a snapshot-packages stub that reproduces an unchanged registry.
#
# setup_case <name> <heads-before> <tags-before> [<packages-before>]
# The snapshot-packages stub writes PKG_AFTER when the case sets it, and otherwise reproduces
# the 'before' registry unchanged.
PKGS_BEFORE='com.mriss.products.dsh 0.2.4'
setup_case() {
  dir="$TMP/$1"
  mkdir -p "$dir"
  printf '%s\n' "$2" | sort > "$dir/rehearsal-heads.before"
  if [ -n "$3" ]; then printf '%s\n' "$3" | sort > "$dir/rehearsal-tags.before"; else : > "$dir/rehearsal-tags.before"; fi
  printf '%s\n' "${4:-$PKGS_BEFORE}" | LC_ALL=C sort > "$dir/rehearsal-packages.before"
  cat > "$dir/rehearsal-snapshot-packages.sh" <<STUB
#!/bin/sh
if [ -n "\${PKG_AFTER:-}" ]; then printf '%s\n' "\$PKG_AFTER" | LC_ALL=C sort > "\$2"
else cp "$dir/rehearsal-packages.before" "\$2"; fi
STUB
  chmod +x "$dir/rehearsal-snapshot-packages.sh"
  echo "$dir"
}

# run_case <name> <heads-after> <tags-after> <stub-fail> [hotfix-branch]
# Sets OUT and RC. The 'before' snapshots are always the baselines above, except where a case
# overrides them before calling.
run_case() {
  OUT="$(
    PATH="$TMP/bin:$PATH" RUNNER_TEMP="$CASE_DIR" \
    STUB_HEADS="$2" STUB_TAGS="$3" STUB_FAIL="$4" \
    bash "$SCRIPT" dsh 0.3.0 staging-0.3.0-SNAPSHOT-RC "${5-0.3.x}" 2>&1
  )"
  RC=$?
}

expect_rc() {
  if [ "$RC" -eq "$2" ]; then pass "$1"; else
    fail "$1 (expected exit $2, got $RC)"; printf '%s\n' "$OUT" | sed 's/^/       | /'
  fi
}
expect_says()     { if printf '%s' "$OUT" | grep -qF -- "$2"; then pass "$1"; else fail "$1"; printf '       expected to contain: %s\n' "$2"; printf '%s\n' "$OUT" | sed 's/^/       | /'; fi; }
expect_not_says() { if printf '%s' "$OUT" | grep -qF -- "$2"; then fail "$1"; printf '       must not contain: %s\n' "$2"; printf '%s\n' "$OUT" | sed 's/^/       | /'; else pass "$1"; fi; }

# --- the happy path: nothing changed, every read succeeded -------------------------

CASE_DIR="$(setup_case clean "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case clean "$HEADS_BEFORE" "$TAGS_BEFORE" ""
expect_rc   "an untouched remote passes" 0
expect_says "an untouched remote says so" "byte-for-byte as it was"

# --- failed reads must fail closed (PR #77 review) ---------------------------------

# The exact scenario the review described, reproduced before this fix: the positive
# assertions are satisfied by a read that never happened.
CASE_DIR="$(setup_case heads_fail "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case heads_fail "$HEADS_BEFORE" "$TAGS_BEFORE" "heads"
expect_rc         "a failed heads read fails the run" 1
expect_not_says   "a failed heads read never reports the hotfix branch absent" "branch 0.3.x: absent, as it must be"
expect_says       "a failed heads read is reported as a failed read" "could not read"

CASE_DIR="$(setup_case tags_fail "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case tags_fail "$HEADS_BEFORE" "$TAGS_BEFORE" "tags"
expect_rc         "a failed tags read fails the run" 1
expect_not_says   "a failed tags read never reports the release tag absent" "tag v0.3.0: absent, as it must be"

# The hole the review did NOT name. A repository with no tags has an empty 'before'
# snapshot; a failed 'after' read is also empty; the two diff equal and pass.
CASE_DIR="$(setup_case tagless_fail "$HEADS_BEFORE" "")"
run_case tagless_fail "$HEADS_BEFORE" "" "tags"
expect_rc         "a failed tags read on a tagless repository still fails the run" 1
expect_not_says   "a tagless repository's failed read never reports tags unchanged" "tags: unchanged"

# --- real writes must be caught ------------------------------------------------------

CASE_DIR="$(setup_case tag_pushed "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case tag_pushed "$HEADS_BEFORE" "$TAGS_BEFORE
fff	refs/tags/v0.3.0" ""
expect_rc   "a pushed release tag fails the run" 1
expect_says "a pushed release tag is named" "v0.3.0"

# ls-remote lists an annotated tag twice, once peeled. Only the peeled form surviving must
# still count as the tag being present.
CASE_DIR="$(setup_case tag_peeled "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case tag_peeled "$HEADS_BEFORE" "$TAGS_BEFORE
fff	refs/tags/v0.3.0^{}" ""
expect_rc   "a pushed release tag seen only in peeled form fails the run" 1

CASE_DIR="$(setup_case branch_created "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case branch_created "$HEADS_BEFORE
ggg	refs/heads/0.3.x" "$TAGS_BEFORE" ""
expect_rc   "a pushed hotfix branch fails the run" 1
expect_says "a pushed hotfix branch is named" "0.3.x"

CASE_DIR="$(setup_case rc_deleted "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case rc_deleted 'aaa	refs/heads/DEVELOP
bbb	refs/heads/master' "$TAGS_BEFORE" ""
expect_rc   "a deleted RC branch fails the run" 1
expect_says "a deleted RC branch is named" "staging-0.3.0-SNAPSHOT-RC"

# --- exact matching ------------------------------------------------------------------

# The version's dots are literal. An unrelated tag that a regex would match must not be
# mistaken for the release tag — present in both snapshots, so the diff is clean.
CASE_DIR="$(setup_case lookalike "$HEADS_BEFORE" "$TAGS_BEFORE
hhh	refs/tags/v0x3x0")"
run_case lookalike "$HEADS_BEFORE" "$TAGS_BEFORE
hhh	refs/tags/v0x3x0" ""
expect_rc   "a lookalike tag is not mistaken for the release tag" 0

# --- the registry (PR #77 review, F1) ------------------------------------------------

# A deploy under any name must show. The snapshot now covers every package in the
# organisation, so this includes a consumer whose package names share nothing with its
# repository name — the case a name filter made invisible.
CASE_DIR="$(setup_case pkg_deployed "$HEADS_BEFORE" "$TAGS_BEFORE")"
# Exported rather than prefixed to the call: an assignment prefixed to a shell FUNCTION is not
# reliably exported to the processes it starts under dash, which is /bin/sh on the runners.
PKG_AFTER="$PKGS_BEFORE
com.example.unrelated-name.core 0.3.0"; export PKG_AFTER
run_case pkg_deployed "$HEADS_BEFORE" "$TAGS_BEFORE" ""
unset PKG_AFTER
expect_rc   "a deployed package version fails the run" 1
expect_says "a deployed package version is named" "com.example.unrelated-name.core 0.3.0"

# The other half of F1. With every package in the snapshot, an UNRELATED product may already
# be at the release version number. That is not a write by this run and must not fail it —
# the positive "no package carries this version" check an earlier revision had would have.
CASE_DIR="$(setup_case pkg_same_version "$HEADS_BEFORE" "$TAGS_BEFORE" "$PKGS_BEFORE
com.mriss.products.mail-processor 0.3.0")"
run_case pkg_same_version "$HEADS_BEFORE" "$TAGS_BEFORE" ""
expect_rc   "an unrelated package already at the release version does not fail the run" 0

# project-hotfix.yml creates no branch and passes an empty hotfix_branch.
CASE_DIR="$(setup_case no_hotfix "$HEADS_BEFORE" "$TAGS_BEFORE")"
run_case no_hotfix "$HEADS_BEFORE" "$TAGS_BEFORE" "" ""
expect_rc   "an empty hotfix branch is skipped, not asserted" 0

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
