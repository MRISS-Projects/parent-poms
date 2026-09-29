#!/bin/sh
# Tests for check-placeholders.sh. Run: sh check-placeholders.test.sh
set -u

SCRIPT="$(dirname "$0")/check-placeholders.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

# expect_exit <description> <expected exit> <generated file> [<source file>]
# The source argument is omitted, not passed empty, when a case tests its absence.
expect_exit() {
  description="$1"; expected="$2"; file="$3"
  if [ "$#" -ge 4 ]; then
    sh "$SCRIPT" "$file" "$4" >/dev/null 2>&1
  else
    sh "$SCRIPT" "$file" >/dev/null 2>&1
  fi
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

# A README source using every placeholder the cases below leave unresolved, the way the
# estate's src/site/markdown/README.md uses them.
printf '# t\n${project.build.version} - ${timestamp}\n${projectVersion2}\n## Release Notes\n${issues.text.list}\n' \
  > "$TMP/source.md"

printf 'title\n0.3.0-SNAPSHOT - RC6 - 20260918-224757\n' > "$TMP/clean.md"
expect_exit "a fully resolved README passes" 0 "$TMP/clean.md" "$TMP/source.md"

printf 'title\n0.3.0-SNAPSHOT - RC6 - ${timestamp}\n' > "$TMP/timestamp.md"
expect_exit "the observed \${timestamp} regression fails" 1 "$TMP/timestamp.md" "$TMP/source.md"

printf 'v: ${project.build.version}\n' > "$TMP/dotted.md"
expect_exit "a dotted property name fails" 1 "$TMP/dotted.md" "$TMP/source.md"

printf 'v: ${projectVersion2}\n' > "$TMP/camel.md"
expect_exit "a camel-case name with a digit fails" 1 "$TMP/camel.md" "$TMP/source.md"

printf '## Release Notes\n${issues.text.list}\n' > "$TMP/no-issues.md"
expect_exit "an unresolved \${issues.text.list} fails" 1 "$TMP/no-issues.md" "$TMP/source.md"

printf 'cost is $100 and $ alone\n' > "$TMP/dollars.md"
expect_exit "a bare dollar sign passes" 0 "$TMP/dollars.md" "$TMP/source.md"

printf 'shell: ${} and ${ } are not properties\n' > "$TMP/empty.md"
expect_exit "an empty or blank brace pair passes" 0 "$TMP/empty.md" "$TMP/source.md"

# #93: the line that failed DSH staging run 36574918380. The ${...} is the literal title of
# DSH #115, substituted in through ${issues.text.list}; the source never had it.
printf '## Release Notes\n| [115](https://github.com/MRISS-Projects/dsh/issues/115) | bug | [STORY] version.properties ships an unresolved ${jenkins.build.number} in two modules | null | mriss | 9/28/26 |\n' \
  > "$TMP/issue-title.md"
expect_exit "a literal \${name} from substituted text, absent from the source, passes" 0 \
  "$TMP/issue-title.md" "$TMP/source.md"

printf 'v ${timestamp}\n## Release Notes\n| 115 | ${jenkins.build.number} |\n' > "$TMP/both.md"
expect_exit "an unresolved source placeholder fails beside a substituted literal" 1 \
  "$TMP/both.md" "$TMP/source.md"

expect_exit "a missing file fails" 1 "$TMP/does-not-exist.md" "$TMP/source.md"

mkdir -p "$TMP/adir"
expect_exit "a directory argument fails" 1 "$TMP/adir" "$TMP/source.md"

expect_exit "no argument fails" 1 ""

expect_exit "a missing source fails" 1 "$TMP/clean.md" "$TMP/no-such-source.md"

expect_exit "a directory as the source fails" 1 "$TMP/clean.md" "$TMP/adir"

expect_exit "no source argument fails" 1 "$TMP/clean.md"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
