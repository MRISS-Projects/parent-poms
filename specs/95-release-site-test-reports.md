# Spec: build the release site from the release's own single test run (`#95`, `#96`)

| | |
|---|---|
| Issues | [`#95`](https://github.com/MRISS-Projects/parent-poms/issues/95) (empty test and coverage reports), [`#96`](https://github.com/MRISS-Projects/parent-poms/issues/96) (no coverage badge) |
| Milestone | `3.9.2-SNAPSHOT`, a hotfix line. `master` re-versioned to it in `d5a80948` |
| Branch | `issue-95-release-site-test-reports`, cut from `master` at `d5a80948` |
| Consuming issue | `MRISS-Projects/dsh#146`, which proves this fix and ships it as DSH 0.3.1. Spec: `dsh/specs/stories/146-release-0-3-1-with-site-reports.md` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** A release and a hotfix release publish a site whose surefire, failsafe, per-module JaCoCo
and aggregate reports carry real results, together with the coverage badge. The tests, integration
tests included, run **once** per release, before the release writes anything.

**Architecture.** `release:prepare`'s forked `clean install` becomes the release's only test run,
with the integration tests added. `release:perform`'s forked `deploy` stops re-running the tests.
`Deploy Site to gh-pages` builds from the workspace checked out at the release tag, where prepare's
fork left its test output, instead of from a fresh `master` clone that has none.

**Tech stack.** GitHub Actions reusable workflows, and maven-release-plugin configuration in
`products/pom.xml`. The proof is by rehearsal from DSH.

**Constraint, from review on 2026-09-29: releases stay as short as possible, and no test run is
repeated.** An earlier draft ran the tests again in a new step before the site, and ran the
integration tests in both prepare and perform. Both were rejected.

## 1. The defect

Full evidence in `#95` and `#96`, and the design input in
[`#95`'s comment of 2026-09-29](https://github.com/MRISS-Projects/parent-poms/issues/95#issuecomment-5897003659).

Today a release runs the unit tests twice and uses neither run for the site:

- **`release:prepare`**'s `clean install` (`<preparationGoals>`, root `pom.xml:373`). It runs in the
  workspace.
- **`release:perform`**'s `deploy` (`<goals>`, root `pom.xml:374`). It runs in `target/checkout`, on
  the same sources, and that output is deleted by `rm -rf target/checkout` in `Merge Release Tag to
  Master` (`project-release.yml:354`, `project-hotfix.yml:229`), which clones `master` in its place.

`Deploy Site to gh-pages` (`project-release.yml:376`, `project-hotfix.yml:248`) then runs `site-deploy`
in that fresh clone. The site lifecycle runs no tests, so:

- surefire `report-only` finds no results, and the root `surefire.html` reports 0 tests;
- `jacoco:report` finds no `jacoco.exec` in any of the 13 modules. DSH's red rehearsal logs `Skipping
  JaCoCo execution due to missing execution data file` 13 times;
- `report-aggregate` runs without data and reports 0%;
- DSH's badge (`dsh-coverage-report`, bound to `verify` under `-Ddeployment`, DSH `#104`) is never
  written in the published tree, which is `#96`.

No release path passes `-DintegrationTests` either, so there is no failsafe report and no
`jacoco-it.exec`. `project-staging.yml` passes it (`:174-182`), and runs `site-deploy` (`:211-216`) in
the workspace its `clean deploy` just built. That is why staging's site is complete.

## 2. Design

### 2.1 One test run: prepare's fork, with the integration tests

`products/pom.xml` gains a property and uses it in the release plugin's `<arguments>` (line 125):

```xml
<!-- #95: what the release plugin's forked builds do about tests. release:prepare's fork
     keeps this default and is the release's only test run, integration tests included,
     before anything is committed or tagged. release:perform overrides it with -DskipTests,
     because it builds the same sources prepare has just tested. -->
<release.forked.test.arguments>-DintegrationTests</release.forked.test.arguments>
```

```xml
<arguments>-Ddeployment -Drelease-deployment -Dproduct-release-deployment ${release.forked.test.arguments} -Dsite.deployment.personal.main=${site.deployment.personal.main}</arguments>
```

Both workflows' `Maven Release Perform` step adds `-Drelease.forked.test.arguments=-DskipTests` to its
`release:perform`.

- **Why a property and not `-Darguments`.** `<arguments>` is configured in the POM, and explicit
  configuration beats a parameter's user property, so `-Darguments=…` on the command line is inert.
  A property the configuration *interpolates* is resolved from the invocation's `-D` values. This is
  the `build.NEXT_DEVELOPMENT_VERSION` mechanism `#69` already relies on (`project-release.yml`,
  `Checkout Hotfix Branch and Set Initial Version`).
- **Why perform gets `-DskipTests` *instead of* `-DintegrationTests`, rather than alongside it.**
  `-DintegrationTests` activates the integration-test profile, and DSH's `dsh-rest-api` starts
  MongoDB and RabbitMQ in Docker under it. With the two combined, perform would start both
  containers only to skip the tests that use them. Replacing the value keeps perform to compile,
  package and deploy.
- **Why skipping perform's tests is safe.** Perform builds the tag, and the tag is exactly the tree
  prepare's fork built and tested: `run-preparation-goals` runs after `rewrite-poms-for-release` and
  before `scm-commit-release`. The rehearsal bridge has made the same argument since `#72`
  (`.github/actions/rehearsal-tag/action.yml`, "`-DskipTests` is a deliberate, stated deviation").
  `-DskipTests` also disarms the coverage-data guard along with the tests, which is that flag's
  documented behaviour.
- **Before the first write.** A failing unit or integration test stops `release:prepare` before it
  commits, tags or pushes. Today a hotfix line's integration tests never run at all: it does not pass
  through staging.
- **Products only.** The root `pom.xml:370` `<arguments>` stays as it is. The infrastructure poms are
  released by `deploy.yml`, not through these forked builds.
- **This is the POM half of the fix.** It is why DSH pins `0.3.x` to `3.9.2-SNAPSHOT` and then `3.9.2`
  (`dsh#146` §4.1), rather than relying on `@master` alone.

**Net effect on a release:** it loses the second unit-test run (perform's) and gains one
integration-test run, inside prepare.

### 2.2 The site is built where the tests ran

`Deploy Site to gh-pages`, in both workflows, stops using `target/checkout` and builds in the
workspace, checked out at the release tag:

```yaml
      # #95/#96: build the site where release:prepare's fork ran the tests: this workspace.
      # target/checkout is a fresh master clone with no test output, which is what published
      # empty reports and no badge. Checking the tag out moves only tracked files; every
      # target/ is ignored and keeps prepare's surefire/failsafe results, jacoco*.exec and
      # the badge. The tag is local in both modes: prepare created it, or, in a rehearsal,
      # the tag bridge did.
      - name: Deploy Site to gh-pages
        run: |
          git checkout --quiet --detach "v${{ inputs.current_version }}"
          bash "$RUNNER_TEMP/rehearsal-marker.sh" site-deploy \
            "publish the generated site to gh-pages"
          mvn -B $RH_SCMPUBLISH_DRYRUN \
            -Dsite.deployment.personal.main="${{ inputs.site_deployment_url }}" \
            -Ddeployment \
            -Drelease-deployment \
            site-deploy
```

`project-hotfix.yml` is the same, with `"v${HOTFIX_RELEASE_NUMBER}"` as the tag.

- **What the output describes.** In a real release, prepare's fork built the release-version tree,
  which is exactly the tag's content. In a rehearsal, dry-run prepare builds the same sources at the
  `-SNAPSHOT` version (`rehearsal-tag/action.yml`), so the classes, and with them the JaCoCo data, are
  the same. The site then renders with the tag's POMs, so it carries the release version in both
  modes.
- **A separate invocation after the build is the proven shape.** It is what `project-staging.yml` does:
  `clean deploy`, then `site-deploy` in the same tree, with the badge and the reports intact. Report
  mojos that fork to `compile`/`test-compile` (`#71`) find the classes up to date, and nothing in the
  site lifecycle runs tests: the red rehearsal's site step has no `Tests run:` line.
- **Why check out the tag at all.** After a real prepare, the workspace is on the *next development*
  version, and a site built there would be versioned wrongly. The detached checkout changes only
  tracked files, and every `target/` is ignored (DSH: `.gitignore:8`, `**/target/`), including
  `target/checkout`, which is a nested clone. Nothing between prepare and the site step touches the
  workspace's tracked files. Every step in between starts with `cd target/checkout`, and the rehearsal
  bridge builds its tag under a temporary `GIT_INDEX_FILE` (`build-release-tag.sh:71-96`). So the
  checkout cannot hit a dirty tree.
- **`README.md` is unchanged.** It is still generated and committed from the `master` clone in
  `target/checkout`, by the two steps that follow. Only the site moves.

### 2.3 Not in scope

- `-Dproduct-release-deployment` on the site step (README.pdf and release notes). Unchanged.
- `project-staging.yml`, `project-stage.yml` and `deploy.yml`.
- The dry-run `- delete` listing that scm-publish prints under `site-deploy` in a rehearsal. It is
  reporting only (see `#95`'s comment). No change.
- Rehearsal markers. No write point is added or removed, so `declared_markers` is unchanged.

## 3. Files to change

| File | Change |
|---|---|
| `products/pom.xml` | §2.1: the `release.forked.test.arguments` property, and its use in `<arguments>` (line 125) |
| `.github/workflows/project-release.yml` | `Maven Release Perform` passes `-Drelease.forked.test.arguments=-DskipTests`. `Deploy Site to gh-pages` (line 376) builds in the workspace at the tag (§2.2) |
| `.github/workflows/project-hotfix.yml` | the same two changes, at `Maven Release Perform` and at `Deploy Site to gh-pages` (line 248) |
| `.github/actions/rehearsal-tag/action.yml` | its `-DskipTests` comment no longer describes a deviation from `deploy`, which now skips the tests too. Reword it to match |
| `CLAUDE.md` | the paragraph at line 96 on `release:perform` running only `deploy`: prepare's fork is the only test run, and the site is built from the workspace at the tag |
| `specs/github-actions-reusable-workflows.md` | §3, which that paragraph points to, and §6.3/§6.4, the release and hotfix step lists |

## 4. Tasks

- [x] **Task 1 — `products/pom.xml`.** §2.1. Check the interpolation with `help:effective-pom` on
      `products`, run twice and logged to `.logs/mvn-help-effective-pom.log`. Without `-D`,
      `<arguments>` must contain `-DintegrationTests`. With
      `-Drelease.forked.test.arguments=-DskipTests`, it must contain `-DskipTests` and not
      `-DintegrationTests`. Run `mvn -B clean install`, logged to `.logs/mvn-clean-install.log`, and
      report its exit code. Commit.
      Done 2026-09-29. The effective `<build><plugins>` release `<arguments>`: by default
      `-Ddeployment -Drelease-deployment -Dproduct-release-deployment -DintegrationTests -Dsite.deployment.personal.main=file:///tmp/sites`.
      With the override, the same with `-DskipTests` in place of `-DintegrationTests`. The root's
      `pluginManagement` entry, which `products` overrides, is unchanged. `mvn -B clean install`
      exited 0, with all 15 modules `SUCCESS`.
- [ ] **Task 2 — `project-hotfix.yml`.** Both changes. Commit.
- [ ] **Task 3 — `project-release.yml`.** Both changes. Commit.
- [ ] **Task 4 — comments and documentation.** §3's `rehearsal-tag`, `CLAUDE.md` and
      `specs/github-actions-reusable-workflows.md` rows. Commit.
- [ ] **Task 5 — PR into `master`.** `build.yml` goes green. Once the PR is merged, the workflow half
      reaches every consumer at `@master`. The POM half reaches only a consumer pinned to
      `3.9.2-SNAPSHOT` or later.
- [ ] **Task 6 — snapshot deploy.** Dispatch `deploy.yml` with `release_type: snapshots` on `master`.
      `com.mriss.mriss-parent:products:3.9.2-SNAPSHOT` is then in GitHub Packages, which is `dsh#146`'s
      step P3.
- [ ] **Task 7 — hotfix proof.** Covered by `dsh#146`'s T3, a DSH `hotfix.yml` dry run on its task
      branch, pinned to `3.9.2-SNAPSHOT`. Read it against §5 and record the run here.
- [ ] **Task 8 — release proof.** In DSH, create scratch branch `rehearsal-95` from `DEVELOP`
      (`0.4.0-SNAPSHOT`) and pin its parent to `3.9.2-SNAPSHOT`, in one commit that is never merged.
      Dispatch DSH `release.yml` with `--ref rehearsal-95`, `branch_name=rehearsal-95`,
      `current_version=0.4.0`, `next_development_version=0.5.0-SNAPSHOT`, `hotfix_branch=0.4.x`,
      `initial_hotfix_version=0.4.1-SNAPSHOT` and `dry_run=true`. Read it against §5, record the run
      here, then delete `rehearsal-95` from the remote. `#69` set the precedent for a scratch branch.
- [ ] **Task 9 — release 3.9.2**, per `dsh#146` §4.3: revise `#95` AC004 and `#96` AC003, close both
      on Tasks 7 and 8, rename the milestone to `3.9.2`, then dispatch `deploy.yml` with
      `release_type: releases`. Expect tag `mriss-parent-3.9.2`, and `master` at `3.10.0-SNAPSHOT`.

A dry-run `release:perform` builds nothing, so Tasks 7 and 8 cannot show perform's `-DskipTests`.
Task 1's effective-pom check is its evidence, and the real 3.9.2-based DSH 0.3.1 release
(`dsh#146` T7) is its confirming run.

## 5. Verification

A rehearsal proves the fix when its log shows all of the following. The job log labels every step
`UNKNOWN STEP`, so delimit steps by their `##[group]Run` lines and `REHEARSAL <point>:` markers, as
`dsh#146` §7.4 did.

In `Maven Release`, the forked `clean install`:

1. surefire `Tests run:` summaries with a non-zero total. For DSH that is 127, the red run's count.
2. `maven-failsafe-plugin:…:integration-test` executing, with a non-zero `Tests run:` total.
3. For DSH, `jacoco-badge-maven-plugin` executing in `dsh-coverage-report`.

In `Deploy Site to gh-pages`:

1. The detached checkout of `v<version>` succeeding.
2. No surefire or failsafe test execution, so the site did not re-run the tests.
3. No `Skipping JaCoCo execution due to missing execution data file`. The red run has 13.
4. `report-aggregate` loading execution data.

And overall: `rehearsal-verify` announcing every declared write point exactly once, with the remote
byte-for-byte unchanged.

Task 7's log is compared with DSH's red run 36614968935, which shows none of the site-step items 3-4
and no failsafe in prepare.

## 6. Acceptance criteria

From the issues:

- [ ] **`#95` AC001** — the release site is generated from a tree in which the unit and integration
      tests of the released code have run, for both workflows. Tasks 7 and 8.
- [ ] **`#95` AC002** — `project-hotfix.yml` is fixed. Task 2, proven by Task 7.
- [ ] **`#95` AC003** — a rehearsal of each workflow still announces every write point exactly once.
      Tasks 7 and 8.
- [ ] **`#95` AC004** — revised at Task 9: proven by Task 7's rehearsal, with the confirming release
      tracked in `dsh#146` AC004.
- [ ] **`#96` AC001** — a release publishes `<coverage-module>/badges/jacoco.svg`, for both workflows.
      Tasks 7 and 8.
- [ ] **`#96` AC002** — the badge is computed from the release's own test run, prepare's fork, and is
      not copied from staging. §2.1 and §2.2.
- [ ] **`#96` AC003** — revised at Task 9: the confirming release is tracked in `dsh#146` AC005.

Added by this spec:

- [ ] **AC-X1** — a release runs its tests once: unit and integration tests in prepare's fork before
      any write, none in perform, none in the site. Tasks 1, 7 and 8.
- [ ] **AC-X2** — `build.yml` is green on the PR.
