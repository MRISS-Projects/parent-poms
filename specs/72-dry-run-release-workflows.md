# Spec: rehearse a release with `dry_run` (`#72`)

| | |
|---|---|
| Issue | [`#72`](https://github.com/MRISS-Projects/parent-poms/issues/72) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-72-dry-run-release-workflows`, cut from `master` |
| Requesting project | `MRISS-Projects/dsh` — Wave 0, `specs/product/PRD.md` §4 |
| Unblocks | [`#69`](https://github.com/MRISS-Projects/parent-poms/issues/69) and [`#65`](https://github.com/MRISS-Projects/parent-poms/issues/65) — see §2.6 |
| Consuming twin | [`dsh#111`](https://github.com/MRISS-Projects/dsh/issues/111) — wrapper passthrough, not required by this spec |
| Sequenced after | [`#71`](https://github.com/MRISS-Projects/parent-poms/issues/71), merged as `0672c2e4` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This repository has no Java source and no harness for GitHub Actions behaviour, so nothing
> here is proven by a unit test except the two shell scripts that carry real logic, which are
> written test-first. Everything else is verified by running Maven and reading the log, or by
> dispatching a workflow and reading the run. Those runs are specified exactly; do not
> substitute a different command and assume the same output.

**Goal.** `project-release.yml` and `project-hotfix.yml` accept `dry_run: true` and rehearse a
complete run: every local operation executes for real, every remote write is either dry-run or
redirected at a local repository, each one announces itself with a marker, and the run proves
against the live remote that it changed nothing. A rehearsal answers `#69`'s question and will
answer `#65`'s.

**Architecture.** A `dry_run` boolean input resolves, in one new step, into a set of environment
variables that expand to Maven flags, `git` flags or SCM URLs. Every existing step interpolates a
variable instead of gaining an `if:`. **In a real release every variable is empty and the expanded
command is byte-identical to today's** — that property is the whole safety argument for putting
this in the release workflows, and §5 re-checks it. One genuinely rehearsal-only step bridges the
gap that `-DdryRun=true` opens, by building the release tag locally from what dry-run `prepare`
already writes to disk. Three composite actions under `.github/actions/` hold the logic so the
workflow diffs stay thin.

**Tech stack.** GitHub Actions composite actions, POSIX shell, `git` plumbing. Maven **3.9.9** —
what every workflow here pins via `stCarolas/setup-maven`; the §1 measurements were taken on
3.9.9 against a DSH clone. `maven-release-plugin` 3.1.1, `maven-scm-plugin` 2.1.0,
`maven-scm-publish-plugin` 3.3.0, `versions-maven-plugin` 2.18.0.

---

## Global constraints

- **A real release must be unchanged.** Every flag variable is empty when `dry_run` is false.
  Task 8 diffs the expanded commands to prove it. If a change cannot be expressed that way, it
  gets a step-level `if:` and is called out — there is exactly one such step (§2.2).
- **Flag variables are interpolated unquoted.** `mvn -B $RH_RELEASE_DRYRUN release:prepare` is
  correct; `mvn -B "$RH_RELEASE_DRYRUN" release:prepare` passes an empty argument. Maven tolerates
  that, `git push "" origin master` does not. Every call site in this spec is unquoted on purpose.
  This is the one place where `shellcheck`'s SC2086 would be wrong.
- **Nothing in a rehearsal may write to a remote.** Not the artifact registry, not `gh-pages`, not
  `master`, not `DEVELOP`, not any branch or tag on the product repository. The single exception is
  the scratch hotfix branch a human creates by hand to demonstrate `project-hotfix.yml` (Task 10),
  which is not created by the workflow.
- **`project-staging.yml`, `project-stage.yml`, `deploy.yml` and `build.yml` are not touched**,
  beyond `commit-readme` gaining an input that defaults to off. `#72` scopes rehearsal to release
  and hotfix.
- Profiles are activated by `-D<name>`, never `-P`.
- The README commit message stays exactly `Auto-generated README.md [skip jenkins]`, byte for byte.

---

## 1. What was measured

Measured on 2026-09-20 against a clone of `MRISS-Projects/dsh` at `staging-0.3.0-SNAPSHOT-RC`
(`9646b1fe`, 13 POMs), Maven 3.9.9, JDK 17, from an isolated scratch clone whose `origin` is a
local path — so no command could have reached GitHub even had it tried to push.

```bash
mvn -B -DdryRun=true \
  -Dbuild.CURRENT_VERSION_NUMBER=0.3.0 \
  -Dbuild.NEXT_DEVELOPMENT_VERSION=0.4.0-SNAPSHOT \
  release:prepare
```

### 1.1 The phase sequence, and what dry-run `prepare` leaves on disk

```text
[INFO] starting prepare goal in dry-run mode, composed of 17 phases: check-poms,
scm-check-modifications, check-dependency-snapshots, create-backup-poms, map-release-versions,
input-variables, map-development-versions, rewrite-poms-for-release, generate-release-poms,
run-preparation-goals, scm-commit-release, scm-tag, rewrite-poms-for-development,
remove-release-poms, run-completion-goals, scm-commit-development, end-release
```

Four findings, each load-bearing for the design:

1. **`rewrite-poms-for-release` writes all 13 `pom.xml.tag` files**, not only the root. The log
   names every module — `Transforming dsh-doc-analyser/dsh-top-sentences-extractor/pom.xml … with
   .tag suffix` — and `find . -name pom.xml.tag` returns 13. The complete release-version tree is
   materialised on disk. **This is what the bridge in §2.2 stands on.**
2. **`release.properties` carries `scm.tag=v0.3.0`**, plus `project.rel.<groupId>:<artifactId>` and
   `project.dev.<groupId>:<artifactId>` for every one of the 13 modules. Those are precisely the
   per-module properties `#69`'s proposed fix consumes, so a rehearsal hands `#69` its input as
   well as its subject.
3. **`check-dependency-snapshots` passes** — `[INFO] Ignoring SNAPSHOT dependencies and plugins
   ...`. DSH's parent is the unreleased `com.mriss.mriss-parent:products:3.9.0-SNAPSHOT`, the very
   milestone this issue sits on, and it does **not** block. `allowTimestampedSnapshots` is pinned
   `true` at `pom.xml:370`. There is no chicken-and-egg: a rehearsal can run today.
4. **The working tree is not rewritten.** `pom.xml` stays at `0.3.0-SNAPSHOT`; the run adds only
   untracked `pom.xml.tag`, `pom.xml.releaseBackup` and `release.properties`. Nothing is committed,
   tagged or pushed.

### 1.2 `<configuration>` beats the user property — a second instance of `#69`'s trap

The probe passed `-DpreparationGoals=validate` to keep the run short. `release.properties` records
`preparationGoals=clean install`. `pom.xml:371` binds `<preparationGoals>` in the release plugin's
`<configuration>`, and configuration beats the user property — exactly the mechanism that makes
`-DdevelopmentVersion` inert in `#69`.

Two consequences:

- **A rehearsal is a full reactor build.** `clean install` runs across all 13 modules, with the
  inherited 95% `jacoco:check`. Budget the wall time accordingly, and read a failure as a build
  failure before reading it as a rehearsal failure.
- **Do not reach for a bound parameter.** `dryRun` is *not* in that `<configuration>` block —
  `pom.xml:365-376` pins `arguments`, `tagNameFormat`, `allowTimestampedSnapshots`,
  `preparationGoals`, `goals`, `scmCommentPrefix`, `branchName`, `developmentVersion` and
  `releaseVersion`. `-DdryRun=true` reaches the mojo. Confirmed by the run above; the
  `<configuration>` block is the list to check before adding any new flag to these workflows.

### 1.3 Every write point and how `dry_run` reaches it

Verified against the plugin descriptors in the resolved jars, not from documentation.

| Write point | Mechanism | Kind |
|---|---|---|
| `release:prepare` — commit, tag, push | `-DdryRun=true` | suppress |
| `release:perform` — `deploy` | `-DdryRun=true` | suppress |
| `scm:branch` — push hotfix branch | `-DdeveloperConnectionUrl=scm:git:file://$GITHUB_WORKSPACE` | redirect |
| `versions:set` | **none — runs for real** | local only |
| `scm:checkin` — push version change | `-DdeveloperConnectionUrl=scm:git:file://$GITHUB_WORKSPACE` | redirect |
| `git merge` + `git push master` | merge real; push gets `--dry-run` | suppress |
| `site-deploy` → `gh-pages` | `-Dscmpublish.dryRun=true` | suppress |
| `commit-readme` push | new `dry-run` input → `git push --dry-run` | suppress |
| `git push --delete <RC>` | `--dry-run` | suppress |

Supporting evidence for each flag:

- `maven-release-plugin` 3.1.1, `perform` mojo: `dryRun` exists with user property `${dryRun}`,
  described as *"Dry run: don't checkout anything from the scm repository, or modify the checkout.
  The goals (by default at least `deploy`) will not be executed."* So `release:perform` in dry run
  neither creates `target/checkout` nor deploys — both halves matter, the first because four later
  steps `cd` into that directory.
- `maven-scm-plugin` 2.1.0: `branch` exposes `pushChanges` **and** `remoteBranching`, `checkin`
  exposes `pushChanges`, and both expose `connectionUrl` / `developerConnectionUrl`. The
  `<pluginManagement>` entry at `pom.xml:356-360` carries only `<version>` — no `<configuration>` —
  so every one of these user properties reaches the mojo. No repeat of §1.2's trap.
- `maven-scm-publish-plugin` 3.3.0, `publish-scm`: `dryRun`, user property `${scmpublish.dryRun}`,
  *"Display list of added, deleted, and changed files, but do not do any actual SCM operations."*
  It prints its own would-change list, which is a useful complement to our marker but is not a
  substitute for it (§2.3).
- `git push --dry-run` is native and applies to `--delete` too, which Task 5 verifies explicitly
  rather than assuming.

**Why `scm:branch` and `scm:checkin` are redirected rather than suppressed.** `-DpushChanges=false`
would work, but then the hotfix branch exists only inside `target/checkout`, and the next step
deletes that directory and re-checks-out the branch from the remote, which would not have it.
Redirecting the SCM URL at `$GITHUB_WORKSPACE` — the runner's own clone — lets the push and the
subsequent checkout both run for real against a local repository, so the rehearsal exercises more
of the real path and needs one less bridge. AC003 explicitly admits redirection alongside
suppression.

### 1.4 What was not measured, and why

The probe stopped at phase 10 of 17. `run-preparation-goals` failed resolving
`org.apache.maven.surefire:surefire-shared-utils:3.5.5` — absent from the local repository, and
`central` returned `Connection reset`. That is an environment failure on the measuring machine, not
a finding about the design.

So phases 11–17 are **unmeasured**: whether dry-run `scm-commit-release`, `scm-tag` and
`scm-commit-development` log the commands they skip, and whether `rewrite-poms-for-development`
writes `pom.xml.next` files. Neither changes the design — the bridge consumes `pom.xml.tag` and
`release.properties`, both confirmed present at phase 9 — but the first affects how the marker set
reads next to the plugin's own output. **Task 1 measures it in CI**, where the reactor builds, and
that is cheaper than a second 15-minute local build for one log line.

---

## 2. Design

### 2.1 The `dry_run` input and the flag-variable pattern

Both workflows gain:

```yaml
      dry_run:
        type: boolean
        required: false
        default: false
        description: 'Rehearse the run: no remote write, every suppression announced'
```

The first step of the job — before `Checkout`'s siblings do anything — calls
`.github/actions/rehearsal-setup`, which writes to `$GITHUB_ENV`:

| Variable | `dry_run: true` | `dry_run: false` |
|---|---|---|
| `RH_ACTIVE` | `1` | *(empty)* |
| `RH_RELEASE_DRYRUN` | `-DdryRun=true` | *(empty)* |
| `RH_SCM_LOCAL_URL` | `-DdeveloperConnectionUrl=scm:git:file://$GITHUB_WORKSPACE -DconnectionUrl=scm:git:file://$GITHUB_WORKSPACE` | *(empty)* |
| `RH_SCMPUBLISH_DRYRUN` | `-Dscmpublish.dryRun=true` | *(empty)* |
| `RH_GIT_PUSH_DRYRUN` | `--dry-run` | *(empty)* |
| `RH_TAG_SOURCE` | `$GITHUB_WORKSPACE` | `origin` |

`RH_TAG_SOURCE` is the one variable that is non-empty in a real release, because the command it
feeds already names `origin` today. Its real-release value is the literal string the workflow
currently hardcodes, so the expansion is still identical.

It also writes `$RUNNER_TEMP/rehearsal-marker.sh` (§2.3) and records the remote's state (§2.4).

Call sites read, for example:

```bash
mvn -B $RH_RELEASE_DRYRUN \
  -Dbuild.NEXT_DEVELOPMENT_VERSION=${{ inputs.next_development_version }} \
  -Dbuild.CURRENT_VERSION_NUMBER=${{ inputs.current_version }} \
  release:prepare
```

```bash
git push $RH_GIT_PUSH_DRYRUN "$REPO_URL" master
```

With `dry_run: false` both collapse to exactly the text in `master` today.

### 2.2 The bridge — the one rehearsal-only step

`release:prepare -DdryRun=true` creates no tag, and `release:perform -DdryRun=true` creates no
`target/checkout`. Without a bridge, steps 3 through 10 are not merely skipped, they are
unreachable, and `#69`'s `versions:set` and `#65`'s merge-back never execute. That is the trap
`#72` identified, and it is the reason a pure suppress-everything mode proves nothing.

**Both commands those issues are about are purely local.** `#69` asks whether
`versions:set -DprocessAllModules=true` writes one POM or thirteen — answered entirely by files on
disk. `#65` asks whether `git merge -X ours` plus a `versions:set` fixup preserves non-version
changes — also local; only the closing `git push` touches a remote. So a mode that suppresses only
the remote half exercises both completely, provided the local half has refs to stand on.

A new step, guarded `if: inputs.dry_run`, calls `.github/actions/rehearsal-tag` immediately after
`Maven Release`:

1. Read `scm.tag` from `release.properties` (§1.1 finding 2) — `v0.3.0`.
2. Build a commit whose tree is `HEAD` with every `pom.xml` replaced by its `pom.xml.tag`.
3. Tag that commit locally with `scm.tag`.
4. Create `target/checkout` as `git clone --branch <tag> "$GITHUB_WORKSPACE" target/checkout`,
   mirroring what `release:perform` would have produced.

**Step 2 uses git plumbing against a temporary index, and must not use `git reset --hard`.** The
obvious implementation — copy the `.tag` files over, commit, tag, then reset — mutates the branch
and the working tree of a checkout that later steps still read. The plumbing form touches neither:

```sh
GIT_INDEX_FILE="$(mktemp)"; export GIT_INDEX_FILE
git read-tree HEAD
find . -name pom.xml.tag -not -path './target/*' -print | while IFS= read -r tagfile; do
  rel="${tagfile#./}"
  blob="$(git hash-object -w "$tagfile")"
  git update-index --add --cacheinfo "100644,$blob,${rel%.tag}"
done
tree="$(git write-tree)"
commit="$(git commit-tree "$tree" -p HEAD -m "[rehearsal] release content for $TAG")"
git tag "$TAG" "$commit"
rm -f "$GIT_INDEX_FILE"
```

This is the only step in either workflow that never runs during a real release, and therefore the
only logic a real release never exercises. That is the honest cost of reaching AC004; it is
confined to one action, guarded by one `if:`, and it writes nothing outside the runner.

### 2.3 Markers and the completeness check

`rehearsal-setup` writes `$RUNNER_TEMP/rehearsal-marker.sh`. Each guarded site calls it once:

```bash
bash "$RUNNER_TEMP/rehearsal-marker.sh" merge-to-master "push the merge of $CURRENT_TAG to master"
```

which, when `RH_ACTIVE` is set, prints

```text
REHEARSAL merge-to-master: would push the merge of v0.3.0 to master
```

to stdout, appends `merge-to-master` to `$RUNNER_TEMP/rehearsal-markers`, and adds a row to
`$GITHUB_STEP_SUMMARY`. When `RH_ACTIVE` is empty the script is a no-op that prints nothing, so the
call site needs no `if:` and a real release's log is unchanged.

**Markers are emitted by the workflow step, never by the plugin.** `release:prepare` and
`publish-scm` print their own dry-run chatter, but that wording belongs to those plugins and can
change under a version bump. The marker asserts our intent independently of it.

The declared sets:

| Workflow | Marker ids | Count |
|---|---|---|
| `project-release.yml` | `release-prepare`, `release-perform-deploy`, `scm-branch`, `scm-checkin-hotfix-version`, `merge-to-master`, `site-deploy`, `commit-readme`, `remove-rc-branch` | 8 |
| `project-hotfix.yml` | `release-prepare`, `release-perform-deploy`, `merge-to-master`, `site-deploy`, `commit-readme` | 5 |

A final `Assert rehearsal completeness` step compares emitted ids against the declared set and
fails on a **missing** id, a **duplicate**, or an **unexpected** one. Set equality, not a count —
which is stronger than AC003 asks and buys the property that matters afterwards: when `#65` adds
the merge into `DEVELOP`, it must add `merge-to-develop` to the declared set or the rehearsal
fails. A write point added without a marker becomes a build failure rather than an oversight.

### 2.4 Asserting the absence of writes against the remote, not the log

AC002 asks for the four absences to be asserted "against the run log, not by inspection of the
YAML". A step cannot read its own job's live log, so a log-based assertion would have to happen
after the fact, by hand, on a downloaded log. Asserting against the **remote** is both stronger and
automatable, and this spec does that instead — §6 restates AC002 to match.

`rehearsal-setup` records, before anything runs:

- `git ls-remote --heads origin` — one snapshot covering `master`, `DEVELOP`, `gh-pages` and the
  RC branch at once
- `git ls-remote --tags origin`
- the product's package-version list from the registry

`rehearsal-verify` re-reads all three at the end, `if: always()`, and fails on any difference, plus
asserts positively that tag `v<current_version>` is absent, the hotfix branch is absent, and the RC
branch is still present. `always()` matters: a rehearsal that dies halfway is exactly when you need
to know whether it wrote something first.

One accepted false-failure mode: a human pushing to the repository during the ~20-minute run makes
the snapshots differ and fails the rehearsal. That is the safe direction to fail in, and a
rehearsal is always dispatched deliberately.

### 2.5 Why `commit-readme`'s four callers keep working

The action gains `dry-run` (default `'false'`). `project-release.yml` and `project-hotfix.yml` pass
`${{ inputs.dry_run }}`; `project-staging.yml` (both call sites, including the `verify-only: 'true'`
one at line 229) and `deploy.yml` pass nothing and are unaffected.

Two details from `#71`'s design that this must not disturb:

- The `verify-only` path runs the placeholder check and stops. It is read-only, so it needs no
  guard — and a rehearsal must not blanket-fail every `commit-readme` invocation, which would break
  it. Adding an input rather than a global kill switch is what keeps that true.
- The push retries up to three times, rebasing between attempts. Under `--dry-run` the first
  attempt succeeds and returns 0, so the loop is never entered and the retry logic is untouched. A
  guard that had neutralised only the first `git push` would have left two live; guarding at the
  action level, as `#72` requires, avoids that.

### 2.6 What this hands `#69` and `#65`

A rehearsal is only worth the code if it produces a result those issues can quote.

- **`#69`.** After `versions:set` runs in `target/checkout`, a rehearsal-only line records how many
  POM files the command actually modified, out of how many exist:
  `git -C target/checkout status --porcelain '*pom.xml' | wc -l`. `#69` predicts 1 of 13. That
  number, in a run log linked from the issue, settles it.
- **`#65`.** Its merge-back is not built here. What this spec provides is the mode it will be
  validated in, the `merge-to-develop` marker slot it must fill, and the same
  `git diff --stat`-style evidence line applied to the merge commit. §7 keeps the fix itself out of
  scope.

---

## 3. File structure

```text
.github/actions/rehearsal-setup/action.yml
.github/actions/rehearsal-setup/marker.sh                   # template copied to RUNNER_TEMP
.github/actions/rehearsal-tag/action.yml
.github/actions/rehearsal-tag/build-release-tag.sh
.github/actions/rehearsal-tag/build-release-tag.test.sh
.github/actions/rehearsal-verify/action.yml
.github/actions/rehearsal-verify/assert-markers.sh
.github/actions/rehearsal-verify/assert-markers.test.sh
.github/actions/rehearsal-verify/assert-no-writes.sh
.github/actions/commit-readme/action.yml                    # modified: dry-run input
.github/workflows/project-release.yml                       # modified
.github/workflows/project-hotfix.yml                        # modified
specs/72-dry-run-release-workflows.md                       # this spec
```

`build-release-tag.sh` and `assert-markers.sh` carry real logic and are written test-first,
following `check-placeholders.test.sh` from `#71`. `assert-no-writes.sh` and `marker.sh` are thin
enough that their verification is the demonstration run.

---

## 4. Tasks

### Task 1: Measure phases 11–17 of a dry run

- [ ] Push this branch and add a temporary workflow, `rehearsal-probe.yml`, dispatchable, that
      checks out DSH at `staging-0.3.0-SNAPSHOT-RC` and runs exactly the §1 command.
- [ ] Dispatch it. Record from the log: whether `scm-commit-release`, `scm-tag` and
      `scm-commit-development` print the git command they skip; whether `pom.xml.next` files are
      written by `rewrite-poms-for-development`; the wall time of `run-preparation-goals`.
- [ ] Write the findings into §1.4, replacing the "unmeasured" paragraph.
- [ ] Delete `rehearsal-probe.yml` in the same commit that records the findings.

**Verify:** §1.4 no longer says "unmeasured", and `git log -p` shows the probe workflow added and
removed on this branch.

### Task 2: `rehearsal-setup`, with markers

- [ ] Write `marker.sh`: takes an id and a description; no-op when `RH_ACTIVE` is empty; otherwise
      prints `REHEARSAL <id>: would <description>`, appends the id to
      `$RUNNER_TEMP/rehearsal-markers`, and appends a row to `$GITHUB_STEP_SUMMARY`.
- [ ] Write `action.yml`: inputs `dry_run`, `git_project`, `branch_name`; sets the six variables of
      §2.1 into `$GITHUB_ENV`; copies `marker.sh` to `$RUNNER_TEMP`; records the three remote
      snapshots of §2.4 into `$RUNNER_TEMP`.
- [ ] Pin the package-registry query. It is the one snapshot whose exact form is unmeasured — try
      `gh api "/orgs/MRISS-Projects/packages?package_type=maven"` filtered to the product, fall back
      to `/users/...` if the org endpoint 404s, and record the working form in a comment in
      `action.yml`.

**Verify:** the `$GITHUB_ENV` block is emitted with every variable empty when `dry_run` is false —
assert by dispatching the probe workflow of Task 1 with the action wired and `dry_run: false`, and
reading the step's output.

### Task 3: `commit-readme` gains `dry-run`

- [ ] Add the input, default `'false'`, documented like its siblings.
- [ ] Interpolate it unquoted into the push: `git push $DRY_RUN_FLAG "$PUSH_TARGET" "HEAD:$TARGET_BRANCH"`.
- [ ] Emit the `commit-readme` marker from inside the action when the flag is on, so all four
      callers are covered by one guard.
- [ ] Leave `verify-only` untouched.

**Verify:** run `check-placeholders.test.sh` — still green. Confirm by reading the diff that the
retry loop is unchanged and that `project-staging.yml`'s two call sites pass no new input.

### Task 4: `rehearsal-tag`, test-first

- [ ] Write `build-release-tag.test.sh` first: build a throwaway git repository with a root and two
      module POMs plus matching `pom.xml.tag` files and a `release.properties`; assert the script
      creates the tag, that the tagged tree's POMs carry the release version, that `HEAD` is
      unmoved, that the working tree is byte-identical afterwards, and that the real index is
      untouched.
- [ ] Write `build-release-tag.sh` to pass it, using the plumbing form of §2.2.
- [ ] Write `action.yml` wrapping it plus the `git clone --branch <tag>` into `target/checkout`.

**Verify:** `sh build-release-tag.test.sh` passes. Deliberately break one assertion and confirm it
fails — a test that cannot fail has not been run.

### Task 5: Wire `project-release.yml`

- [ ] Add the `dry_run` input.
- [ ] Add `rehearsal-setup` as the first step after `Checkout`.
- [ ] Interpolate the variables at each of the eight write points of §2.3, and add the marker call
      to each.
- [ ] Add the guarded `rehearsal-tag` step after `Maven Release`.
- [ ] Add the `#69` evidence line after `versions:set` (§2.6).
- [ ] Add `rehearsal-verify` as the last step, `if: always()`.
- [ ] Verify `git push --dry-run --delete <branch>` really is a no-op, against a scratch branch in
      a throwaway repository. Do not assume it; `--delete` changes the refspec shape.

**Verify:** with `dry_run: false`, `git diff master -- .github/workflows/project-release.yml` shows
only additions — no existing command line altered except by variable interpolation that expands to
empty.

### Task 6: Wire `project-hotfix.yml`

- [ ] The same, for its five write points. No `scm:branch`, no `versions:set`, no RC deletion.
- [ ] Its `Merge Release Tag to Master` carries `--allow-unrelated-histories` (line 163); keep it.

**Verify:** as Task 5, for this workflow.

### Task 7: The completeness and no-write assertions

- [ ] Write `assert-markers.test.sh` first: feed it a markers file and a declared set, and assert it
      passes on equality and fails on each of missing, duplicate and unexpected.
- [ ] Write `assert-markers.sh` to pass it.
- [ ] Write `assert-no-writes.sh`: re-read the three snapshots, diff, and assert the three positive
      conditions of §2.4.
- [ ] Write `rehearsal-verify/action.yml` calling both, taking the declared set as an input so each
      workflow passes its own.

**Verify:** `sh assert-markers.test.sh` passes, and fails when an assertion is inverted.

### Task 8: Prove a real release is unchanged

- [ ] For both workflows, expand every modified command by hand with all `RH_*` variables empty and
      diff against the same line on `master`.
- [ ] Record the result in this spec as a Task 8 results block, listing each modified line and its
      expansion.

**Verify:** every expanded line is byte-identical to `master`'s, or the difference is stated and
justified. This is the gate on the whole change: if a real release's commands are not identical,
stop and redesign rather than proceed.

### Task 9: Demonstrate — `project-release.yml` — `#72` AC006

- [ ] On DSH, create a scratch branch carrying a `release.yml` that wires `dry_run` and points
      `uses:` at `MRISS-Projects/parent-poms/.github/workflows/project-release.yml@issue-72-dry-run-release-workflows`.
      `dsh#111` is the permanent passthrough and is not a prerequisite — `workflow_dispatch` takes a
      ref.
- [ ] Dispatch against the real `staging-0.3.0-SNAPSHOT-RC` with `current_version: 0.3.0`,
      `next_development_version: 0.4.0-SNAPSHOT`, `hotfix_branch: 0.3.x`,
      `initial_hotfix_version: 0.3.1-SNAPSHOT`, `dry_run: true`. Nothing is pushed, so this is safe
      against the live RC branch.
- [ ] Record: the run URL, all eight marker lines, the `assert-no-writes` output, and the `#69`
      POM-count line.
- [ ] Independently confirm from a shell that `v0.3.0` and `0.3.x` are absent from the remote and
      that `master`, `DEVELOP`, `gh-pages` and the RC branch are at their pre-run SHAs.

**Verify:** the run is green, eight markers appear exactly once each, and the independent check
agrees with `assert-no-writes`.

### Task 10: Demonstrate — `project-hotfix.yml`

- [ ] `project-hotfix.yml`'s `Validate version` requires FIX > 0, and DSH has no hotfix line —
      `git ls-remote --heads` shows `DEVELOP`, `master`, `gh-pages`, the RC branch and issue
      branches only. Create `0.3.x-rehearsal` on DSH **from the current RC branch content**, with
      the version set to `0.3.1-SNAPSHOT`.
- [ ] Not from tag `dsh-0.2.4`: that tree carries an older parent and may fail `clean install` for
      reasons unrelated to this issue, which would make the rehearsal inconclusive rather than
      negative.
- [ ] Dispatch the hotfix wrapper against it with `dry_run: true`.
- [ ] Record the run URL, all five markers, and the `assert-no-writes` output.
- [ ] Delete the scratch branch and record the command in this spec's Task 10 results block — this
      is the whole of AC005, since nothing else outlives the runner.

**Verify:** the run is green, five markers, and `git ls-remote --heads origin` after deletion
matches the pre-Task-10 listing.

### Task 11: Report on `#72`, `#69` and `#65`

- [ ] Comment on `#72` with both run URLs, the marker listings, and the restated AC001–AC003 of §6.
- [ ] Comment on `#69` with the measured POM count from Task 9 — the number its analysis predicted,
      confirmed or refuted against the real 13-module reactor.
- [ ] Comment on `#65` with how to validate its merge-back once built: the `merge-to-develop` marker
      slot, and the dispatch that exercises it.

**Verify:** all three comments posted; `#72`'s acceptance criteria updated in the issue body to
match §6.

---

## 5. Self-review

- **Placeholders.** One deliberate unknown remains: the exact package-registry endpoint (Task 2).
  It is scoped to a single snapshot, it has a stated fallback, and it cannot change the design. §1.4
  is a second, and Task 1 closes it before any code is written.
- **Internal consistency.** The marker counts in §2.3 match the write points in §1.3 — eight for
  release (every row except `versions:set`, which writes nothing remote), five for hotfix (those
  eight minus `scm-branch`, `scm-checkin-hotfix-version` and `remove-rc-branch`). Tasks 5 and 6
  enumerate the same numbers.
- **Scope.** One implementation plan: three small actions, one input added to a fourth, two
  workflows wired, two demonstration runs. No POM change, so this reaches consumers on merge
  without a release — the path `#58` and `#57` took.
- **Ambiguity.** Two readings were closed explicitly: "suppress the write" can mean skip or
  redirect, and §1.3 states which applies where and why; "real refs" in AC004 can mean pushed or
  local, and §2.2 argues local, on the grounds that both commands under test are local operations.
- **The risk this spec carries.** The bridge (§2.2) is code a real release never runs, so a real
  release never tests it. Task 8 exists because of that: it proves the *other* direction, that a
  real release's commands are untouched. If Task 8 fails, the design is wrong and the answer is to
  redesign, not to weaken the task.

---

## 6. Acceptance criteria, restated

`#72`'s AC001–AC003 were written for a suppress-everything design. §2 changes what "suppress" and
"assert" mean, so they are restated here; Task 11 updates the issue body to match. AC004–AC006
stand as written.

- **AC001 — unchanged in substance.** Both workflows take `dry_run`, no dispatch-time edit.
- **AC002 — strengthened.** A rehearsal performs no artifact deploy, no `gh-pages` publication, no
  push to `master` and no deletion of the RC branch. Asserted against the **live remote** before and
  after the run (§2.4), not against the run log — a step cannot read its own job's log, and remote
  state is the stronger evidence anyway.
- **AC003 — strengthened.** Every suppressed or redirected action emits exactly one marker. The
  check is **set equality** against a declared list, failing on missing, duplicate or unexpected —
  so the marker set's completeness is enforced on every future rehearsal, not only measured once.
- **AC004 — met.** `versions:set` and the tag merge-back run for real against local refs built by
  the bridge, and Task 9 records the result `#69` needs.
- **AC005 — met, nearly vacuously.** The workflow creates no remote ref. The only ref that outlives
  a rehearsal is the scratch hotfix branch a human creates for Task 10, whose deletion command that
  task records.
- **AC006 — met by Tasks 9 and 10.**

---

## 7. Out of scope

- **Fixing `#69` or `#65`.** This spec builds what they are validated with. `#65`'s merge-back will
  add a ninth marker id, `merge-to-develop`, and §2.3's set-equality check will require it.
- **`project-stage.yml`, `project-staging.yml`, `deploy.yml`, `build.yml`.** Staging already runs
  routinely against RC branches. `commit-readme` gains an input they do not pass.
- **`dsh#111`**, the consuming wrapper's passthrough. Tasks 9 and 10 dispatch from a scratch branch,
  which `workflow_dispatch`'s ref argument makes sufficient.
- **A rehearsal fixture repository.** Running the unmodified workflows against a throwaway consumer
  was weighed against this design and set aside: it adds no conditional logic to the release
  workflows, which is a real advantage, but it deploys artifacts for real and proves the path only
  for a fixture that must then be kept in step with real consumers. Revisit if the bridge in §2.2
  proves hard to maintain.
- **`#59`**, the Maven 3.9.9 → 3.9.16 bump. §1's measurements were taken on 3.9.9, the pinned CI
  version, so nothing here depends on the bump.
