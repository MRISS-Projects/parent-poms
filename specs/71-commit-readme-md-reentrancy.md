# Spec: move the README commit out of the reactor (`#71`)

| | |
|---|---|
| Issue | [`#71`](https://github.com/MRISS-Projects/parent-poms/issues/71) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-71-commit-readme-md-reentrancy`, cut from `master` |
| Consuming issue | `MRISS-Projects/dsh` Wave 0, `specs/product/PRD.md` §4 |
| Blocks | `#72` — see "Sequencing" |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> The repository has no unit-test harness for POM or workflow behaviour, so several tasks
> verify by running Maven and reading the log. Those runs are specified exactly; do not
> substitute a different command and assume the same output.

**Goal.** `README.md` is committed exactly once per build, by the workflow that owns the
build, and a `README.md` containing an unresolved `${...}` placeholder can never be
committed at all.

**Architecture.** README *generation* stays in the POM, inherited by every consuming
project exactly as today. README *committing* moves out of the reactor into a composite
GitHub Action called by the four workflows that build with `-Ddeployment`. Re-entrancy
stops being a correctness problem because a replayed `process-resources` can only
regenerate a file in the working tree, never commit one.

**Tech stack.** Maven 3.9.16, `maven-resources-plugin`, `buildnumber-maven-plugin`,
`maven-scm-plugin` 2.1.0, GitHub Actions composite actions, POSIX shell.

---

## Global constraints

- Profiles are activated by `-D<name>`, never `-P`. **Never reintroduce `-P`.**
- Commit message for the README commit stays exactly `Auto-generated README.md [skip jenkins]`,
  byte for byte. Downstream tooling and the `[skip jenkins]` convention depend on it.
- The `readme-generation` profile's two activators (`-Ddeployment` **and**
  `${basedir}/src/site/markdown/README.md` exists) stay as they are. Their rationale is
  recorded in `pom.xml:997-1022` and none of it is superseded here.
- `commit.readme.phase` stays defined as a property for compatibility with any consumer that
  passes it, but it controls nothing once the execution it bound is gone. `build.yml` passed
  `-Dcommit.readme.phase=none` on two steps to disarm the commit; Task 5 removes both, since
  there is no longer anything to disarm.
- Java 17, Maven 3.9.16 as pinned by the workflows.

---

## 1. The defect

`commit-readme-md` executes three times in one `project-staging.yml` run. One of those
executions commits a `README.md` whose line 7 contains the literal string `${timestamp}`.
A later execution overwrites it with a correct value, so a run that *completes* ends
correct. A run that fails inside that window leaves the consuming repository holding a
published `README.md` with an unresolved placeholder, and nothing reports it.

Reproduced four times: twice on DSH branch `issue-85-update-maven-and-java-versions-in-docs`
(run [35403050676](https://github.com/MRISS-Projects/dsh/actions/runs/35403050676),
conclusion **success**, commits `957fcf04` → `973ced8c` (corrupt) → `7afcb9b8`), once in
this repository's own `3.9.0-SNAPSHOT` deploy, and once in a DSH staging run on
`staging-0.3.0-SNAPSHOT-RC`.

### 1.1 What the issue got wrong, and what measurement corrected

`#71` reads the failure stack as `maven-site-plugin:site` → `maven-jxr-plugin` →
`maven-scm-plugin:checkin (commit-readme-md)` and attributes the re-entry to the `jxr`
report. The mechanism — a report mojo forking a lifecycle past `process-resources` — is
right. The attribution is wrong in two ways, both measured against DSH rather than reasoned
about.

**`jxr` itself cannot reach the README executions.** From `META-INF/maven/plugin.xml` in
`maven-jxr-plugin-3.6.0.jar`:

| Goal | `executePhase` | Replays `process-resources`? |
|---|---|---|
| `jxr` | `generate-sources` | **no** — the fork ends two phases early |
| `test-jxr` | `generate-test-sources` | no |
| `aggregate` | `compile` | **yes** |
| `test-aggregate` | `test-compile` | **yes** |

Maven's phase order is `generate-sources` → `process-sources` → `generate-resources` →
`process-resources` → `compile`. All three README executions (`create-time-stamp`,
`copy-readme-md`, `commit-readme-md`) bind to `process-resources` — the first two
explicitly at `pom.xml:1060,1077`, the third via `${commit.readme.phase}`
(`pom.xml:1103`), whose default is `process-resources` (`pom.xml:82`).

**It is two plugins, not one, and four forks, not three.** Measured: one `mvn -Ddeployment
site` in DSH replays `copy-readme-md` **four** times in the root module, and only in the
root module — no other module activates the profile, because only `./src/site/markdown/README.md`
exists. The four forks are:

| Log line | Forking mojo | Forked phase |
|---|---|---|
| 34 | `maven-jxr-plugin:aggregate` | `compile` |
| 521 | `maven-jxr-plugin:test-aggregate` | `test-compile` |
| 1078 | **`maven-javadoc-plugin:aggregate`** | `compile` |
| 1565 | **`maven-javadoc-plugin:test-aggregate`** | `test-compile` |

Maven states it outright: `Preparing maven-jxr-plugin:aggregate report requires 'compile'
forked phase execution`. Javadoc's aggregate reports fork identically and the issue does
not mention them.

**Where the issue's "three" comes from.** Not from `site` alone. A staging run makes two
separate Maven invocations — `clean deploy` (`project-staging.yml:203`) then `site-deploy`
(`project-staging.yml:226`) — so the three commits span both. A `site`-only run has no main
`process-resources` pass at all; every occurrence is a fork.

The consequence for the fix: rebinding `commit-readme-md` to a later phase cannot help. A
fork to `compile` or `test-compile` replays everything up to that phase, so any later phase
is *further inside* a fork's reach, not outside it.

### 1.2 Why ordering cannot be the fix either

`create-time-stamp` precedes `copy-readme-md` in every pass — same phase, POM declaration
order, and §1.3 shows it runs first and then short-circuits. Making that ordering "more
robust", which is `#71`'s second suggested direction, therefore addresses nothing that is
broken, and leaves the commits standing, so AC001 fails by construction. The defect is not
*when* the commit happens relative to the timestamp; it is that a commit happens inside a
lifecycle phase Maven is free to replay.

### 1.3 How `${timestamp}` actually works — settled

`buildnumber-maven-plugin` 3.3.0 logs
**`Skipping because we are not in root module.`** for the root module, on every pass. It is
not skipping anything. Disassembled from `CreateTimestampMojo.class`:

```java
public void execute() {
    if (skip) { log.info("Skipping execution."); return; }

    if (session.getCurrentProject().isExecutionRoot() && !executeRootOnly) {
        log.info("Skipping because we are not in root module.");
        // bytecode offsets 39-45: logs, then falls through to 50. There is NO return.
    }

    String ts = session.getTopLevelProject().getProperties().getProperty(timestampPropertyName);
    if (ts != null) { log.debug("Using previously created timestamp."); return; }

    ts = Utils.createTimestamp(timestampFormat, timezone);
    for (MavenProject p : session.getProjectDependencyGraph().getSortedProjects()) {
        p.getProperties().setProperty(timestampPropertyName, ts);
    }
}
```

Three facts follow, all confirmed in a `-X` run:

1. **The message is a cosmetic bug with no effect.** It prints, then the mojo stores the
   property anyway. This is why every committed `README.md` in this repository and in DSH
   carries a real timestamp despite the log saying it was skipped. The guard's condition is
   also inverted relative to its own message: `isExecutionRoot() && !executeRootOnly` logs
   "we are not in root module" precisely when it *is* the root module.
2. **The timestamp is minted once per Maven invocation** and written to every reactor
   project; later executions short-circuit. Observed: `Storing timestamp property:
   timestamp 20260919-153845` on the first fork, then `Using previously created timestamp.`
   on forks two, three and four.
3. **So two invocations mint two different values.** This explains something `#71` records
   but does not account for: its two *good* commits read `20260918-224757` and
   `20260918-225016`, 2m19s apart — one per Maven invocation, not one per fork.

**What is still unproven, stated plainly.** The placeholder did **not** reproduce locally in
six configurations — `site`, root-only `-N`, with and without `-Dbuild.number`, with `-X`.
All four forks resolved the timestamp every time. So the precise trigger for the corrupt
commit is CI-specific and remains unidentified.

**The design does not depend on identifying it**, and that is deliberate rather than a
concession. Removing every in-lifecycle commit means no pass can commit anything, whichever
pass would have been the corrupt one; and the guard in §2.5 turns a silent corruption into a
failed build. What the CI-only nature does change is where AC002's evidence comes from: Task
6, not a local run. §2.3 says so.

One asymmetry in the corrupt commit is consistent with the clone-visibility theory and worth
recording for whoever revisits it: `973ced8c` read `0.3.0-SNAPSHOT - RC6 - ${timestamp}`, so
`${build.number}` resolved while `${timestamp}` did not. `build.number` arrives as a
user property (`-Dbuild.number=RC6`) and survives project cloning; `timestamp` is a project
property written to `getSortedProjects()`, which a forked clone need not be among. Suggestive,
not established — the local runs show clones resolving it fine.

---

## 2. Design

### 2.1 Split generation from committing

| Concern | Today | After | Delivered to consumers by |
|---|---|---|---|
| `create-time-stamp` (sets `${timestamp}`) | POM profile | **unchanged** | Maven inheritance |
| `copy-readme-md` (filters `src/site/markdown/README.md` → `README.md`) | POM profile | **unchanged** | Maven inheritance |
| `commit-readme-md` (`scm:checkin`) | POM profile | **removed** | reusable workflows |

Only the `scm:checkin` leaves. A consuming project's README is still filtered with that
project's own version, build number and timestamp, from the inherited POM, with no change
to how it is configured or activated.

### 2.2 Why moving the commit does not break the inheritance contract

This repository exists to give consuming projects shared behaviour for free. Moving a
step out of the POM trades Maven inheritance for workflow reuse, so the contract has to
be shown to survive. It does, and measurably:

**No consuming project activates `readme-generation` by itself.** `grep -rn 'Ddeployment'`
over `MRISS-Projects/dsh/.github/workflows/` returns **nothing**. Every invocation that
activates the profile for DSH originates here — `project-staging.yml:203,226`,
`project-release.yml:212,220`, `project-hotfix.yml:171,179`. The reusable workflows are
already the sole activation vehicle in practice; Maven inheritance delivers the profile
but never switches it on for a consumer.

So the "for free" property is preserved by construction: any project that points its
release wrappers at this repository's reusable workflows — which it must do anyway to
release at all — gets the README commit, exactly as DSH does today.

**The coupling this makes explicit was already there.** A consuming project has always
needed both halves: the parent POM *and* workflows pointing here. This change moves one
step from the first half to the second, making the dependency visible rather than
creating it. Accepted deliberately; see §6 for the future mitigation.

**Precedent already in the tree.** `build.yml:162,170` passes
`-Dcommit.readme.phase=none`, so this repository's own CI already treats committing the
README as not-part-of-the-build.

**One narrowing, and it is an improvement.** A consumer running `mvn -Ddeployment` by hand,
or from a bespoke workflow of its own, gets a README commit today and will not afterwards.
No such invocation exists in DSH — `grep -rn 'Ddeployment'` over its workflows is empty — so
nothing in the estate loses behaviour it relies on.

It is an improvement because the current behaviour is a trap, demonstrated accidentally while
building this story: a single diagnostic `mvn -B -N -Ddeployment process-resources`, run to
inspect a property, silently committed `9b5f2bb5 Auto-generated README.md [skip jenkins]` to
DSH's `staging-0.3.0-SNAPSHOT-RC`. No prompt, no warning, and it would have been pushed by
the next unrelated `git push`. After this change the same command regenerates `README.md` in
the working tree and commits nothing — verified in Task 4 Step 5, where a fully armed
`mvn -Ddeployment site` left `HEAD` untouched. A build step that writes to a developer's
branch without being asked is the surprising behaviour; removing it is the point, not a cost.

### 2.3 Why this fixes all four acceptance criteria

With no `scm:checkin` bound to a lifecycle phase, the `aggregate` and `test-aggregate`
forks still regenerate `README.md` in the working tree several times per run. None of
those regenerations can reach git. The workflow commits the final working-tree state,
once.

| `#71` AC | How it is met |
|---|---|
| AC001 — one commit, not three | By construction: one commit step, outside the lifecycle |
| AC002 — no placeholder committed *at any point* | **The guard in §2.5 is load-bearing here**, not the architecture. Intermediate regenerations no longer reach git, which removes the observed failure mode, but §1.3 could not reproduce the placeholder locally — so the guard is what makes AC002 hold whatever the CI-specific trigger turns out to be. Evidence comes from Task 6, in CI. |
| AC003 — a rejected README push does not fail the reactor naming `maven-site-plugin`/`maven-jxr-plugin` | By deletion: no `scm:checkin` runs during `site`, so a push cannot fail inside a report |
| AC004 — verified on a real consuming staging run | Task 6 |

AC003 is worth spelling out. Today a concurrent push to the branch makes
`maven-scm-plugin:checkin` fail *inside* `maven-site-plugin:site`'s report chain, and the
reactor reports a `maven-jxr-plugin` failure — pointing an investigator at reports when
the cause is README generation. Once the commit is a workflow step, a rejected push fails
that step, named for what it is.

### 2.4 The composite action

`.github/actions/commit-readme/action.yml`. A composite action, not four copies, because
four workflows call it: `project-staging.yml`, `project-release.yml`, `project-hotfix.yml`,
and `deploy.yml` (this repository consuming itself — it is not a reusable workflow, so it
cannot inherit the step any other way).

Inputs:

| Input | Required | Default | Purpose |
|---|---|---|---|
| `branch` | yes | — | branch to push to |
| `working-directory` | no | `.` | `target/checkout` for the master-merge contexts |
| `push-url` | no | `''` | explicit remote URL; empty means push to `origin` |
| `message` | no | `Auto-generated README.md [skip jenkins]` | commit message |

`push-url` exists because the two contexts differ. All four workflows check out with
`actions/checkout@v4` and `token: ${{ secrets.DEPLOY_TOKEN }}`
(`project-staging.yml:82-87`, `project-release.yml:52-57`, `project-hotfix.yml:36-41`,
`deploy.yml:53-56`), so `persist-credentials` defaults to true and `git push origin` works
in the workspace with no URL construction. But `project-release.yml` and
`project-hotfix.yml` `rm -rf target/checkout` and `git clone` master into it for the merge,
and that clone needs the explicit
`https://x-access-token:${DEPLOY_TOKEN}@github.com/...` form those workflows already build
at `project-release.yml:194,226` and `project-hotfix.yml:153`.

The action is a no-op when `README.md` is unchanged, so a build that regenerates an
identical file produces no empty commit.

**Resolved: `uses: ./` does not work in a reusable workflow.** A relative path resolves
against the **caller's** workspace, not the repository owning the workflow. Measured, not
assumed — DSH staging run
[35463833006](https://github.com/MRISS-Projects/dsh/actions/runs/35463833006) failed with:

```text
Can't find 'action.yml', 'action.yaml' or 'Dockerfile' under
'/home/runner/work/dsh/dsh/.github/actions/commit-readme'.
Did you forget to run actions/checkout before running your local action?
```

An earlier draft of this spec recorded the opposite as "the current documented behaviour",
with a caveat that it could not be verified locally. The caveat was the useful half.

**So the reference is qualified**, and the two contexts differ deliberately:

| Workflow | Reference | Why |
|---|---|---|
| `deploy.yml` | `./.github/actions/commit-readme` | runs in this repository; the workspace is this repo |
| `project-staging.yml`, `project-release.yml`, `project-hotfix.yml` | `MRISS-Projects/parent-poms/.github/actions/commit-readme@master` | run in a consumer's workspace; must name the providing repository |

The qualified form is the same consumer-to-provider pointer DSH already uses for the reusable
workflows themselves (`project-staging.yml@master`), so it introduces no new concept.

**The hazard it creates, and the check that removes it.** A qualified reference carries a ref.
Validating a change to the action requires pointing that ref at a task branch — Task 6 did
exactly that. Merging a task-branch pin would break every consumer's release the moment the
branch is deleted, silently, at release time. `build.yml` therefore fails if any `uses:` line
pins the action to anything but `@master`, which makes the mistake unmergeable rather than
merely documented. The check matches only real `uses:` lines, so it does not flag its own
grep pattern — the first version did.

### 2.5 The placeholder guard

`.github/actions/commit-readme/check-placeholders.sh` — the one genuinely unit-testable
piece, and therefore the one with real tests. It takes a file path and exits non-zero if
the file contains an unresolved Maven placeholder.

It runs inside the composite action, before `git add`. This is the only place it can be
correct: it is the moment of committing, and it is reached identically by all four
callers. `#71`'s third suggested direction asked for exactly this.

**Two consequences of the guard, both accepted deliberately** (raised in code review):

- **It fails on any `${NAME}`, not only properties this estate uses.** That is intended. A literal
  `${...}` in a README *source* is already broken under Maven filtering — the filtered output would
  differ from the source unpredictably — so the guard catches a latent bug rather than inventing a
  false positive. What genuinely changes is the consequence: a silent bad commit before, a failed
  build now. Both estate READMEs are clean today, checked. If a consumer ever needs a literal
  `${...}`, add an allowlist here rather than loosening the pattern.
- **A failure can now stop a run mid-publish.** `generate-list-of-issues` is configured
  `<failOnError>false</failOnError>` (`pom.xml:1051`) and `${issues.text.list}` sits in both README
  templates (`parent-poms` line 17, `dsh` line 579). So an API hiccup, an expired token or a missing
  milestone leaves it literal *without* failing the build, and the guard then reddens the run. Before
  this change that produced a bad commit but a completed release. Mitigated by checking **early as
  well**: `project-staging.yml` calls the action with `verify-only: 'true'` right after the build, and
  `deploy.yml` calls the script directly — both before the site is published. Not fully closed, since
  artifact deploy happens first, but an artifact deploy is re-runnable (the 409 handling makes it
  idempotent) whereas a half-published site is not. `project-release.yml` and `project-hotfix.yml` get
  no early check: there the README is generated *after* the site deploy, inside `target/checkout`, so
  the commit-time guard already sits immediately after generation and no earlier point exists. Making
  `generate-list-of-issues` fail fast was rejected — a transient GitHub API failure would then block
  releases outright, which is worse than a stale issue list.

The pattern must match what `maven-resources-plugin` actually leaves behind. An
unresolvable `${...}` is emitted verbatim, and property names in this estate include dots
(`${project.build.version}`, `${site.deployment.personal.main}`), so the pattern is
`\$\{[A-Za-z0-9_.-]+\}`. `#71` suggested `\$\{[a-z.]*\}`, which is both too narrow (misses
`${projectVersion}`-style camel case and digits) and matches the empty string `${}`.

---

## 3. File structure

| Path | Action | Responsibility |
|---|---|---|
| `pom.xml:1097-1114` | Modify | delete the `commit-readme-md` execution and its `maven-scm-plugin` block from `readme-generation` |
|  `pom.xml:79-82` | Modify | mark `commit.readme.phase` deprecated in its comment; keep the property |
| `.github/actions/commit-readme/action.yml` | Create | the commit step, once, for four callers |
| `.github/actions/commit-readme/check-placeholders.sh` | Create | fail on an unresolved `${...}` |
| `.github/actions/commit-readme/check-placeholders.test.sh` | Create | tests for the guard |
| `.github/workflows/project-staging.yml` | Modify | call the action after `Deploy Staging Site` |
| `.github/workflows/project-release.yml` | Modify | replace `Update README.md on Master` (216-222) with a call |
| `.github/workflows/project-hotfix.yml` | Modify | replace `Update README.md on Master` (175-180) with a call |
| `.github/workflows/deploy.yml` | Modify | call the action after the snapshot and release site steps |
| `.github/workflows/build.yml` | Modify | run the guard's tests; drop the now-redundant `-Dcommit.readme.phase=none` |
| `.gitignore` | Modify | add `.logs/`, which this spec's procedures write to (Task 1) |

---

## 4. Tasks

### Task 1: Confirm the fork count and the forking mojo

Establishes the baseline the fix is measured against, and verifies §1.1 empirically
rather than from a plugin descriptor alone. No production change.

**Files:** none — a measurement, recorded on the issue.

- [ ] **Step 1: make `.logs/` ignorable, then build this branch's parent into the local repository**

This repository's `.gitignore` has no `.logs/` entry — verified — so the log redirection
this spec uses everywhere would otherwise leave build logs as untracked files, and
`maven-scm-plugin`'s historical `git commit -a` fallback is exactly the kind of thing that
sweeps those into a commit. Add the entry first.

```bash
cd /c/Users/marce/github/parent-poms
grep -qxF '.logs/' .gitignore || printf '\n# Local Maven build logs (never committed)\n.logs/\n' >> .gitignore
git add .gitignore && git commit -m "chore(#71): ignore .logs/ so local build logs cannot be committed

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6EQDNWoodRfdaJLVytfG8"

mkdir -p .logs
mvn -B -DskipTests install > .logs/mvn-install.log 2>&1 &
MVN_PID=$!
echo "Monitor with:  tail -f .logs/mvn-install.log"
wait $MVN_PID; echo "maven exit=$?"
```

Expected: `maven exit=0`.

- [ ] **Step 2: run a `site` build in DSH with commits disarmed, and count the replays**

`-Dcommit.readme.phase=none` is the escape hatch documented at `pom.xml:80`. It keeps this
diagnostic from committing to the working repository while leaving `copy-readme-md` — which
shares the phase, and therefore the replay count — fully active.

```bash
cd /c/Users/marce/github/dsh
mkdir -p .logs
mvn -B -Ddeployment -Dcommit.readme.phase=none \
  -Dsite.deployment.personal.main=file:///tmp/sites \
  site > .logs/mvn-site-forkcount.log 2>&1 &
MVN_PID=$!
echo "Monitor with:  tail -f .logs/mvn-site-forkcount.log"
wait $MVN_PID; echo "maven exit=$?"

echo "--- copy-readme-md executions ---"
grep -c 'copy-readme-md' .logs/mvn-site-forkcount.log
echo "--- forking report mojos ---"
grep -nE 'maven-jxr-plugin.*(aggregate|jxr)' .logs/mvn-site-forkcount.log
```

Expected: **4** `copy-readme-md` executions, and four `requires '<phase>' forked phase
execution` lines naming `maven-jxr-plugin:aggregate`, `maven-jxr-plugin:test-aggregate`,
`maven-javadoc-plugin:aggregate` and `maven-javadoc-plugin:test-aggregate`. If the count
differs, stop and reconcile with §1.1 before continuing.

**Measured 2026-09-19:** exactly that — 4 replays at log lines 58, 545, 1102, 1589, from the
four forks at lines 34, 521, 1078, 1565. An earlier draft of this spec predicted 3 from `jxr`
alone; both the count and the plugin set were wrong and §1.1 now carries the corrected
version. The `-X` follow-up also settled the timestamp mechanism — see §1.3.

- [ ] **Step 3: restore the working tree**

`copy-readme-md` rewrites `README.md` in place.

```bash
cd /c/Users/marce/github/dsh && git checkout -- README.md && git status --short
```

Expected: no output.

- [ ] **Step 4: record the measurement on the issue**

```bash
gh issue comment 71 --repo MRISS-Projects/parent-poms --body "Baseline confirmed: 3 \`copy-readme-md\` executions in one \`site\` run, and the forking mojos are \`aggregate\` (executePhase \`compile\`) and \`test-aggregate\` (\`test-compile\`), not \`jxr\` (\`generate-sources\`), which cannot reach \`process-resources\`. Three commits = one main pass + two aggregate report forks. Correcting the stack reading in the issue body."
```

---

### Task 2: The placeholder guard, test-first

**Files:**

- Create: `.github/actions/commit-readme/check-placeholders.sh`
- Test: `.github/actions/commit-readme/check-placeholders.test.sh`

**Interfaces:**

- Produces: `check-placeholders.sh <file>` — exit `0` clean, exit `1` on an unresolved
  placeholder or a missing file, with the offending line and line number on stderr.
- Consumed by: Task 3's `action.yml`.

- [ ] **Step 1: write the failing test**

```bash
#!/bin/sh
# Tests for check-placeholders.sh. Run: sh check-placeholders.test.sh
set -u

SCRIPT="$(dirname "$0")/check-placeholders.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

expect_exit() {
  description="$1"; expected="$2"; file="$3"
  sh "$SCRIPT" "$file" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "ok   - $description"
  else
    echo "FAIL - $description (expected exit $expected, got $actual)"
    failures=$((failures + 1))
  fi
}

printf 'title\n0.3.0-SNAPSHOT - RC6 - 20260918-224757\n' > "$TMP/clean.md"
expect_exit "a fully resolved README passes" 0 "$TMP/clean.md"

printf 'title\n0.3.0-SNAPSHOT - RC6 - ${timestamp}\n' > "$TMP/timestamp.md"
expect_exit "the observed \${timestamp} regression fails" 1 "$TMP/timestamp.md"

printf 'v: ${project.build.version}\n' > "$TMP/dotted.md"
expect_exit "a dotted property name fails" 1 "$TMP/dotted.md"

printf 'v: ${projectVersion2}\n' > "$TMP/camel.md"
expect_exit "a camel-case name with a digit fails" 1 "$TMP/camel.md"

printf 'cost is $100 and $ alone\n' > "$TMP/dollars.md"
expect_exit "a bare dollar sign passes" 0 "$TMP/dollars.md"

printf 'shell: ${} and ${ } are not properties\n' > "$TMP/empty.md"
expect_exit "an empty or blank brace pair passes" 0 "$TMP/empty.md"

expect_exit "a missing file fails" 1 "$TMP/does-not-exist.md"

if [ "$failures" -eq 0 ]; then echo "All tests passed."; else echo "$failures test(s) failed."; fi
exit "$failures"
```

- [ ] **Step 2: run it to make sure it fails**

```bash
cd /c/Users/marce/github/parent-poms && sh .github/actions/commit-readme/check-placeholders.test.sh
```

Expected: every case FAILs — `check-placeholders.sh` does not exist yet, so `sh` exits 127
and no expectation matches. Exit code 7.

- [ ] **Step 3: write the minimal implementation**

```bash
#!/bin/sh
# Fail if a generated file still contains an unresolved Maven property placeholder.
#
# maven-resources-plugin leaves an unresolvable ${...} as literal text rather than
# substituting blank, which is what makes the MRISS-Projects/parent-poms#71 regression
# visible. Property names in this estate contain dots (${project.build.version}), so the
# pattern allows them; ${} and ${ } are excluded because they are not property references
# and appear in shell snippets.
set -eu

file="${1:?usage: check-placeholders.sh <file>}"

if [ ! -f "$file" ]; then
  echo "check-placeholders: no such file: $file" >&2
  exit 1
fi

if match=$(grep -nE '\$\{[A-Za-z0-9_.-]+\}' "$file"); then
  echo "check-placeholders: unresolved placeholder in $file:" >&2
  echo "$match" >&2
  exit 1
fi

exit 0
```

- [ ] **Step 4: run the tests to verify they pass**

```bash
cd /c/Users/marce/github/parent-poms && sh .github/actions/commit-readme/check-placeholders.test.sh
```

Expected: 7 × `ok`, `All tests passed.`, exit 0.

- [ ] **Step 5: commit**

```bash
cd /c/Users/marce/github/parent-poms
chmod +x .github/actions/commit-readme/check-placeholders.sh
git add .github/actions/commit-readme/check-placeholders.sh \
        .github/actions/commit-readme/check-placeholders.test.sh
git commit -m "feat(#71): add a guard that fails on an unresolved README placeholder

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6EQDNWoodRfdaJLVytfG8"
```

---

### Task 3: The composite action

**Files:**

- Create: `.github/actions/commit-readme/action.yml`

**Interfaces:**

- Consumes: `check-placeholders.sh` from Task 2.
- Produces: an action referenced as `./.github/actions/commit-readme` with inputs
  `branch` (required), `working-directory` (default `.`), `push-url` (default `''`),
  `message` (default `Auto-generated README.md [skip jenkins]`). Consumed by Tasks 4 and 5.

- [ ] **Step 1: write the action**

```yaml
name: Commit generated README.md
description: >
  Commit and push the README.md produced by the inherited readme-generation profile.
  Kept outside the Maven lifecycle so a forked lifecycle cannot replay it — see
  specs/71-commit-readme-md-reentrancy.md.

inputs:
  branch:
    description: 'Branch to push the README commit to'
    required: true
  working-directory:
    description: 'Directory holding the generated README.md. Default: the workspace'
    required: false
    default: '.'
  push-url:
    description: >
      Explicit remote URL to push to. Empty pushes to origin, which works wherever
      actions/checkout persisted credentials. Required in a directory produced by
      git clone rather than by checkout.
    required: false
    default: ''
  message:
    description: 'Commit message'
    required: false
    default: 'Auto-generated README.md [skip jenkins]'

runs:
  using: composite
  steps:
    - name: Verify the generated README has no unresolved placeholders
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      run: ${{ github.action_path }}/check-placeholders.sh README.md

    - name: Commit and push README.md
      shell: bash
      working-directory: ${{ inputs.working-directory }}
      env:
        COMMIT_MESSAGE: ${{ inputs.message }}
        PUSH_URL: ${{ inputs.push-url }}
        TARGET_BRANCH: ${{ inputs.branch }}
      run: |
        set -euo pipefail

        git add README.md

        if git diff --cached --quiet -- README.md; then
          echo "README.md is unchanged; nothing to commit."
          exit 0
        fi

        git commit -m "$COMMIT_MESSAGE" -- README.md

        if [ -n "$PUSH_URL" ]; then
          git push "$PUSH_URL" "HEAD:$TARGET_BRANCH"
        else
          git push origin "HEAD:$TARGET_BRANCH"
        fi
```

**Why `env:` rather than `${{ }}` inside `run:`.** An expression interpolated into a shell
body is substituted as raw text before the shell runs, so a branch name or commit message
containing shell metacharacters would execute. `push-url` carries `DEPLOY_TOKEN`, which makes
this the worst place in the repository to leave that pattern. Passing the values as
environment variables and quoting them in the script removes the injection path entirely and
keeps the token out of the rendered command line. Note the `working-directory:` interpolation
above is unavoidable — it is a workflow-syntax field, not shell input, and GitHub evaluates it
itself.

- [ ] **Step 2: verify the action parses as YAML**

```bash
cd /c/Users/marce/github/parent-poms
export PATH="/c/Users/marce/apps/node-v24.21.0-win-x64:$PATH"
node -e "const f=require('fs');const s=f.readFileSync('.github/actions/commit-readme/action.yml','utf8');if(!/using: composite/.test(s))throw new Error('not composite');console.log('action.yml readable, composite');"
```

Expected: `action.yml readable, composite`.

- [ ] **Step 3: commit**

```bash
cd /c/Users/marce/github/parent-poms
git add .github/actions/commit-readme/action.yml
git commit -m "feat(#71): add a composite action that commits the generated README

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6EQDNWoodRfdaJLVytfG8"
```

---

### Task 4: Remove `commit-readme-md` from the POM

This is the step that fixes the defect. After it, no lifecycle phase commits anything, so
a replayed `process-resources` is harmless.

**Files:**

- Modify: `pom.xml` — delete the `maven-scm-plugin` block inside `readme-generation`
  (currently lines 1097-1114); amend the `commit.readme.phase` comment at 79-81.

- [ ] **Step 1: write the failing check**

There is no test framework for POM structure, so the assertion is a grep over the
effective POM of a consuming project — which is what actually matters, since the profile
reaches DSH by inheritance.

```bash
cd /c/Users/marce/github/dsh
mvn -B -N -Ddeployment help:effective-pom -Doutput=/tmp/dsh-effective.xml > /dev/null 2>&1
echo "commit-readme-md occurrences in DSH's effective POM:"
grep -c 'commit-readme-md' /tmp/dsh-effective.xml || true
```

Expected **now**: `1`. Expected **after** this task plus a reinstall of the parent: `0`.

- [ ] **Step 2: delete the execution**

Remove the whole `maven-scm-plugin` `<plugin>` block from the `readme-generation` profile —
the one whose single execution is `commit-readme-md` at `pom.xml:1102`. Leave
`maven-changes-plugin`, `buildnumber-maven-plugin` and `maven-resources-plugin` untouched.

- [ ] **Step 3: amend the `commit.readme.phase` comment**

The property stays — `build.yml` passes it today and consuming projects may pin it — but it
now controls nothing. Replace the comment at `pom.xml:79-81` with:

```xml
        <!-- Retained for compatibility only. It used to bind the commit-readme-md execution,
             which moved out of the lifecycle in #71 because a forked lifecycle (maven-jxr-plugin's
             aggregate and test-aggregate report mojos fork to compile and test-compile) replayed
             process-resources and committed the README up to three times, one of them carrying an
             unresolved ${timestamp}. The README is now committed by
             .github/actions/commit-readme. Passing -Dcommit.readme.phase=none is harmless and no
             longer necessary. Remove this property once no consuming project passes it. -->
```

- [ ] **Step 4: reinstall the parent and re-run the check**

```bash
cd /c/Users/marce/github/parent-poms
mvn -B -DskipTests install > .logs/mvn-install-task4.log 2>&1 &
MVN_PID=$!
echo "Monitor with:  tail -f .logs/mvn-install-task4.log"
wait $MVN_PID; echo "maven exit=$?"

cd /c/Users/marce/github/dsh
mvn -B -N -Ddeployment help:effective-pom -Doutput=/tmp/dsh-effective.xml > /dev/null 2>&1
grep -c 'commit-readme-md' /tmp/dsh-effective.xml || echo 0
```

Expected: `maven exit=0`, then `0`.

- [ ] **Step 5: prove the site build no longer commits**

```bash
cd /c/Users/marce/github/dsh
mvn -B -Ddeployment -Dsite.deployment.personal.main=file:///tmp/sites \
  site > .logs/mvn-site-after.log 2>&1 &
MVN_PID=$!
echo "Monitor with:  tail -f .logs/mvn-site-after.log"
wait $MVN_PID; echo "maven exit=$?"

echo "--- scm:checkin executions (expect 0) ---"
grep -c 'maven-scm-plugin.*checkin' .logs/mvn-site-after.log || echo 0
echo "--- copy-readme-md executions (expect 4, unchanged) ---"
grep -c 'copy-readme-md' .logs/mvn-site-after.log
echo "--- git state: README modified, nothing committed ---"
git status --short README.md
git log --oneline -1
```

Expected: `0` checkins; `4` `copy-readme-md` — the forks still replay, which is the point,
they are simply harmless now; `README.md` shown as modified; `git log` unchanged from
before the run. Note this run is **not** passing `-Dcommit.readme.phase=none`, unlike
Task 1 — nothing needs disarming any more.

- [ ] **Step 6: restore and commit**

```bash
cd /c/Users/marce/github/dsh && git checkout -- README.md
cd /c/Users/marce/github/parent-poms
git add pom.xml
git commit -m "fix(#71): stop committing README.md from inside the Maven lifecycle

maven-jxr-plugin's aggregate and test-aggregate report mojos fork the
lifecycle to compile and test-compile, replaying process-resources and
with it all three README executions. That produced three commits per
staging run, one carrying an unresolved \${timestamp}. Generation stays
in the profile; the commit moves to .github/actions/commit-readme.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6EQDNWoodRfdaJLVytfG8"
```

---

### Task 5: Wire the four workflows

**Files:**

- Modify: `.github/workflows/project-staging.yml` — add a step after `Deploy Staging Site`
- Modify: `.github/workflows/project-release.yml` — replace `Update README.md on Master` (216-222)
- Modify: `.github/workflows/project-hotfix.yml` — replace `Update README.md on Master` (175-180)
- Modify: `.github/workflows/deploy.yml` — add steps after the snapshot and release site steps
- Modify: `.github/workflows/build.yml` — run the guard's tests; drop `-Dcommit.readme.phase=none`

**Interfaces:**

- Consumes: the action from Task 3.

- [ ] **Step 1: `project-staging.yml` — add after `Deploy Staging Site`**

The workspace was checked out with `token:`, so credentials are persisted and `origin` works.

```yaml
      - name: Commit generated README.md
        uses: ./.github/actions/commit-readme
        with:
          branch: ${{ inputs.branch_name }}
```

- [ ] **Step 2: `project-release.yml` — replace `Update README.md on Master`**

The existing step runs `process-resources` inside `target/checkout`, which is a `git clone`
of master, so it needs the explicit URL. Generation still has to happen — only the commit
moved — so the Maven call stays and the commit is appended.

```yaml
      - name: Generate README.md on Master
        run: |
          cd target/checkout
          mvn -B \
            -Ddeployment \
            -Drelease-deployment \
            process-resources

      - name: Commit generated README.md on Master
        uses: ./.github/actions/commit-readme
        with:
          branch: master
          working-directory: target/checkout
          push-url: https://x-access-token:${{ secrets.DEPLOY_TOKEN }}@github.com/MRISS-Projects/${{ inputs.git_project }}.git
```

- [ ] **Step 3: `project-hotfix.yml` — the same replacement**

Identical shape. Repeated rather than cross-referenced, because tasks are read out of order.

```yaml
      - name: Generate README.md on Master
        run: |
          cd target/checkout
          mvn -B \
            -Ddeployment \
            -Drelease-deployment \
            process-resources

      - name: Commit generated README.md on Master
        uses: ./.github/actions/commit-readme
        with:
          branch: master
          working-directory: target/checkout
          push-url: https://x-access-token:${{ secrets.DEPLOY_TOKEN }}@github.com/MRISS-Projects/${{ inputs.git_project }}.git
```

- [ ] **Step 4: `deploy.yml` — add a commit after each site step**

This repository consuming itself. `deploy.yml` is dispatched, not reusable, so it cannot
inherit the step; it calls the same action by path. Add after `Deploy Snapshot Site`:

```yaml
      - name: Commit generated README.md (snapshot)
        if: ${{ inputs.release_type == 'snapshots' }}
        uses: ./.github/actions/commit-readme
        with:
          branch: ${{ github.ref_name }}
```

**`github.ref_name`, never a hardcoded `master`.** `deploy.yml` is normally dispatched on
`master`, where the two are identical. Dispatched on a task branch — which Task 6 Step 1 does
deliberately — a hardcoded `master` makes the action run `git push origin HEAD:master` from a
checkout of the branch, fast-forwarding `master` to the branch tip and merging unreviewed work
without a pull request. `github.ref_name` always names the ref actually checked out. The two
release workflows keep `branch: master` because there `target/checkout` is an explicit
`git clone --branch master`, so master genuinely is the target.

**The release path gets no commit step.** Its `scm:checkin` for version changes
(`deploy.yml:356`) already sweeps `README.md` into the release commit, so a second commit step
would find nothing staged. What it lacks is a guard, which goes inline immediately before that
checkin — see Step 4b.

- [ ] **Step 4b: `deploy.yml` — guard the release path inline**

Immediately before the `Commit all version changes` block inside `Release Deploy`:

```bash
          # ---- #71: guard before the commit below sweeps README.md in ----
          .github/actions/commit-readme/check-placeholders.sh README.md
```

- [ ] **Step 5: `build.yml` — run the guard's tests and drop the disarming flag**

Add before the existing Maven steps:

```yaml
      - name: Test the README placeholder guard
        run: sh .github/actions/commit-readme/check-placeholders.test.sh
```

Then remove `-Dcommit.readme.phase=none` from lines 162 and 170. It is now a no-op, and
leaving it implies the lifecycle still commits.

- [ ] **Step 6: verify every workflow still parses, and that no `scm:checkin` for the README survives**

```bash
cd /c/Users/marce/github/parent-poms
export PATH="/c/Users/marce/apps/node-v24.21.0-win-x64:$PATH"
for f in .github/workflows/*.yml .github/actions/commit-readme/action.yml; do
  node -e "require('fs').readFileSync('$f','utf8')" && echo "readable: $f"
done
echo "--- commit-readme-md must be gone from the POM ---"
grep -c 'commit-readme-md' pom.xml || echo 0
echo "--- callers of the action (expect 4 uses: staging, release, hotfix, deploy-snapshot) ---"
grep -rc 'actions/commit-readme' .github/workflows/ | grep -v ':0'
```

Expected: every file readable; `0` in the POM; four `uses:` call sites plus one inline guard.

- [ ] **Step 7: commit**

```bash
cd /c/Users/marce/github/parent-poms
git add .github/workflows/ .github/actions/
git commit -m "feat(#71): commit the generated README from the workflows, not the reactor

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01V6EQDNWoodRfdaJLVytfG8"
```

---

### Task 6: Validate on a real DSH staging run — `#71` AC004

Local runs cannot prove AC001 or AC004; only a real staging run can. This task is the
acceptance evidence.

**Files:** none — a run, plus comments on the issue.

- [ ] **Step 1: snapshot-deploy this branch's parent**

Consuming repositories resolve the parent from GitHub Packages, so the change has to be
published before DSH's workflow can see it. Per `CLAUDE.md`'s light round trip, dispatch
`deploy.yml` with `release_type: snapshots` — but from **this branch**, not `master`,
because the work is not merged yet.

```bash
cd /c/Users/marce/github/parent-poms
gh workflow run deploy.yml --ref issue-71-commit-readme-md-reentrancy -f release_type=snapshots
gh run list --workflow=deploy.yml --limit 1
```

- [ ] **Step 2: watch it, and check its own README commits**

`deploy.yml` is itself a caller now, so this run is the first test of Task 5's Step 4.

```bash
cd /c/Users/marce/github/parent-poms
gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
git fetch origin master
git log --oneline origin/master -5 | grep -c 'Auto-generated README.md' || echo 0
```

Expected: at most one new `Auto-generated README.md` commit, not three.

- [ ] **Step 3: dispatch a DSH staging run against the RC branch**

```bash
cd /c/Users/marce/github/dsh
gh workflow run staging.yml --ref staging-0.3.0-SNAPSHOT-RC
gh run list --workflow=staging.yml --limit 1
```

- [ ] **Step 4: count the README commits the run produced — the acceptance check**

```bash
cd /c/Users/marce/github/dsh
gh run watch "$(gh run list --workflow=staging.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
git fetch origin staging-0.3.0-SNAPSHOT-RC
git log --oneline origin/staging-0.3.0-SNAPSHOT-RC -6
echo "--- README commits from this run (expect exactly 1) ---"
git log --oneline origin/staging-0.3.0-SNAPSHOT-RC -6 | grep -c 'Auto-generated README.md' || echo 0
echo "--- no committed README may contain a placeholder (expect 0) ---"
for sha in $(git log --format=%H -6 origin/staging-0.3.0-SNAPSHOT-RC); do
  git show "$sha:README.md" 2>/dev/null | grep -cE '\$\{[A-Za-z0-9_.-]+\}' || true
done
```

Expected: exactly **1** README commit, and `0` placeholder matches in every commit
inspected — AC001 and AC002 against a real run.

- [ ] **Step 5: record the evidence on `#71`**

Comment the run URL, the commit list, and both counts. AC004 requires the commit list to
be shown, not summarised.

### Task 6 results — 2026-09-19

**parent-poms snapshot deploy**, run
[35463510690](https://github.com/MRISS-Projects/parent-poms/actions/runs/35463510690), success.
One README commit (`366ac3ec`), one line changed, zero placeholders, on the task branch.
`master` untouched at `fc78b679` — the `github.ref_name` fix held. For contrast, `master`'s two
most recent commits are *both* `Auto-generated README.md`, which is the old behaviour.

**DSH staging, first attempt**, run
[35463833006](https://github.com/MRISS-Projects/dsh/actions/runs/35463833006), **failed** at
`Commit generated README.md` on the relative-path resolution described in §2.4. It still
produced positive evidence: `clean deploy` and `site-deploy` both ran with `-Ddeployment` and
made **zero** README commits, where the defect produced three. That is the POM removal
confirmed in CI for a real consumer.

**DSH staging, second attempt** with the qualified reference, run
[35465923115](https://github.com/MRISS-Projects/dsh/actions/runs/35465923115), **success**:

| Check | Result |
|---|---|
| README commits on the RC branch | **1** (`2c2349bc`) — AC001 |
| Placeholders in the committed README | **0** — AC002 |
| `README.md` line 7 | `0.3.0-SNAPSHOT - RC10 - 20260919-200804` |
| Reactor errors naming `maven-site-plugin` / `maven-jxr-plugin` | none — AC003 |

Both values resolved, so the run also confirms the timestamp reaches the workflow step
correctly now that only one commit happens.

**A note on how the RC branch reached `9b5f2bb5`.** While diagnosing §1.3, a single
`mvn -B -N -Ddeployment process-resources` — run only to read a property — committed **and
pushed** a README to the shared RC branch, because `scm:checkin` pushes. From that run's log:

```text
Executing: git push https://mriss:********@github.com/MRISS-Projects/dsh.git
  refs/heads/staging-0.3.0-SNAPSHOT-RC:refs/heads/staging-0.3.0-SNAPSHOT-RC
```

A local `git reset --hard` undid it locally only, and `git status` reported the branch in sync
because it does not fetch. The commit was left in place by the repository owner's decision;
run 35465923115 regenerated the content correctly on top of it, replacing the `dev` build
number with `RC10`. It is the sharpest available evidence for §2.2's narrowing argument: before
this change, a read-only-looking diagnostic could push to a shared release branch with no
prompt and no warning.

---

### Task 7: Note the sequencing on `#72`

- [ ] **Step 1: comment on `#72`**

```bash
gh issue comment 72 --repo MRISS-Projects/parent-poms --body "#71 lands before this issue and changes its write-point table. It removes the in-reactor \`README.md\` commit — the \`Update README.md on Master\` rows at \`project-release.yml:216-222\` and \`project-hotfix.yml:175-180\` — and replaces it with a \`.github/actions/commit-readme\` step in \`project-staging.yml\`, \`project-release.yml\`, \`project-hotfix.yml\` and \`deploy.yml\`. So a rehearsal gains one write point to guard — the action's \`git push\` — and loses one Maven-internal one. Guarding it once inside the composite action covers all four callers. \`deploy.yml\`'s release path is the exception: its existing \`scm:checkin\` already carries the README, so it gets an inline placeholder guard rather than the action."
```

---

## 5. Self-review

**Spec coverage.** `#71` AC001 → Tasks 4 and 6; AC002 → Tasks 2, 4, 6; AC003 → Task 4
(by deletion — no `scm:checkin` during `site`); AC004 → Task 6. `#71`'s three suggested
directions: "establish why the pair is reachable from the site chain" → Task 1 and §1.1;
"make `create-time-stamp` a prerequisite" → rejected with reasons in §1.2; "fail on a
surviving `${...}`" → Task 2.

**Placeholder scan.** No TBDs. Every code step carries the actual content. Task 5 Step 3
repeats Task 5 Step 2's YAML verbatim rather than referring back to it.

**Type consistency.** The action's four input names (`branch`, `working-directory`,
`push-url`, `message`) are identical in §2.4, Task 3 and all four `uses:` call sites in Task 5.
`check-placeholders.sh` takes one positional argument in Task 2's implementation, its
test, and Task 3's invocation. The placeholder regex `\$\{[A-Za-z0-9_.-]+\}` is the same
in §2.5, Task 2 and Task 6.

**Known gap.** Task 6 Step 1 dispatches `deploy.yml` from an unmerged branch, which
publishes `3.9.0-SNAPSHOT` from a branch rather than `master`. That is deliberate and
matches what `CLAUDE.md`'s light round trip does, but it means `master`'s snapshot is
temporarily behind the branch's. Re-deploy from `master` after merge.

---

## 6. Out of scope, and one piece of future work

**Out of scope:**

- **`#69` and `#65`.** Different defects in the same workflows. `#71` lands first; see Task 7.
- **The rehearsal mode.** `#72`'s.
- **Removing the `commit.readme.phase` property.** Kept for compatibility; Task 4 Step 3
  marks it deprecated with the condition for removing it.
- **`maven-changes-plugin`'s `generate-list-of-issues`.** In the same profile, unaffected —
  it writes into `target/`, not the working tree.
- **The three-times-per-run behaviour of `copy-readme-md` itself.** After this change it
  regenerates an identical file in the working tree two extra times. Wasteful, not
  incorrect, and suppressing a fork's `process-resources` is a much larger change than
  this defect warrants. Recorded here so the next reader knows it was seen and left.
- **Converting the archetypes' APT pages.** `#70`'s, and it excludes archetype-resources.

**Future work — the coupling this change makes explicit.**

Moving a step from the POM to the workflows trades Maven inheritance for workflow reuse.
§2.2 shows the "for free" contract survives, because consuming projects already reach the
profile only through these workflows. But it does make the two-part contract explicit: a
new consumer needs the parent POM **and** workflows pointing here.

The natural mitigation is the `product-parent` archetype, which would scaffold
`.github/workflows/` alongside the parent declaration so a new project gets both halves in
one step. It cannot do that today: `infrastructure/maven-archetypes/product-parent/src/main/resources/archetype-resources/`
ships `git.sh`, `set-version.sh`, `svn-add.sh`, `svn-add.bat` and 17 APT site pages, and no
archetype in this repository contains a `.github` directory or any workflow file.

Modernising the archetypes is its own body of work, acknowledged as not near-term, and
deliberately has no issue. Recorded here so the reasoning is not lost.
