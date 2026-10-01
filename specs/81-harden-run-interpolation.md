# Spec: no `${{ }}` in any `run:` body (`#81`)

| | |
|---|---|
| Issue | [`#81`](https://github.com/MRISS-Projects/parent-poms/issues/81): harden `project-release.yml`, where dispatch inputs are interpolated into `run:` bodies in 12 more steps |
| Milestone | `3.10.0-SNAPSHOT` |
| Branch | `issue-81-harden-run-interpolation`, cut from `master` at `ca7a6e5f` |
| Precedent | PR #80 fixed its own two steps with the `env:` pattern. `#95` set the scratch-branch rehearsal used in §4 |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** No caller-supplied value is ever parsed as shell code, in any reusable workflow or
composite action in this repository. A guard in `build.yml` keeps it that way.

**Architecture.** Every `${{ }}` expression inside a `run:` body moves into the step's `env:` block,
and the script reads it as a quoted variable. This is PR #80's pattern, already used by
`Check the development branch exists`, `Create Hotfix Branch` and others. Once every body is clean,
the rule is simple enough to enforce mechanically: **no `${{` in any `run:` body**.

**Tech stack.** GitHub Actions YAML and bash. The proof is a static guard plus dry-run rehearsals
from DSH.

## 1. The audit

The issue's list was written against `project-release.yml` before later changes, and asked for the
other workflows to be audited "in the same pass". A scan of every `run:` body (block and
single-line, in `.github/workflows/*.yml` and `.github/actions/*/action.yml`) on `ca7a6e5f` finds
the following.

### 1.1 Caller-supplied inputs in `run:` bodies: the defect

| File | Step | Inputs interpolated |
|---|---|---|
| `project-release.yml` | `Maven Release` | `next_development_version`, `current_version` (×3 across both branches of the dry-run `if`) |
| `project-release.yml` | `Maven Release Perform` | `site_deployment_url` |
| `project-release.yml` | `Create Hotfix Branch` | `hotfix_branch` (×2) |
| `project-release.yml` | `Merge Release Tag to Master` | `current_version`, `git_project` |
| `project-release.yml` | `Deploy Site to gh-pages` | `site_deployment_url` |
| `project-release.yml` | `Remove RC Branch` | `git_project`, `branch_name` (×2) |
| `project-hotfix.yml` | `Maven Release Perform` | `site_deployment_url` |
| `project-hotfix.yml` | `Merge Release Tag to Master` | `git_project` |
| `project-hotfix.yml` | `Deploy Site to gh-pages` | `site_deployment_url` |
| `project-stage.yml` | `Create RC branch` | `next_development_version` |
| `project-staging.yml` | `Build and Deploy Staging Artifacts` | `build_number`, `appengine_project_version` (×2), `cloudrun_project_version` (×2) |
| `project-staging.yml` | `Deploy Staging Site` | `build_number` |
| `actions/rehearsal-tag` | `Install the release-version artifacts…` | `inputs.site_deployment_url` |

That is 13 steps. `build.yml` and `deploy.yml` have none.

### 1.2 Issue entries that are not `run:` interpolation

Six of the issue's twelve have no `${{ }}` in a `run:` body:

- `Checkout`, `Rehearsal setup`, `Rehearsal tag bridge`, `Rehearsal verify`,
  `Render consumer Maven properties` and `Commit generated README.md on Master` are `uses:` steps.
- They pass inputs through `with:`, which is data, not script. The composite actions behind them
  then read those inputs safely through `env:`. The one exception is `rehearsal-tag`, listed in
  §1.1.

### 1.3 Runner-supplied values: not a defect, cleaned anyway

`${{ github.action_path }}` appears in five composite-action steps (`commit-readme`,
`rehearsal-setup`, `rehearsal-tag`, `rehearsal-verify` ×2). No caller can set it. It is replaced by
`$GITHUB_ACTION_PATH`, which the runner exports in composite actions and which `maven-properties` and
`merge-to-develop` already use. That makes the guard's rule absolute, with no allowlist to maintain.

### 1.4 DSH, the consumer

DSH's own workflows were scanned too. Their only `run:` interpolation is `${{ github.repository }}`,
in `wiki-sync.yml`, which no caller can set. They are out of scope here.

## 2. Design

### 2.1 The rewrite, per step

```yaml
      - name: Remove RC Branch
        env:
          GIT_PROJECT: ${{ inputs.git_project }}
          BRANCH_NAME: ${{ inputs.branch_name }}
        run: |
          REPO_URL="https://x-access-token:${DEPLOY_TOKEN}@github.com/MRISS-Projects/${GIT_PROJECT}.git"
          git push $RH_GIT_PUSH_DRYRUN "$REPO_URL" --delete "$BRANCH_NAME"
```

- **One name per input.** The `env:` name is the input's name in upper case
  (`NEXT_DEVELOPMENT_VERSION`, `SITE_DEPLOYMENT_URL`), the convention the existing hardened steps use.
- **Merging with existing `env:`.** A step that already has an `env:` block gets the new names added
  to it.
- **Quoting.** Every use is double-quoted, including inside `-Dprop="$VAR"` and the
  `rehearsal-marker.sh` message strings.
- **Composite actions.** `${{ inputs.x }}` becomes `env: X: ${{ inputs.x }}` on the step.
- **`dry_run`.** `inputs.dry_run` stays in `if:` conditions. An `if:` is an expression, not a
  script, so it is not affected.
- **Existing unquoted variables are left alone.** `$RH_GIT_PUSH_DRYRUN` and `$RH_SCM_LOCAL_URL` are
  set by the workflow itself, are never caller input, and are deliberately unquoted so that an empty
  value adds no argument. Changing them is a different change.

### 2.2 The guard, in `build.yml`

A new step, `Check no run: body interpolates an expression`, sits beside the existing guards
(`#71`, `#72`, `#78`). It uses their style: inline, `set -euo pipefail`, a `::error::` naming every
offending line, and a short reason.

- **What it scans.** An `awk` pass tracks `run:` bodies. Those are a `run: |` or `run: >` block
  until the indentation returns to the `run:` key, or a single-line `run: …`. It fails on any
  `${{` inside one, across `.github/workflows/*.yml` and `.github/actions/*/action.yml`.
- **Red first.** Against `ca7a6e5f` it reports every line of §1.1 and §1.3, 31 in all: 25 caller inputs and 6 `github.action_path`. That run is
  the guard's red, recorded in task 1.
- **Self-check.** The step's own body names the pattern only inside a regular expression, never as
  a literal `${{`, so the guard does not flag itself. The task 1 run proves that too: the guard step
  is not among the offenders.

### 2.3 Not in scope

- **Validating version shapes.** The issue excludes this, and `#69` already rejects a malformed
  version at `release:update-versions`.
- **`with:` values passed to third-party actions.** They are data.
- **DSH's workflows** (§1.4).

## 3. Files to change

| File | Change |
|---|---|
| `.github/workflows/project-release.yml` | §1.1, 6 steps |
| `.github/workflows/project-hotfix.yml` | §1.1, 3 steps |
| `.github/workflows/project-stage.yml` | §1.1, 1 step |
| `.github/workflows/project-staging.yml` | §1.1, 2 steps |
| `.github/actions/rehearsal-tag/action.yml` | §1.1 `inputs.site_deployment_url`; §1.3 `github.action_path` |
| `.github/actions/commit-readme/action.yml`, `rehearsal-setup/action.yml`, `rehearsal-verify/action.yml` | §1.3 `github.action_path` → `$GITHUB_ACTION_PATH` |
| `.github/workflows/build.yml` | the guard (§2.2) |

## 4. Verification design

### 4.1 Static: the guard

The guard runs on every push. It goes red on the unfixed tree (task 1) and green on the fixed one
(task 3). It also checks the whole tree, including the steps no rehearsal can reach.

### 4.2 Dynamic: dry-run rehearsals from DSH

These follow `#95`'s method. A scratch DSH branch points one wrapper at
`project-*.yml@issue-81-harden-run-interpolation`, and is dispatched with `dry_run=true`. The
composite actions stay at `@master` during these runs, as in `#95`. Their changes are covered by the
guard, and run for real at the next release.

- **R1, the release path, ordinary inputs.** Scratch branch `rehearsal-81` from DSH `DEVELOP`.
  `release.yml` is dispatched with `branch_name=rehearsal-81`, `current_version=0.4.0`,
  `next_development_version=0.4.1-SNAPSHOT`, `hotfix_branch=0.4.x`,
  `initial_hotfix_version=0.4.1-SNAPSHOT` and `dry_run=true`. Expect green, with `rehearsal-verify`
  announcing every write point and the remote unchanged. This proves the rewrite did not break the
  release path.
- **R2, the release path, an awkward input**, as the issue asks. It is the same as R1, but with
  `next_development_version='0.4.1-SNAPSHOT$(printf "INJ%s" 81 >&2)'`.
  - **Why this payload.** It is chosen so that a failure is still harmless. Executed as code, it
    prints `INJ81` to stderr, and the substitution captures nothing. So the command line keeps all
    its arguments, `-DdryRun` included, and nothing is truncated. Its literal text contains
    `INJ%s`, never `INJ81`.
  - **Pass condition.** The job log contains no `INJ81`. Maven receives the value as data: it either
    rejects it as an invalid version, or carries it through the dry run. Either outcome passes,
    provided no `INJ81` appears.
  - **No red rehearsal against `@master`.** The issue's own payload shape (`; …`) truncates the
    command line. In `Maven Release`, the truncation could drop the arguments that make the run a
    dry run, and turn a rehearsal into a real `release:prepare`. The guard's red (§4.1) is the
    evidence that the defect exists.
- **R3, the hotfix path.** Scratch branch `rehearsal-81-hotfix` from DSH `0.3.x`. `hotfix.yml`
  points at the task branch, and is dispatched with `branch_name=rehearsal-81-hotfix` and
  `dry_run=true`. Expect green.
- **Stage and staging cannot be rehearsed.** `project-stage.yml` and `project-staging.yml` have no
  `dry_run` input, and a run writes: an RC branch, a version bump, staging packages and a site.
  Their three steps are covered by the guard and by review. They run for real at DSH's next staging,
  0.4.0's RC, which should be watched with this change in mind.

All scratch branches are deleted from the remote after their run. The run URLs and the scratch
commit SHAs are recorded in §7.

## 5. Tasks

- [ ] **Task 1 (red).** Add the guard step to `build.yml`, push, and record the CI run that fails,
      listing the 31 offending lines.
- [ ] **Task 2.** Rewrite the 13 steps of §1.1 and the six `github.action_path` uses of §1.3 (five steps), one
      commit per file.
- [ ] **Task 3 (green).** Push, and record the green CI run, with the guard passing.
- [ ] **Task 4.** Rehearsal R1.
- [ ] **Task 5.** Rehearsal R2, the awkward input.
- [ ] **Task 6.** Rehearsal R3, the hotfix path.
- [ ] **Task 7.** Delete the scratch branches, record the runs in §7, and open a PR into `master`
      that references `#81`.

## 6. Acceptance criteria

The issue states its fix and validation in prose, not as numbered criteria. This spec holds itself
to the following:

| # | Criterion | Covered by |
|---|---|---|
| 1 | No `run:` body in any workflow or composite action interpolates a `${{ }}` expression | §2.1, task 2 |
| 2 | The build fails if one is reintroduced | §2.2, tasks 1 and 3 |
| 3 | The release and hotfix paths still rehearse green | R1, R3 |
| 4 | An awkward caller value is received as data, not executed | R2 |
| 5 | `deploy.yml`, `project-hotfix.yml` and the staging workflows are audited, as the issue asks | §1 |

## 7. Verification results

To be filled in during the build.
