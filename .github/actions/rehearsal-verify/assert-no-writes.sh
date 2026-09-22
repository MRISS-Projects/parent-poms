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
#   2. positive assertions — the release tag is absent, the hotfix branch is absent, and the
#      dispatched branch is still present. None for the registry; see the note at the end.
#
# FAIL CLOSED ON EVERY READ. This script's whole job is to say "nothing was written", so the
# worst defect it can have is to say that without having looked. PR #77's review found exactly
# that: each positive assertion re-queried the remote as `git ls-remote ... | grep -q .`, which
# cannot tell "no such ref" from "the read failed", so an auth or network error reported the
# release tag absent and the run clean. The same flaw hid a second hole: a repository with no
# tags has an empty 'before' snapshot, a failed 'after' read is also empty, and the two diffed
# equal. Now each kind of ref is read exactly once, its exit status is checked on its own rather
# than through a pipe, and the positive assertions consult that verified snapshot instead of
# asking the remote again. A read that failed makes every assertion depending on it fail as
# unproven — never pass. assert-no-writes.test.sh covers each path.
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

# read_refs <heads|tags> <output-file>
# The exit status of `git ls-remote` is taken on its own. Piped straight into `sort`, a failure
# would still leave a well-formed — empty — file behind, which is precisely how an unreachable
# remote used to pass as an untouched one.
read_refs() {
  local kind="$1" out="$2" raw
  raw="$(mktemp)"
  if ! git ls-remote "--$kind" origin > "$raw" 2> "$raw.err"; then
    bad "could not read the remote's ${kind} (git ls-remote exited non-zero). Every assertion" \
        "about ${kind} is unproven, so the rehearsal fails rather than reporting them clean."
    sed 's/^/  /' "$raw.err" >&2
    rm -f "$raw" "$raw.err"
    return 1
  fi
  sort "$raw" > "$out"
  rm -f "$raw" "$raw.err"
}

# has_ref <snapshot-file> <full-ref-name>
# Exact comparison on the ref column, never a regex: the version's dots are literal, and a
# lookalike such as v0x3x0 must not count as v0.3.0. An annotated tag appears twice in
# ls-remote output, once peeled with ^{}; either form means the tag exists.
has_ref() {
  awk -v r="$2" '$2 == r || $2 == r "^{}" { found = 1 } END { exit !found }' "$1"
}

# --- 1. the before/after diff ------------------------------------------------------

heads_ok=0; tags_ok=0
read_refs heads "$RUNNER_TEMP/rehearsal-heads.after" && heads_ok=1
read_refs tags  "$RUNNER_TEMP/rehearsal-tags.after"  && tags_ok=1

packages_ok=0
if "$RUNNER_TEMP/rehearsal-snapshot-packages.sh" "$project" "$RUNNER_TEMP/rehearsal-packages.after"; then
  packages_ok=1
else
  bad "the package-registry snapshot could not be retaken; the artifact-deploy assertion is unproven."
fi

for what in heads tags packages; do
  case "$what" in
    heads)    ok=$heads_ok ;;
    tags)     ok=$tags_ok ;;
    packages) ok=$packages_ok ;;
  esac
  # Already reported as a failed read. Diffing what it left behind would at best repeat that,
  # and at worst — an empty 'before' against an empty 'after' — report it unchanged.
  [ "$ok" -eq 1 ] || continue

  before="$RUNNER_TEMP/rehearsal-${what}.before"
  after="$RUNNER_TEMP/rehearsal-${what}.after"

  if [ ! -f "$before" ]; then
    bad "no '${what}' snapshot was taken before the run, so nothing can be compared." \
        "rehearsal-setup did not complete."
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
#
# Each reads the snapshot verified above. None asks the remote a second time.

heads_after="$RUNNER_TEMP/rehearsal-heads.after"
tags_after="$RUNNER_TEMP/rehearsal-tags.after"
release_tag="v${current_version}"

if [ "$tags_ok" -eq 1 ]; then
  if has_ref "$tags_after" "refs/tags/${release_tag}"; then
    bad "the release tag '${release_tag}' exists on the remote. release:prepare was not suppressed."
  else
    note "tag ${release_tag}: absent, as it must be"
  fi
else
  bad "tag ${release_tag}: unproven — the remote's tags could not be read."
fi

if [ -n "$hotfix_branch" ]; then
  if [ "$heads_ok" -eq 1 ]; then
    if has_ref "$heads_after" "refs/heads/${hotfix_branch}"; then
      bad "the hotfix branch '${hotfix_branch}' exists on the remote. scm:branch was not redirected."
    else
      note "branch ${hotfix_branch}: absent, as it must be"
    fi
  else
    bad "branch ${hotfix_branch}: unproven — the remote's heads could not be read."
  fi
fi

if [ "$heads_ok" -eq 1 ]; then
  if has_ref "$heads_after" "refs/heads/${dispatch_branch}"; then
    note "branch ${dispatch_branch}: still present, as it must be"
  else
    bad "the branch the run was dispatched against, '${dispatch_branch}', is gone from the" \
        "remote. The 'Remove RC Branch' step deleted it for real."
  fi
else
  bad "branch ${dispatch_branch}: unproven — the remote's heads could not be read."
fi

# There is deliberately no positive assertion for the registry. An earlier revision also checked
# that no package carried the release version. Once the snapshot covers every package in the
# organisation (PR #77's review, F1), that check would fail whenever an unrelated product was
# legitimately at the same version number — a false failure with no connection to this run. And
# it adds nothing: the snapshot is now complete and fail-closed, so a deploy under any name adds a
# line, and the diff above already fails on any added line.

if [ "$status" -eq 0 ]; then
  echo "rehearsal: the remote is byte-for-byte as it was before the run."
fi

exit "$status"
