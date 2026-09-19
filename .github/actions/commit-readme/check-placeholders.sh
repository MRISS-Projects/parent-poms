#!/bin/sh
# Fail if a generated file still contains an unresolved Maven property placeholder.
#
# maven-resources-plugin leaves an unresolvable ${...} as literal text rather than
# substituting blank, which is what makes the MRISS-Projects/parent-poms#71 regression
# visible. Property names in this estate contain dots (${project.build.version}), so the
# pattern allows them; ${} and ${ } are excluded because they are not property references
# and appear in shell snippets.
set -eu

file="${1:?usage: check-placeholders.sh <file>}"

if [ ! -f "$file" ]; then
  echo "check-placeholders: no such file: $file" >&2
  exit 1
fi

if match=$(grep -nE '\$\{[A-Za-z0-9_.-]+\}' "$file"); then
  echo "check-placeholders: unresolved placeholder in $file:" >&2
  echo "$match" >&2
  exit 1
fi

exit 0
