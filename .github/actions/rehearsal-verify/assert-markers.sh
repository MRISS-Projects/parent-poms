#!/bin/sh
# Assert that a rehearsal announced exactly the write points its workflow declares.
#
#   assert-markers.sh <markers-file> "<declared ids, whitespace separated>"
#
# Set equality, not a count: it fails on a missing id, on a duplicate, and on an unexpected
# one. The third direction is the point. When MRISS-Projects/parent-poms#65 adds the merge
# into DEVELOP, the new write point emits an id the declared set does not contain and the
# rehearsal goes red — so a write point added without a marker is a build failure rather
# than an oversight. See specs/72-dry-run-release-workflows.md §2.3.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: assert-markers.sh <markers-file> <declared-ids>" >&2
  exit 1
fi

markers_file="$1"
declared_raw="$2"

if [ ! -f "$markers_file" ]; then
  echo "::error::rehearsal: no markers file at '$markers_file'. The rehearsal announced" \
       "nothing at all, which means either no guarded step ran or marker.sh was never" \
       "installed." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# tr rather than a `for` over an unquoted expansion: the declared set arrives from a YAML
# block scalar and may carry newlines as well as spaces.
printf '%s' "$declared_raw" | tr -s '[:space:]' '\n' | grep -v '^$' | LC_ALL=C sort -u > "$TMP/declared"

if [ ! -s "$TMP/declared" ]; then
  echo "::error::rehearsal: the declared marker set is empty. A workflow with no declared" \
       "write point cannot be rehearsed — declare its write points or do not call this." >&2
  exit 1
fi

grep -v '^[[:space:]]*$' "$markers_file" | tr -d '\r' | LC_ALL=C sort > "$TMP/emitted"
LC_ALL=C sort -u "$TMP/emitted" > "$TMP/emitted-unique"

status=0

duplicates="$(LC_ALL=C uniq -d "$TMP/emitted")"
if [ -n "$duplicates" ]; then
  echo "::error::rehearsal: duplicate marker(s) — a write point announced itself more than once:" >&2
  printf '  %s\n' $duplicates >&2
  status=1
fi

missing="$(LC_ALL=C comm -23 "$TMP/declared" "$TMP/emitted-unique")"
if [ -n "$missing" ]; then
  echo "::error::rehearsal: missing marker(s) — a declared write point did not announce itself:" >&2
  printf '  %s\n' $missing >&2
  status=1
fi

unexpected="$(LC_ALL=C comm -13 "$TMP/declared" "$TMP/emitted-unique")"
if [ -n "$unexpected" ]; then
  echo "::error::rehearsal: unexpected marker(s) — a marker was emitted that this workflow" \
       "does not declare. Add it to the declared set if the write point is intended:" >&2
  printf '  %s\n' $unexpected >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "rehearsal: all $(wc -l < "$TMP/declared" | tr -d ' ') declared write point(s) announced exactly once."
  sed 's/^/  /' "$TMP/emitted"
fi

exit "$status"
