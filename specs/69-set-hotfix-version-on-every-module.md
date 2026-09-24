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
`release:update-versions`, driven through `build.NEXT_DEVELOPMENT_VERSION`, instead of
`versions:set`, which rewrites the root POM and nothing else. The result is then asserted by a
new composite action that runs `mvn -B validate` in the checkout and requires every
`[INFO] Building …` line to carry the expected version. The assertion runs in real releases and
rehearsals alike, and it replaces `#72`'s rehearsal-only evidence line with a permanent check.

**Tech stack.** GitHub Actions composite actions; POSIX `sh`; `maven-release-plugin` 3.1.1 (via
`${release.plugin.version}`); Maven **3.9.9 in CI**, which every workflow here
pins via `stCarolas/setup-maven`. The local measurements in §1 and §2 were taken on Maven 3.9.16
against the real `MRISS-Projects/dsh` 13-module reactor.

> **This spec was corrected after review; see §6.1.** Its first version specified
> `-Dproject.dev.<groupId>:<artifactId>`, which moves only the root module, and every
> measurement it offered as proof used the one hotfix version at which that is indistinguishable
> from the right answer. §1's table, §1.3, §2.1, §2.2 and the Task 4 and Task 7 result blocks
> all carry the correction inline rather than being rewritten, because how the mistake survived
> a green end-to-end rehearsal is the more useful record.

---

## Global constraints

- Profiles are activated by `-D<name>`, never `-P`. **Never reintroduce `-P`.**
- **`<configuration>` beats the user property.** `pom.xml:365-377` binds `arguments`,
  `tagNameFormat`, `allowTimestampedSnapshots`, `preparationGoals`, `goals`, `scmCommentPrefix`,
  `branchName`, `developmentVersion` and `releaseVersion` in the release plugin's
  `<configuration>`. Any `-D` naming one of those **parameters** is inert. Check that list before
  reaching for a command-line flag — it is what makes `-DdevelopmentVersion` useless here.
  **The constraint is about parameter names, not about every name that appears in the block.**
  `<developmentVersion>` is bound to `${build.NEXT_DEVELOPMENT_VERSION}`, and that is a POM
  interpolation variable, so `-Dbuild.NEXT_DEVELOPMENT_VERSION` resolves normally and reaches the
  plugin — it is the mechanism §2.1 uses. Reading the constraint as covering it too is what sent
  the first attempt at §2.2 down the wrong path.
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

> **Both of those last two rows are a trap, and the first of them nearly shipped.** `0.3.1-SNAPSHOT`
> is exactly what the release plugin's default version policy produces from `0.3.0` unaided, so
> **every** command that moves the root at all scores 13 of 13 here, whatever it does to the other
> twelve. The measurement cannot tell the two mechanisms apart. §2.2 re-runs it at a version that
> is *not* the natural increment, which is the only form of this measurement worth trusting.

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

### 1.3 Nothing downstream catches it — in either mode

**This section originally claimed the opposite, and was wrong. Corrected in review; the original
reasoning is kept below because the correction is the whole argument for §3.**

The claim was that a rehearsal fails loudly, because `dry_run` deploys nothing and so the parent
version the twelve modules still name exists in no repository:

```text
[ERROR] Non-resolvable parent POM for com.mriss.products.dsh:dsh-data:0.3.0:
        com.mriss.products:dsh:pom:0.3.0 (absent)
```

That is not what a rehearsal does. `rehearsal-tag/action.yml` runs `mvn … install` of the
release-version artifacts precisely so later steps resolve — its own comment says so — so
`com.mriss.products:dsh:pom:0.3.0` sits in the runner's local repository by the time this step
runs, and a stale parent resolves. The error above was quoted from
[`dsh` run 35662168807](https://github.com/MRISS-Projects/dsh/actions/runs/35662168807), whose
`Checkout Hotfix Branch and Set Initial Version` step did fail; **that run's logs have since
expired (HTTP 410) and the quote can no longer be checked**, so what actually failed there is
now unknown. It is not evidence for anything and is not relied on here.

A real release does not catch it either, for the reason originally given: that step runs *after*
`release:perform` has deployed `0.3.0` to the registry, so the parent resolves, `scm:checkin`
succeeds, and the hotfix branch is committed with a root at the hotfix version and twelve modules
inheriting the released one. The `0.3.x` line then starts life re-releasing the version it was
branched from.

So **both** modes commit a mixed-version reactor quietly. That is what decides the shape of the
fix: the remedy needs a positive assertion that the versions are right, because there is no error
whose absence means anything. §3 is that assertion — and §2.2 is the record of it catching a real
defect in the first attempt at §2.1.

---

## 2. The remedy

### 2.1 The command

In `target/checkout`, replacing the `versions:set` call:

```bash
mvn -B -Dbuild.NEXT_DEVELOPMENT_VERSION=${{ inputs.initial_hotfix_version }} \
  release:update-versions
```

`pom.xml:375` binds `<developmentVersion>${build.NEXT_DEVELOPMENT_VERSION}</developmentVersion>`,
so a `-D` on that name resolves the interpolation and the value becomes the default development
version for **every** project in the reactor. It is a POM interpolation variable, not a plugin
parameter's user property, which is exactly why the "`<configuration>` beats the user property"
constraint does not bite here — while `-DdevelopmentVersion`, which names the parameter, is
rendered inert by that same binding.

Measured from a tree in exactly the state the real step sees it — all 13 POMs at the **released**
`0.3.0`, not at a SNAPSHOT — and asking for `0.9.9-SNAPSHOT`, deliberately *not* the natural
increment:

```text
13 files changed, 13 insertions(+), 13 deletions(-)      all at 0.9.9-SNAPSHOT
${project.version} references: untouched
untracked (--untracked-files=all): (none)
```

One line per POM, the root's own `<version>` and each module's `<parent><version>`, nothing else
touched. No `pom.xml.releaseBackup`, no `release.properties`, no untracked file of any kind is
left behind for `scm:checkin` to sweep in.

### 2.2 Why not `project.dev.<groupId>:<artifactId>` — a defect caught in review

**This section previously recommended `-Dproject.dev.<groupId>:<artifactId>` and rejected
`-Dbuild.NEXT_DEVELOPMENT_VERSION`. That was wrong, it was implemented, it passed a full
rehearsal, and code review caught it. The record is kept because the way it hid is the lesson.**

`project.dev.<groupId>:<artifactId>` sets the development version of **one project** — the one
whose coordinates it names. Here that is the root, and nothing else. The other twelve modules
fall through to the release plugin's default version policy, which increments **each module's
own** version independently.

`-DautoVersionSubmodules=true` does not rescue it. `AbstractMapVersionsPhase` takes that path
only when `isAutoVersionSubmodules() && ArtifactUtils.isSnapshot(rootProject.getVersion())`, and
at this point `target/checkout` is a checkout of the release tag, so the root is at `0.3.0` — a
release version. The guard fails and the per-project branch runs.

The two mechanisms **agree exactly** when `initial_hotfix_version` is
`MAJOR.MINOR.(FIX+1)-SNAPSHOT` of the released version, because that is what the policy computes
unaided. `0.3.0` → `0.3.1-SNAPSHOT` is that case. Every measurement in the first pass of this
story used it, including a green end-to-end rehearsal, so nothing disagreed with anything.

Re-measured at `0.9.9-SNAPSHOT` off `0.3.0`, the disagreement is stark:

```text
  8 lines ->  0.9.9-SNAPSHOT      root <version> and each <parent><version>
 12 lines ->  0.3.1-SNAPSHOT      the policy default, NOT what was asked for
  9 lines:   <version>${project.version}</version>  ->  <version>0.3.1-SNAPSHOT</version>
```

— a mixed-version reactor, plus nine `dependencyManagement` entries in the root POM that were
deliberately `${project.version}` hardcoded to a version the build no longer carries. (Those nine
survive in the coincidence case only because `${project.version}` still resolves correctly when
root and modules land together.)

`initial_hotfix_version` is a free-text `workflow_dispatch` input and no step validates its shape,
so this is reachable by typing: release `1.0.0`, open the hotfix line at `1.1.0-SNAPSHOT`.

The original objection to `-Dbuild.NEXT_DEVELOPMENT_VERSION` — that it routes a *hotfix* version
through a property whose name says "next development version", so a consumer who overrides the
release plugin's `<configuration>` would silently get something else — is a real one, and is not
dismissed. It is answered by §3: that consumer now fails at the verification step, loudly and by
name, instead of silently. The guard is what converts this class of mistake from silent to loud,
which is an argument for keeping the guard rather than against the flag.

**The check caught this defect.** Run against the `project.dev` tree at `0.9.9-SNAPSHOT`:

```text
::error::12 of 13 module(s) are not at 0.9.9-SNAPSHOT:
  DSH Test Data Set is at 0.3.1-SNAPSHOT
  dsh-data is at 0.3.1-SNAPSHOT
  …
```

That is AC002 firing on a real defect rather than on a fixture.

### 2.3 A side effect worth keeping

`release:update-versions` rejects a non-SNAPSHOT target:

```text
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-release-plugin:3.1.1:update-versions
        (default-cli) on project dsh: 0.3.0 is invalid, expected a snapshot
```

So an operator who dispatches `initial_hotfix_version: 0.3.1` instead of `0.3.1-SNAPSHOT` now
fails at that step instead of opening a hotfix line pinned to a release version. `versions:set`
accepted it.

Re-checked against §2.1's corrected command, since the rejection could plausibly have lived in
the `project.dev` path alone: `-Dbuild.NEXT_DEVELOPMENT_VERSION=0.3.1` exits **1** with
`0.3.1 is invalid, expected a snapshot` and leaves every POM untouched. The side effect survives
the correction.

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
# present. "Building jar:", "Building tar.gz:" and their siblings are packaging messages from a
# different plugin: a validate-only run never reaches them, and skipping them costs nothing if
# some caller ever runs a later phase.
#
# The filter matches the SHAPE of those messages — a lowercase packaging token, then a colon
# and a space — rather than enumerating types. An enumeration was tried first and missed tar,
# tar.gz, tar.bz2 and sar; any list would go stale the next time a packaging is added, and a
# missed one is read as a module named "Building" at a version of "/x/y.tar.gz". A module line
# cannot collide with this: it carries a version after the name, never a colon.
sed -n 's/^\[INFO\] Building \(.*\)$/\1/p' "$log" \
  | grep -vE '^[a-z][a-z0-9.-]*: ' \
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
| 6b | the same for `war ear zip rar tar tar.gz tar.bz2 sar maven-plugin`, one log each | exit 0, says `all 13` |
| 7 | one argument instead of two | exit 1, says `usage:` |
| 8 | a log path that does not exist | exit 1, says `no Maven log` |

Case 2 is the regression test for this issue and case 6 is the one that would break under a naive
`grep`; neither is optional. Case 6b was added in review: the filter originally enumerated six
packaging types and missed `tar`, `tar.gz`, `tar.bz2` and `sar`, so it now matches the shape of a
packaging message instead of a list that would go stale again.

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
          # release:update-versions reaches all 13, driven through build.NEXT_DEVELOPMENT_VERSION.
          # pom.xml:375 binds <developmentVersion> to that property, so a -D resolves it and it
          # becomes the default development version for EVERY project in the reactor. It is a POM
          # interpolation variable, not a plugin parameter's user property, which is why the
          # "<configuration> beats the user property" trap does not apply to it — unlike
          # -DdevelopmentVersion, which that same binding does render inert.
          #
          # -Dproject.dev.<groupId>:<artifactId> was tried first and is WRONG here, subtly: it
          # moves the root and nothing else, and the other twelve modules are then moved by the
          # release plugin's default version policy, which increments each module's own version.
          # -DautoVersionSubmodules=true does not save it, because the plugin takes that path only
          # when the root is a SNAPSHOT and this checkout is the release tag. The two agree only
          # when initial_hotfix_version happens to equal MAJOR.MINOR.(FIX+1)-SNAPSHOT of the
          # release, which is what made the first measurement of this look correct. Asking for
          # 0.9.9-SNAPSHOT off 0.3.0 instead produced a mixed reactor AND rewrote nine
          # ${project.version} references in the root to a hardcoded 0.3.1-SNAPSHOT.
          # See specs/69-set-hotfix-version-on-every-module.md §2.2.
          mvn -B -Dbuild.NEXT_DEVELOPMENT_VERSION=${{ inputs.initial_hotfix_version }} \
            release:update-versions

      # #69: nothing upstream of this catches a wrong version here. A rehearsal will not: the
      # bridge installs the release-version artifacts locally (rehearsal-tag/action.yml), so a
      # stale parent resolves and scm:checkin succeeds. A real release will not either: by this
      # point release:perform has deployed them, so the hotfix line just quietly starts at the
      # version it was branched from. Hence a POSITIVE assertion, in both modes — the absence of
      # an error proves nothing here. It replaces the rehearsal-only evidence line #72 added to
      # measure this issue, and it has already earned its keep: it is what caught the
      # project.dev.<g>:<a> defect described in the previous step's comment.
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
- [x] **Task 3 — `action.yml`.** Create it as §4.1. Verify with
      `git ls-files -s .github/actions/verify-reactor-version/` that both scripts are `100755`.
      Commit.
- [x] **Task 4 — prove the command locally, before touching the workflow.** In a throwaway
      worktree of `dsh`'s RC with every POM edited to the released `0.3.0`, run the two
      `help:evaluate` lookups and `release:update-versions` from §2.1, then
      `git status --porcelain '*pom.xml' | wc -l`. Expect `13`, a diff of 13 insertions and 13
      deletions, and no untracked file. Then run `mvn -B validate > /tmp/v.log` and
      `sh assert-reactor-version.sh 0.3.1-SNAPSHOT /tmp/v.log`; expect
      `all 13 module(s) are at 0.3.1-SNAPSHOT`. Record both outputs in this spec's Task 4 results
      block. **This is the end-to-end rehearsal of the fix that costs nothing to repeat** — do it
      before the workflow edit, not after.

      > **Superseded — read §2.2 first.** Everything below measured the command at
      > `0.3.1-SNAPSHOT` off `0.3.0`, which is the one value at which the wrong command and the
      > right one agree. It is recorded unchanged because the shape of the mistake matters: the
      > numbers are all real and all correct, and they still do not establish what they were
      > taken to establish. Task 4R below is the measurement that does.

      **Task 4 results.** Maven 3.9.16, worktree `D:\w69-task4` detached at `94060ecf`, all 13
      POMs edited to the released `0.3.0` and committed, so the baseline was clean
      (`git status --porcelain --untracked-files=all` empty).

      The lookups printed the coordinates alone, no surrounding whitespace:

      ```text
      ROOT_GROUP_ID=[com.mriss.products]
      ROOT_ARTIFACT_ID=[dsh]
      ```

      `mvn -B -DautoVersionSubmodules=true -Dproject.dev.com.mriss.products:dsh=0.3.1-SNAPSHOT
      release:update-versions` exited 0, and:

      ```text
      git status --porcelain '*pom.xml' | wc -l   ->  13
      git diff --shortstat  ->  13 files changed, 13 insertions(+), 13 deletions(-)
      untracked (--untracked-files=all)  ->  (none)
      ```

      The whole diff is 13 `<version>` lines — 9 tab-indented, 3 space-indented, 1 at the root —
      each `0.3.0` to `0.3.1-SNAPSHOT`, per-file indentation preserved. Nothing else moved; the
      `<scm><tag>` at `pom.xml:277` is untouched.

      Then `mvn -B validate` exited 0 and the guard agreed:

      ```text
      $ sh assert-reactor-version.sh 0.3.1-SNAPSHOT .logs/validate.log
      all 13 module(s) are at 0.3.1-SNAPSHOT
      $ echo $?
      0
      ```

      The reactor's real `[INFO] Building …` lines match the §4.3 fixtures line for line, which
      is what makes the suite's fixtures evidence rather than invention.

      **The defect, reproduced in the same worktree.** `mvn -B -DprocessAllModules=true
      -DnewVersion=0.3.1-SNAPSHOT versions:set` exited 0 and rewrote **1 of 13** — a third
      measurement of §1, now on Maven 3.9.16 locally. `mvn -B validate` on what it produced
      exited 1 with the error §1.3 quotes:

      ```text
      [ERROR] The build could not read 7 projects
      [FATAL] Non-resolvable parent POM for com.mriss.products.dsh:dsh-data:0.3.0:
              com.mriss.products:dsh:pom:0.3.0 (absent)
      ```

      and the guard refused it rather than passing vacuously:

      ```text
      ::error::'.logs/validate-broken.log' holds no '[INFO] Building …' line. …
      guard exit=1
      ```

      Both of §1.3's failure modes are therefore covered by measurement: the unresolvable-parent
      one here, and the resolvable-but-skewed one by the suite's case 2 — which cannot be
      measured locally, because `0.3.0` was never deployed. That is the same reason §1.3 reasons
      about it rather than measuring it.

      One local-only observation, recorded so nobody chases it: the release plugin rewrote the
      POMs with CRLF on this Windows box, so `git diff` warned `CRLF will be replaced by LF`.
      The runners are `ubuntu-latest`; this does not arise there, and it changed no content.
- [x] **Task 5 — `project-release.yml`.** Apply §4.4: the three steps, the new comments, and the
      `:204` touch-up. Delete the `RH_ACTIVE` evidence block. Commit.
- [x] **Task 6 — pin for validation.** Point the new action's `uses:` at
      `@issue-69-set-hotfix-version-on-every-module`, and push. Expect `build.yml` red on
      "Check this repository's actions are pinned to master" and green elsewhere; note the run
      URL in the spec. Commit.

      **Task 6 result.** Pin commit `1687c6a1`, build run
      [35911573060](https://github.com/MRISS-Projects/parent-poms/actions/runs/35911573060) —
      failed on `Check this repository's actions are pinned to master` and nothing else. Every
      step before it is green, including the two that matter here:

      ```text
      --- .github/actions/verify-reactor-version/assert-reactor-version.test.sh
      Ran 8 action test suite(s).
      All action scripts are mode 100755.
      ```

      So the new suite is picked up by `build.yml`'s glob with no edit there — #76's
      generalisation working as the global constraint above assumes — and both scripts carry
      the executable bit as CI sees it, not merely as this Windows box reports it.
- [x] **Task 7 — the rehearsal.** Run §5 steps 1, 3 and 4. Record in this spec: the run URL, the
      verification step's output, all eight markers, the `assert-no-writes` block, and the
      `git ls-remote --heads origin` comparison. Link the run in the PR.

      > **Superseded — read §2.2 first.** This rehearsal ran the *wrong* command and passed,
      > because it too used `0.3.1-SNAPSHOT` off `0.3.0`. A green end-to-end run is not evidence
      > that a command is right when the inputs cannot distinguish it from the default. Task 7R
      > re-runs it at a version that can. Everything recorded here about the *workflow* — the
      > step split, the eight markers, `assert-no-writes` — stands; only the conclusion about
      > the command does not.

      **Task 7 result.** [`dsh` run 35911734453](https://github.com/MRISS-Projects/dsh/actions/runs/35911734453),
      dispatched from the scratch branch `scratch-69-rehearsal` at `c595a920`, cut from the RC
      at `94060ecf`. Inputs as §5 step 3, plus `branch_name: staging-0.3.0-SNAPSHOT-RC`, which
      the `dsh` wrapper requires and §5 omitted. **Conclusion: success — every step green.**

      `release:update-versions` transformed all thirteen POMs, where `versions:set` logged one
      `Updating project`:

      ```text
      [INFO] --- release:3.1.1:update-versions (default-cli) @ dsh ---
      [INFO] Transforming pom.xml dsh 'DSH - Document Smart Highlights'...
      [INFO] Transforming dsh-test-dataset/pom.xml dsh-test-dataset 'DSH Test Data Set'...
      [INFO] Transforming dsh-data/pom.xml dsh-data 'dsh-data'...
      …thirteen in all, one per module…
      [INFO] Transforming dsh-coverage-report/pom.xml dsh-coverage-report 'DSH Coverage Report …'
      [INFO] BUILD SUCCESS
      ```

      The verification step then passed, in 5.5 s rather than the 12 s §3.1 budgeted:

      ```text
      EXPECTED_VERSION: 0.3.1-SNAPSHOT
      all 13 module(s) are at 0.3.1-SNAPSHOT
      ```

      `scm:checkin` ran next and succeeded. Run 35662168807 died before it on
      `Non-resolvable parent POM … com.mriss.products:dsh:pom:0.3.0 (absent)`; that error does
      not appear anywhere in this log.

      **All eight markers, for the first time in a `project-release.yml` run.** The four after
      `scm:checkin` had never been reached:

      ```text
      REHEARSAL release-prepare: would commit the release POMs, tag v0.3.0 and push both
      REHEARSAL release-perform-deploy: would check out the tag and deploy the artifacts to the registry
      REHEARSAL scm-branch: would push the new hotfix branch 0.3.x to the remote
      REHEARSAL scm-checkin-hotfix-version: would push the 0.3.1-SNAPSHOT version change to 0.3.x
      REHEARSAL merge-to-master: would push the merge of v0.3.0 to master
      REHEARSAL site-deploy: would publish the generated site to gh-pages
      REHEARSAL commit-readme: would commit and push the generated README.md to master
      REHEARSAL remove-rc-branch: would delete the RC branch staging-0.3.0-SNAPSHOT-RC from the remote

      rehearsal: all 8 declared write point(s) announced exactly once.
      ```

      `assert-no-writes`:

      ```text
        heads: unchanged (14 entries)
        tags: unchanged (12 entries)
        packages: unchanged (267 entries)
        tag v0.3.0: absent, as it must be
        branch 0.3.x: absent, as it must be
        branch staging-0.3.0-SNAPSHOT-RC: still present, as it must be
      rehearsal: the remote is byte-for-byte as it was before the run.
      ```

      The 14 heads are the 13 listed before the run plus `scratch-69-rehearsal` itself, which
      was pushed before the dispatch and deleted after it. `git ls-remote --heads origin`
      compared before and after: identical, 13 entries, byte for byte — the listing is in this
      story's Task 8 note.
- [x] **Task 8 — unpin.** Flip the action reference back to `@master`, confirm `build.yml` is
      green, and confirm the `dsh` scratch branch is deleted. Commit.

      **Task 8 result.** Unpinned in `5c90d32e`; build run
      [35914528696](https://github.com/MRISS-Projects/parent-poms/actions/runs/35914528696)
      green on every step, `Check this repository's actions are pinned to master` included.
      `dsh`'s `scratch-69-rehearsal` is deleted from the remote.
      `git ls-remote --heads origin` on `dsh`, taken before the dispatch and again
      after the deletion, `diff`s clean at 13 entries — the run left the consumer's remote
      exactly as it found it, which is `assert-no-writes`'s claim confirmed from outside the
      run as well as inside it.
- [x] **Task 9 — docs.** Apply §4.5 to `specs/github-actions-reusable-workflows.md`. Commit.
- [x] **Task 10 — report.** Comment on `#69` with the measurement from Task 4 and the rehearsal
      from Task 7, and on [`#72`](https://github.com/MRISS-Projects/parent-poms/issues/72) that
      its AC006 now has its eighth marker. Neither issue is closed by Claude.

      **Task 10 result.** Posted, neither issue closed:
      [`#69` comment](https://github.com/MRISS-Projects/parent-poms/issues/69#issuecomment-5804843996)
      and
      [`#72` comment](https://github.com/MRISS-Projects/parent-poms/issues/72#issuecomment-5804844172).
      Both predate the review round below and assert the `project.dev` mechanism; Task 12
      corrects them in place rather than leaving the issue's record wrong.

### 6.1 Review round 1 — the mechanism was wrong

Local review of the finished branch found that §2.1's command did not do what §2.1 said, and
that every measurement taken to prove it had used the one input value that hides the difference.
§1.3's premise was independently wrong as well. The tasks that follow are that round.

- [x] **Task 11 — widen the packaging filter, TDD.** Case 6b first: `war ear zip rar tar tar.gz
      tar.bz2 sar maven-plugin`, one log each. Red on `tar`, `tar.gz`, `tar.bz2` and `sar` —
      exactly the four the enumeration missed, the other five already passing. Replace the
      enumeration with a shape match, `^[a-z][a-z0-9.-]*: `. Suite green at 36 assertions.
- [x] **Task 4R — re-measure at a version that can tell the two apart.** Same worktree recipe,
      all 13 POMs at the released `0.3.0`, asking for `0.9.9-SNAPSHOT`.

      **`-DautoVersionSubmodules=true -Dproject.dev.com.mriss.products:dsh=0.9.9-SNAPSHOT`** —
      13 files touched, and wrong:

      ```text
        8 lines ->  0.9.9-SNAPSHOT     root <version>, each <parent><version>
       12 lines ->  0.3.1-SNAPSHOT     the default version policy, not what was asked
        9 lines:    <version>${project.version}</version> -> <version>0.3.1-SNAPSHOT</version>
      ```

      **`-Dbuild.NEXT_DEVELOPMENT_VERSION=0.9.9-SNAPSHOT`** — correct:

      ```text
      13 files changed, 13 insertions(+), 13 deletions(-)    all at 0.9.9-SNAPSHOT
      ${project.version}: untouched      untracked: (none)
      mvn -B validate -> exit 0
      assert-reactor-version.sh 0.9.9-SNAPSHOT -> all 13 module(s) are at 0.9.9-SNAPSHOT
      ```

      And the guard on the bad tree, which is AC002 firing on a real defect:

      ```text
      ::error::12 of 13 module(s) are not at 0.9.9-SNAPSHOT:
        DSH Test Data Set is at 0.3.1-SNAPSHOT
        dsh-data is at 0.3.1-SNAPSHOT
        …
      ```

      §2.3 re-checked against the new command: `-Dbuild.NEXT_DEVELOPMENT_VERSION=0.3.1` exits 1,
      `0.3.1 is invalid, expected a snapshot`, no POM touched. The side effect survives.
- [x] **Task 5R — apply the correction.** `project-release.yml`: the new command, the corrected
      comment, the corrected verify-step comment. `specs/github-actions-reusable-workflows.md`
      and this spec's §1, §1.3, §2.1, §2.2, §2.3, §4.2, §4.3 and §4.4 to match. Commit.
- [x] **Task 7R — re-rehearse, at a version that proves the mechanism.** §5 again, but with
      `initial_hotfix_version: 0.9.9-SNAPSHOT` so a pass means the command works rather than
      that the policy agreed. `hotfix_branch` stays `0.3.x`. Record the run URL, the
      verification output, the eight markers and `assert-no-writes`.

      **Task 7R result.** [`dsh` run 35938090065](https://github.com/MRISS-Projects/dsh/actions/runs/35938090065),
      from `scratch-69-rehearsal-2` cut at `94060ecf`, **`initial_hotfix_version: 0.9.9-SNAPSHOT`**
      against a `0.3.0` release. **Conclusion: success — every step green.**

      That input is the point. `0.9.9-SNAPSHOT` is not the default version policy's increment of
      `0.3.0`, so the two mechanisms cannot agree by accident here: the superseded command would
      have left twelve modules at `0.3.1-SNAPSHOT` and failed this very step. The hotfix step
      logged thirteen transforms and then:

      ```text
      [INFO] --- release:3.1.1:update-versions (default-cli) @ dsh ---
      [INFO] Transforming pom.xml dsh 'DSH - Document Smart Highlights'...
      …thirteen in all, one per module…

      all 13 module(s) are at 0.9.9-SNAPSHOT
      ```

      All eight markers again, with `scm-checkin-hotfix-version` now carrying the new version:

      ```text
      REHEARSAL scm-checkin-hotfix-version: would push the 0.9.9-SNAPSHOT version change to 0.3.x
      rehearsal: all 8 declared write point(s) announced exactly once.
      ```

      `assert-no-writes`:

      ```text
        heads: unchanged (14 entries)
        tags: unchanged (12 entries)
        packages: unchanged (267 entries)
        tag v0.3.0: absent, as it must be
        branch 0.3.x: absent, as it must be
        branch staging-0.3.0-SNAPSHOT-RC: still present, as it must be
      rehearsal: the remote is byte-for-byte as it was before the run.
      ```

      **Task 8R result.** Action unpinned to `@master`; `scratch-69-rehearsal-2` deleted.
      `git ls-remote --heads origin` on `dsh` before the dispatch and after the deletion `diff`s
      clean at 13 entries.
- [ ] **Task 12 — correct the record on the issues.** The `#69` comment posted at Task 10 asserts
      the `project.dev` mechanism as proven. Post a follow-up correcting it and linking Task 4R
      and Task 7R. `#72`'s comment is unaffected — its subject is the markers, which stand.

---

## 7. Acceptance criteria

- [x] **AC001** — `project-release.yml` sets `initial_hotfix_version` on every module of the
      consuming reactor, not only the root. Proven by Task 7's run and by Task 4's local
      measurement.
- [x] **AC002** — A hotfix step that leaves any module at another version fails at that step,
      naming the offending modules, before `scm:checkin` runs. Proven by the test suite's case 2
      and by the assertion's position in §4.4.
- [x] **AC003** — The check runs in real releases and rehearsals alike. No `RH_ACTIVE` guard
      remains around it, and `#72`'s rehearsal-only evidence block is gone.
- [x] **AC004** — `project-release.yml` completes past `scm:checkin` in a `dry_run` rehearsal of
      `dsh`, with all eight declared markers fired and `assert-no-writes` clean.
- [x] **AC005** — `assert-reactor-version.sh` has a `*.test.sh` beside it that `build.yml` runs,
      both files are committed `100755`, and the action is pinned `@master` at merge.
- [x] **AC006** — The reference doc describes the step as it is.

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
