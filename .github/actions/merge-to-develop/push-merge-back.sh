#!/bin/sh
# Push the merge-back, merging again onto the development branch's new tip if it advanced.
#
#   push-merge-back.sh <push-url> <tag> <aligned-ref> <branch>
#
# Run in the development-branch clone, after merge-into-develop.sh has committed the merge on
# <branch>. RH_GIT_PUSH_DRYRUN must be set: empty in a real release, --dry-run in a rehearsal.
#
# A release takes minutes, and the development branch is where everyday PRs merge, so the tip
# the merge-back was built on can be stale by the time it is pushed. PR #82's review found this.
# The retry follows commit-readme's loop (three attempts, and a retry only when the remote
# branch really advanced), with one difference. commit-readme rebases a single commit, but a
# merge is redone instead: reset to the new tip and run merge-into-develop.sh again, so the
# plain-merge and alignment assertions are proven again against what is actually pushed.
#
# A retry goes ahead only if no pom.xml changed between the tip the alignment was built against
# and the new one. The aligned commit carries that branch's version and SCM tag, so a POM change
# under it means the alignment may no longer be the right one, and that is for a human to
# judge. With POMs unchanged, the merged POMs are those verify-reactor-version already checked.
# specs/65-merge-release-back-into-develop.md §3.4 has the reasoning.
set -u

if [ "$#" -ne 4 ]; then
  echo "usage: push-merge-back.sh <push-url> <tag> <aligned-ref> <branch>"
  exit 1
fi
url="$1"; tag="$2"; aligned="$3"; branch="$4"
here="$(cd "$(dirname "$0")" && pwd)"

if [ "${RH_GIT_PUSH_DRYRUN+set}" != set ]; then
  echo "::error::RH_GIT_PUSH_DRYRUN is unset, so it is unknown whether this is a rehearsal." \
       "rehearsal-setup must run earlier in the job; nothing was pushed."
  exit 1
fi

recovery() {
  echo "::error::$* Nothing was pushed to $branch. The release itself is complete: only this" \
       "merge-back remains. Merge $tag into $branch by hand, keep $branch's own version in" \
       "every pom.xml, and resolve any conflict on its merits rather than taking one side" \
       "wholesale."
}

# The tip the alignment was built against: the merge's first parent.
base="$(git rev-parse HEAD^1)"

for attempt in 1 2 3; do
  # Unquoted on purpose: empty in a real release, so it must expand to no argument at all.
  # shellcheck disable=SC2086
  if push_output="$(git push $RH_GIT_PUSH_DRYRUN "$url" "HEAD:$branch" 2>&1)"; then
    printf '%s\n' "$push_output"
    exit 0
  fi
  printf '%s\n' "$push_output"

  if ! fetch_output="$(git fetch --no-tags "$url" "$branch" 2>&1)"; then
    printf '%s\n' "$fetch_output"
    recovery "the push to $branch failed and its latest tip could not be fetched."
    exit 1
  fi

  if git merge-base --is-ancestor FETCH_HEAD HEAD; then
    recovery "the push to $branch failed for a reason other than the branch advancing."
    exit 1
  fi

  if [ "$attempt" -eq 3 ]; then
    recovery "the push to $branch was rejected after 3 attempts."
    exit 1
  fi

  moved="$(git diff --name-only "$base" FETCH_HEAD -- ':(glob)**/pom.xml')"
  if [ -n "$moved" ]; then
    recovery "$branch advanced during the release and changed POMs, so the alignment of $tag" \
             "may no longer match it:"
    printf '%s\n' "$moved" | sed 's/^/  /'
    exit 1
  fi

  echo "The push to $branch was rejected because it advanced; merging again onto its new tip" \
       "($attempt/3)."
  base="$(git rev-parse FETCH_HEAD)"
  git reset -q --hard "$base"
  if ! sh "$here/merge-into-develop.sh" "$tag" "$aligned" "$branch"; then
    exit 1
  fi
done
