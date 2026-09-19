#!/bin/sh
# Fail if a generated file still contains an unresolved Maven property placeholder.
#
# maven-resources-plugin leaves an unresolvable ${...} as literal text rather than
# substituting blank, which is what makes the MRISS-Projects/parent-poms#71 regression
# visible. Property names in this estate contain dots (${project.build.version}), so the
# pattern allows them; ${} and ${ } are excluded because they are not property references
# and appear in shell snippets.
#
# The pattern deliberately matches any ${NAME}, not only names this estate uses today. A
# consuming project that legitimately wants a literal ${...} in its README source must
# escape it for maven-resources-plugin anyway, or the filtered output would differ from the
# source. If that ever becomes a real constraint, add an allowlist here rather than
# loosening the pattern.
set -eu

file="${1:?usage: check-placeholders.sh <file>}"

if [ ! -f "$file" ]; then
  echo "check-placeholders: no such file: $file" >&2
  exit 1
fi

# grep exits 0 on a match, 1 on no match, and >=2 on an error such as an unreadable file.
# Collapsing >=2 into the no-match branch would report success without having inspected the
# file, so the three cases are separated. (The >=2 branch has no unit test: the NTFS
# development box cannot produce an unreadable file via chmod.)
set +e
match=$(grep -nE '\$\{[A-Za-z0-9_.-]+\}' "$file")
rc=$?
set -e

if [ "$rc" -ge 2 ]; then
  echo "check-placeholders: could not read $file (grep exit $rc); refusing to pass it" >&2
  exit 1
fi

if [ "$rc" -eq 0 ]; then
  echo "check-placeholders: unresolved placeholder in $file:" >&2
  echo "$match" >&2
  exit 1
fi

exit 0
