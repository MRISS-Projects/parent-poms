#!/usr/bin/env bash
# Record every Maven package version in the organisation's GitHub Packages registry.
#
#   snapshot-packages.sh <git_project> <output_file>
#
# rehearsal-setup runs it before the rehearsal and rehearsal-verify runs it again after;
# assert-no-writes.sh diffs the two. A rehearsal must publish no artifact, so the two files
# must be identical. See specs/72-dry-run-release-workflows.md §2.4.
#
# EVERY PACKAGE, NOT THE PRODUCT'S. An earlier revision kept only packages whose name contained
# git_project. PR #77's review (F1) showed why that is wrong: a consumer whose Maven
# coordinates do not contain its repository name matches nothing, both snapshots come out empty,
# and a real deploy is invisible to the diff. Guessing package names from a repository name is a
# mapping this repository has no way to get right for every consumer, so it does not try. A deploy
# of any artifact, under any name, adds a line.
#
# The cost is one versions request per package in the organisation, twice per rehearsal. The
# accepted false-failure mode widens to match: another product publishing during the run fails the
# rehearsal, the same safe direction as a human pushing to the repository during it.
#
# git_project is used only to label the log. It is kept in the signature so the two callers and
# the actions that feed them did not change inside a review round.
#
# ENDPOINT — pinned to /orgs/, because it was measured. specs/72 Task 2 left the exact form open
# and asked for the working one to be recorded once found: it tried /orgs/{org}/packages first
# with /users/{user}/packages as a fallback. Both demonstration runs logged "package listing
# served by /orgs/MRISS-Projects/packages?package_type=maven" (dsh runs 35662168807 and
# 35665353914). MRISS-Projects is an organisation, so that is the form that applies.
#
# The fallback was removed rather than repaired. PR #77's review (F4) found it switched only the
# listing to /users/, leaving the versions request below hard-coded to /orgs/ — so if the fallback
# had ever been taken, every versions request would have failed. It never was taken, and could not
# be for an organisation. Dead code with a latent defect is better deleted than fixed.
#
# Failure is deliberately hard. If the snapshot could not be taken, the before/after diff
# would compare two empty files and pass while proving nothing — the one outcome worse than
# a failed rehearsal.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: snapshot-packages.sh <git_project> <output_file>" >&2
  exit 1
fi

project="$1"
output="$2"
org=MRISS-Projects

# The listing and every versions request below are built from this one base, so they cannot
# disagree about which endpoint they are talking to — the defect F4 found.
base="/orgs/${org}"

if ! packages_json="$(gh api --paginate "${base}/packages?package_type=maven")"; then
  echo "::error::rehearsal: could not list Maven packages at ${base}/packages. DEPLOY_TOKEN" \
       "needs the read:packages scope. Refusing to continue: an empty snapshot would let the" \
       "before/after diff pass without having inspected the registry." >&2
  exit 1
fi

echo "rehearsal: package listing served by ${base}/packages?package_type=maven"

mapfile -t names < <(printf '%s' "$packages_json" | jq -r '.[] | .name' | sort -u)

echo "rehearsal: snapshotting all ${#names[@]} Maven package(s) in ${org} for the ${project} rehearsal"

: > "$output"
for name in "${names[@]:-}"; do
  [ -n "$name" ] || continue
  # The package name goes in a path segment. Dots are legal there; a slash is not, and a
  # Maven package name cannot contain one.
  gh api --paginate "${base}/packages/maven/${name}/versions" \
    --jq '.[] | .name' 2>/dev/null \
    | sed "s|^|${name} |" >> "$output" || {
      echo "::error::rehearsal: could not list versions of package '${name}'." >&2
      exit 1
    }
done

LC_ALL=C sort -o "$output" "$output"
echo "rehearsal: $(wc -l < "$output") package version(s) recorded in $(basename "$output")"
