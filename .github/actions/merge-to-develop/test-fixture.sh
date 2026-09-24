#!/bin/sh
# Scratch-repository fixture shared by this action's *.test.sh suites. Sourced, not run.
#
# It reproduces, at the scale of two POMs and two text files, the shape measured on the real
# MRISS-Projects/dsh branches in specs/65-merge-release-back-into-develop.md §1.2:
#
#   base ── DEVELOP         the next-version bump project-stage.yml leaves, and nothing else
#     └──── rc ── v<ver>    stabilisation fixes, then the release commit and its tag
#                  └── merge-back/v<ver>   the tag, aligned to DEVELOP's version and SCM tag
#
# Every function acts on $REPO. Callers edit files with `put` between the steps to create the
# case under test.

g() { git -C "$REPO" "$@"; }

root_pom() {
  cat <<EOF
<project>
    <groupId>com.example</groupId>
    <artifactId>fixture</artifactId>
    <version>$1</version>
    <packaging>pom</packaging>
    <modules>
        <module>mod</module>
    </modules>
    <scm>
        <url>https://example.invalid/fixture</url>
        <tag>$2</tag>
    </scm>
</project>
EOF
}

module_pom() {
  cat <<EOF
<project>
    <parent>
        <groupId>com.example</groupId>
        <artifactId>fixture</artifactId>
        <version>$1</version>
    </parent>
    <artifactId>mod</artifactId>
</project>
EOF
}

# put <path> <content> — overwrite a file in $REPO with content, backslash escapes expanded.
put() { printf '%b' "$2" > "$REPO/$1"; }

# set_poms <version> <scm-tag> — what release:prepare, release:update-versions and
# versions:set-scm-tag do to the reactor, between them.
set_poms() {
  root_pom "$1" "$2" > "$REPO/pom.xml"
  module_pom "$1" > "$REPO/mod/pom.xml"
}

commit() { g add -A && g commit -q -m "$1"; }

# new_repo <dir> — base commit, DEVELOP at 2.0-SNAPSHOT, and `rc` checked out at 1.0-SNAPSHOT.
new_repo() {
  REPO="$1"
  rm -rf "$REPO"
  git init -q "$REPO"
  g config user.name fixture
  g config user.email fixture@example.invalid
  g config core.autocrlf false
  g config commit.gpgsign false
  g config tag.gpgsign false
  mkdir -p "$REPO/mod"
  set_poms 1.0-SNAPSHOT HEAD
  put a.txt 'one\ntwo\nthree\nfour\nfive\n'
  put b.txt 'alpha\nbeta\n'
  commit base
  g branch rc
  g checkout -q -b DEVELOP
  set_poms 2.0-SNAPSHOT HEAD
  commit "next development iteration"
  g checkout -q rc
}

# release <version> — the release commit on rc, tagged v<version>.
release() {
  g checkout -q rc
  set_poms "$1" "v$1"
  commit "prepare release v$1"
  g tag "v$1"
}

# align <version> — merge-back/v<version>: the tag, set to DEVELOP's 2.0-SNAPSHOT and HEAD.
align() {
  g checkout -q -b "merge-back/v$1" "v$1"
  set_poms 2.0-SNAPSHOT HEAD
  commit "align v$1"
}

# on_develop — check out DEVELOP, where both scripts under test run.
on_develop() { g checkout -q DEVELOP; }
