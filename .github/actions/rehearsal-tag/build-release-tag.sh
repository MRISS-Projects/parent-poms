#!/bin/sh
# Build the release tag a dry-run `release:prepare` did not create.
#
# `release:prepare -DdryRun=true` stops short of scm-tag, and `release:perform -DdryRun=true`
# creates no target/checkout. Without a tag, the steps after them in project-release.yml and
# project-hotfix.yml are not merely skipped, they are unreachable — so the very commands
# MRISS-Projects/parent-poms#69 and #65 are about would never execute, and a rehearsal would
# prove nothing about them.
#
# What the dry run does leave behind is the complete release-version tree: rewrite-poms-for-
# release writes a pom.xml.tag beside every pom.xml, and release.properties records scm.tag.
# That is enough to assemble the commit the plugin would have made and tag it locally.
#
# This is the only logic in either workflow that a real release never runs. It is confined
# here, guarded by one `if: inputs.dry_run`, and writes nothing outside the runner.
#
# IT MUST NOT DISTURB THE CHECKOUT. Later steps read this same working tree. The obvious
# implementation — copy the .tag files over pom.xml, commit, tag, `git reset --hard` — moves
# the branch and rewrites the working tree. The plumbing form below touches neither: every
# staging operation goes to a private index named by GIT_INDEX_FILE, and the commit is made
# with commit-tree, which does not move HEAD.
set -eu

cd "$(git rev-parse --show-toplevel)"

if ! git rev-parse -q --verify HEAD >/dev/null; then
  echo "rehearsal-tag: HEAD does not resolve; there is no commit to build the tag on." >&2
  exit 1
fi

if [ ! -f release.properties ]; then
  echo "rehearsal-tag: release.properties is absent. Did release:prepare run?" >&2
  exit 1
fi

# scm.tag is written by map-release-versions and is the tag the plugin would have created —
# v@{project.version} expanded, per <tagNameFormat> in parent-poms/pom.xml. Reading it is
# what keeps the rehearsal's tag name identical to a real release's instead of guessing it
# from the version inputs.
TAG="$(sed -n 's/^scm\.tag=//p' release.properties | head -1)"

if [ -z "$TAG" ]; then
  echo "rehearsal-tag: release.properties carries no scm.tag entry." >&2
  exit 1
fi

# The value reaches `git tag`, so it is validated rather than trusted.
if ! git check-ref-format "refs/tags/$TAG"; then
  echo "rehearsal-tag: '$TAG' is not a valid tag name." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "rehearsal-tag: tag '$TAG' already exists. Refusing to reuse it — a rehearsal that" \
       "silently adopted a stale tag would validate the wrong tree." >&2
  exit 1
fi

TAGFILES="$(mktemp)"
# target/ is excluded because release:perform's checkout, when one exists, carries its own
# pom.xml.tag copies; committing those would put the release tree at the wrong paths.
find . -name pom.xml.tag -not -path './target/*' -print > "$TAGFILES"

if [ ! -s "$TAGFILES" ]; then
  rm -f "$TAGFILES"
  echo "rehearsal-tag: no pom.xml.tag file found. rewrite-poms-for-release did not run," \
       "so there is no release tree to tag." >&2
  exit 1
fi

GIT_INDEX_FILE="$(mktemp)"
# mktemp creates the file; git rejects a zero-length index, so hand it a path that does not
# exist yet and let read-tree create it.
rm -f "$GIT_INDEX_FILE"
export GIT_INDEX_FILE
# Not a trap on EXIT: the script is `set -e`, and on the failure paths above GIT_INDEX_FILE
# is not yet exported, so a single cleanup at the end plus the shell's own exit is enough —
# and RUNNER_TEMP is discarded with the runner regardless.

git read-tree HEAD

count=0
while IFS= read -r tagfile; do
  [ -n "$tagfile" ] || continue
  rel="${tagfile#./}"
  blob="$(git hash-object -w "$tagfile")"
  git update-index --add --cacheinfo "100644,$blob,${rel%.tag}"
  count=$((count + 1))
done < "$TAGFILES"

tree="$(git write-tree)"
commit="$(git commit-tree "$tree" -p HEAD -m "[rehearsal] release content for $TAG")"
git tag "$TAG" "$commit"

rm -f "$GIT_INDEX_FILE" "$TAGFILES"
unset GIT_INDEX_FILE

echo "rehearsal-tag: tagged $commit as $TAG from $count pom.xml.tag file(s)."
