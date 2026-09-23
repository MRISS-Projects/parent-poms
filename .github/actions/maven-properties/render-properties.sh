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
# The contract is a line whose *trimmed content* is exactly the marker, so both the count and the
# rewrite anchor on it. Substring matching accepted `<!-- MAVEN_PROPERTIES --> trailing` as the
# marker, rendered at column 0 because the indentation lookup below found nothing, and destroyed
# the trailing text; it also counted an unrelated line that merely mentioned the marker.
MARKER_RE='^[[:blank:]]*<!-- MAVEN_PROPERTIES -->[[:blank:]]*$'

SETTINGS="${1:-}"
if [ -z "$SETTINGS" ]; then
  echo "::error::render-properties.sh: no settings file given"
  exit 1
fi
if [ ! -f "$SETTINGS" ]; then
  echo "::error::render-properties.sh: $SETTINGS does not exist"
  exit 1
fi

markers="$(grep -cE "$MARKER_RE" "$SETTINGS" || true)"
if [ "$markers" -ne 1 ]; then
  echo "::error::render-properties.sh: expected exactly one line whose content is '$MARKER' in $SETTINGS, found $markers"
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
  # escaped. The start character must be one XML permits, or the tag is unparsable and Maven
  # fails later on a settings.xml this script reported success for — `<123foo>` is not a name.
  # A leading underscore is valid XML and stays allowed.
  #
  # The message gives the line number and nothing else: this block is where a consumer puts its
  # passwords, so quoting the rejected line would publish one into the Actions log.
  if ! printf '%s' "$line" | grep -Eq '^[A-Za-z_][A-Za-z0-9._-]*='; then
    echo "::error::render-properties.sh: line $lineno of maven_properties is not a valid name=value pair, or its name is not a valid XML element name (it must start with a letter or underscore). The line is not quoted here because it may contain a secret."
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
awk -v marker_re="$MARKER_RE" -v rendered="$rendered" '
  $0 ~ marker_re {
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
