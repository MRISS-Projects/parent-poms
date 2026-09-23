# Spec: set the hotfix version on every module, and prove it (`#69`)

| | |
|---|---|
| Issue | [`#69`](https://github.com/MRISS-Projects/parent-poms/issues/69) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-69-set-hotfix-version-on-every-module`, cut from `master` at `3b17c9ac` |
| Blocks | `MRISS-Projects/dsh` `0.3.0` — the first real release on this path |
| Validated by | a `dry_run` rehearsal of `dsh`'s `release.yml`, built by `#72` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> The repository has no unit-test harness for workflow behaviour, so the workflow change is
> verified by running Maven and reading the log, and by one dispatched rehearsal. Those runs are
> specified exactly; do not substitute a different command and assume the same output. The one
> piece of new logic that *can* be unit-tested — the assertion script — is, and its tests come
> first.

**Goal.** When `project-release.yml` opens a hotfix branch, every POM in the consuming reactor
carries `initial_hotfix_version`. A run that fails to achieve that fails at that step, naming the
modules that are wrong, before anything is committed or pushed.

**Architecture.** Two changes to one step. The version is set with the release plugin's
`release:update-versions` keyed by the root project's own coordinates, instead of
`versions:set`, which rewrites the root POM and nothing else. The result is then asserted by a
new composite action that runs `mvn -B validate` in the checkout and requires every
`[INFO] Building …` line to carry the expected version. The assertion runs in real releases and
rehearsals alike, and it replaces `#72`'s rehearsal-only evidence line with a permanent check.

**Tech stack.** GitHub Actions composite actions; POSIX `sh`; `maven-release-plugin` 3.1.1 (via
`${release.plugin.version}`); `maven-help-plugin`; Maven **3.9.9 in CI**, which every workflow here
pins via `stCarolas/setup-maven`. The local measurements in §1 and §2 were taken on Maven 3.9.16
against the real `MRISS-Projects/dsh` 13-module reactor.

---

## Global constraints

- Profiles are activated by `-D<name>`, never `-P`. **Never reintroduce `-P`.**
- **`<configuration>` beats the user property.** `pom.xml:365-377` binds `arguments`,
  `tagNameFormat`, `allowTimestampedSnapshots`, `preparationGoals`, `goals`, `scmCommentPrefix`,
  `branchName`, `developmentVersion` and `releaseVersion` in the release plugin's
  `<configuration>`. Any `-D` naming one of those is inert. Check that list before reaching for a
  command-line flag — it is what makes `-DdevelopmentVersion` useless here, and it is the reason
  §2.2 chooses `project.dev.<groupId>:<artifactId>`, which is not on it.
- The hotfix commit message stays exactly
  `[maven-release-plugin] set hotfix version <initial_hotfix_version>`, byte for byte.
- The declared rehearsal marker set is unchanged. This change adds no write point: both new
  commands are local to `target/checkout`, and the only push in the step is the existing
  `scm:checkin`, which keeps its `scm-checkin-hotfix-version` marker.
- Every `*.sh` under `.github/actions/` is committed mode `100755`. A Windows checkout with
  `core.fileMode false` commits `100644` silently and `chmod +x` there records nothing — use
  `git update-index --chmod=+x <file>`. `build.yml` enforces this uniformly; see its comment at
  `build.yml:95-108` for why the rule is not narrowed to scripts an action executes directly.
- Scripts are `sh`, not `bash`, matching `check-placeholders.sh`, `render-properties.sh` and the
  rehearsal scripts. Test suites run as `sh <file>`.
- Every new `.github/actions/<name>/*.test.sh` is picked up by `build.yml`'s glob with no edit
  there — that is the point of `#76`'s generalisation, and this story relies on it.
- Action references in the reusable workflows are pinned `@master` **on merge**. Task 6 pins this
  story's new action to the task branch to validate it and Task 8 flips it back; `build.yml`'s
  guard is red in between, which is the guard working (it caught the same flip in `#72`, `dsh`
  run 35660362564).

---

## 1. The defect

`project-release.yml:257`, inside `target/checkout` on the freshly created hotfix branch:

```bash
mvn -B -DprocessAllModules=true -DnewVersion=${{ inputs.initial_hotfix_version }} versions:set
```

It rewrites the root POM only. Measured twice, on the real `dsh` reactor:

- In CI, by `#72`'s rehearsal —
  [`dsh` run 35662168807](https://github.com/MRISS-Projects/dsh/actions/runs/35662168807):
  `REHEARSAL evidence for #69: versions:set modified 1 of 13 pom.xml file(s).`
- Again from the consuming project against `master` as it stands —
  [`dsh` run 35888661612](https://github.com/MRISS-Projects/dsh/actions/runs/35888661612), the same
  line.

Reproduced locally for this spec in a worktree of the `0.3.0` RC, `git status --porcelain
'*pom.xml' | wc -l` after each command:

| Command | POMs rewritten |
|---|---|
| `mvn -B -DprocessAllModules=true -DnewVersion=0.3.1-SNAPSHOT versions:set` | **1 of 13** |
| the same, plus `-DgroupId='*' -DartifactId='*' -DoldVersion='*'` | **1 of 13** |
| the same, on `versions-maven-plugin` **2.20.0** rather than the pinned 2.18.0 | **1 of 13** |
| `mvn -B -DautoVersionSubmodules=true -Dproject.dev.com.mriss.products:dsh=0.3.1-SNAPSHOT release:update-versions` | **13 of 13** |
| `mvn -B -DautoVersionSubmodules=true -Dbuild.NEXT_DEVELOPMENT_VERSION=0.3.1-SNAPSHOT release:update-versions` | **13 of 13** |

### 1.1 What `versions:set` actually does here

`-X` shows the goal computing the full change set and then applying one file. For every module it
logs both halves of the change it intends:

```text
[DEBUG] Module: D:\w69\dsh-data\pom.xml
[DEBUG]     parent is com.mriss.products:dsh:0.3.0-SNAPSHOT
[DEBUG]     will become com.mriss.products:dsh:0.3.1-SNAPSHOT
[DEBUG]     module is com.mriss.products.dsh:dsh-data:0.3.0-SNAPSHOT
[DEBUG]     will become com.mriss.products.dsh:dsh-data:0.3.1-SNAPSHOT
```

— thirteen times, one per module, and then:

```text
[INFO] Processing com.mriss.products:dsh
[INFO]     Updating project com.mriss.products:dsh
[INFO]         from version 0.3.0-SNAPSHOT to 0.3.1-SNAPSHOT
```

and nothing else. The reactor summary for the same run lists the other twelve modules as
`SKIPPED`: `versions:set` is an aggregator goal, so it executes once, against the root POM, and
the twelve changes it computed for the module files are never written.

### 1.2 No flag and no plugin version rescues it

Two hypotheses were tested and both are dead, which matters because either would have been a
one-token fix:

- **The coordinate filter.** `versions:set` defaults `groupId`/`artifactId` to the project's own,
  and `dsh`'s children sit under `com.mriss.products.dsh` while the root is `com.mriss.products`
  — a plausible cause. `-DgroupId='*' -DartifactId='*' -DoldVersion='*'` changes nothing: still
  1 of 13, and the log still reads `Processing change of *:*:*` followed by one `Updating project`.
- **A plugin regression.** `org.codehaus.mojo:versions-maven-plugin:2.20.0:set` with the same
  arguments is also 1 of 13. The behaviour is not specific to the pinned 2.18.0, so bumping
  `versions.plugin.version` is not a fix — see §8.

The goal has to change. That is what the issue body proposes and what `set-version.sh` already
does in both repositories.

### 1.3 The rehearsal's failure is the lucky one

In a rehearsal the step fails loudly. `dry_run` deploys nothing, so the parent version the twelve
modules still name exists in no repository and the next command cannot build the project model:

```text
[ERROR] Non-resolvable parent POM for com.mriss.products.dsh:dsh-data:0.3.0:
        com.mriss.products:dsh:pom:0.3.0 (absent)
```

**A real release is expected to behave differently, and worse.** That step runs *after*
`release:perform` has deployed `0.3.0` to the registry, so `com.mriss.products:dsh:pom:0.3.0`
resolves, `scm:checkin` succeeds, and the hotfix branch is committed with a root at
`0.3.1-SNAPSHOT` and twelve modules inheriting `0.3.0` from a parent declaration that was never
updated. The `0.3.x` line then starts life re-releasing the version it was branched from.

This is reasoning from the order of the steps and from what `release:perform` deploys, not a
measurement — a rehearsal cannot produce it, because a rehearsal deploys nothing. It is recorded
here because it decides the shape of the fix: **the remedy needs a positive assertion that the
versions are right, not merely the absence of the error `scm:checkin` happened to raise.** §3 is
that assertion.

---

## 2. The remedy

### 2.1 The command

In `target/checkout`, replacing the `versions:set` call:

```bash
ROOT_GROUP_ID=$(mvn -q -N -DforceStdout -Dexpression=project.groupId help:evaluate)
ROOT_ARTIFACT_ID=$(mvn -q -N -DforceStdout -Dexpression=project.artifactId help:evaluate)

mvn -B -DautoVersionSubmodules=true \
  "-Dproject.dev.${ROOT_GROUP_ID}:${ROOT_ARTIFACT_ID}=${{ inputs.initial_hotfix_version }}" \
  release:update-versions
```

Measured from a tree in exactly the state the real step sees it — all 13 POMs at the **released**
`0.3.0`, not at a SNAPSHOT:

```text
13 files changed, 13 insertions(+), 13 deletions(-)
```

One line per POM, the root's own `<version>` and each module's `<parent><version>`, nothing else
touched. No `pom.xml.releaseBackup`, no `release.properties`, no untracked file of any kind is
left behind for `scm:checkin` to sweep in — checked with `git status --untracked-files=all`.

The `mvn -q -N … help:evaluate` lookup is the house pattern already used twice in
`project-hotfix.yml:160` and `:166`. It prints the value alone, with no surrounding whitespace.

`-DautoVersionSubmodules=true` is deliberate even though `dsh`'s modules carry no `<version>` of
their own and inherit it. A consumer whose modules *do* declare one would otherwise have each of
them auto-incremented independently instead of following the root.

### 2.2 Why `project.dev.<groupId>:<artifactId>` and not `-Dbuild.NEXT_DEVELOPMENT_VERSION`

Both reach 13 of 13. The difference is what they depend on.

`project.dev.<groupId>:<artifactId>` is a per-project property the release plugin reads directly.
It is not one of the names bound in `pom.xml`'s release `<configuration>`, so the trap of the
global constraint above does not apply to it — measured: it produced `0.3.1-SNAPSHOT` across all
13 modules *while* `<developmentVersion>${build.NEXT_DEVELOPMENT_VERSION}</developmentVersion>`
was bound and unresolved.

`-Dbuild.NEXT_DEVELOPMENT_VERSION` works only by feeding that binding. It routes the *hotfix*
version through a property whose name says "next development version", and a consumer that
overrides the release plugin's `<configuration>` gets a silently different version. Rejected for
both reasons.

### 2.3 A side effect worth keeping

`release:update-versions` rejects a non-SNAPSHOT target:

```text
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-release-plugin:3.1.1:update-versions
        (default-cli) on project dsh: 0.3.0 is invalid, expected a snapshot
```

So an operator who dispatches `initial_hotfix_version: 0.3.1` instead of `0.3.1-SNAPSHOT` now
fails at that step instead of opening a hotfix line pinned to a release version. `versions:set`
accepted it.

---

## 3. The guard

### 3.1 What it checks, and why this check

`mvn -B validate` in the checkout builds the model for every module and prints one line each:

```text
[INFO] Building DSH - Document Smart Highlights 0.3.1-SNAPSHOT           [1/13]
[INFO] Building DSH Test Data Set 0.3.1-SNAPSHOT                         [2/13]
…
[INFO] Building DSH Coverage Report Aggregation Module 0.3.1-SNAPSHOT   [13/13]
```

Asserting that every one of those carries `initial_hotfix_version` catches both failure modes of
§1.3 with one command: an unresolvable parent makes `validate` itself fail, and a resolvable but
skewed reactor makes the assertion fail with the offending modules named. It costs 12 seconds on
the `dsh` reactor, measured, and it needs nothing the step does not already have — the
`settings.xml` with registry credentials is written long before.

The check is a *version equality*, not a count of changed files. Counting would fail on a
consumer that legitimately holds an independently-versioned module, and would pass a reactor that
changed every file to the wrong value.

### 3.2 Where it lives

A new composite action, `.github/actions/verify-reactor-version`, with the Maven run in
`action.yml` and the parsing in `assert-reactor-version.sh` beside its `*.test.sh`. Parsing a log
has edge cases — a single-module reactor prints no `[n/m]` suffix, and `Building jar:` is a
different message from a different plugin — so it is a tested script rather than inline `bash`,
which is the pattern `check-placeholders.sh` and `render-properties.sh` already set.

It replaces `#72`'s rehearsal-only evidence block at `project-release.yml:259-273`. That block
existed to measure `#69`; the assertion supersedes it, prints the same fact in both modes, and
fails the run instead of recording a number nobody reads on a green run.

---

## 4. The changes, file by file

### 4.1 `.github/actions/verify-reactor-version/action.yml` — new

```yaml
name: Verify reactor version
description: >
  Fail unless every module of the Maven reactor in `working-directory` reports the expected
  version. See specs/69-set-hotfix-version-on-every-module.md.

inputs:
  expected-version:
    description: The version every module must carry, e.g. 0.3.1-SNAPSHOT.
    required: true
  working-directory:
    description: The directory holding the reactor root POM. Defaults to the workspace.
    required: false
    default: '.'

runs:
  using: composite
  steps:
    - name: Verify every module carries the expected version
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      # The version reaches the script through the environment rather than being interpolated
      # into the run body, for the same reason maven-properties does it: an input is not a
      # literal until something makes it one.
      env:
        EXPECTED_VERSION: ${{ inputs.expected-version }}
      run: |
        set -euo pipefail

        log="$RUNNER_TEMP/verify-reactor-version.log"

        # validate is the cheapest phase that still builds the model of every module, which is
        # what makes a missing parent version fail here rather than at the next command.
        if ! mvn -B validate > "$log" 2>&1; then
          echo "::error::mvn -B validate failed in $(pwd). The reactor does not build its" \
               "model — a module very likely names a parent version that does not exist."
          cat "$log"
          exit 1
        fi

        summary="$("$GITHUB_ACTION_PATH/assert-reactor-version.sh" "$EXPECTED_VERSION" "$log")"
        echo "$summary"
        echo "- **#69 check** — $summary" >> "$GITHUB_STEP_SUMMARY"
```

### 4.2 `.github/actions/verify-reactor-version/assert-reactor-version.sh` — new

```sh
#!/bin/sh
# Assert that every module of a Maven reactor is at the expected version.
#
#   assert-reactor-version.sh <expected-version> <maven-log>
#
# The input is the log of a Maven run over the whole reactor; each module contributes one
# "[INFO] Building <name> <version> [n/m]" line. Parsing that is deliberate: it reports the
# version Maven resolved for each module, which is what the hotfix branch will carry, rather
# than what any single pom.xml happens to say. specs/69-set-hotfix-version-on-every-module.md
# §3 has the reasoning, and #69 has the failure it exists to stop.
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: assert-reactor-version.sh <expected-version> <maven-log>" >&2
  exit 1
fi

expected="$1"
log="$2"

if [ ! -f "$log" ]; then
  echo "::error::no Maven log at '$log'." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The [n/m] progress suffix is absent in a single-module reactor, so it is stripped only when
# present. "Building jar:", "Building war:" and their siblings are packaging messages from a
# different plugin: a validate-only run never reaches them, and skipping them costs nothing if
# some caller ever runs a later phase.
sed -n 's/^\[INFO\] Building \(.*\)$/\1/p' "$log" \
  | grep -vE '^(jar|war|ear|zip|rar|maven-plugin):' \
  | sed -e 's/[[:space:]]*\[[0-9][0-9]*\/[0-9][0-9]*\][[:space:]]*$//' \
  > "$TMP/modules"

if [ ! -s "$TMP/modules" ]; then
  echo "::error::'$log' holds no '[INFO] Building …' line. Either the run never reached a" \
       "module or the log is not a Maven reactor log — either way the versions are unverified" \
       "and this must not pass." >&2
  exit 1
fi

count=0
: > "$TMP/offenders"
while IFS= read -r line; do
  count=$((count + 1))
  version="${line##* }"
  name="${line% *}"
  if [ "$version" != "$expected" ]; then
    printf '  %s is at %s\n' "$name" "$version" >> "$TMP/offenders"
  fi
done < "$TMP/modules"

if [ -s "$TMP/offenders" ]; then
  bad="$(wc -l < "$TMP/offenders" | tr -d ' ')"
  echo "::error::$bad of $count module(s) are not at $expected:" >&2
  cat "$TMP/offenders" >&2
  echo "Committing this would leave the branch with a mixed-version reactor. See #69." >&2
  exit 1
fi

echo "all $count module(s) are at $expected"
```

### 4.3 `.github/actions/verify-reactor-version/assert-reactor-version.test.sh` — new

Structured like `assert-markers.test.sh`: `pass`/`fail` helpers, a `check_exit` and a
`check_says`, a `$TMP` scrubbed by `trap`, and a non-zero exit when any case fails. The fixtures
are real lines from the `dsh` reactor.

```sh
#!/bin/sh
# Tests for assert-reactor-version.sh. Run: sh assert-reactor-version.test.sh
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/assert-reactor-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

check_exit() {
  description="$1"; expected="$2"; version="$3"; file="$4"
  sh "$SCRIPT" "$version" "$file" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then pass "$description"
  else fail "$description (expected exit $expected, got $actual)"; fi
}

check_says() {
  description="$1"; needle="$2"; version="$3"; file="$4"
  output="$(sh "$SCRIPT" "$version" "$file" 2>&1)"
  if printf '%s' "$output" | grep -qF "$needle"; then pass "$description"
  else
    fail "$description"
    printf '       expected output to contain: %s\n' "$needle"
    printf '       actual output:\n%s\n' "$output"
  fi
}

# A reactor log at one uniform version. $1 is the version every module carries.
write_uniform_log() {
  version="$1"; file="$TMP/uniform-$version.log"
  cat > "$file" <<EOF
[INFO] Scanning for projects...
[INFO] Building DSH - Document Smart Highlights $version           [1/13]
[INFO] Building DSH Test Data Set $version                         [2/13]
[INFO] Building dsh-data $version                                  [3/13]
[INFO] Building DSH REST API $version                              [4/13]
[INFO] Building DSH - SOLR Extensions/Plugins $version             [5/13]
[INFO] Building SOLR - Terms Vector Orderer $version               [6/13]
[INFO] Building SOLR - Advanced Numbers Filter $version            [7/13]
[INFO] Building DSH - Document Indexer Worker $version             [8/13]
[INFO] Building DSH - Document Analyzer $version                   [9/13]
[INFO] Building DSH - Document Keyword Extractor $version         [10/13]
[INFO] Building dsh-top-sentences-extractor $version              [11/13]
[INFO] Building DSH - Document Processor Worker $version          [12/13]
[INFO] Building DSH Coverage Report Aggregation Module $version   [13/13]
[INFO] BUILD SUCCESS
EOF
  printf '%s' "$file"
}
```

The `#69` fixture of case 2 is the uniform `0.3.0` log with its **first** line rewritten to
`0.3.1-SNAPSHOT` — root moved, twelve modules left behind, which is exactly what run
35662168807 produced. Case 6 appends `[INFO] Building jar: /home/runner/work/dsh/x.jar` to a good
log. Case 4 is one `[INFO] Building dsh-data 0.3.1-SNAPSHOT` line with no progress suffix.

Cases, all required:

| # | Fixture | Expected |
|---|---|---|
| 1 | 13 modules, all at `0.3.1-SNAPSHOT` | exit 0, says `all 13 module(s) are at 0.3.1-SNAPSHOT` |
| 2 | the `#69` shape: root at `0.3.1-SNAPSHOT`, 12 at `0.3.0` | exit 1, says `12 of 13`, names `dsh-data` |
| 3 | 13 modules, one at a wrong version | exit 1, says `1 of 13` |
| 4 | one module, no `[n/m]` suffix, right version | exit 0, says `all 1 module(s)` |
| 5 | a log with no `Building` line at all | exit 1, says `holds no` |
| 6 | a good log that also contains `[INFO] Building jar: /x/y.jar` | exit 0, says `all 13` |
| 7 | one argument instead of two | exit 1, says `usage:` |
| 8 | a log path that does not exist | exit 1, says `no Maven log` |

Case 2 is the regression test for this issue and case 6 is the one that would break under a naive
`grep`; neither is optional.

### 4.4 `.github/workflows/project-release.yml` — modify

Replace the body of `Checkout Hotfix Branch and Set Initial Version` (`:242-278`) with three
steps. The `scm:checkout` block at `:244-256` is unchanged and is elided here as `…`:

```yaml
      - name: Checkout Hotfix Branch and Set Initial Version
        run: |
          …

          cd target/checkout

          # #69: `versions:set -DprocessAllModules=true` rewrote the root POM and nothing else —
          # measured at 1 of 13 on the dsh reactor (run 35662168807), and neither a flag nor a
          # plugin-version problem: -DgroupId='*' -DartifactId='*' -DoldVersion='*' and
          # versions-maven-plugin 2.20.0 both reproduce it. It is an aggregator goal; it computes
          # the change for every module and writes one file.
          #
          # release:update-versions keyed by the root's own coordinates reaches all 13.
          # project.dev.<groupId>:<artifactId> rather than -DdevelopmentVersion or
          # -Dbuild.NEXT_DEVELOPMENT_VERSION: it is a per-project property, so it is not one of
          # the names pom.xml's release <configuration> binds, and a -D naming one of those is
          # inert. See specs/69-set-hotfix-version-on-every-module.md §2.2.
          ROOT_GROUP_ID=$(mvn -q -N -DforceStdout -Dexpression=project.groupId help:evaluate)
          ROOT_ARTIFACT_ID=$(mvn -q -N -DforceStdout -Dexpression=project.artifactId help:evaluate)

          mvn -B -DautoVersionSubmodules=true \
            "-Dproject.dev.${ROOT_GROUP_ID}:${ROOT_ARTIFACT_ID}=${{ inputs.initial_hotfix_version }}" \
            release:update-versions

      # #69: in a rehearsal a wrong version here fails the next command outright, because
      # nothing was deployed for the stale parent to resolve against. In a real release the
      # registry holds it, scm:checkin succeeds, and the hotfix line silently starts at the
      # version it was branched from. So the check is positive and runs in both modes; it
      # replaces the rehearsal-only evidence line #72 added to measure this issue.
      - name: Verify every module carries the hotfix version
        uses: MRISS-Projects/parent-poms/.github/actions/verify-reactor-version@master
        with:
          expected-version: ${{ inputs.initial_hotfix_version }}
          working-directory: target/checkout

      - name: Commit the Hotfix Version
        run: |
          cd target/checkout

          bash "$RUNNER_TEMP/rehearsal-marker.sh" scm-checkin-hotfix-version \
            "push the ${{ inputs.initial_hotfix_version }} version change to ${{ inputs.hotfix_branch }}"

          mvn -B $RH_SCM_LOCAL_URL -Dmessage="[maven-release-plugin] set hotfix version ${{ inputs.initial_hotfix_version }}" scm:checkin
```

Splitting the step is forced: a composite action cannot run inside a `run:` block, and the
assertion must sit between the version change and the commit. Each step re-enters
`target/checkout`, since a `cd` does not survive a step boundary.

Also update the comment at `:204`, which says the bridge exists so that "`#69`'s `versions:set`
and `#65`'s merge-back" are reachable. The reason is unchanged, the command is not: it is the
hotfix version step.

### 4.5 `specs/github-actions-reusable-workflows.md` — modify

- §6.3 step 9 (`:757-776`): replace the `versions:set` line in the quoted block with the lookup
  plus `release:update-versions`, and show the verification step between it and `scm:checkin`.
- The Jenkinsfile mapping table (`:830`): `Generates Version at Hotfix Branch` maps to
  "Step 9 (`release:update-versions` + verify + `scm:checkin`)".

---

## 5. Validating it

`dsh` is the only consumer of these workflows, and its wrappers reach them at `@master`, so a
rehearsal against the task branch needs two temporary pins — one in each repository. This is the
route `#76` Task 11 used.

1. In `dsh`, on a scratch branch cut from the RC, point `release.yml`'s `uses:` at
   `@issue-69-set-hotfix-version-on-every-module`.
2. In this repository, on the task branch, point the new action's `uses:` at the same ref
   (Task 6). `build.yml` goes red on the pin guard while it is flipped; that is expected and
   Task 8 flips it back.
3. Dispatch `release.yml` with `dry_run: true` and the inputs `#72` Task 9 used:
   `current_version: 0.3.0`, `next_development_version: 0.4.0-SNAPSHOT`, `hotfix_branch: 0.3.x`,
   `initial_hotfix_version: 0.3.1-SNAPSHOT`.
4. Delete the scratch branch afterwards and confirm `git ls-remote --heads origin` matches the
   listing taken before the run — `#72` Tasks 9 and 10 set that precedent, and `assert-no-writes`
   checks it from inside the run.

The two steps `#72` needed to recreate a rehearsal — adding `mongo.*` properties by hand and
copying `release.yml` with a `dry_run` passthrough — are both gone now that
[`dsh#114`](https://github.com/MRISS-Projects/dsh/issues/114) and
[`dsh#111`](https://github.com/MRISS-Projects/dsh/issues/111) have landed.

**What the run must show:**

- `Verify every module carries the hotfix version` passes with
  `all 13 module(s) are at 0.3.1-SNAPSHOT`, and the same sentence in the step summary.
- `scm:checkin` gets past the parent resolution that killed run 35662168807, and the
  `scm-checkin-hotfix-version` marker fires.
- The four markers downstream of that failure — `merge-to-master`, `site-deploy`,
  `commit-readme`, `remove-rc-branch` — fire for the first time in a `project-release.yml` run,
  so `assert-markers` sees all eight and `#72`'s AC006 closes with it.
- `assert-no-writes` reports the remote byte-for-byte unchanged.

---

## 6. Tasks

- [x] **Task 1 — the test suite, red.** Create
      `.github/actions/verify-reactor-version/assert-reactor-version.test.sh` with the eight cases
      of §4.3 and real `dsh` fixture lines. Run `sh assert-reactor-version.test.sh`: it must fail,
      because the script does not exist yet. Commit the failing suite on its own.
- [x] **Task 2 — the script, green.** Create `assert-reactor-version.sh` exactly as §4.2.
      `git update-index --chmod=+x` both files. Run the suite: eight `ok`, exit 0. Commit.
- [ ] **Task 3 — `action.yml`.** Create it as §4.1. Verify with
      `git ls-files -s .github/actions/verify-reactor-version/` that both scripts are `100755`.
      Commit.
- [ ] **Task 4 — prove the command locally, before touching the workflow.** In a throwaway
      worktree of `dsh`'s RC with every POM edited to the released `0.3.0`, run the two
      `help:evaluate` lookups and `release:update-versions` from §2.1, then
      `git status --porcelain '*pom.xml' | wc -l`. Expect `13`, a diff of 13 insertions and 13
      deletions, and no untracked file. Then run `mvn -B validate > /tmp/v.log` and
      `sh assert-reactor-version.sh 0.3.1-SNAPSHOT /tmp/v.log`; expect
      `all 13 module(s) are at 0.3.1-SNAPSHOT`. Record both outputs in this spec's Task 4 results
      block. **This is the end-to-end rehearsal of the fix that costs nothing to repeat** — do it
      before the workflow edit, not after.
- [ ] **Task 5 — `project-release.yml`.** Apply §4.4: the three steps, the new comments, and the
      `:204` touch-up. Delete the `RH_ACTIVE` evidence block. Commit.
- [ ] **Task 6 — pin for validation.** Point the new action's `uses:` at
      `@issue-69-set-hotfix-version-on-every-module`, and push. Expect `build.yml` red on
      "Check this repository's actions are pinned to master" and green elsewhere; note the run
      URL in the spec. Commit.
- [ ] **Task 7 — the rehearsal.** Run §5 steps 1, 3 and 4. Record in this spec: the run URL, the
      verification step's output, all eight markers, the `assert-no-writes` block, and the
      `git ls-remote --heads origin` comparison. Link the run in the PR.
- [ ] **Task 8 — unpin.** Flip the action reference back to `@master`, confirm `build.yml` is
      green, and confirm the `dsh` scratch branch is deleted. Commit.
- [ ] **Task 9 — docs.** Apply §4.5 to `specs/github-actions-reusable-workflows.md`. Commit.
- [ ] **Task 10 — report.** Comment on `#69` with the measurement from Task 4 and the rehearsal
      from Task 7, and on [`#72`](https://github.com/MRISS-Projects/parent-poms/issues/72) that
      its AC006 now has its eighth marker. Neither issue is closed by Claude.

---

## 7. Acceptance criteria

- [ ] **AC001** — `project-release.yml` sets `initial_hotfix_version` on every module of the
      consuming reactor, not only the root. Proven by Task 7's run and by Task 4's local
      measurement.
- [ ] **AC002** — A hotfix step that leaves any module at another version fails at that step,
      naming the offending modules, before `scm:checkin` runs. Proven by the test suite's case 2
      and by the assertion's position in §4.4.
- [ ] **AC003** — The check runs in real releases and rehearsals alike. No `RH_ACTIVE` guard
      remains around it, and `#72`'s rehearsal-only evidence block is gone.
- [ ] **AC004** — `project-release.yml` completes past `scm:checkin` in a `dry_run` rehearsal of
      `dsh`, with all eight declared markers fired and `assert-no-writes` clean.
- [ ] **AC005** — `assert-reactor-version.sh` has a `*.test.sh` beside it that `build.yml` runs,
      both files are committed `100755`, and the action is pinned `@master` at merge.
- [ ] **AC006** — The reference doc describes the step as it is.

---

## 8. Out of scope

- **`deploy.yml`.** It calls `versions:set` twice, at `:346` and `:355`, both `-N` and
  root-only, with a `versions:update-parent` recursion for parent-poms' own
  independently-versioned modules. That is a correct design for that case, not an instance of
  this bug.
- **`project-hotfix.yml`.** Checked: it has no version-setting step. It runs `release:prepare`
  and `release:perform` on a branch whose POMs already carry the hotfix version, and its own
  comment at `:268` says so — "Five, not eight: no `scm:branch`, no `versions:set` checkin, no
  RC deletion". Nothing to fix there.
- **Bumping `versions.plugin.version`.** 2.20.0 reproduces the defect (§1.2), so a bump buys
  nothing here. `#59`-style version maintenance is its own concern.
- **`#65`, the merge back into `DEVELOP`.** This story makes the steps after `scm:checkin`
  reachable, which `#65` needs, but adds none of them.
- **Releasing `3.9.0`.** The milestone has four other open issues; clearing it is not this
  story's job.
