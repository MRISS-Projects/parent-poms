#!/bin/sh
# Tests for assert-markers.sh. Run: sh assert-markers.test.sh
#
# The check is set equality, not a count. specs/72 §2.3 chose that deliberately: it is
# stronger than #72's AC003 asks for, and it buys the property that matters afterwards —
# when #65 adds the merge into DEVELOP it must add `merge-to-develop` to the declared set,
# or the rehearsal fails. A write point added without a marker becomes a build failure
# rather than an oversight. So all three directions are tested, not just the missing one.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/assert-markers.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

DECLARED='release-prepare release-perform-deploy merge-to-master site-deploy commit-readme'

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

check_exit() {
  description="$1"; expected="$2"; file="$3"; declared="$4"
  sh "$SCRIPT" "$file" "$declared" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    pass "$description"
  else
    fail "$description (expected exit $expected, got $actual)"
  fi
}

check_says() {
  description="$1"; needle="$2"; file="$3"; declared="$4"
  output="$(sh "$SCRIPT" "$file" "$declared" 2>&1)"
  if printf '%s' "$output" | grep -qF "$needle"; then
    pass "$description"
  else
    fail "$description"
    printf '       expected output to contain: %s\n' "$needle"
    printf '       actual output:\n%s\n' "$output"
  fi
}

write_markers() {
  file="$TMP/$1"; shift
  : > "$file"
  for id in "$@"; do echo "$id" >> "$file"; done
  echo "$file"
}

# --- equality ----------------------------------------------------------------------

exact="$(write_markers exact release-prepare release-perform-deploy merge-to-master site-deploy commit-readme)"
check_exit "the declared set, emitted once each, passes" 0 "$exact" "$DECLARED"

shuffled="$(write_markers shuffled commit-readme site-deploy release-prepare merge-to-master release-perform-deploy)"
check_exit "order does not matter" 0 "$shuffled" "$DECLARED"

# Whitespace and blank lines survive round-tripping through $GITHUB_ENV and YAML block
# scalars more often than one would like; neither should be mistaken for an id.
padded="$(write_markers padded release-prepare '' release-perform-deploy merge-to-master site-deploy '' commit-readme)"
check_exit "blank lines in the markers file are ignored" 0 "$padded" "$DECLARED"

check_exit "extra whitespace in the declared list is ignored" 0 "$exact" \
  "  release-prepare   release-perform-deploy
   merge-to-master site-deploy   commit-readme  "

# --- missing -----------------------------------------------------------------------

missing="$(write_markers missing release-prepare release-perform-deploy merge-to-master site-deploy)"
check_exit "a missing id fails" 1 "$missing" "$DECLARED"
check_says "a missing id is named" "commit-readme" "$missing" "$DECLARED"
check_says "a missing id is reported as missing" "missing" "$missing" "$DECLARED"

# --- duplicate ---------------------------------------------------------------------

duplicate="$(write_markers duplicate release-prepare release-prepare release-perform-deploy merge-to-master site-deploy commit-readme)"
check_exit "a duplicate id fails" 1 "$duplicate" "$DECLARED"
check_says "a duplicate id is named" "release-prepare" "$duplicate" "$DECLARED"
check_says "a duplicate id is reported as a duplicate" "duplicate" "$duplicate" "$DECLARED"

# --- unexpected --------------------------------------------------------------------

unexpected="$(write_markers unexpected release-prepare release-perform-deploy merge-to-master site-deploy commit-readme merge-to-develop)"
check_exit "an unexpected id fails" 1 "$unexpected" "$DECLARED"
check_says "an unexpected id is named" "merge-to-develop" "$unexpected" "$DECLARED"
check_says "an unexpected id is reported as unexpected" "unexpected" "$unexpected" "$DECLARED"

# --- degenerate inputs -------------------------------------------------------------

empty="$(write_markers empty)"
check_exit "an empty markers file fails against a non-empty declared set" 1 "$empty" "$DECLARED"

check_exit "an absent markers file fails" 1 "$TMP/does-not-exist" "$DECLARED"

# A workflow that declares no write point is a bug in the workflow, not a rehearsal that
# has nothing to prove.
check_exit "an empty declared set fails" 1 "$exact" ""

check_exit "a missing argument fails" 1 "$exact" ""

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
