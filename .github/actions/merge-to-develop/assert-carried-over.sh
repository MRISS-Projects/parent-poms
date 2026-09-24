#!/bin/sh
# Assert that HEAD is exactly the plain merge of a release into the development branch.
#
#   assert-carried-over.sh <tag> <branch-before> <aligned-ref> <branch>
#
# Run in the development-branch clone, after merge-into-develop.sh has merged <aligned-ref>
# (the tag, aligned to the development branch's version and SCM tag) into <branch>, whose tip
# before that merge was <branch-before>. Two checks, both needed:
#
#   1. HEAD's tree is the tree `git merge-tree` computes for a plain merge of the two, and that
#      merge has no conflicts. `-X ours` and `-X theirs` only ever differ from a plain merge
#      where there was a conflict, so any side-picking in any file fails here. The first design
#      compared paths one by one and skipped paths both sides changed. Those are the only paths
#      `-X ours` can lose hunks in, so that design could not catch the defect it was for.
#   2. Outside files named pom.xml, <aligned-ref> is identical to <tag>. Check 1 takes the
#      aligned commit as given, so it cannot see an alignment step that rewrote something other
#      than a POM. This check can.
#
# The evidence line counts the non-POM paths the release changed since it diverged from the
# development branch. Those are the paths the merge-back exists to carry.
# specs/65-merge-release-back-into-develop.md §3.3 has the reasoning.
set -u

if [ "$#" -ne 4 ]; then
  echo "usage: assert-carried-over.sh <tag> <branch-before> <aligned-ref> <branch>"
  exit 1
fi
tag="$1"; before="$2"; aligned="$3"; branch="$4"
not_poms=':(exclude,glob)**/pom.xml'
failed=0

# --- 1. HEAD is the plain merge -------------------------------------------------------
plain="$(git merge-tree --write-tree --name-only --no-messages "$before" "$aligned" 2>&1)"
status=$?
if [ "$status" -eq 1 ]; then
  echo "::error::merging $tag into $branch conflicts, so HEAD cannot be the plain merge of" \
       "the two: a conflict was resolved by picking a side. Conflicted path(s):"
  printf '%s\n' "$plain" | sed '1d' | sed '/^$/d' | sort -u | sed 's/^/  /'
  failed=1
elif [ "$status" -ne 0 ]; then
  echo "::error::git merge-tree could not merge $before and $aligned (exit $status):"
  printf '%s\n' "$plain"
  exit 1
else
  plain_tree="$(printf '%s\n' "$plain" | head -1)"
  head_tree="$(git rev-parse 'HEAD^{tree}')"
  if [ "$plain_tree" != "$head_tree" ]; then
    echo "::error::HEAD is not the plain merge of $tag into $branch. Path(s) that differ:"
    git diff --name-only "$plain_tree" "$head_tree" | sed 's/^/  /'
    failed=1
  fi
fi

# --- 2. alignment changed POMs and nothing else -----------------------------------------
if ! misaligned="$(git diff --name-only "$tag" "$aligned" -- . "$not_poms")"; then
  echo "::error::could not compare $tag with $aligned"
  exit 1
fi
if [ -n "$misaligned" ]; then
  echo "::error::the alignment of $tag changed more than POMs, so $branch would receive" \
       "content the release never had. Non-POM path(s) that differ from $tag:"
  printf '%s\n' "$misaligned" | sed 's/^/  /'
  failed=1
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi

base="$(git merge-base "$tag" "$before")" || {
  echo "::error::$tag and $branch share no history"
  exit 1
}
carried="$(git diff --name-only --no-renames "$base" "$tag" -- . "$not_poms" | wc -l | tr -d ' ')"
echo "merge-to-develop: carried $carried path(s) from $tag into $branch; 0 lost"
