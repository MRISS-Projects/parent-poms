#!/bin/sh
# Tests for assert-reactor-version.sh. Run: sh assert-reactor-version.test.sh
#
# The fixtures are real "[INFO] Building …" lines from the MRISS-Projects/dsh 13-module
# reactor. Two cases are load-bearing and neither is optional:
#
#   - Case 2 is the regression test for #69. It is the shape run 35662168807 produced:
#     `versions:set -DprocessAllModules=true` moved the root POM to the hotfix version and
#     left the other twelve naming the old parent.
#   - Case 6 is the one a naive `grep Building` gets wrong. "Building jar:" is a packaging
#     message from a different plugin, not a module of the reactor.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/assert-reactor-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

check_exit() {
  description="$1"; expected="$2"; version="$3"; file="$4"
  sh "$SCRIPT" "$version" "$file" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then pass "$description"
  else fail "$description (expected exit $expected, got $actual)"; fi
}

check_says() {
  description="$1"; needle="$2"; version="$3"; file="$4"
  output="$(sh "$SCRIPT" "$version" "$file" 2>&1)"
  if printf '%s' "$output" | grep -qF "$needle"; then pass "$description"
  else
    fail "$description"
    printf '       expected output to contain: %s\n' "$needle"
    printf '       actual output:\n%s\n' "$output"
  fi
}

# The dsh reactor as Maven logs it, in reactor order. $1 is the version on the root module,
# $2 the version on the other twelve — separate parameters so the #69 shape, where they
# differ, is a fixture rather than a post-hoc edit.
emit_reactor() {
  root="$1"; modules="$2"
  echo "[INFO] Scanning for projects..."
  echo "[INFO] Building DSH - Document Smart Highlights $root           [1/13]"
  echo "[INFO] Building DSH Test Data Set $modules                      [2/13]"
  echo "[INFO] Building dsh-data $modules                               [3/13]"
  echo "[INFO] Building DSH REST API $modules                           [4/13]"
  echo "[INFO] Building DSH - SOLR Extensions/Plugins $modules          [5/13]"
  echo "[INFO] Building SOLR - Terms Vector Orderer $modules            [6/13]"
  echo "[INFO] Building SOLR - Advanced Numbers Filter $modules         [7/13]"
  echo "[INFO] Building DSH - Document Indexer Worker $modules          [8/13]"
  echo "[INFO] Building DSH - Document Analyzer $modules                [9/13]"
  echo "[INFO] Building DSH - Document Keyword Extractor $modules      [10/13]"
  echo "[INFO] Building dsh-top-sentences-extractor $modules           [11/13]"
  echo "[INFO] Building DSH - Document Processor Worker $modules       [12/13]"
  echo "[INFO] Building DSH Coverage Report Aggregation Module $modules [13/13]"
  echo "[INFO] BUILD SUCCESS"
}

write_log() {
  file="$TMP/$1.log"; shift
  emit_reactor "$@" > "$file"
  printf '%s' "$file"
}

# --- 1. the reactor the fix is supposed to produce -----------------------------------

good="$(write_log good 0.3.1-SNAPSHOT 0.3.1-SNAPSHOT)"
check_exit "a reactor uniformly at the expected version passes" 0 0.3.1-SNAPSHOT "$good"
check_says "it reports how many modules it checked" \
  "all 13 module(s) are at 0.3.1-SNAPSHOT" 0.3.1-SNAPSHOT "$good"

# --- 2. the #69 regression -----------------------------------------------------------

split="$(write_log hotfix-root-only 0.3.1-SNAPSHOT 0.3.0)"
check_exit "the #69 shape — root moved, twelve modules left behind — fails" 1 0.3.1-SNAPSHOT "$split"
check_says "it counts the modules left behind" "12 of 13" 0.3.1-SNAPSHOT "$split"
check_says "it names an offending module" "dsh-data" 0.3.1-SNAPSHOT "$split"
check_says "it reports the version the offender is actually at" "0.3.0" 0.3.1-SNAPSHOT "$split"

# --- 3. a single skewed module -------------------------------------------------------

one_bad="$TMP/one-bad.log"
sed 's/^\[INFO\] Building dsh-data 0\.3\.1-SNAPSHOT/[INFO] Building dsh-data 0.2.9-SNAPSHOT/' \
  "$good" > "$one_bad"
check_exit "one module at a wrong version fails" 1 0.3.1-SNAPSHOT "$one_bad"
check_says "a lone offender is counted as one" "1 of 13" 0.3.1-SNAPSHOT "$one_bad"

# --- 4. a single-module reactor prints no [n/m] suffix -------------------------------

single="$TMP/single-module.log"
printf '%s\n' \
  '[INFO] Scanning for projects...' \
  '[INFO] Building dsh-data 0.3.1-SNAPSHOT' \
  '[INFO] BUILD SUCCESS' > "$single"
check_exit "a single-module reactor, with no progress suffix, passes" 0 0.3.1-SNAPSHOT "$single"
check_says "the missing suffix does not corrupt the count" \
  "all 1 module(s)" 0.3.1-SNAPSHOT "$single"

# --- 5. a log that proves nothing must not pass --------------------------------------

silent="$TMP/no-building-line.log"
printf '%s\n' \
  '[INFO] Scanning for projects...' \
  '[ERROR] The goal you specified requires a project to execute but there is no POM' > "$silent"
check_exit "a log with no Building line fails rather than vacuously passing" 1 0.3.1-SNAPSHOT "$silent"
check_says "it says why it could not check" "holds no" 0.3.1-SNAPSHOT "$silent"

# --- 6. packaging messages are not modules -------------------------------------------

with_jar="$TMP/with-jar.log"
cp "$good" "$with_jar"
echo '[INFO] Building jar: /home/runner/work/dsh/dsh-data/target/dsh-data-0.3.1-SNAPSHOT.jar' \
  >> "$with_jar"
check_exit "'Building jar:' is not counted as a module" 0 0.3.1-SNAPSHOT "$with_jar"
check_says "the module count ignores the packaging line" "all 13" 0.3.1-SNAPSHOT "$with_jar"

# --- 7 and 8. misuse -----------------------------------------------------------------

sh "$SCRIPT" 0.3.1-SNAPSHOT >/dev/null 2>&1
actual=$?
if [ "$actual" -eq 1 ]; then pass "one argument instead of two fails"
else fail "one argument instead of two fails (expected exit 1, got $actual)"; fi

output="$(sh "$SCRIPT" 0.3.1-SNAPSHOT 2>&1)"
if printf '%s' "$output" | grep -qF "usage:"; then pass "misuse prints a usage line"
else
  fail "misuse prints a usage line"
  printf '       actual output:\n%s\n' "$output"
fi

check_exit "a log path that does not exist fails" 1 0.3.1-SNAPSHOT "$TMP/does-not-exist.log"
check_says "the absent log is named as the reason" "no Maven log" 0.3.1-SNAPSHOT \
  "$TMP/does-not-exist.log"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
