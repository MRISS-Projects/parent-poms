# Spec: one `gh-pages` concurrency group per consumer (`#106`)

| | |
|---|---|
| Issue | [`#106`](https://github.com/MRISS-Projects/parent-poms/issues/106): `project-staging.yml` has no concurrency group, unlike `project-release.yml` and `project-hotfix.yml` |
| Milestone | `3.11.0-SNAPSHOT` |
| Branch | `issue-106-site-concurrency-group`, cut from `master` at `4dee01a6` |
| Found in | `MRISS-Projects/dsh#149`, in review |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** Two runs that publish the same consumer's site never overlap. The later one waits, and no
run is cancelled, in progress or waiting, short of 100 runs waiting at once.

**Architecture.** The three reusable workflows that publish to a consumer's `gh-pages` branch
(`project-staging.yml`, `project-release.yml` and `project-hotfix.yml`) carry one identical
job-level `concurrency` block, keyed on the consumer. A throwaway probe settles first whether
`queue: max` works at job level inside a called workflow. No POM change and no new action.

## 1. What is true today

- `project-release.yml` (job `release`) and `project-hotfix.yml` (job `hotfix`) each serialise
  against themselves:

  ```yaml
      concurrency:
        group: ${{ github.workflow }}-${{ inputs.git_project }}-release   # -hotfix in project-hotfix.yml
        cancel-in-progress: false
  ```

- `project-staging.yml` (job `staging`) has no `concurrency`. Since `#104` it serves both a
  consumer's RC staging and its snapshot deploy, and both push to the same `gh-pages` branch.
- `project-stage.yml` does not publish to `gh-pages`. It is out of scope.
- Each of the three workflows has a single job, and that job does the `gh-pages` publish.

Five facts about GitHub Actions concurrency shape the design:

1. **Groups are scoped to one repository.** A called workflow runs in its caller's repository, so
   a group declared in `project-staging.yml` while DSH calls it competes only with DSH's runs. The
   repository does the separating. `inputs.git_project` stays in the name because it states the
   intent.
2. **`${{ github.workflow }}` in a called workflow is the caller's workflow name.** The siblings'
   pattern would give DSH's `Staging` and `Deploy Snapshot` separate groups, and they would race.
3. **By default a group holds one pending run.** A newer run cancels the one waiting, even with
   `cancel-in-progress: false`. `queue: max` keeps up to 100 pending runs, served first in, first
   out. It cannot be combined with `cancel-in-progress: true`.
4. **The docs show `queue` only at workflow level.** They do not say whether a job-level
   `concurrency` accepts it. Task 1 settles that.
5. **A job has exactly one group.** Joining release and hotfix to the site group replaces their
   current groups.

## 2. Design

### 2.1 The decision on scope (AC003)

**Per consumer, shared by all three workflows.** The group is `${{ inputs.git_project }}-site`.

- **Per calling workflow was rejected.** It is the siblings' pattern, keyed on `github.workflow`.
  It serialises each caller only against itself, so an RC staging and a snapshot deploy could
  still race. That race is the one `#106` is about.
- **Release and hotfix share the group** because they publish to the same branch. A release is
  the run that can least afford a `gh-pages` race.
- **`queue: max` is the condition for sharing.** Without it, a snapshot deploy dispatched while a
  release waits would cancel the release. Release and hotfix join the group only if task 1 proves
  `queue: max` works at job level (§2.4).
- **A side effect: release and hotfix now serialise against each other too.** Spec 65 noted that
  their separate groups let both clone the development branch. Its push retry stays, because a PR
  merged during a release still races that push, and no group prevents that.

### 2.2 The block

This goes in all three workflows, job level, directly after `permissions:`. In
`project-release.yml` and `project-hotfix.yml` it replaces the existing block.

```yaml
    # #106: one group per consumer, shared by project-staging.yml, project-release.yml and
    # project-hotfix.yml, because all three publish that consumer's site to the same gh-pages
    # branch. Keyed on git_project, not github.workflow: in a called workflow that is the
    # caller's name, so 'Staging' and 'Deploy Snapshot' would get separate groups and race.
    # Never cancel-in-progress: a run cancelled after its artifact deploy leaves a partial
    # deployment. queue: max keeps up to 100 waiting runs, and only a run beyond that is
    # cancelled; by default a newer one would cancel the one pending, and that could be a
    # release. A caller must not use <git_project>-site for a group of its own, at workflow or
    # job level: the called job would wait on its own caller.
    concurrency:
      group: ${{ inputs.git_project }}-site
      cancel-in-progress: false
      queue: max
```

- **AC001.** A second run for the same consumer waits, and with `queue: max` so does a third.
- **AC002.** `cancel-in-progress: false`.
- **`#81` holds.** `inputs.git_project` appears in a `concurrency` expression, not in a `run:`
  body.
- **No deadlock today.** DSH's only workflow-level group is `deploy-snapshot` in `deploy.yml`,
  which is not `dsh-site`.

### 2.3 `CLAUDE.md`

A bullet after the `#104` one:

```markdown
- The three workflows that publish a consumer's site (`project-staging.yml`, `project-release.yml`,
  `project-hotfix.yml`) share one job-level concurrency group, `<git_project>-site` (`#106`), with
  `cancel-in-progress: false` and `queue: max`. Every run that pushes to a consumer's `gh-pages` waits
  for the one before it, and this group cancels none of them while fewer than 100 wait. A caller's own
  group can still drop a run before it gets there, unless it queues too. A caller must not use that
  name for a group of its own, at workflow or job level: the called job would wait on its own caller.
```

### 2.4 The fallback, if task 1 fails

Task 1 fails if `queue` is rejected at job level, or if it is accepted but a pending run is still
cancelled. Then:

- Only `project-staging.yml` gets a group: `${{ inputs.git_project }}-site`,
  `cancel-in-progress: false`, no `queue`. The comment loses its `queue` and "shared by" sentences,
  and says instead that release and hotfix keep their own groups.
- `project-release.yml` and `project-hotfix.yml` are unchanged.
- §7 records the probe's failure. It also records the known gap: a release or hotfix can still
  overlap a staging run on `gh-pages`, and a third staging run cancels the second while it waits.
- A follow-up issue is proposed to the human, not opened.
- `CLAUDE.md`'s bullet describes the staging-only group.

### 2.5 Not in scope

- DSH's `deploy-snapshot` group. It becomes redundant but stays harmless. Removing it is DSH work.
- `project-stage.yml`, which does not publish a site.
- The development-branch push race of spec 65, which keeps its retry.

## 3. Verification

- **Task 1's probe**, on this branch, settles §1 fact 4 and proves the block's behaviour across
  two differently named caller workflows.
- **CI.** `build.yml` on the branch stays green, the `#81` guard included.
- **The real workflows, before the merge (AC001, AC002).** On a throwaway DSH branch, never merged
  and deleted afterwards:
  - `deploy.yml` and `hotfix.yml` point at `@issue-106-site-concurrency-group`.
  - Dispatch `Deploy Snapshot` on that branch, then, while it runs, `Hotfix` with `branch_name: 0.3.x`
    and `dry_run: true`.
  - It passes if the hotfix job waits on group `dsh-site` until the snapshot job ends, then runs,
    and neither run is cancelled.
  - This runs `project-staging.yml` and `project-hotfix.yml` as they are on this branch. A hotfix
    dry run writes nothing (`#72`).
- **`project-release.yml` is not run before the merge.** A release dry run needs an RC branch, and
  DSH has none open. It gets the block that the probe and the hotfix run have proved. Its first
  real run is DSH's 0.4.0 release.

## 4. Files to change

| File | Change |
|---|---|
| `.github/workflows/project-staging.yml` | the block (§2.2), added to job `staging` |
| `.github/workflows/project-release.yml` | the block, replacing job `release`'s group (skipped under §2.4) |
| `.github/workflows/project-hotfix.yml` | the block, replacing job `hotfix`'s group (skipped under §2.4) |
| `CLAUDE.md` | the bullet (§2.3) |
| `.github/workflows/probe-106-*.yml` | created in task 1, deleted in task 2 |

## 5. Tasks

### Task 1: the probe

- [x] **Step 1.** Create `.github/workflows/probe-106-called.yml`. The job sleeps 60 seconds, so the
  other calls have to wait on it.

  ```yaml
  # #106 throwaway probe: does job-level queue: max work in a called workflow? Deleted before the PR.
  name: Probe 106 Called

  on:
    workflow_call:
      inputs:
        git_project:
          type: string
          required: true
        label:
          type: string
          required: true

  jobs:
    hold:
      runs-on: ubuntu-latest
      concurrency:
        group: ${{ inputs.git_project }}-site
        cancel-in-progress: false
        queue: max
      env:
        LABEL: ${{ inputs.label }}
      steps:
        - run: |
            echo "start $LABEL $(date -u +%T)"
            sleep 60
            echo "end $LABEL $(date -u +%T)"
  ```

- [x] **Step 2.** Create two callers with different workflow names, so that `github.workflow`
  differs between them. `probe-106-a.yml`:

  ```yaml
  # #106 throwaway probe. Deleted before the PR.
  name: Probe 106 A

  on:
    push:
      branches: [issue-106-site-concurrency-group]
      paths: ['.github/workflows/probe-106-*.yml']

  jobs:
    a1:
      uses: ./.github/workflows/probe-106-called.yml
      with:
        git_project: probe
        label: a1
    a2:
      uses: ./.github/workflows/probe-106-called.yml
      with:
        git_project: probe
        label: a2
  ```

  `probe-106-b.yml` is identical except `name: Probe 106 B`, with a single job `b1` and
  `label: b1`.

- [x] **Step 3.** Commit (`test(#106): probe job-level queue: max in a called workflow`) and push.
  The single push starts both callers, so three `hold` jobs contend for group `probe-site`.

- [x] **Step 4.** Read the result:

  ```bash
  gh run list -R MRISS-Projects/parent-poms -b issue-106-site-concurrency-group --limit 5 \
    --json databaseId,workflowName,conclusion
  gh run view <id> -R MRISS-Projects/parent-poms --json jobs \
    -q '.jobs[] | [.name, .conclusion, .startedAt, .completedAt] | @tsv'
  ```

  **Pass:**
  - both runs are `success`, with no validation error;
  - the three `hold` jobs' start-to-end windows do not overlap;
  - none is `cancelled`, which means two were pending at once.

  **Fail:** a validation error naming `queue`, or any `hold` job `cancelled`. On a fail, follow §2.4
  from here on.

- [x] **Step 5.** Record the result in §7.1, with run links.

### Task 2: the change

- [x] **Step 1.** Delete the three `probe-106-*.yml` files.
- [x] **Step 2.** Apply §2.2 to the three workflows, or under §2.4 the staging-only variant.
- [x] **Step 3.** Check the result:

  ```bash
  grep -n -A3 'concurrency:' .github/workflows/project-{staging,release,hotfix}.yml
  ```

  Expected: three blocks with `${{ inputs.git_project }}-site`, `cancel-in-progress: false` and
  `queue: max`. Under §2.4: one block, in staging, and the release and hotfix blocks unchanged.
- [x] **Step 4.** Add the `CLAUDE.md` bullet (§2.3).
- [x] **Step 5.** Commit (`ci(#106): one gh-pages concurrency group per consumer`) and push.
  `build.yml` must be green. Record the run in §7.2.

### Task 3: the proof in DSH

- [x] **Step 1.** In DSH, cut a throwaway branch `proof-parent-poms-106` from `DEVELOP`. Point
  `deploy.yml` and `hotfix.yml` at `@issue-106-site-concurrency-group`, commit and push. Under §2.4,
  only `deploy.yml` is changed, and the second dispatch below is another `Deploy Snapshot`.
- [x] **Step 2.** Dispatch both on that branch, the second while the first runs:

  ```bash
  gh workflow run deploy.yml -R MRISS-Projects/dsh --ref proof-parent-poms-106
  gh workflow run hotfix.yml -R MRISS-Projects/dsh --ref proof-parent-poms-106 \
    -f branch_name=0.3.x -f dry_run=true
  ```

- [x] **Step 3.** It passes if the hotfix job's log shows it waiting on `dsh-site`, it starts only
  after the snapshot job ends, and both runs end `success`.
- [x] **Step 4.** Delete the DSH branch. Record the runs in §7.3, and comment them on `dsh#149`.

### Task 4: the PR

- [ ] **Step 1.** Open a PR into `master` that references `#106`, after the human approves its
  content.

## 6. Acceptance criteria

| AC | Covered by |
|---|---|
| AC001: two `project-staging.yml` runs for the same consumer do not overlap; the second waits | §2.2; tasks 1 and 3 |
| AC002: a run in progress is never cancelled | §2.2; tasks 1 and 3 |
| AC003: the scope of the group is an explicit decision, recorded in the spec | §2.1 |

## 7. Verification results

### 7.1 The probe

On 2026-10-03. Two pushes, so the probe was first seen to fail:

- **Red, without `queue`** (`0cf481c2`).
  [Probe 106 A run 37125181065](https://github.com/MRISS-Projects/parent-poms/actions/runs/37125181065)
  ended `cancelled`: `a1 / hold` was cancelled while waiting, with "Canceling since a higher priority
  waiting request for probe-site exists". `b1` and `a2` ran one after the other, so the group already
  spans the two caller names. §1 fact 3 is confirmed: the default drops a pending run.
- **Green, with `queue: max`** (`1109b802`).
  [Probe 106 A run 37125328048](https://github.com/MRISS-Projects/parent-poms/actions/runs/37125328048)
  and [Probe 106 B run 37125328074](https://github.com/MRISS-Projects/parent-poms/actions/runs/37125328074)
  are both `success`, with no validation error. Job-level `queue: max` is accepted in a called
  workflow (§1 fact 4). The three `hold` jobs ran in sequence, none cancelled:

  | Job | Started | Ended |
  |---|---|---|
  | `a2 / hold` | 13:11:16Z | 13:12:19Z |
  | `a1 / hold` | 13:12:21Z | 13:13:24Z |
  | `b1 / hold` | 13:13:26Z | 13:14:28Z |

Task 1 passes, so §2.4's fallback does not apply.

### 7.2 CI

[Build run 37125553093](https://github.com/MRISS-Projects/parent-poms/actions/runs/37125553093), at
`20aedb3a`, is green, with the `#81` guard passing. The three blocks match §2.2 (task 2, step 3).

### 7.3 The proof in DSH

On 2026-10-03, on DSH's throwaway branch `proof-parent-poms-106`, deleted afterwards. `deploy.yml` and
`hotfix.yml` called this branch's `project-staging.yml` and `project-hotfix.yml` at `20aedb3a`.

| Run | Dispatched | Job | Started | Ended | Result |
|---|---|---|---|---|---|
| [Deploy Snapshot 37125567724](https://github.com/MRISS-Projects/dsh/actions/runs/37125567724) | 13:15:38Z | `deploy / staging` | 13:15:47Z | 13:33:21Z | `success` |
| [Hotfix 37125601861](https://github.com/MRISS-Projects/dsh/actions/runs/37125601861), `0.3.x`, dry run | 13:16:12Z | `hotfix / hotfix` | 13:33:23Z | 13:49:16Z | `success` |

- **AC001.** The hotfix job was `pending` for the whole 17 minutes of the snapshot job and started
  two seconds after it ended. Before this change the two workflows shared no group, and the hotfix
  job would have started at once.
- **AC002.** Neither run was cancelled.
- **A deviation from task 3, step 3.** The group's name in the wait message ("waiting for … in
  group `dsh-site`") is shown only on the run page. The REST API reports a waiting job as
  `pending`, with no reason. The timing above is the evidence instead. Task 1 already showed the
  group name in the cancellation message.

### 7.4 Review

- **Local review, before the PR**, on `4dee01a6..26cf9f9f`. No critical or important finding.
  Three minor ones were fixed:
  - Spec 65 still said release and hotfix use different groups (`0d47b723`).
  - The deadlock warning named only a caller's workflow-level group; a job-level one deadlocks
    too (`be0312f9`).
  - `CLAUDE.md` said no run is cancelled, where only this group cancels none; a caller's own
    group still can (`be0312f9`).
- **Copilot, round 1** on [#107](https://github.com/MRISS-Projects/parent-poms/pull/107), at
  `be0312f9`, effort Balanced, requested. One finding in six threads: the three workflow
  comments, `CLAUDE.md`, and the spec's goal and §2.2 promised an unbounded queue. Valid. GitHub
  caps `queue: max` at 100 pending runs and cancels any beyond that, as §1 fact 3 already said.
  Fixed in `f1d88ef1`. The PR description is corrected to match.
