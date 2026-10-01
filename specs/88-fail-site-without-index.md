# Spec: fail site publication when a module's staged site has no `index.html` (`#88`)

| | |
|---|---|
| Issue | [`#88`](https://github.com/MRISS-Projects/parent-poms/issues/88): fail staging/release site publication when a module's staged site has no `index.html` |
| Milestone | `3.10.0-SNAPSHOT` |
| Branch | `issue-88-fail-site-without-index`, cut from `master` at `5fc7d5e9` |
| Origin | `MRISS-Projects/dsh#90`: every DSH module published a site with no `index.html`, 2,600+ files, and no workflow noticed |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** A site whose module has no `index.html` is never pushed to `gh-pages`. The run fails
first, and names the module.

**Architecture.** Today one `mvn site-deploy` generates, stages and pushes, module by module, so
there is no point at which a workflow can look at the result before it is published. The step is
split in three: stage everything without publishing, check the staged tree, then publish once.

**Tech stack.** GitHub Actions, one new composite action with a POSIX `sh` script and its test
suite, and two `maven-scm-publish-plugin` user properties. No POM changes.

## 1. What happens today

All three workflows publish with a single command, `mvn … site-deploy`, plus their own flags. The
log of DSH run 36876508148, a dry-run release, shows what it does, in reactor order:

```text
site:3.21.0:deploy (default-deploy) @ dsh
scm-publish:3.3.0:publish-scm (publish-to-github) @ dsh
site:3.21.0:deploy (default-deploy) @ dsh-test-dataset
scm-publish:3.3.0:publish-scm (publish-to-github) @ dsh-test-dataset
…
```

- **`site:deploy` stages.** It copies the module's `target/site` into
  `/tmp/sites/<release.type>/…`, because every workflow passes
  `-Dsite.deployment.personal.main=file:///tmp/sites`.
- **`publish-scm` pushes, once per module.** The `deployment` profile binds it to the `site-deploy`
  phase with `<content>/tmp/sites</content>`, and every module inherits the binding. So the root
  module pushes before the second module has generated anything. DSH pushes 13 times in a run.

**Consequence for this issue.** A check added inside that Maven run, at any phase, cannot meet
the first acceptance criterion. By the time a late module turns out to have no `index.html`, the
earlier modules are already on `gh-pages`.

## 2. Design

### 2.1 The step becomes three

```yaml
      - name: Stage the site
        run: |
          mvn -B … -Dscmpublish.skipDeploy=true site-deploy

      - name: Verify every staged module site has an index.html
        uses: MRISS-Projects/parent-poms/.github/actions/verify-staged-site@master

      - name: Publish the staged site to gh-pages
        run: |
          mvn -B -N -Ddeployment … scm-publish:publish-scm@publish-to-github
```

1. **Stage.** The existing command, with `-Dscmpublish.skipDeploy=true` added. `site:deploy` still
   fills `/tmp/sites` for every module. `publish-scm` still executes in each module, but skips
   itself. Nothing reaches the remote.
2. **Verify.** The new action checks the staged tree (§2.2). If it fails, the job stops here, with
   nothing pushed.
3. **Publish.** `publish-scm` is an aggregator goal, so it is run once, from the root (`-N`), as
   `scm-publish:publish-scm@publish-to-github`. The `@publish-to-github` suffix makes Maven use the
   profile's own execution configuration (`content`, `scmBranch`, `pubScmUrl`, `serverId`), so
   nothing is restated in the workflow.

What else changes, and what does not:

- **One push instead of one per module.** `gh-pages` gets a single commit per run,
  `Publishing <root project name> site <version>`, where DSH got 13. The published content is the
  same: every module's push already sent the whole of `/tmp/sites` as it stood.
- **No POM change, so no re-pin.** Both properties and the `publish-to-github` execution id exist
  in every released parent. A consumer still pinned to `3.9.2`, as DSH is, gets the check as soon as
  this merges, because the wrappers call `@master`.
- **Rehearsals.** `$RH_SCMPUBLISH_DRYRUN` moves to the publish step. The `site-deploy` marker moves
  with it, so it still announces the one suppressed write.
- **`#81`'s rule holds.** No new `run:` body interpolates an expression.

### 2.2 The check: `verify-staged-site`

A composite action at `.github/actions/verify-staged-site/`, with `verify-staged-site.sh` and
`verify-staged-site.test.sh`. The `Test the action scripts` step in `build.yml` picks the suite up
with no edit.

- **What a module's site is.** A directory under the staged root that holds `project-info.html`.
  parent-poms' own `<reporting>` gives that page to every module. On DSH's published release site
  exactly 13 directories hold it, one per module. It is also the page that kept publishing during
  `dsh#90` while `index.html` was missing.
- **The rule.** Every such directory must also hold `index.html`. The action prints each one that
  does not, as a path relative to the staged root (for example `rcs/products/dsh/dsh-data`), and
  fails.
- **An empty stage is a failure, not a pass.** If the root does not exist, or no directory under it
  holds `project-info.html`, the action fails. Otherwise a run that staged nothing would pass.
- **It checks the staged tree, not `target/site`.** `dsh#90` suspected the loss happened between
  generation and publication. The staged tree is exactly what `publish-scm` pushes.
- **Input.** `path`, default `/tmp/sites`, passed through `env:`.

**Known limit.** A module whose site has no `project-info.html` is not recognised as a module, so
it is not checked. That needs a consumer to remove parent-poms' project-info reports.

### 2.3 Which workflows

| Workflow | Step today | In scope |
|---|---|---|
| `project-staging.yml` | `Deploy Staging Site` | Yes, named by the issue. This is where `dsh#90` happened |
| `project-release.yml` | `Deploy Site to gh-pages` | Yes, named by the issue |
| `project-hotfix.yml` | `Deploy Site to gh-pages` | Yes, named by the issue |
| `deploy.yml` | `Deploy Snapshot Site` | Yes, added by this spec. It is parent-poms' own snapshot site, built the same way. It is also the only one of the four that can prove the real, non-dry-run publish cheaply (§3.3) |

### 2.4 Not in scope

- Moving the `publish-scm` binding out of the `deployment` profile. A consumer running
  `mvn -Ddeployment site-deploy` by hand keeps today's behaviour.
- Checking pages other than `index.html`.

## 3. Verification design

### 3.1 The script's tests

`verify-staged-site.test.sh`, written first and run red against a stub. The cases:

- a tree where every module has `index.html` passes;
- a missing `index.html` in the root module fails, and the output names it;
- a missing one in a nested module (`dsh-doc-analyser/dsh-keyword-extractor`) fails, and names it;
- two modules missing it are both named;
- a report directory without `project-info.html` (`jacoco/`, `apidocs/`) is not treated as a
  module;
- a missing root directory fails, and so does a root with no module site at all.

### 3.2 Dry-run rehearsals from DSH

These follow `#95` and `#81`, with one addition. The new action does not exist at `@master` until
this merges, and `build.yml` forbids pinning an action to a task branch.

- **Scratch branch in parent-poms.** `rehearsal-88` is this branch plus one commit that points the
  three `verify-staged-site@master` references at `@rehearsal-88`. It is never merged.
- **Scratch branches in DSH.** Each has its wrapper pointing at `project-*.yml@rehearsal-88`.
- **Nothing is pushed to DSH while a rehearsal runs.** That is `#81`'s lesson.

| Run | Setup | Expect |
|---|---|---|
| R1, release | DSH `rehearsal-88`, from `DEVELOP` | Green. `Stage the site` shows no push. The check lists 13 module sites. `publish-scm` executes once, at the root, in dry-run. All nine markers appear, and the remote is unchanged |
| R2, release, a module with no index | DSH `rehearsal-88-noindex`: the same, minus `dsh-test-dataset/src/site/markdown/index.md` | Red at the verify step, naming `…/dsh-test-dataset`. The publish step does not run. The remote is unchanged |
| R3, hotfix | DSH `rehearsal-88-hotfix`, from `0.3.x` | Green, as R1 |

**R2's assumption.** Deleting a module's `index.md` is assumed to leave it with no `index.html`.
If Maven still generates one, R2 goes green and proves nothing. The fixture is then changed and
the spec says how.

### 3.3 The real publish

A dry run never pushes, so R1 to R3 do not prove that the new publish step can push. Staging cannot
be rehearsed at all, because `project-staging.yml` has no `dry_run`. The proof is `deploy.yml`:

- **After the merge**, dispatch parent-poms' `deploy.yml` on `master` with
  `release_type: snapshots`. This is the routine snapshot deploy of the light round trip. It
  publishes parent-poms' snapshot site through the same three steps.
- **Pass condition.** The verify step lists parent-poms' module sites, the publish step pushes one
  commit to `gh-pages`, and the snapshot site is reachable.
- **Why after the merge.** Dispatched from the task branch, `deploy.yml` would commit a generated
  `README.md` to the PR branch.

DSH's staging first runs the new steps for real at the 0.4.0 RC.

## 4. Files to change

| File | Change |
|---|---|
| `.github/actions/verify-staged-site/action.yml`, `verify-staged-site.sh`, `verify-staged-site.test.sh` | new (§2.2) |
| `.github/workflows/project-staging.yml`, `project-release.yml`, `project-hotfix.yml`, `deploy.yml` | the three-step split (§2.1) |
| `CLAUDE.md` | the split, in the paragraph of the Profiles section that describes `site-deploy` |

## 5. Tasks

- [x] **Task 1 (red).** Write `verify-staged-site.test.sh` and a stub script that always passes. Run
      the suite, and record which cases fail.
- [x] **Task 2 (green).** Write `verify-staged-site.sh` and `action.yml`, with the script committed
      as mode `100755`. Run the suite until it is green.
- [x] **Task 3.** Split the step in the four workflows (§2.1). The `#81` guard and the rest of
      `build.yml` must stay green.
- [ ] **Task 4.** Create parent-poms `rehearsal-88` and the DSH scratch branches. Run R1.
- [ ] **Task 5.** Run R2, the module with no index.
- [ ] **Task 6.** Run R3, the hotfix path.
- [ ] **Task 7.** Delete every scratch branch, record the runs in §7, and open a PR into `master`
      that references `#88`.
- [ ] **Task 8, after the merge.** Dispatch `deploy.yml` snapshots on `master` (§3.3) and record
      the run on the PR.

## 6. Acceptance criteria

| Criterion (from the issue) | Covered by |
|---|---|
| A run where a module has no `index.html` fails before anything is pushed to `gh-pages`, and names the module | §2.1's order, §2.2, the script's tests, R2 |
| A normal run passes | R1, R3, task 8 |

## 7. Verification results

To be filled in during the build.
