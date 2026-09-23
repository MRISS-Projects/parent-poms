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

# --- Case 4: several properties, in input order -----------------------------------------------
make_settings "$TMP/four.xml"
render 'mongo.host=localhost
mongo.port=27017
mongo.user=dshuser
mongo.password=dshpass' "$TMP/four.xml"
check "four properties exit 0" 0 $?
check "four properties render in input order" \
  "mongo.host mongo.port mongo.user mongo.password" \
  "$(sed -n 's/^ *<\(mongo\.[a-z]*\)>.*/\1/p' "$TMP/four.xml" | tr '\n' ' ' | sed 's/ $//')"

# --- Case 5: surrounding whitespace -----------------------------------------------------------
make_settings "$TMP/spaces.xml"
render '   mongo.port=27017   ' "$TMP/spaces.xml"
check "a line padded with spaces renders trimmed" \
  "                <mongo.port>27017</mongo.port>" \
  "$(grep 'mongo.port' "$TMP/spaces.xml")"

# --- Case 6: CRLF input -----------------------------------------------------------------------
make_settings "$TMP/crlf.xml"
render "$(printf 'mongo.port=27017\r')" "$TMP/crlf.xml"
check "a trailing carriage return is stripped" \
  "                <mongo.port>27017</mongo.port>" \
  "$(tr -d '\r' < "$TMP/crlf.xml" | grep 'mongo.port')"
check "no carriage return survives into the file" "0" \
  "$(tr -cd '\r' < "$TMP/crlf.xml" | wc -c | tr -d ' ')"

# --- Case 7: XML-significant characters in the value ------------------------------------------
make_settings "$TMP/escape.xml"
render 'app.query=a<b & c>d' "$TMP/escape.xml"
check "a value's XML characters are escaped" \
  "                <app.query>a&lt;b &amp; c&gt;d</app.query>" \
  "$(grep 'app.query' "$TMP/escape.xml")"

make_settings "$TMP/amp.xml"
render 'app.entity=already &amp; escaped' "$TMP/amp.xml"
check "an ampersand is escaped once, not twice" \
  "                <app.entity>already &amp;amp; escaped</app.entity>" \
  "$(grep 'app.entity' "$TMP/amp.xml")"

# --- Case 8: a value containing '=' -----------------------------------------------------------
make_settings "$TMP/equals.xml"
render 'flyway.url=jdbc:postgresql://h/db?user=x&ssl=true' "$TMP/equals.xml"
check "the line splits at the first = only" \
  "                <flyway.url>jdbc:postgresql://h/db?user=x&amp;ssl=true</flyway.url>" \
  "$(grep 'flyway.url' "$TMP/equals.xml")"

# --- Case 9: an empty value -------------------------------------------------------------------
make_settings "$TMP/empty-value.xml"
render 'mongo.user=' "$TMP/empty-value.xml"
check "an empty value renders an empty element" \
  "                <mongo.user></mongo.user>" \
  "$(grep 'mongo.user' "$TMP/empty-value.xml")"

# --- Cases 10-11: invalid lines ---------------------------------------------------------------
# Each also asserts the file is untouched: a rejected block must not half-render (case 15).
expect_rejected() {
  description="$1"; block="$2"; needle="$3"
  make_settings "$TMP/reject.xml"
  cp "$TMP/reject.xml" "$TMP/reject.before"
  render "$block" "$TMP/reject.xml"
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "$description (expected a non-zero exit, got 0)"
  else
    pass "$description"
  fi
  if grep -q "$needle" "$TMP/stdout" "$TMP/stderr"; then
    pass "$description - the message names the offending line"
  else
    fail "$description - the message names the offending line"
    sed 's/^/       /' "$TMP/stdout" "$TMP/stderr"
  fi
  if diff -q "$TMP/reject.xml" "$TMP/reject.before" >/dev/null 2>&1; then
    pass "$description - the settings file is untouched"
  else
    fail "$description - the settings file is untouched"
  fi
}

expect_rejected "a line with no = is rejected" 'mongo.port' 'mongo.port'
expect_rejected "a name containing a space is rejected" 'mongo port=1' 'mongo port=1'
expect_rejected "a name containing XML syntax is rejected" 'a><b=1' 'a><b=1'
expect_rejected "a good line after a bad one still rejects the block" 'bad line
mongo.port=27017' 'bad line'

# --- Cases 12-14: the file itself -------------------------------------------------------------
make_settings "$TMP/no-marker.xml"
grep -v 'MAVEN_PROPERTIES' "$TMP/no-marker.xml" > "$TMP/no-marker.tmp"
mv "$TMP/no-marker.tmp" "$TMP/no-marker.xml"
cp "$TMP/no-marker.xml" "$TMP/no-marker.before"
render 'mongo.port=27017' "$TMP/no-marker.xml"
check "a missing marker exits non-zero" 1 $?
if diff -q "$TMP/no-marker.xml" "$TMP/no-marker.before" >/dev/null 2>&1; then
  pass "a missing marker leaves the file untouched"
else
  fail "a missing marker leaves the file untouched"
fi

make_settings "$TMP/two-markers.xml"
sed 's/.*MAVEN_PROPERTIES.*/&\n&/' "$TMP/two-markers.xml" > "$TMP/two-markers.tmp"
mv "$TMP/two-markers.tmp" "$TMP/two-markers.xml"
render 'mongo.port=27017' "$TMP/two-markers.xml"
check "a duplicated marker exits non-zero" 1 $?

render 'mongo.port=27017' "$TMP/does-not-exist.xml"
check "a missing settings file exits non-zero" 1 $?

sh "$SCRIPT" >/dev/null 2>&1
check "no settings file argument exits non-zero" 1 $?

if [ "$failures" -eq 0 ]; then
  echo "All render-properties tests passed."
else
  echo "$failures render-properties test(s) failed."
  exit 1
fi
