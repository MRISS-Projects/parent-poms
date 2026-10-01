#!/bin/sh
# Fail if a module's staged site has no index.html.
#
# MRISS-Projects/parent-poms#88, from MRISS-Projects/dsh#90: every DSH module published a
# site with no index.html - 2,600+ files, a "Home" link that 404'd on every page - and the
# build that staged it and the publication that pushed it both succeeded.
#
# A module's site is a directory holding project-info.html: parent-poms' <reporting> gives
# that page to every module, and it is the page that kept publishing during dsh#90 while
# index.html was missing. Report directories (apidocs, jacoco, xref) have no
# project-info.html, so their own index.html, or lack of one, does not count.
#
# A stage with no module site at all fails rather than passes: the alternative is a run
# that staged nothing being reported as verified.
#
# Known limit: a module whose site has no project-info.html is not recognised as a module,
# so it is not checked. That takes a consumer removing parent-poms' project-info reports.
#
# Usage: verify-staged-site.sh [<staged root>]   (default: /tmp/sites)
set -eu

ROOT="${1:-/tmp/sites}"
ROOT="${ROOT%/}"

if [ ! -d "$ROOT" ]; then
  echo "::error::verify-staged-site: the staged site directory '$ROOT' does not exist."
  exit 1
fi

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
find "$ROOT" -type f -name project-info.html | sort > "$list"

total=0
missing=0
names=""
while IFS= read -r page; do
  dir="${page%/project-info.html}"
  total=$((total + 1))
  if [ ! -f "$dir/index.html" ]; then
    missing=$((missing + 1))
    if [ "$dir" = "$ROOT" ]; then
      rel="."
    else
      rel="${dir#"$ROOT"/}"
    fi
    names="${names}  ${rel}
"
  fi
done < "$list"

if [ "$total" -eq 0 ]; then
  echo "::error::verify-staged-site: no module site found under '$ROOT' (no project-info.html)."
  echo "Nothing was staged, or the site was staged somewhere else. Nothing is verified."
  exit 1
fi

if [ "$missing" -ne 0 ]; then
  echo "::error::verify-staged-site: $missing of $total module site(s) have no index.html:"
  printf '%s' "$names"
  echo "The site is not published. See MRISS-Projects/parent-poms#88."
  exit 1
fi

echo "verify-staged-site: all $total module site(s) under '$ROOT' have an index.html."
