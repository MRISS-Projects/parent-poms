#!/bin/sh
# Tests for check-placeholders.sh. Run: sh check-placeholders.test.sh
set -u

SCRIPT="$(dirname "$0")/check-placeholders.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

expect_exit() {
  description="$1"; expected="$2"; file="$3"
  sh "$SCRIPT" "$file" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

printf 'title\n0.3.0-SNAPSHOT - RC6 - 20260918-224757\n' > "$TMP/clean.md"
expect_exit "a fully resolved README passes" 0 "$TMP/clean.md"

printf 'title\n0.3.0-SNAPSHOT - RC6 - ${timestamp}\n' > "$TMP/timestamp.md"
expect_exit "the observed \${timestamp} regression fails" 1 "$TMP/timestamp.md"

printf 'v: ${project.build.version}\n' > "$TMP/dotted.md"
expect_exit "a dotted property name fails" 1 "$TMP/dotted.md"

printf 'v: ${projectVersion2}\n' > "$TMP/camel.md"
expect_exit "a camel-case name with a digit fails" 1 "$TMP/camel.md"

printf 'cost is $100 and $ alone\n' > "$TMP/dollars.md"
expect_exit "a bare dollar sign passes" 0 "$TMP/dollars.md"

printf 'shell: ${} and ${ } are not properties\n' > "$TMP/empty.md"
expect_exit "an empty or blank brace pair passes" 0 "$TMP/empty.md"

expect_exit "a missing file fails" 1 "$TMP/does-not-exist.md"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
