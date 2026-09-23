#!/bin/sh
# Tests for render-properties.sh. Run: sh render-properties.test.sh
#
# The script rewrites the marker line a workflow leaves inside the <properties> of the
# github-packages profile, turning a consumer's `name=value` block into XML elements. Two
# assertions matter more than the rest and are asserted byte-for-byte rather than by grep:
# with no properties the file must come out exactly as if the feature did not exist (specs/76
# AC002), and a run that fails must leave the file untouched rather than half-rendered.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/render-properties.sh"
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

# The settings.xml as the workflows write it: the heredoc's own indentation is stripped by the
# YAML block scalar, so the marker lands at 16 columns, under <github.personal.token>.
make_settings() {
  cat > "$1" <<'SETTINGS'
<settings>
    <profiles>
        <profile>
            <id>github-packages</id>
            <properties>
                <github.personal.token>TOKEN</github.personal.token>
                <!-- MAVEN_PROPERTIES -->
            </properties>
        </profile>
    </profiles>
</settings>
SETTINGS
}

# What the same file looks like with the marker line simply deleted - the byte-for-byte target
# for every case that renders nothing.
make_settings_without_marker() {
  make_settings "$1"
  grep -v 'MAVEN_PROPERTIES' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

render() {
  MAVEN_PROPERTIES="$1" sh "$SCRIPT" "$2" >"$TMP/stdout" 2>"$TMP/stderr"
}

# --- Case 1: no properties at all -------------------------------------------------------------
make_settings "$TMP/empty-input.xml"
make_settings_without_marker "$TMP/empty-input.expected"
render '' "$TMP/empty-input.xml"
check "an empty block exits 0" 0 $?
if diff -q "$TMP/empty-input.xml" "$TMP/empty-input.expected" >/dev/null 2>&1; then
  pass "an empty block leaves the file byte-identical to one without the marker"
else
  fail "an empty block leaves the file byte-identical to one without the marker"
  diff "$TMP/empty-input.expected" "$TMP/empty-input.xml" | sed 's/^/       /'
fi

# --- Case 2: only blanks and comments ---------------------------------------------------------
make_settings "$TMP/blank-input.xml"
make_settings_without_marker "$TMP/blank-input.expected"
render '

# a comment

' "$TMP/blank-input.xml"
check "a block of blanks and comments exits 0" 0 $?
if diff -q "$TMP/blank-input.xml" "$TMP/blank-input.expected" >/dev/null 2>&1; then
  pass "a block of blanks and comments renders nothing"
else
  fail "a block of blanks and comments renders nothing"
  diff "$TMP/blank-input.expected" "$TMP/blank-input.xml" | sed 's/^/       /'
fi

# --- Case 3: one property ---------------------------------------------------------------------
make_settings "$TMP/one.xml"
render 'mongo.port=27017' "$TMP/one.xml"
check "one property exits 0" 0 $?
check "one property renders at the marker's indentation" \
  "                <mongo.port>27017</mongo.port>" \
  "$(grep 'mongo.port' "$TMP/one.xml")"
check "one property removes the marker" "" "$(grep 'MAVEN_PROPERTIES' "$TMP/one.xml" || true)"

# Byte-for-byte: the only difference from the untouched file is the marker line becoming the
# element. Anything else the script disturbs - indentation, line endings, the token line - shows
# up here rather than being missed by a targeted grep.
cat > "$TMP/one.expected" <<'SETTINGS'
<settings>
    <profiles>
        <profile>
            <id>github-packages</id>
            <properties>
                <github.personal.token>TOKEN</github.personal.token>
                <mongo.port>27017</mongo.port>
            </properties>
        </profile>
    </profiles>
</settings>
SETTINGS
if diff -q "$TMP/one.xml" "$TMP/one.expected" >/dev/null 2>&1; then
  pass "one property changes nothing but the marker line"
else
  fail "one property changes nothing but the marker line"
  diff "$TMP/one.expected" "$TMP/one.xml" | sed 's/^/       /'
fi

if [ "$failures" -eq 0 ]; then
  echo "All render-properties tests passed."
else
  echo "$failures render-properties test(s) failed."
  exit 1
fi
