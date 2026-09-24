#!/bin/sh
# Assert that every module of a Maven reactor is at the expected version.
#
#   assert-reactor-version.sh <expected-version> <maven-log>
#
# The input is the log of a Maven run over the whole reactor; each module contributes one
# "[INFO] Building <name> <version> [n/m]" line. Parsing that is deliberate: it reports the
# version Maven resolved for each module, which is what the hotfix branch will carry, rather
# than what any single pom.xml happens to say. specs/69-set-hotfix-version-on-every-module.md
# §3 has the reasoning, and #69 has the failure it exists to stop.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: assert-reactor-version.sh <expected-version> <maven-log>" >&2
  exit 1
fi

expected="$1"
log="$2"

if [ ! -f "$log" ]; then
  echo "::error::no Maven log at '$log'." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The [n/m] progress suffix is absent in a single-module reactor, so it is stripped only when
# present. "Building jar:", "Building tar.gz:" and their siblings are packaging messages from a
# different plugin: a validate-only run never reaches them, and skipping them costs nothing if
# some caller ever runs a later phase.
#
# The filter matches the SHAPE of those messages — a lowercase packaging token, then a colon
# and a space — rather than enumerating types. An enumeration was tried first and missed tar,
# tar.gz, tar.bz2 and sar; any list would go stale the next time a packaging is added, and a
# missed one is read as a module named "Building" at a version of "/x/y.tar.gz". A module line
# cannot collide with this: it carries a version after the name, never a colon.
sed -n 's/^\[INFO\] Building \(.*\)$/\1/p' "$log" \
  | grep -vE '^[a-z][a-z0-9.-]*: ' \
  | sed -e 's/[[:space:]]*\[[0-9][0-9]*\/[0-9][0-9]*\][[:space:]]*$//' \
  > "$TMP/modules"

if [ ! -s "$TMP/modules" ]; then
  echo "::error::'$log' holds no '[INFO] Building …' line. Either the run never reached a" \
       "module or the log is not a Maven reactor log — either way the versions are unverified" \
       "and this must not pass." >&2
  exit 1
fi

count=0
: > "$TMP/offenders"
while IFS= read -r line; do
  count=$((count + 1))
  version="${line##* }"
  name="${line% *}"
  if [ "$version" != "$expected" ]; then
    printf '  %s is at %s\n' "$name" "$version" >> "$TMP/offenders"
  fi
done < "$TMP/modules"

if [ -s "$TMP/offenders" ]; then
  bad="$(wc -l < "$TMP/offenders" | tr -d ' ')"
  echo "::error::$bad of $count module(s) are not at $expected:" >&2
  cat "$TMP/offenders" >&2
  echo "Committing this would leave the branch with a mixed-version reactor. See #69." >&2
  exit 1
fi

echo "all $count module(s) are at $expected"
