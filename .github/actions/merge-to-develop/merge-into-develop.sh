#!/bin/sh
# Merge a release into the development branch, after it has been aligned to that branch.
#
#   merge-into-develop.sh <tag> <aligned-ref> <branch>
#
# Run in a clone with <branch> checked out. <aligned-ref> is <tag> plus one commit that sets
# every POM to <branch>'s own version and SCM tag (action.yml builds it). That commit removes
# the version conflicts before the merge, so the merge itself can be plain: no -s, no -X.
# Whatever still conflicts is real, and it stops the merge-back instead of being resolved by
# picking a side. The `-X ours` in #65's issue body would have discarded an RC fix silently
# wherever the development branch had touched the same lines.
#
# On success the merge is left committed, not pushed, and assert-carried-over.sh has proven
# it is exactly the plain merge. On any failure the clone is put back where it started.
# specs/65-merge-release-back-into-develop.md §3.3 has the reasoning.
set -u

if [ "$#" -ne 3 ]; then
  echo "usage: merge-into-develop.sh <tag> <aligned-ref> <branch>"
  exit 1
fi
tag="$1"; aligned="$2"; branch="$3"
here="$(cd "$(dirname "$0")" && pwd)"

current="$(git symbolic-ref --quiet --short HEAD || echo '(detached)')"
if [ "$current" != "$branch" ]; then
  echo "::error::merge-into-develop.sh must run on $branch, but the checkout is on '$current'"
  exit 1
fi
before="$(git rev-parse HEAD)"

if ! output="$(git merge --no-ff --no-edit \
      -m "[maven-release-plugin] merge release $tag into $branch" "$aligned" 2>&1)"; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  git merge --abort 2>/dev/null || git reset -q --hard "$before"
  echo "::error::merging $tag into $branch conflicts, so nothing was pushed. The release" \
       "itself is complete: only this merge-back remains. Merge $tag into $branch by hand," \
       "keep $branch's own version in every pom.xml, and resolve each path below on its" \
       "merits rather than taking one side wholesale."
  if [ -n "$conflicts" ]; then
    printf '%s\n' "$conflicts" | sed 's/^/  /'
  else
    printf '%s\n' "$output"
  fi
  exit 1
fi

if ! sh "$here/assert-carried-over.sh" "$tag" "$before" "$aligned" "$branch"; then
  git reset -q --hard "$before"
  echo "::error::the merge commit was reset, so $branch is back at $before and nothing was" \
       "pushed. The release itself is complete: only this merge-back remains."
  exit 1
fi
