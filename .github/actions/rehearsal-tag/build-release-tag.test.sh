#!/bin/sh
# Tests for build-release-tag.sh. Run: sh build-release-tag.test.sh
#
# The script bridges the gap that `release:prepare -DdryRun=true` opens: no tag is created,
# so every later step in the release workflow is unreachable. It builds the tag locally from
# the pom.xml.tag tree the dry run already wrote to disk.
#
# The assertions that matter most are the negative ones. This runs inside the same checkout
# that later steps still read, so if it moved HEAD, dirtied the working tree or left entries
# in the real index, it would corrupt the rehearsal it exists to enable. The obvious
# implementation — copy the .tag files over, commit, then `git reset --hard` — does exactly
# that, which is why specs/72 §2.2 mandates the plumbing form.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/build-release-tag.sh"
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

# A throwaway repository shaped like what dry-run release:prepare leaves behind: the working
# tree still at the SNAPSHOT version, and untracked pom.xml.tag files carrying the release
# version, for the root and for every module.
make_repo() {
  repo="$TMP/$1"
  mkdir -p "$repo/module-a" "$repo/module-b"
  cd "$repo" || exit 1
  git init -q .
  git config user.name  "Test"
  git config user.email "test@example.com"
  git config commit.gpgsign false

  printf '<project><version>0.3.0-SNAPSHOT</version></project>\n' > pom.xml
  printf '<project><version>0.3.0-SNAPSHOT</version></project>\n' > module-a/pom.xml
  printf '<project><version>0.3.0-SNAPSHOT</version></project>\n' > module-b/pom.xml
  printf 'unrelated tracked file\n' > README.md
  git add -A
  git commit -q -m "initial"

  printf '<project><version>0.3.0</version></project>\n' > pom.xml.tag
  printf '<project><version>0.3.0</version></project>\n' > module-a/pom.xml.tag
  printf '<project><version>0.3.0</version></project>\n' > module-b/pom.xml.tag
  printf 'scm.tag=v0.3.0\ncompletedPhase=end-release\npreparationGoals=clean install\n' \
    > release.properties
}

# --- the happy path ----------------------------------------------------------------

make_repo happy
head_before="$(git rev-parse HEAD)"
branch_before="$(git rev-parse --abbrev-ref HEAD)"
status_before="$(git status --porcelain | sort)"
worktree_before="$(find . -path ./.git -prune -o -type f -print | sort | xargs sha1sum | sha1sum)"

out="$(sh "$SCRIPT" 2>&1)"
rc=$?
[ "$rc" -eq 0 ] || printf '       script output:\n%s\n' "$out"
check "exits 0 on a well-formed dry-run tree" "0" "$rc"

check "creates the tag named by release.properties" "v0.3.0" \
  "$(git tag --list 'v*')"

check "the tagged root pom carries the release version" "<project><version>0.3.0</version></project>" \
  "$(git show v0.3.0:pom.xml 2>/dev/null)"

check "the tagged module poms carry the release version too" \
  "<project><version>0.3.0</version></project> <project><version>0.3.0</version></project>" \
  "$(printf '%s %s' "$(git show v0.3.0:module-a/pom.xml 2>/dev/null)" \
                    "$(git show v0.3.0:module-b/pom.xml 2>/dev/null)")"

check "the tagged tree keeps files the dry run did not rewrite" "unrelated tracked file" \
  "$(git show v0.3.0:README.md 2>/dev/null)"

check "the tagged commit's parent is HEAD" "$head_before" \
  "$(git rev-parse 'v0.3.0^{commit}^' 2>/dev/null)"

check "no pom.xml.tag file is committed under its own name" "" \
  "$(git ls-tree -r --name-only v0.3.0 2>/dev/null | grep 'pom.xml.tag' || true)"

# --- the negative assertions: nothing in the checkout may move ---------------------

check "HEAD is unmoved" "$head_before" "$(git rev-parse HEAD)"
check "the branch is unmoved" "$branch_before" "$(git rev-parse --abbrev-ref HEAD)"
check "the working tree is byte-identical" "$worktree_before" \
  "$(find . -path ./.git -prune -o -type f -print | sort | xargs sha1sum | sha1sum)"
check "git status is unchanged — the real index was not touched" "$status_before" \
  "$(git status --porcelain | sort)"

# `git diff --cached` reads the real index against HEAD. An implementation that staged the
# .tag files without exporting GIT_INDEX_FILE would show them here even if it then reset.
check "nothing is staged in the real index" "" "$(git diff --cached --name-only)"

# --- failure modes -----------------------------------------------------------------

make_repo no_properties
rm -f release.properties
sh "$SCRIPT" >/dev/null 2>&1
check "a missing release.properties fails" "1" "$?"

make_repo no_scm_tag
printf 'completedPhase=end-release\n' > release.properties
sh "$SCRIPT" >/dev/null 2>&1
check "a release.properties without scm.tag fails" "1" "$?"

make_repo no_tag_files
find . -name 'pom.xml.tag' -delete
sh "$SCRIPT" >/dev/null 2>&1
check "no pom.xml.tag file at all fails" "1" "$?"

make_repo tag_exists
git tag v0.3.0 HEAD
sh "$SCRIPT" >/dev/null 2>&1
check "an already-existing tag fails rather than being silently kept" "1" "$?"

# The tag name comes from a file on disk; it reaches `git tag`, so a nonsense value must be
# rejected rather than passed through.
make_repo bad_tag_name
printf 'scm.tag=not a valid ref\n' > release.properties
sh "$SCRIPT" >/dev/null 2>&1
check "an invalid tag name fails" "1" "$?"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
