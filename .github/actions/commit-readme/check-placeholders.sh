#!/bin/sh
# Fail if a generated file still contains an unresolved Maven property placeholder.
#
# maven-resources-plugin leaves an unresolvable ${...} as literal text rather than
# substituting blank, which is what makes the MRISS-Projects/parent-poms#71 regression
# visible. Property names in this estate contain dots (${project.build.version}), so the
# pattern allows them; ${} and ${ } are excluded because they are not property references
# and appear in shell snippets.
#
# A ${name} in the generated file is unresolved only if the source it was filtered from has
# the same ${name}. Filtering either replaces a placeholder or leaves it as it was, so every
# unresolved one is still in the source. A ${name} found only in the generated file came in
# through a property *value*, which is never re-filtered: #93 was DSH #115's issue title,
# "... unresolved ${jenkins.build.number} ...", written into the release notes through
# ${issues.text.list}. Rejecting it would make an issue title able to block a release.
#
# Known limit: a value quoting a placeholder the source also uses is still reported. That
# errs towards a false alarm, never a missed placeholder; reword the value. If it ever
# becomes a real constraint, add an allowlist here rather than loosening the pattern.
#
# The source is required, not defaulted: a default path resolved from the wrong working
# directory would compare against nothing and pass everything.
set -eu

PATTERN='\$\{[A-Za-z0-9_.-]+\}'

# Checked explicitly rather than with ${1:?...}: a parameter-expansion error exits 2 under
# dash (Ubuntu's /bin/sh, so GitHub runners) and 1 under Git Bash, which made the exit code
# environment-dependent. CI caught that.
if [ "$#" -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "usage: check-placeholders.sh <generated-file> <source-file>" >&2
  exit 1
fi

file="$1"
source="$2"

for f in "$file" "$source"; do
  if [ ! -f "$f" ]; then
    echo "check-placeholders: no such file: $f" >&2
    exit 1
  fi
done

# Prints the distinct ${name}s in a file. grep exits 0 on a match, 1 on no match, and >=2 on
# an error such as an unreadable file. Collapsing >=2 into the no-match branch would report
# success without having inspected the file, so the error case exits here. (The >=2 branch
# has no unit test: the NTFS development box cannot produce an unreadable file via chmod.)
placeholders_in() {
  set +e
  found=$(grep -oE "$PATTERN" "$1")
  rc=$?
  set -e
  if [ "$rc" -ge 2 ]; then
    echo "check-placeholders: could not read $1 (grep exit $rc); refusing to pass it" >&2
    exit 1
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$found" | sort -u
  fi
}

# Command substitution runs placeholders_in in a subshell, so its exit 1 would not stop this
# script; the explicit check does.
generated_names=$(placeholders_in "$file") || exit 1
source_names=$(placeholders_in "$source") || exit 1

unresolved=""
if [ -n "$generated_names" ] && [ -n "$source_names" ]; then
  unresolved=$(printf '%s\n' "$generated_names" | while IFS= read -r name; do
    if printf '%s\n' "$source_names" | grep -qxF -- "$name"; then
      printf '%s\n' "$name"
    fi
  done)
fi

if [ -n "$unresolved" ]; then
  echo "check-placeholders: unresolved placeholder in $file:" >&2
  printf '%s\n' "$unresolved" | while IFS= read -r name; do
    grep -nF -- "$name" "$file" >&2
  done
  exit 1
fi

exit 0
