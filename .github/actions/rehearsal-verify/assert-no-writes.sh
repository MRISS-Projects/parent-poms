#!/usr/bin/env bash
# Prove, against the live remote, that a rehearsal wrote nothing.
#
#   assert-no-writes.sh <git_project> <current_version> <dispatch_branch> [<hotfix_branch>]
#
# #72's AC002 asked for the four absences to be asserted "against the run log". A step
# cannot read its own job's live log, so a log-based assertion could only happen after the
# fact, by hand, on a downloaded log. This asserts against the remote instead, which is both
# automatable and stronger evidence: it does not ask what the workflow said it did, it asks
# what the remote looks like now. specs/72 §2.4 and §6 restate AC002 to match.
#
# Two halves:
#   1. the before/after diff — heads, tags and package versions must be identical;
#   2. positive assertions — the release tag is absent, the hotfix branch is absent, the
#      dispatched branch is still present, and no package carries the release version.
#
# The diff alone would pass if both snapshots failed to be taken, which is why
# snapshot-packages.sh fails hard rather than writing an empty file, and why (1) and (2)
# are both here.
#
# One accepted false-failure mode: a human pushing to the repository during the run makes
# the snapshots differ and fails the rehearsal. That is the safe direction to fail in, and
# a rehearsal is always dispatched deliberately.
set -uo pipefail

if [ "$#" -lt 3 ]; then
  echo "usage: assert-no-writes.sh <git_project> <current_version> <dispatch_branch> [<hotfix_branch>]" >&2
  exit 1
fi

project="$1"
current_version="$2"
dispatch_branch="$3"
hotfix_branch="${4:-}"

status=0
note() { echo "  $*"; }
bad()  { echo "::error::rehearsal: $*" >&2; status=1; }

# --- 1. the before/after diff ------------------------------------------------------

git ls-remote --heads origin | sort > "$RUNNER_TEMP/rehearsal-heads.after"
git ls-remote --tags  origin | sort > "$RUNNER_TEMP/rehearsal-tags.after"
"$RUNNER_TEMP/rehearsal-snapshot-packages.sh" "$project" "$RUNNER_TEMP/rehearsal-packages.after" \
  || bad "the package-registry snapshot could not be retaken; the artifact-deploy assertion is unproven."

for what in heads tags packages; do
  before="$RUNNER_TEMP/rehearsal-${what}.before"
  after="$RUNNER_TEMP/rehearsal-${what}.after"

  if [ ! -f "$before" ]; then
    bad "no '${what}' snapshot was taken before the run, so nothing can be compared." \
        "rehearsal-setup did not complete."
    continue
  fi
  if [ ! -f "$after" ]; then
    bad "the '${what}' snapshot could not be retaken after the run."
    continue
  fi

  if diff -u "$before" "$after" > "$RUNNER_TEMP/rehearsal-${what}.diff"; then
    note "${what}: unchanged ($(wc -l < "$after" | tr -d ' ') entries)"
  else
    bad "the remote's '${what}' changed during the rehearsal. A rehearsal must write nothing."
    sed 's/^/  /' "$RUNNER_TEMP/rehearsal-${what}.diff" >&2
  fi
done

# --- 2. positive assertions --------------------------------------------------------

release_tag="v${current_version}"

if git ls-remote --tags origin "refs/tags/${release_tag}" | grep -q .; then
  bad "the release tag '${release_tag}' exists on the remote. release:prepare was not suppressed."
else
  note "tag ${release_tag}: absent, as it must be"
fi

if [ -n "$hotfix_branch" ]; then
  if git ls-remote --heads origin "refs/heads/${hotfix_branch}" | grep -q .; then
    bad "the hotfix branch '${hotfix_branch}' exists on the remote. scm:branch was not redirected."
  else
    note "branch ${hotfix_branch}: absent, as it must be"
  fi
fi

if git ls-remote --heads origin "refs/heads/${dispatch_branch}" | grep -q .; then
  note "branch ${dispatch_branch}: still present, as it must be"
else
  bad "the branch the run was dispatched against, '${dispatch_branch}', is gone from the" \
      "remote. The 'Remove RC Branch' step deleted it for real."
fi

# The package snapshot is already on disk, so the deploy assertion costs no extra API call.
# It is stated positively as well as by diff because a diff of two identical failures would
# pass without having inspected anything.
packages_after="$RUNNER_TEMP/rehearsal-packages.after"
if [ -f "$packages_after" ]; then
  if awk -v v="$current_version" '$2 == v { found = 1 } END { exit !found }' "$packages_after"; then
    packages_before="$RUNNER_TEMP/rehearsal-packages.before"
    if [ -f "$packages_before" ] && awk -v v="$current_version" '$2 == v { found = 1 } END { exit !found }' "$packages_before"; then
      bad "version '${current_version}' was already published to the registry before this" \
          "run started. The rehearsal cannot prove anything about a deploy of a version that" \
          "already exists — rehearse an unreleased version."
    else
      bad "version '${current_version}' appeared in the package registry during the run." \
          "release:perform deployed for real."
    fi
  else
    note "registry: no package carries version ${current_version}"
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "rehearsal: the remote is byte-for-byte as it was before the run."
fi

exit "$status"
