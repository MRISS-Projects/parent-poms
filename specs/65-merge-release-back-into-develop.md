# Spec: merge every release back into the development branch (`#65`)

| | |
|---|---|
| Issue | [`#65`](https://github.com/MRISS-Projects/parent-poms/issues/65) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-65-merge-release-back-into-develop`, cut from `master` at `aa8a8916` |
| Blocks | `MRISS-Projects/dsh` `0.3.0`: 152 commits exist only on `staging-0.3.0-SNAPSHOT-RC` |
| Validated by | `dry_run` rehearsals of `dsh`'s `release.yml` and `hotfix.yml`, built by `#72` |
| Confirmed by | `dsh`'s real `0.3.0` release (accepted decision, DSH PRD §6) |

> **For agentic workers:** implement this task by task. Steps use checkbox (`- [ ]`) syntax.
> Task 1 is a **measurement**, not an implementation step, and the mechanism in §3.2 depends on
> its result. Do not build §3.2 before Task 1 has been run and its result recorded here. The one
> piece of new logic that can be unit-tested, the merge-and-assert script, is tested first,
> against scratch git repositories.

**Goal.** When `project-release.yml` or `project-hotfix.yml` finishes a release, the release tag
is merged into the consumer's development branch. Every change made on the RC or hotfix branch
reaches that branch, and the development branch keeps its own version. A merge that cannot
guarantee both fails, names the files, and pushes nothing.

**Architecture.** A new composite action, `merge-to-develop`, becomes the last write point of
both workflows. It does not resolve version conflicts during the merge. It removes them
beforehand: it builds a throwaway *alignment commit* on top of the tag that sets the reactor to
the development branch's own version and SCM tag. Then it merges that commit with a **plain**
merge, with no `-X` strategy option. The only conflicts a plain merge can still hit are real
ones, and those stop the run. Two positive assertions follow, in real releases and rehearsals
alike. Every module must carry the development version (reusing `verify-reactor-version` from
`#69`). Every non-POM path the release changed must arrive intact, unless the development branch
changed it too.

**Tech stack.** GitHub Actions composite actions, POSIX `sh`, `git`, and `maven-release-plugin`
3.1.1 (via `${release.plugin.version}`). CI pins Maven 3.9.9. The simulation in §1.2 is git only,
run against the real `MRISS-Projects/dsh` branches on 2026-09-24.

---

## Global constraints

- Profiles are activated by `-D<name>`, never `-P`. **Never reintroduce `-P`.**
- **`<configuration>` beats the user property.** Before using any `-D` for a release-plugin
  parameter, check `pom.xml`'s release-plugin `<configuration>` (see `#69` spec, Global
  constraints). `-Dbuild.NEXT_DEVELOPMENT_VERSION` works because it is a POM interpolation
  variable, not a parameter's user property.
- **No `-X ours` and no `-X theirs` in this merge.** See §2.2. Resolving a conflict by picking a
  side is exactly the silent data loss this issue exists to prevent.
- **Dispatch inputs never reach a `run:` body through `${{ }}`.** They go through `env:`, as
  `#69`'s review round established (PR `#80`). The existing steps that still interpolate are
  `#81`'s problem, on `3.10.0-SNAPSHOT`, and are not touched here.
- Every new remote write carries a rehearsal marker and is declared in `declared_markers`. The
  new id is `merge-to-develop`, the name `assert-markers.sh` and its test already anticipate.
- In a real release every `RH_*` variable expands exactly as it did before, as `#72` requires.
  The new step uses `$RH_TAG_SOURCE` and `$RH_GIT_PUSH_DRYRUN` in the same way the
  `Merge Release Tag to Master` step does.

---

## 1. The defect

### 1.1 Nothing carries a release back

Both workflows merge the release tag into `master` and stop. The development branch only ever
receives `project-stage.yml`'s next-version bump. Every fix made on the RC branch during
stabilisation stays on the RC branch, and `project-release.yml` then **deletes** that branch
(`Remove RC Branch`). After that, the fixes live only in the tag and on `master`.

This is no longer hypothetical. On 2026-09-24:

```text
$ git rev-list --left-right --count origin/DEVELOP...origin/staging-0.3.0-SNAPSHOT-RC
1       152
```

The one `DEVELOP`-only commit is `60c759cc7 [maven-release-plugin][skip] prepare for next
development iteration`, which touches the version of 13 POMs and nothing else. The 152 RC-only
commits are the whole of DSH Wave 0 so far. Releasing `0.3.0` through today's workflow would put
them on `master` and never on `DEVELOP`.

### 1.2 A plain merge conflicts on every POM, and only there

Simulated in a scratch clone of `dsh`. The `v0.3.0` tag was faked as the RC branch plus one
commit taking every `0.3.0-SNAPSHOT` in the 13 POMs to `0.3.0`, which is what `release:prepare`
writes. It was then merged into `DEVELOP` with `git merge --no-commit v0.3.0`:

- **13 conflicts, all `pom.xml`.** Each is the module's own `<version>`: `0.4.0-SNAPSHOT` on
  `DEVELOP` against `0.3.0` on the tag.
- **The root POM also conflicts on `<scm><tag>`.** `DEVELOP` has `HEAD`, the tag has the RC's.
  A real `release:prepare` writes `v0.3.0` there, so the conflict is real, and it is not a
  version. Anything that resolves only `<version>` elements leaves it unresolved.
- **No conflict outside a POM.** The RC's other changes, including its re-pin of the parent to
  `3.9.0-SNAPSHOT`, merged cleanly.

The same fake tag was then **aligned** first: every module version set to `0.4.0-SNAPSHOT` and
the SCM tag set to `HEAD`, committed on a branch off the tag, then merged plainly into `DEVELOP`:

```text
conflicts:                                             0
files changed vs DEVELOP:                              96
non-POM paths differing from the tag:                  0
diff tag..merged:     13 files changed, 14 insertions(+), 14 deletions(-)   (versions only)
```

That is the design in §3, shown to work on the real branches before any code is written. The
sed stand-in for alignment is exactly what Task 1 replaces with Maven, and measures.

---

## 2. What the issue proposed, and why this spec departs from it

The issue proposes `git merge -s recursive -X ours --no-commit`, followed by
`mvn -DprocessAllModules=true -DnewVersion=<dev> versions:set` as a "safety net". Both halves
are wrong, for different reasons.

### 2.1 The safety net is the command `#69` proved broken

`versions:set -DprocessAllModules=true` writes the root POM and nothing else. It was measured at
1 of 13 on this exact reactor (`dsh` run 35662168807), which is why `#69` replaced it with
`release:update-versions`. Used here, it would leave 12 modules on whatever the merge produced.
And because `-X ours` already took `DEVELOP`'s side, the safety net would look like it worked.

### 2.2 `-X ours` resolves every conflict, not just the version conflicts

`-X ours` is a strategy option for the whole merge. Any conflicting hunk in **any file** goes to
the development branch's side. If a real fix on the RC branch touches lines that the development
branch also changed, the fix is discarded, the merge succeeds, and nothing reports it. That breaks
the issue's own third acceptance criterion: non-version changes must survive.

§1.2 shows this does not happen on DSH today, because no non-POM file conflicts. It stays a
design hazard anyway: the day it matters, it fails silently. `#69`'s lesson applies: a mechanism
that looks right because this reactor happens not to trigger its failure is not validated.

### 2.3 `development_branch` does not exist where the issue says it does

The issue's fourth criterion says to reuse the `development_branch` input "added in `#55`". It
exists only on `project-stage.yml` (default `DEVELOPMENT`; DSH's `stage.yml` passes `DEVELOP`).
`project-release.yml` and `project-hotfix.yml` have no such input. This spec adds it to both,
with the same name, meaning and default. That is the only sense in which the input can be
"reused".

---

## 3. The remedy

### 3.1 A new input and a preflight

Both workflows gain:

```yaml
      development_branch:
        type: string
        required: false
        default: 'DEVELOPMENT'
        description: 'Branch every release is merged back into, e.g. DEVELOP or DEVELOPMENT'
```

The default matches `project-stage.yml`, so one consumer names its branch the same way for all
three workflows. It is optional rather than required. A required input would make every
unchanged caller fail to parse, and that includes rehearsals. With an optional input, the
workflow can fail with a message that says what to do.

A **preflight** step runs straight after `Configure Git`, before `release:prepare` pushes
anything:

```sh
# DEVELOPMENT_BRANCH arrives through env:, never interpolated.
if ! git ls-remote --exit-code --heads origin "$DEVELOPMENT_BRANCH" > /dev/null; then
  echo "::error::development branch '$DEVELOPMENT_BRANCH' does not exist on the remote." \
       "Pass development_branch from the calling workflow (dsh: DEVELOP)."
  exit 1
fi
```

The step reads the remote and writes nothing, so it runs the same way in both modes. Without it,
a consumer that forgets the input finds out at the very end, after the tag, the deploy, the
`master` merge and the site are all done. With it, the consumer finds out in the first minute.

### 3.2 Alignment: remove the conflicts instead of resolving them

Inside the new action, working in a fresh clone of the development branch:

1. **Read the development branch's identity.** Its reactor version (`DEV_VERSION`, via
   `mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N`) and its root
   `<scm><tag>` (`DEV_SCM_TAG`, via `project.scm.tag`).
2. **Build the alignment commit.** Fetch the tag from `$RH_TAG_SOURCE`, check out a detached
   branch `merge-back/v<version>` at it, and set it to `DEV_VERSION` using `#69`'s proven
   mechanism:
   `mvn -B "-Dbuild.NEXT_DEVELOPMENT_VERSION=$DEV_VERSION" release:update-versions`.
   Then set the SCM tag to `DEV_SCM_TAG` with
   `mvn -B -N versions:set-scm-tag "-DnewTag=$DEV_SCM_TAG"`. Task 1 measured both goals (see
   its results): `release:update-versions` does not touch `<scm><tag>`, and
   `versions:set-scm-tag` writes the root POM only, like `versions:set`. That is enough here,
   because `<scm>` is declared once, in the root, and inherited from there. A consumer module
   that declares its own `<scm><tag>` would keep the tag's value, conflict, and **fail the
   merge loudly** (§3.3). That is the safe direction, so the spec accepts it rather than
   editing POMs by hand. `-N` states the root-only scope instead of leaving it to the goal.
3. **Assert the alignment** with `verify-reactor-version`, `expected-version: $DEV_VERSION`, and
   commit it as `[maven-release-plugin] align v<version> to <DEV_VERSION> for merge-back`.
   This commit exists only as a merge input. The tag does not move.

The value comes from the **development branch**, never from `next_development_version`. The two
normally agree, which is exactly why Task 6 rehearses with them set apart.

### 3.3 The merge, and what makes it fail

`merge-into-develop.sh <tag> <aligned-ref>`, run in the development-branch clone:

- `git merge --no-ff --no-edit -m "[maven-release-plugin] merge release <tag> into <branch>"
  <aligned-ref>`. **No `-s`, no `-X`.**
- **On conflict:** `git merge --abort`. List the conflicted paths as `::error::` lines. Say that
  the release itself is complete and only the merge-back remains, and name the tag to merge by
  hand. Exit 1.
- **Carried-over assertion** (on success), `assert-carried-over.sh`. It makes two checks:
  1. **The merged tree is the clean plain merge.**
     `git merge-tree --write-tree <branch-before> <aligned-ref>` must exit 0, with no
     conflicts, and the tree it prints must equal `HEAD^{tree}`. A `-X ours` or `-X theirs`
     resolution only ever differs from a plain merge where there was a conflict, and
     `merge-tree` reports exactly those. So any side-picking, in any file, fails this.
     *Correction made while building:* the first version of this check, as the spec was
     approved, compared paths one by one and **skipped paths the development branch had also
     changed**. Those are the only paths `-X ours` can lose hunks in, so it could never have
     caught the defect it was written for. This came to light while writing the
     `lost_change_detected` test, before any code existed: its fixture has to be a conflict,
     and a conflict means both sides changed the path.
  2. **Alignment touched nothing but POMs.** Outside files named `pom.xml`, the aligned commit
     must be identical to the tag: `git diff --name-only <tag> <aligned-ref>`, with every
     `pom.xml` excluded, must print nothing. Check 1 takes the aligned commit as its input, so
     it cannot see an alignment step that rewrote a non-POM file. This check can. Together, the
     two checks say that HEAD is exactly the plain merge of the development branch and the
     release, with only POMs changed in between.

  A violation is an error naming the paths, and the merge commit is reset away, so the
  development-branch clone ends where it started. A plain merge of a correct alignment never
  trips either check. They are here so that a future `-X`, or a Maven goal that writes more
  than versions, fails a release instead of costing one. That is the positive-assertion rule
  `#69` set.
- Print the evidence line:
  `merge-to-develop: carried <n> path(s) from <tag> into <branch>; 0 lost`.

Then `verify-reactor-version` runs on the merged clone with `DEV_VERSION`, before the push.

### 3.4 Where it sits: last

The merge-back is the **last write point** in both workflows: after `Remove RC Branch` in
`project-release.yml`, and after `Commit generated README.md on Master` in `project-hotfix.yml`.
It sits before `Rehearsal verify`, which stays `if: always()`.

If the merge-back is last and it fails, the release is complete, and only a merge that a human
can finish from the tag is missing. If it came earlier, a conflict would leave a release with no
site, no README commit, and a live RC branch. Deleting the RC branch first loses nothing: the tag
holds its content, and the next-development commit that `release:prepare` puts on the RC branch
changes only versions, which alignment recomputes from the development branch anyway.

Push: marker `merge-to-develop` ("push the merge of `<tag>` into `<branch>`"), then
`git push $RH_GIT_PUSH_DRYRUN "$REPO_URL" "$DEVELOPMENT_BRANCH"`. `merge-to-develop` is added to
`declared_markers` in both workflows. `rehearsal-verify` already snapshots every head, so
`assert-no-writes.sh` covers the development branch staying untouched with no change.

### 3.5 Hotfix specifics

`project-hotfix.yml` runs the same action. After `0.3.0` merges back, the merge base of `v0.3.1`
and `DEVELOP` is the `v0.3.0` tag commit. Alignment takes `v0.3.1`'s `0.3.1` to `DEVELOP`'s
version, and the hotfix's real changes merge plainly. `--allow-unrelated-histories` is **not**
carried over from that workflow's `master` merge. A hotfix tag with no history in common with
the development branch is a situation for a human, and the merge should say so.

---

## 4. The changes, file by file

| File | Change |
|---|---|
| `.github/actions/merge-to-develop/action.yml` | **new**: §3.2 to §3.4 as composite steps |
| `.github/actions/merge-to-develop/merge-into-develop.sh` | **new**: §3.3, POSIX `sh`, git only |
| `.github/actions/merge-to-develop/merge-into-develop.test.sh` | **new**: scratch-repo tests, picked up by `build.yml`'s `*.test.sh` glob with no edit |
| `.github/actions/merge-to-develop/assert-carried-over.sh` | **new**: §3.3's two checks, called by `merge-into-develop.sh` and testable alone |
| `.github/actions/merge-to-develop/assert-carried-over.test.sh` | **new**: includes `lost_change_detected` |
| `.github/workflows/project-release.yml` | `development_branch` input, preflight step, new last step, marker declared |
| `.github/workflows/project-hotfix.yml` | the same |
| `specs/github-actions-reusable-workflows.md` | document the input, the step and the failure mode |

The action's inputs are `tag`, `development_branch`, `git_project` and `token`. They reach its
scripts through `env:`. *Changed while building:* the action has **no `dry_run` input**. It reads
the `RH_TAG_SOURCE` and `RH_GIT_PUSH_DRYRUN` that `rehearsal-setup` already exported to the job,
as the workflow's own `Merge Release Tag to Master` step does, so the run has one rehearsal
switch rather than one per action. It fails if `RH_TAG_SOURCE` is unset, which can only mean
`rehearsal-setup` did not run.

**Consumer follow-up, not in this PR.** `dsh`'s `release.yml` and `hotfix.yml` must pass
`development_branch: DEVELOP`. Order matters. Passing an input the called workflow does not
declare is a hard error, so the DSH change cannot land first. Once this merges, the preflight
fails DSH's wrappers until they pass the input, and it fails them loudly, in the first minute.
The DSH change is two one-line edits under a DSH issue opened for it, twinned with this one, as
with `#57`/`dsh#85`.

---

## 5. Validating it

1. **Unit:** `merge-into-develop.test.sh`, red then green (Task 2).
2. **Measurement:** Task 1, on the real `dsh` reactor, locally.
3. **Release rehearsal:** `dsh` `release.yml` with `dry_run: true`, dispatched against
   `staging-0.3.0-SNAPSHOT-RC` from a DSH branch that passes `development_branch: DEVELOP`. Use
   **`next_development_version: 0.9.9-SNAPSHOT`**, a value nothing would choose on its own. The
   merged `DEVELOP` must still be at **`0.4.0-SNAPSHOT`**. That proves alignment reads the
   branch and not the input. Required log evidence:
   - `merge-to-develop: carried <n> path(s) … 0 lost`, with `n` in the order of §1.2's 96
   - the `verify-reactor-version` summary at `0.4.0-SNAPSHOT`, 13 of 13, for both the alignment
     and the merge
   - the `merge-to-develop` marker exactly once, `rehearsal-verify` green, and no remote change
4. **Hotfix rehearsal:** `dsh` `hotfix.yml`, `dry_run: true`, against a scratch branch
   `rehearsal-65-hotfix` cut from the RC at a `0.3.1-SNAPSHOT` version (the `#72` Task 10
   method). It has the same evidence requirements.
5. **Conflict rehearsal:** the property that matters most is that a real conflict **stops** the
   run. Push a commit to a scratch RC branch that edits one line of a non-POM file, and push a
   commit editing the same line to a scratch *development* branch. Dispatch the release rehearsal
   with `development_branch` set to the scratch one. The step must fail, name that file, and push
   nothing. The scratch branches are deleted afterwards and recorded here.
6. **Confirmation:** `dsh`'s real `0.3.0` release (DSH PRD §6). Anything it finds is fixed from
   the hotfix line.

---

## 6. Tasks

### Task 1: measure the alignment mechanism (no code)

- [x] In a clone of `dsh` at `staging-0.3.0-SNAPSHOT-RC`, apply `pom.xml.tag`-equivalent release
      versions (`0.3.0`, SCM tag `v0.3.0`) as a local commit.
- [x] Run `mvn -B "-Dbuild.NEXT_DEVELOPMENT_VERSION=0.4.0-SNAPSHOT" release:update-versions`.
      Record how many POMs changed, and whether `<scm><tag>` changed.
- [x] Run `mvn -B versions:set-scm-tag -DnewTag=HEAD`. Record which POMs it wrote. Repeat with
      `-DnewTag=zz-not-a-default`, a value no default would produce.
- [x] Merge the result into `DEVELOP` plainly. Record the conflict count, which must be 0.
- [x] Write the measured mechanism into §3.2, replacing "Task 1's to measure", and record the
      results here.

**Results, 2026-09-24.** Maven 3.9.9, JDK 17, `maven-release-plugin` 3.1.1 and
`versions-maven-plugin` 2.18.0, both managed by this repository's `pom.xml`. `dsh` was at
`origin/staging-0.3.0-SNAPSHOT-RC` and `origin/DEVELOP` as of that morning.

| Measurement | Result |
|---|---|
| `release:update-versions` at `0.4.0-SNAPSHOT` on the fake tag | 13 of 13 POMs, one `<version>` line each. `<scm><tag>` untouched (`v0.3.0`) |
| `versions:set-scm-tag -DnewTag=zz-not-a-default` | Reactor stopped at `[1/13]`. Root `pom.xml` only, one line (`:277`). The unrelated `<tag>` at `:905` untouched |
| `versions:set-scm-tag -DnewTag=HEAD`, then `git merge --no-ff` into `DEVELOP` | Exit 0, **0 conflicts** |
| Merged result against `DEVELOP` | 96 files changed |
| Merged result against the tag | 13 files, 14 lines: 13 `<version>`s and the one `<scm><tag>`. Non-POM paths differing: **0** |
| Every POM of the merged result | `0.4.0-SNAPSHOT`, 13 of 13 |

`generateBackupPoms` is already `false` in the managed `versions-maven-plugin` configuration, so
the goal leaves no `pom.xml.versionsBackup` to be swept into a commit.

### Task 2: the scripts, tests first

Both suites build their scratch repositories with a shared, sourced `test-fixture.sh`: a base
commit, a `DEVELOP` branch with only the next-version bump, an `rc` branch, a release tag, and an
aligned `merge-back/<tag>` branch. This mirrors §1.2 at the scale of two POMs and two text files.

- [x] Write `assert-carried-over.test.sh`:
  - a clean plain merge passes and prints the evidence line
  - `lost_change_detected`: a conflicting RC fix merged with `-X ours` fails and names the
    path. This is the regression the assertion exists for.
  - the same with `-X theirs`
  - a merge commit edited after the fact (tree differs from the plain merge) fails
  - an aligned commit that also rewrote a non-POM file fails and names it
  - a deletion on the release is counted and passes
  - misuse prints usage and exits 1
- [x] Write `merge-into-develop.test.sh`:
  - `rc_fix_survives`, `dev_change_survives`, and edits to different lines of one file both
    survive
  - `real_conflict_fails`: exit 1, the path and the tag are named, the branch ref is unchanged,
    no merge is in progress, and the working tree is clean
  - the merge is a two-parent commit with the §3.3 message, and the POMs carry the development
    version and SCM tag
  - `evidence_line`: the count equals the number of non-POM paths the release changed
  - run on the wrong branch, or with the wrong arguments, it exits 1
- [x] Run both. They must be red.
- [x] Implement both scripts until green. Run `sh -n` and `shellcheck`.

### Task 3: the composite action

- [x] `action.yml`: clone, read `DEV_VERSION` and `DEV_SCM_TAG`, fetch the tag, align (Task 1
      mechanism), `verify-reactor-version`, commit, `merge-into-develop.sh`,
      `verify-reactor-version`, marker, push. All inputs go through `env:`.
- [x] The executable bit on the scripts (`build.yml` checks it).

### Task 4: the workflows

- [x] Both workflows: `development_branch` input, preflight after `Configure Git`, and the
      new last step before `Rehearsal verify`.
- [x] Add `merge-to-develop` to both `declared_markers` lists, and replace the comment that
      anticipated it.
- [x] Hand-check that, in a real release, every pre-existing command expands byte for byte as
      before (`#72` §8 method).

### Task 5: docs

- [x] `specs/github-actions-reusable-workflows.md`: the input, the preflight, the step, and the
      manual recovery when the merge-back conflicts.

### Task 6: rehearsals

- [x] Open the DSH twin issue ([`dsh#117`](https://github.com/MRISS-Projects/dsh/issues/117)). The wrapper change is its work, after this merges.
- [x] Run §5 items 3, 4 and 5. Record the run URLs and the evidence lines here.
- [ ] Comment on `#65` with the evidence, and state that `dsh` `0.3.0` is the confirming run.

**Results, 2026-09-24.** These runs used #72's final-round method. A throwaway parent-poms branch,
`rehearsal-65`, was cut from the PR head at `cc675702` and differed from it only in the two
`merge-to-develop@` refs. The DSH scratch branches were: `rehearsal-65` (the wrappers pointed at
it, passing `development_branch`), `rehearsal-65-hotfix` (cut from the RC with all 13 POMs at
`0.3.1-SNAPSHOT`), `rehearsal-65-conflict-rc` (the RC plus an edit to line 1 of
`connect-mongo.bat`), and `rehearsal-65-conflict-dev` (`DEVELOP` plus a different edit to the
same line). Every scratch branch was deleted afterwards. DSH's `ls-remote --heads` and `--tags`
are identical to the listings taken before the first push.

| §5 | Run | Result |
|---|---|---|
| 3: release, `next_development_version: 0.9.9-SNAPSHOT` | [`dsh` 35997012261](https://github.com/MRISS-Projects/dsh/actions/runs/35997012261) | **green**. `DEVELOP is at 0.4.0-SNAPSHOT`: the value came from the branch, not the input. 13 of 13 at `0.4.0-SNAPSHOT` after alignment and again after the merge. `carried 94 path(s) from v0.3.0 into DEVELOP; 0 lost`. All 9 declared write points announced exactly once. Heads 17, tags 12 and packages 267 all unchanged |
| 4: hotfix, `rehearsal-65-hotfix` | [`dsh` 35997055587](https://github.com/MRISS-Projects/dsh/actions/runs/35997055587) | **green**. `carried 94 path(s) from v0.3.1 into DEVELOP; 0 lost`. 13 of 13 at `0.4.0-SNAPSHOT` both times. All 6 declared write points. Remote unchanged |
| 5: conflict | [`dsh` 35997059122](https://github.com/MRISS-Projects/dsh/actions/runs/35997059122) | **red, as required.** It failed in `Merge Release Tag to Development Branch` with `merging v0.3.0 into rehearsal-65-conflict-dev conflicts, so nothing was pushed. The release itself is complete…` and listed `connect-mongo.bat`. Heads, tags and packages unchanged, and the RC branch still present. `assert-markers` also reported `merge-to-develop` missing. That is correct and wanted: the step stopped before its push, so the write point never happened |

The 94 matches the local simulation exactly: 94 non-POM paths changed between the branch point
and the tag. §1.2's 96 is a different count, every path of the merged result that differs from
`DEVELOP`, which is 93 non-POM paths and 3 POMs. The gap of one is a path the release changed that
`DEVELOP` already held in the same state.

**AC004's negative path**, dispatched afterwards from a scratch DSH branch,
`rehearsal-65-preflight`, passing `development_branch: does-not-exist-65`.
[`dsh` 36004008611](https://github.com/MRISS-Projects/dsh/actions/runs/36004008611) failed at
`Check the development branch exists`, the step straight after `Configure Git`, with
`development branch 'does-not-exist-65' does not exist on the remote. Pass development_branch
from the calling workflow (dsh: DEVELOP).` Nothing after it ran: no `Validate version` and no
`release:prepare`. Heads, tags and packages were unchanged. `assert-markers` reported no markers
at all, which is correct, since no write point was reached.

One lesson, recorded so it is not repeated. The first attempt,
[`dsh` 36003903318](https://github.com/MRISS-Projects/dsh/actions/runs/36003903318), pointed the
DSH wrapper at the PR branch directly, reasoning that the preflight runs before `merge-to-develop`
is ever reached. It died in `Set up job`, with `Can't find 'action.yml' … merge-to-develop@master`.
**The runner downloads every action a job references before its first step**, so an action that
exists only on an unmerged branch breaks the whole job, whether or not the job would ever reach it.
The flipped `rehearsal-65` branch is not optional for any rehearsal of this workflow before merge.
That run wrote nothing either. DSH's refs were identical before and after both runs, and every
scratch branch is deleted.

The twin is [`dsh#117`](https://github.com/MRISS-Projects/dsh/issues/117). It can only merge
after this PR does.

---

## 7. Acceptance criteria

The issue's five criteria, corrected where §2 showed them wrong:

- [x] **AC001:** `project-release.yml` merges the release tag into the development branch after
      its `master` merge. The development branch keeps its own version on every module, which
      `verify-reactor-version` asserts.
- [x] **AC002:** `project-hotfix.yml` does the same.
- [x] **AC003:** non-version changes from the RC or hotfix branch are on the development branch
      afterwards, which the carried-over assertion checks. A conflicting change **fails the run**
      rather than being resolved by picking a side.
- [x] **AC004:** the branch is named by a `development_branch` input on both workflows, with the
      same name and default as `project-stage.yml`. A missing branch fails before the release
      starts.
- [ ] **AC005:** validated against `dsh`, whose RC branch carries 152 RC-only commits, by §5's
      rehearsals. The conflict path is proven by §5.5. `dsh` `0.3.0` confirms it.
- [x] **AC006:** `merge-to-develop` is a declared rehearsal marker in both workflows, and every
      rehearsal in §5 proves the remote unchanged.

---

## 8. Out of scope

- **Merging a hotfix into an RC branch that is open at the same time.** A fix on `0.3.x` while
  `staging-0.4.0-SNAPSHOT-RC` is open reaches `DEVELOP` but not that RC branch. That is real, and
  it is a separate decision about release-line topology.
- **The other `${{ }}`-in-`run:` interpolations:** `#81`.
- **Merging `master`'s generated README commit into the development branch.** The development
  branch's README is regenerated by its own staging runs.
- **Automatic conflict resolution of any kind.**
