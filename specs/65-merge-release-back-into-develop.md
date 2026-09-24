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
   Then set the SCM tag to `DEV_SCM_TAG`. **The mechanism for this is Task 1's to measure.**
   The candidate is `versions:set-scm-tag -DnewTag="$DEV_SCM_TAG"`. The fallback, if it is
   aggregator-only like `versions:set`, is a guarded edit of the root POM's single `<scm><tag>`
   element that fails if it matches anything other than exactly one line.
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
- **Carried-over assertion** (on success). For every path the release changed relative to the
  merge base, excluding `pom.xml` files, the merged content must equal the tag's content unless
  the development branch changed that path too. Any violation is an error naming the path.
  A plain merge should never trip this. It is here so that a future `-X` fails a release
  instead of costing one, which is the positive-assertion rule `#69` set.
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
| `.github/workflows/project-release.yml` | `development_branch` input, preflight step, new last step, marker declared |
| `.github/workflows/project-hotfix.yml` | the same |
| `specs/github-actions-reusable-workflows.md` | document the input, the step and the failure mode |

The action's inputs are `tag`, `development_branch`, `git_project` and `token`. It also reads
`dry_run` so it can pass it through to the marker. Inputs reach its scripts through `env:`.

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

- [ ] In a clone of `dsh` at `staging-0.3.0-SNAPSHOT-RC`, apply `pom.xml.tag`-equivalent release
      versions (`0.3.0`, SCM tag `v0.3.0`) as a local commit.
- [ ] Run `mvn -B "-Dbuild.NEXT_DEVELOPMENT_VERSION=0.4.0-SNAPSHOT" release:update-versions`.
      Record how many POMs changed, and whether `<scm><tag>` changed.
- [ ] Run `mvn -B versions:set-scm-tag -DnewTag=HEAD`. Record which POMs it wrote. Repeat with
      `-DnewTag=zz-not-a-default`, a value no default would produce.
- [ ] Merge the result into `DEVELOP` plainly. Record the conflict count, which must be 0.
- [ ] Write the measured mechanism into §3.2, replacing "Task 1's to measure", and record the
      results here.

### Task 2: `merge-into-develop.sh`, tests first

- [ ] Write `merge-into-develop.test.sh` with these scratch-repo cases:
  - `rc_fix_survives`: RC-only change to a non-POM file, present after the merge
  - `dev_change_survives`: development-only change to a non-POM file, still present
  - `real_conflict_fails`: same line edited on both sides. Exit 1, path in the output,
    development branch ref unchanged, no merge in progress
  - `lost_change_detected`: a merged state produced with `-X ours` over a conflicting RC fix is
    fed to the assertion alone. It must fail and name the path. This is the regression the
    assertion exists for.
  - `poms_excluded`: a POM that differs from the tag after the merge is not reported
  - `evidence_line`: the count printed equals the number of non-POM paths the release changed
- [ ] Run it. It must be red.
- [ ] Implement `merge-into-develop.sh` until green. Run `sh -n` and `shellcheck` if available.

### Task 3: the composite action

- [ ] `action.yml`: clone, read `DEV_VERSION` and `DEV_SCM_TAG`, fetch the tag, align (Task 1
      mechanism), `verify-reactor-version`, commit, `merge-into-develop.sh`,
      `verify-reactor-version`, marker, push. All inputs go through `env:`.
- [ ] The executable bit on the scripts (`build.yml` checks it).

### Task 4: the workflows

- [ ] Both workflows: `development_branch` input, preflight after `Configure Git`, and the
      new last step before `Rehearsal verify`.
- [ ] Add `merge-to-develop` to both `declared_markers` lists, and replace the comment that
      anticipated it.
- [ ] Hand-check that, in a real release, every pre-existing command expands byte for byte as
      before (`#72` §8 method).

### Task 5: docs

- [ ] `specs/github-actions-reusable-workflows.md`: the input, the preflight, the step, and the
      manual recovery when the merge-back conflicts.

### Task 6: rehearsals

- [ ] Open the DSH twin issue and branch, and pass `development_branch: DEVELOP` in both wrappers.
- [ ] Run §5 items 3, 4 and 5. Record the run URLs and the evidence lines here.
- [ ] Comment on `#65` with the evidence, and state that `dsh` `0.3.0` is the confirming run.

---

## 7. Acceptance criteria

The issue's five criteria, corrected where §2 showed them wrong:

- [ ] **AC001:** `project-release.yml` merges the release tag into the development branch after
      its `master` merge. The development branch keeps its own version on every module, which
      `verify-reactor-version` asserts.
- [ ] **AC002:** `project-hotfix.yml` does the same.
- [ ] **AC003:** non-version changes from the RC or hotfix branch are on the development branch
      afterwards, which the carried-over assertion checks. A conflicting change **fails the run**
      rather than being resolved by picking a side.
- [ ] **AC004:** the branch is named by a `development_branch` input on both workflows, with the
      same name and default as `project-stage.yml`. A missing branch fails before the release
      starts.
- [ ] **AC005:** validated against `dsh`, whose RC branch carries 152 RC-only commits, by §5's
      rehearsals. The conflict path is proven by §5.5. `dsh` `0.3.0` confirms it.
- [ ] **AC006:** `merge-to-develop` is a declared rehearsal marker in both workflows, and every
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
