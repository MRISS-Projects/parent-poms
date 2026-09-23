#!/bin/sh
# Render a consumer's `name=value` block into the <properties> of the github-packages profile
# in a settings.xml the calling workflow has already written.
#
# Usage: MAVEN_PROPERTIES="<block>" render-properties.sh <settings-file>
#
# The block arrives in the environment rather than as an argument: it is multi-line, it may
# contain spaces and shell metacharacters, and a consumer's password is a plausible value.
#
# The workflow's settings heredoc is quoted, so it cannot interpolate anything - it leaves a
# marker comment inside <properties> and this script replaces that line. With no properties to
# render the marker is deleted, which leaves the file exactly as it would have been without this
# feature at all. See specs/76-consumer-supplied-maven-properties.md.
set -eu

MARKER='<!-- MAVEN_PROPERTIES -->'

SETTINGS="${1:-}"
if [ -z "$SETTINGS" ]; then
  echo "::error::render-properties.sh: no settings file given"
  exit 1
fi
if [ ! -f "$SETTINGS" ]; then
  echo "::error::render-properties.sh: $SETTINGS does not exist"
  exit 1
fi

markers="$(grep -c -- "$MARKER" "$SETTINGS" || true)"
if [ "$markers" -ne 1 ]; then
  echo "::error::render-properties.sh: expected exactly one '$MARKER' line in $SETTINGS, found $markers"
  exit 1
fi

# Render at the marker's own indentation rather than a hard-coded width, so the script stays
# correct if a workflow ever indents its settings heredoc differently.
indent="$(sed -n "s/^\\([ 	]*\\)$MARKER[ 	]*\$/\\1/p" "$SETTINGS")"

rendered="$SETTINGS.rendered.$$"
count_file="$SETTINGS.count.$$"
input="$SETTINGS.input.$$"
: > "$rendered"
: > "$count_file"
printf '%s\n' "${MAVEN_PROPERTIES:-}" > "$input"

# Read from a file, not a pipe: a pipeline would put this loop in a subshell, where `exit 1` on
# a rejected line would end the subshell and let the script carry on and render the rest.
lineno=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  line="$(printf '%s' "$line" | tr -d '\r' | sed 's/^[ 	]*//; s/[ 	]*$//')"
  [ -n "$line" ] || continue
  case "$line" in '#'*) continue ;; esac

  # A name becomes an XML tag in a file the release build trusts, so it is rejected rather than
  # escaped. The alphabet is what Maven property names actually use.
  if ! printf '%s' "$line" | grep -Eq '^[A-Za-z0-9._-]+='; then
    echo "::error::render-properties.sh: line $lineno is not a valid name=value pair: $line"
    rm -f "$rendered" "$count_file" "$input"
    exit 1
  fi

  name="${line%%=*}"
  value="${line#*=}"
  # & first, or the escapes introduced by < and > would be escaped again.
  value="$(printf '%s' "$value" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"

  printf '%s<%s>%s</%s>\n' "$indent" "$name" "$value" "$name" >> "$rendered"
  printf '%s\n' "$name" >> "$count_file"
done < "$input"

# Write beside the target and move into place, so a failure above never leaves a half-rendered
# settings.xml - valid XML with properties missing, which fails later and further away.
awk -v marker="$MARKER" -v rendered="$rendered" '
  index($0, marker) > 0 {
    while ((getline line < rendered) > 0) print line
    close(rendered)
    next
  }
  { print }
' "$SETTINGS" > "$SETTINGS.new"
mv "$SETTINGS.new" "$SETTINGS"

n="$(grep -c '' "$count_file" || true)"
if [ "$n" -eq 0 ]; then
  echo "render-properties: no properties supplied; settings.xml left as written."
else
  [ "$n" -eq 1 ] && noun="property" || noun="properties"
  # Names only. A value may be a password, and dsh passes one today.
  echo "render-properties: rendered $n $noun into $SETTINGS:"
  sed 's/^/  - /' "$count_file"
fi

rm -f "$rendered" "$count_file" "$input"
