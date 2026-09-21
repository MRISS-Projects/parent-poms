#!/bin/sh
# Announce one suppressed or redirected write during a rehearsal.
#
#   bash "$RUNNER_TEMP/rehearsal-marker.sh" <id> <description>
#
# Called from steps that also run during a real release. When RH_ACTIVE is empty — which
# is every real release — this is a silent no-op, so the call site needs no `if:` and the
# release log is byte-identical to today's. See specs/72-dry-run-release-workflows.md §2.3.
#
# The marker is emitted by the workflow, never by the plugin being suppressed.
# maven-release-plugin and maven-scm-publish-plugin print their own dry-run chatter, but
# that wording belongs to those plugins and moves under a version bump; this asserts our
# intent independently of it.
set -eu

if [ "$#" -ne 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  # Fails in both modes deliberately. A malformed call site is a workflow bug, and the
  # marker set it produces would be a lie — rehearsal-verify would report a missing id for
  # a site that thinks it emitted one. Tolerating it while inactive would mean every real
  # release silently carries the same bug.
  echo "usage: rehearsal-marker.sh <id> <description>" >&2
  exit 1
fi

id="$1"
description="$2"

[ -n "${RH_ACTIVE:-}" ] || exit 0

echo "REHEARSAL $id: would $description"

# Mandatory when active: without it the id goes nowhere and the completeness check would
# fail on a marker that was in fact emitted.
if [ -z "${RUNNER_TEMP:-}" ]; then
  echo "rehearsal-marker: RUNNER_TEMP is unset, so marker '$id' cannot be recorded." >&2
  exit 1
fi

echo "$id" >> "$RUNNER_TEMP/rehearsal-markers"

# Bullets rather than table rows on purpose. GITHUB_STEP_SUMMARY is a separate file per
# step and the files are concatenated, so a table header written once by rehearsal-setup
# would be separated from its rows by whatever the intervening steps appended. A bullet
# list renders correctly however the pieces interleave.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "- \`$id\` — would $description" >> "$GITHUB_STEP_SUMMARY"
fi
