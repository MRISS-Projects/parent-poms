# Spec: a `release_type` input for `project-staging.yml` (`#104`)

| | |
|---|---|
| Issue | [`#104`](https://github.com/MRISS-Projects/parent-poms/issues/104): `project-staging.yml`: a `release_type` input, so a consumer can deploy its snapshot site |
| Milestone | `3.10.0-SNAPSHOT` |
| Branch | `issue-104-staging-release-type`, cut from `master` at `14de6181` |
| Consuming issue | `MRISS-Projects/dsh#127`, which proves this change before it merges. Spec: `dsh/specs/stories/127-deploy-snapshot-site.md` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** A consumer can deploy its snapshot artifacts and site through `project-staging.yml`, by
passing `release_type: snapshots`. A caller that passes nothing gets today's behaviour.

**Architecture.** One new input, one pre-flight step that validates it, and two `run:` steps that
read it from `env:` where they held literals. No POM change and no new action.

## 1. What is RC-specific today

`project-staging.yml` has two literals, each in two steps (`Build and Deploy Staging Artifacts`,
`Stage the Staging Site`):

```bash
-Drelease.type=rcs \
"-Dbuild.number=RC${BUILD_NUM}" \
```

Everything else in the workflow is the same for a snapshot: the checkout of `branch_name`, the
generated `settings.xml`, the integration tests, the README check, `verify-staged-site`, the single
publish and the README commit.

## 2. Design

### 2.1 The input

```yaml
      release_type:
        type: string
        required: false
        default: 'rcs'
        description: >-
          'rcs' stages a release candidate: the site goes under rcs/ and the build number is
          RC<n>. 'snapshots' deploys a development snapshot: the site goes under snapshots/ and
          the build number is <n>. Any other value fails the run before it writes anything.
```

A `workflow_call` input cannot be a `choice`, so the two values are enforced by a step (§2.2).

### 2.2 A pre-flight check

A new step, `Check the release type`, placed before `Build and Deploy Staging Artifacts`, which is
the first write. It reads the input from `env:` and fails on anything but `rcs` or `snapshots`,
naming the value it was given (AC001).

### 2.3 The two steps

Each gains `RELEASE_TYPE` in its `env:` block and derives the build number from it:

```bash
BUILD_NUM="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER}}"
if [ "$RELEASE_TYPE" = "rcs" ]; then
  BUILD_NUM="RC${BUILD_NUM}"
fi
…
  "-Drelease.type=$RELEASE_TYPE" \
  "-Dbuild.number=${BUILD_NUM}" \
```

- **With the default**, the arguments are `-Drelease.type=rcs` and `-Dbuild.number=RC<n>`, exactly
  as before (AC002).
- **With `snapshots`**, they are `-Drelease.type=snapshots` and `-Dbuild.number=<n>`, which is what
  this repository's own `deploy.yml` passes for a snapshot (AC003).
- **`#81` holds.** The value reaches the scripts through `env:` and is used quoted (AC004).

### 2.4 Names and descriptions

- `branch_name`'s description says "RC branch name". It becomes "the branch to build and publish: an
  RC branch for `rcs`, a development branch for `snapshots`".
- The workflow and its steps keep their names (`Project Staging`, `Stage the Staging Site`).
  Renaming them would change what every consumer's run page shows, for no gain in behaviour.
- `CLAUDE.md` names the input where it describes `project-staging.yml`.

### 2.5 Not in scope

- A `dry_run` for this workflow. It still has none.
- Skipping the integration tests for a snapshot. `dsh#127` decided to keep them.
- A separate reusable workflow for snapshots. One input covers it.

## 3. Verification

- **The argument logic, locally.** §2.3's snippet is run in a shell for four cases: `rcs` and
  `snapshots`, each with and without an explicit build number. The `rcs` results must be
  byte-for-byte what the current lines produce.
- **The pre-flight check, locally.** The condition is run against `rcs`, `snapshots`, an empty
  value, `releases` and `RCS`.
- **CI.** `build.yml` on the branch: the `#81` guard and the other checks stay green.
- **The `snapshots` path, for real (AC005).** `dsh#127`'s proof run: DSH's `deploy.yml`, pointed at
  this branch, dispatched on DSH's task branch. It deploys DSH's snapshot artifacts and publishes
  its site under `snapshots/products/dsh/`. This PR does not merge before that run is green.
- **The `rcs` path is not run before the merge.** This workflow has no dry run, and an RC staging
  needs an RC branch. The local comparison stands in for it. Its first real run is DSH's 0.4.0 RC.

## 4. Files to change

| File | Change |
|---|---|
| `.github/workflows/project-staging.yml` | the input (§2.1), the pre-flight step (§2.2), the two steps (§2.3), `branch_name`'s description (§2.4) |
| `CLAUDE.md` | the input, where `project-staging.yml` is described |

## 5. Tasks

- [ ] **Task 1.** Record what the current lines produce for the default case, as the baseline.
- [ ] **Task 2.** Make the change (§2).
- [ ] **Task 3.** Run the local checks (§3), and record them. Push, and record the CI run.
- [ ] **Task 4.** Hand over to `dsh#127` for the proof run. Record its run here.
- [ ] **Task 5.** Open a PR into `master` that references `#104`.

## 6. Acceptance criteria

| AC | Covered by |
|---|---|
| AC001: only `rcs` and `snapshots` are accepted; anything else fails before a write | §2.2; task 3 |
| AC002: a call without `release_type` produces the same Maven commands as before | §2.3; tasks 1 and 3 |
| AC003: `snapshots` deploys the artifacts and publishes under `snapshots/`, with no `RC` prefix | §2.3; task 4 |
| AC004: the input reaches the `run:` bodies through `env:`; the guard stays green | §2.3; task 3 |
| AC005: proved by `dsh#127`'s snapshot deploy before the merge | task 4 |

## 7. Verification results

To be filled in during the build.
