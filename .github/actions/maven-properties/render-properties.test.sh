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
#
# The message must locate the bad line without quoting it. PR #79 review, thread 4082708674: the
# block is where a consumer puts its passwords, so echoing a rejected line into the Actions log
# publishes one. The earlier version of this helper asserted the opposite - that the message
# named the offending line - which is how the leak got written and stayed green.
expect_rejected() {
  description="$1"; block="$2"; lineno="$3"
  make_settings "$TMP/reject.xml"
  cp "$TMP/reject.xml" "$TMP/reject.before"
  render "$block" "$TMP/reject.xml"
  status=$?
  if [ "$status" -eq 0 ]; then
    fail "$description (expected a non-zero exit, got 0)"
  else
    pass "$description"
  fi
  if grep -q "line $lineno" "$TMP/stdout" "$TMP/stderr"; then
    pass "$description - the message names the line number"
  else
    fail "$description - the message names the line number"
    sed 's/^/       /' "$TMP/stdout" "$TMP/stderr"
  fi
  if diff -q "$TMP/reject.xml" "$TMP/reject.before" >/dev/null 2>&1; then
    pass "$description - the settings file is untouched"
  else
    fail "$description - the settings file is untouched"
  fi
}

expect_rejected "a line with no = is rejected" 'mongo.port' 1
expect_rejected "a name containing a space is rejected" 'mongo port=1' 1
expect_rejected "a name containing XML syntax is rejected" 'a><b=1' 1
expect_rejected "a good line after a bad one still rejects the block" 'bad line
mongo.port=27017' 1

# A name that is not a valid XML element name renders a tag no parser accepts, so the renderer
# would report success and Maven would fail later on an unparsable settings.xml. PR #79 review,
# thread 4082708779.
expect_rejected "a name starting with a digit is rejected" '123foo=bar' 1
expect_rejected "a name starting with a dot is rejected" '.foo=bar' 1
expect_rejected "a name starting with a hyphen is rejected" '-foo=bar' 1

# XML permits a leading underscore, so rejecting it would be over-tightening.
make_settings "$TMP/underscore.xml"
render '_foo=bar' "$TMP/underscore.xml"
check "a name starting with an underscore is accepted" 0 $?
check "the underscore name renders" \
  "                <_foo>bar</_foo>" \
  "$(grep '_foo' "$TMP/underscore.xml")"

# The whole point of the message change: a rejected line's value never reaches the log.
make_settings "$TMP/secret.xml"
render 'mongo password=supersecret' "$TMP/secret.xml"
check "a rejected line exits non-zero" 1 $?
if grep -q 'supersecret' "$TMP/stdout" "$TMP/stderr"; then
  fail "a rejected line's value never reaches the log"
  sed 's/^/       /' "$TMP/stdout" "$TMP/stderr"
else
  pass "a rejected line's value never reaches the log"
fi

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

# The marker contract is "exactly one line whose trimmed content is the marker". Substring
# matching accepted a line with trailing text, rendered at column 0 because the indentation
# lookup found nothing, and destroyed the trailing text. PR #79 review, thread 4082708735.
make_settings "$TMP/trailing.xml"
sed 's|<!-- MAVEN_PROPERTIES -->|<!-- MAVEN_PROPERTIES --> trailing|' "$TMP/trailing.xml" > "$TMP/trailing.tmp"
mv "$TMP/trailing.tmp" "$TMP/trailing.xml"
cp "$TMP/trailing.xml" "$TMP/trailing.before"
render 'mongo.port=27017' "$TMP/trailing.xml"
check "a marker line with trailing content exits non-zero" 1 $?
if diff -q "$TMP/trailing.xml" "$TMP/trailing.before" >/dev/null 2>&1; then
  pass "a marker line with trailing content leaves the file untouched"
else
  fail "a marker line with trailing content leaves the file untouched"
  diff "$TMP/trailing.before" "$TMP/trailing.xml" | sed 's/^/       /'
fi

# An unrelated line that merely mentions the marker is not a marker either - and with a real
# marker present, it must not turn a valid file into a "duplicated marker" failure.
make_settings "$TMP/mention.xml"
awk '{ print } /<github.personal.token>/ { print "                <!-- see <!-- MAVEN_PROPERTIES --> in the release workflow -->" }' \
  "$TMP/mention.xml" > "$TMP/mention.tmp"
mv "$TMP/mention.tmp" "$TMP/mention.xml"
render 'mongo.port=27017' "$TMP/mention.xml"
check "a line merely mentioning the marker is not counted as one" 0 $?
check "the real marker is still the one replaced" \
  "                <mongo.port>27017</mongo.port>" \
  "$(grep '<mongo.port>' "$TMP/mention.xml")"

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
