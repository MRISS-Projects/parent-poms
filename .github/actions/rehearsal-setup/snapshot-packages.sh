#!/usr/bin/env bash
# Record the product's package versions in the GitHub Packages Maven registry.
#
#   snapshot-packages.sh <git_project> <output_file>
#
# rehearsal-setup runs it before the rehearsal and rehearsal-verify runs it again after;
# assert-no-writes.sh diffs the two. A rehearsal must publish no artifact, so the two files
# must be identical. See specs/72-dry-run-release-workflows.md §2.4.
#
# ENDPOINT — specs/72 Task 2 left the exact form open. The organisation endpoint is tried
# first and the user endpoint is the documented fallback, because GitHub serves an
# organisation's packages from /orgs/{org}/packages and a user account's from
# /users/{user}/packages, and MRISS-Projects is an organisation. The form that answered is
# echoed into the run log, so the demonstration runs in specs/72 Tasks 9 and 10 pin it.
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

packages_json=''
endpoint=''
for candidate in "/orgs/${org}/packages?package_type=maven" "/users/${org}/packages?package_type=maven"; do
  if packages_json="$(gh api --paginate "$candidate" 2>/dev/null)"; then
    endpoint="$candidate"
    break
  fi
done

if [ -z "$endpoint" ]; then
  echo "::error::rehearsal: could not list Maven packages for '${org}'. Both" \
       "/orgs/${org}/packages and /users/${org}/packages failed. DEPLOY_TOKEN needs the" \
       "read:packages scope. Refusing to continue: an empty snapshot would let the" \
       "before/after diff pass without having inspected the registry." >&2
  exit 1
fi

echo "rehearsal: package listing served by ${endpoint}"

# Over-inclusive on purpose. A substring match can pick up a package merely named after the
# project, which costs nothing in a before/after diff, whereas a too-narrow groupId filter
# would silently drop the package a deploy actually created.
mapfile -t names < <(
  printf '%s' "$packages_json" \
    | jq -r --arg p "$project" '.[] | select(.name | contains($p)) | .name' \
    | sort -u
)

if [ "${#names[@]}" -eq 0 ]; then
  echo "rehearsal: no Maven package in ${org} matches '${project}' yet; snapshot is empty."
fi

: > "$output"
for name in "${names[@]:-}"; do
  [ -n "$name" ] || continue
  # The package name goes in a path segment. Dots are legal there; a slash is not, and a
  # Maven package name cannot contain one.
  gh api --paginate "/orgs/${org}/packages/maven/${name}/versions" \
    --jq '.[] | .name' 2>/dev/null \
    | sed "s|^|${name} |" >> "$output" || {
      echo "::error::rehearsal: could not list versions of package '${name}'." >&2
      exit 1
    }
done

LC_ALL=C sort -o "$output" "$output"
echo "rehearsal: $(wc -l < "$output") package version(s) recorded in $(basename "$output")"
