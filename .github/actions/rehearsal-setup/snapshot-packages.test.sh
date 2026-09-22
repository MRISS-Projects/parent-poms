#!/bin/sh
# Tests for snapshot-packages.sh. Run: sh snapshot-packages.test.sh   (needs jq on PATH)
#
# The live registry cannot be tested here — which endpoint GitHub serves, pagination, token
# scope. Those are what the demonstration rehearsals measure. But everything this script decides
# on its own can be, and PR #77's review found two such defects: F1, a name filter that dropped
# any package whose name did not contain the repository name; and F4, a fallback that moved the
# package listing to /users/ while every versions request stayed on /orgs/. `gh` is replaced by a
# stub on PATH that records each URL it is asked for.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/snapshot-packages.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# --- the stub gh ---------------------------------------------------------------------
#
# gh api --paginate <url> [--jq <expr>]
#   <base>/packages?package_type=maven       -> STUB_PACKAGES (JSON)
#   <base>/packages/maven/<name>/versions    -> the versions of <name> listed in STUB_VERSIONS
# STUB_FAIL_ORGS_LIST=1 fails the /orgs/ listing only, as a 404 would, while /users/ still
# answers — the one situation in which a fallback would be taken. STUB_FAIL_VERSIONS=<name>
# fails that package's versions request.
mkdir -p "$TMP/bin"

# A native Windows jq.exe writes CRLF, so every package name would arrive with a trailing \r and
# never equal anything. That is a property of the development box, not of the script: the
# Ubuntu runners' jq writes LF. The shim strips it here rather than teaching production code to
# expect a quirk it will never meet, and is a no-op wherever there is no \r to strip.
REAL_JQ="$(command -v jq)" || { echo "snapshot-packages.test.sh needs jq on PATH" >&2; exit 1; }
printf '#!/bin/sh\n"%s" "$@" | tr -d '"'"'\\r'"'"'\n' "$REAL_JQ" > "$TMP/bin/jq"
chmod +x "$TMP/bin/jq"

cat > "$TMP/bin/gh" <<'STUB'
#!/bin/sh
url="$3"
echo "$url" >> "$STUB_LOG"
case "$url" in
  /orgs/*/packages\?package_type=maven)
    [ "${STUB_FAIL_ORGS_LIST:-}" = 1 ] && { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    printf '%s' "$STUB_PACKAGES" ;;
  /users/*/packages\?package_type=maven)
    printf '%s' "$STUB_PACKAGES" ;;
  */packages/maven/*/versions)
    name="${url#*/packages/maven/}"; name="${name%/versions}"
    [ "$name" = "${STUB_FAIL_VERSIONS:-}" ] && { echo "gh: Server Error (HTTP 500)" >&2; exit 1; }
    printf '%s\n' "$STUB_VERSIONS" | awk -v n="$name" '$1 == n { print $2 }' ;;
  *) echo "stub gh: unexpected url: $url" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gh"

# run_case <name> ; sets OUT, RC, LOG and SNAPSHOT for the case
run_case() {
  LOG="$TMP/$1.urls"; SNAPSHOT="$TMP/$1.snapshot"
  : > "$LOG"
  OUT="$(PATH="$TMP/bin:$PATH" STUB_LOG="$LOG" bash "$SCRIPT" dsh "$SNAPSHOT" 2>&1)"
  RC=$?
}

check() {
  if [ "$2" = "$3" ]; then pass "$1"; else
    fail "$1"; printf '       expected: %s\n       actual:   %s\n' "$2" "$3"
    printf '%s\n' "$OUT" | sed 's/^/       | /'
  fi
}

TWO_PACKAGES='[{"name":"com.mriss.products.dsh"},{"name":"com.example.unrelated.core"}]'
TWO_VERSIONS='com.mriss.products.dsh 0.2.4
com.mriss.products.dsh 0.2.3
com.example.unrelated.core 1.0.0'

# --- F1: every package, whatever it is called ----------------------------------------

STUB_PACKAGES="$TWO_PACKAGES" STUB_VERSIONS="$TWO_VERSIONS"; export STUB_PACKAGES STUB_VERSIONS
run_case every_package
check "exits 0 on a healthy registry" 0 "$RC"
check "includes a package whose name does not contain the repository name" 1 \
  "$(grep -c '^com.example.unrelated.core 1.0.0$' "$SNAPSHOT" 2>/dev/null)"
check "records one 'name version' line per version, sorted" \
  "com.example.unrelated.core 1.0.0|com.mriss.products.dsh 0.2.3|com.mriss.products.dsh 0.2.4" \
  "$(tr '\n' '|' < "$SNAPSHOT" 2>/dev/null | sed 's/|$//')"

# --- F4: one endpoint, and no fallback to a different one ----------------------------

run_case one_base
check "every request goes to the organisation endpoint" 0 \
  "$(grep -vc '^/orgs/MRISS-Projects/' "$LOG")"

# The situation in which the old fallback was taken: /orgs/ refuses the listing and /users/
# would answer it. The old script then listed from /users/ and asked /orgs/ for every version.
STUB_FAIL_ORGS_LIST=1; export STUB_FAIL_ORGS_LIST
run_case orgs_refuses
unset STUB_FAIL_ORGS_LIST
check "a refused listing fails the snapshot" 1 "$RC"
check "a refused listing never falls through to another endpoint" 0 \
  "$(grep -c '^/users/' "$LOG")"

# --- failing hard --------------------------------------------------------------------

STUB_FAIL_VERSIONS=com.example.unrelated.core; export STUB_FAIL_VERSIONS
run_case versions_fail
unset STUB_FAIL_VERSIONS
check "a failed versions request fails the snapshot" 1 "$RC"

# An organisation with no Maven packages is a legitimate, empty registry — not a failed read.
# A deploy into it adds the first line, which the before/after diff catches.
STUB_PACKAGES='[]'; export STUB_PACKAGES
run_case empty_org
check "an organisation with no packages is an empty snapshot, not a failure" 0 "$RC"
check "an organisation with no packages records nothing" 0 "$(wc -l < "$SNAPSHOT" | tr -d ' ')"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
