# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`mriss-parent` (`com.mriss:mriss-parent`) is the root Maven parent POM hierarchy shared by all
MRISS-Projects Java/Maven repositories (e.g. `dsh`, `mail-processor-service`). It is packaging-only
(`<packaging>pom</packaging>`) — there is no application code here, just POM inheritance,
plugin/version management, Maven site generation, archetypes, skins, and the CI/CD pipelines that
release downstream products. Changes here affect every consuming repository, often without a
compile-time signal, so profile and plugin-management edits need to be verified against how
downstream products actually invoke Maven (see "Profiles" below).

## Module layout

```
mriss-parent (root pom.xml)
├── infrastructure   → maven-plugins, maven-archetypes (module-standard, product-parent, maven-plugin),
│                      skins (company-skin, product-module-skin, products-skin), announcement-templates
├── framework        → intermediate parent pom for framework-level modules
└── products         → parent pom for product repositories (dsh, etc. inherit from this, not from root)
```

Downstream product repos inherit `products/pom.xml`, which inherits the root `pom.xml`. Site/PDF/release
profiles are layered across these three levels plus the product's own `pom.xml` — see "Profiles" below
before changing behavior at any single level.

## Common commands

```bash
# Full reactor build (compile + unit tests, install to local repo)
mvn -B -U clean install

# Run a single test class in a specific module
mvn -pl <module-path> -Dtest=SomeTest test

# Unit tests plus integration tests (naming convention: *IT.java or *IntegrationTest.java)
mvn -B clean install -DintegrationTests
# Without the flag, failsafe does not execute at all: it is declared in <pluginManagement> and
# only the integration-tests profile (FR015) promotes it into the build. Surefire excludes
# *IT/*IntegrationTest either way, so a test named that way runs only under the flag.

# Generate the Maven site locally without publishing (mirrors the Build workflow)
mvn -B -Ddeployment -Drelease-deployment \
  -Dsite.deployment.personal.main=file:///tmp/sites site
```

`-Dcommit.readme.phase=none` used to be required on any local build that activated the
`deployment` profile, to stop it committing — and pushing — `README.md`. **It is no longer needed.**
`#71` moved the commit out of the Maven lifecycle, so no build commits anything. The property still
exists but is inert, kept only for consumers that still pass it.

There is no separate lint step; `maven-compiler-plugin` (Java 17 source/target) and `maven-surefire-plugin`
are the only gates run on a plain `mvn install`.

**PowerMock is forbidden** here and in every inheriting project, in any scope, directly or transitively:
the root `pom.xml`'s `ban-powermock` enforcer execution fails `validate`, and it has no skip property —
not even `-Denforcer.skip=true` disarms it. Mockito is the sanctioned mocking tool, `mockStatic` included.

Integration tests never count toward the 95% `jacoco:check` gate. The `integration-tests`
profile attaches a second JaCoCo agent writing `target/jacoco-it.exec`, and `jacoco:check` reads
`target/jacoco.exec`. This is load-bearing: `maven-failsafe-plugin` defaults its `argLine` to
`${argLine}`, the property `jacoco:prepare-agent` writes, so without the second agent the
integration run appends straight into the file the gate measures. `project-staging.yml` passes
`-DintegrationTests`, so staging is where integration tests are mandatory; what a product's
integration tests *start* is that product's decision, not this repository's.

## Profiles (the core mechanism in this repo)

Profiles are activated by **`-D<name>` property flags, not `-P`** (deliberate — see FR004/FR005 notes in
`pom.xml` and `products/pom.xml`: `-P` with multi-module inheritance caused profile-merge bugs). When
adding or editing a profile, follow the existing convention and never reintroduce `-P`.

| Profile | Activated by | Defined at | Purpose |
|---|---|---|---|
| `deployment` | `-Ddeployment` | root `pom.xml` | Timestamped build version, `clean-site-temporary-folder`, `maven-scm-publish-plugin` site-deploy to `gh-pages` |
| `readme-generation` | `-Ddeployment` **and** `src/site/markdown/README.md` present | root `pom.xml` | `generate-list-of-issues`, `create-time-stamp`, `copy-readme-md` — README.md **regeneration only**. Inherited by every consuming project, and active only in the module that actually holds a README source. It commits nothing: since `#71` the commit is a workflow step (`.github/actions/commit-readme`), because report mojos that fork the lifecycle to `compile`/`test-compile` replayed `process-resources` and committed up to four times per invocation |
| `release-deployment` | `-Drelease-deployment` | root `pom.xml` | Sets `release.type=releases` (site goes to `releases/` instead of `snapshots/` on gh-pages); binds `attach-descriptor` |
| `product-release-deployment` | `-Dproduct-release-deployment` | `products/pom.xml` | `maven-changes-plugin:github-text-list` (closed-milestone issue list), copies `src/site` → `target/generated-site` for PDF, patches the PDF's fluido skin version, generates + attaches `README.pdf` |

Two Maven lifecycles are involved and are **not interchangeable**:
- `mvn ... site-deploy` → site lifecycle: renders the site and pushes it to `gh-pages`. It **does**
  reach `copy-readme-md` in practice, contrary to what this section used to claim: `maven-jxr-plugin`
  and `maven-javadoc-plugin` each contribute `aggregate` and `test-aggregate` reports whose mojos
  declare `executePhase` `compile`/`test-compile`, so the site build forks the default lifecycle four
  times and replays `process-resources` with it. That is the whole cause of `#71`.
  **The workflows no longer let it push.** Run by hand, `site-deploy` pushes once per module, the
  root first, because the `deployment` profile binds `publish-scm` to every module's `site-deploy`
  phase. Since `#88` the four workflows split it in three: `site-deploy` with
  `-Dscmpublish.skipDeploy=true` stages every module under `/tmp/sites` and pushes nothing;
  `.github/actions/verify-staged-site` fails the run if a module's staged site has no `index.html`;
  then `mvn -N -Ddeployment scm-publish:publish-scm@publish-to-github` publishes once, from the
  root. Do not fold the three back into one command: there is then no point at which the staged
  site can be checked before it is public.
- `mvn ... process-resources` → default lifecycle: regenerates root `README.md`. It does **not** commit
  it (since `#71`) and does **not** publish the site.
- Committing the regenerated `README.md` is a **workflow** step, not a Maven one:
  `.github/actions/commit-readme`, called by `project-staging.yml`, `project-release.yml`,
  `project-hotfix.yml` and `deploy.yml`. It must be pinned `@master` in the reusable workflows — a
  relative `./` path resolves against the *caller's* workspace and fails — and `build.yml` enforces
  that pin.

**A consumer's "Products" parent link is a redirect page, on purpose (`#89`).** `maven-site-plugin`
builds `<menu ref="parent"/>` from the relative path between the parent's and the child's
`distributionManagement` site URLs, not from `<url>`. A child's is always its parent's plus its
artifactId, so a consumer's root site always links "Products" to `../index.html`, while `products`
itself is published in this repository's Pages. The link cannot be changed from here.
`products/pom.xml`'s `link-parent-products-site` execution (profile `deployment`, phase `post-site`)
therefore writes a one-page redirect at that address, pointing at
`${parent.poms.site.url}/releases/products/`. It acts only in a module whose parent is `products`.
Do not "fix" the relative link in a consumer's `site.xml`, and do not expect a `products/` directory
in a consumer's staged site to be a real site: it holds that one page.

`release:perform` only runs `deploy` (per the release plugin's `<goals>`), so a real release requires
both an explicit `site-deploy` **and** an explicit `process-resources` invocation afterward — see
`specs/github-actions-reusable-workflows.md` §3 for the full rationale if you touch release automation.
The two run in different trees. `process-resources` runs against the post-release `master` checkout
in `target/checkout`. `site-deploy` runs in the workspace, detached at the release tag, because that
is where the test output is (`#95`). A release runs its tests **once**: `release:prepare`'s forked
`clean install`, unit and integration tests, before any write. `products/pom.xml`'s
`release.forked.test.arguments` defaults to `-DintegrationTests` for that fork, and the workflows
override it with `-DskipTests` for `release:perform`, which builds the same tag. Do not add a test run
back to perform or the site step. The reports would be no better, and the release slower.

`generatedSiteDirectory` in `products/pom.xml`'s deployment profile is deliberately redirected to
`target/generated-site-reports` (not the default `target/generated-site`) because
`copy-site-resources-for-pdf` copies `src/site` into `target/generated-site` for the PDF plugin, and
`maven-site-plugin` auto-scanning that same path causes a "file clashes with existing" failure. Keep
these two paths distinct if you touch PDF or site generation in `products/pom.xml`.

## CI/CD

GitHub Actions is the current CI, migrated from the `Project*Jenkinsfile` files (which are being phased
out — see `specs/github-actions-reusable-workflows.md` for the full Jenkins→Actions migration spec,
including exact reusable-workflow inputs/secrets and a Jenkinsfile-to-step mapping):

- `.github/workflows/build.yml` — runs on every push; mirrors `ReleaseJenkinsfile` build steps but with
  publishing disabled (`install`/`site` instead of `deploy`/`site-deploy`). It also runs the README
  placeholder guard's tests and checks that the `commit-readme` action is pinned `@master`.
- `.github/workflows/deploy.yml` — manual (`workflow_dispatch`), `release_type` input of `snapshots` or
  `releases`. Snapshot path deploys artifacts + site (tolerating 409 Conflict as non-fatal). Release path
  computes the next version, recursively deploys every module (skipping independently-released children:
  `skins`, `announcement-templates`, `maven-archetypes`, `maven-plugins`), then commits and tags.
- `ProjectStageJenkinsfile` / `ProjectStagingJenkinsfile` / `ProjectReleaseJenkinsfile` /
  `ProjectHotfixJenkinsfile` / `ReleaseJenkinsfile` — legacy Jenkins pipelines for the stage → staging →
  release/hotfix flow used by downstream product repos; being replaced by reusable
  `project-stage.yml` / `project-staging.yml` / `project-release.yml` / `project-hotfix.yml` workflows
  called from each product repo via `uses: MRISS-Projects/parent-poms/.github/workflows/<name>.yml@ref`.
- `project-staging.yml` is also a consumer's **snapshot deploy** (`#104`). Its `release_type` input
  defaults to `rcs`, a release candidate: the site under `rcs/`, the build number `RC<n>`. With
  `snapshots` it deploys a development branch: the site under `snapshots/`, a plain `<n>`. The
  consumer needs only a wrapper that passes it (DSH's `deploy.yml`). `deploy.yml` here does the same
  job for this repository, but it is dispatched, not reusable. The workflow has no dry run in either
  mode.

Required secret: `DEPLOY_TOKEN` (a cross-repo PAT — the default `GITHUB_TOKEN` cannot read/write
`MRISS-Projects/maven-repo`, which is a separate repository from this one). JDK 17 (Temurin) +
Maven 3.9.16 (pinned via `stCarolas/setup-maven@v5`, installed after `setup-java`, and asserted by a
`Verify Maven version` step) are standard across all workflows.

## Versioning

Root `pom.xml` version and `README.md`'s "Version" section are kept in sync by the `readme-generation`
profile's `copy-readme-md` execution filtering `src/site/markdown/README.md` with
`${project.version}` / `${project.build.version}`. Don't hand-edit the root `README.md` directly — edit
`src/site/markdown/README.md` instead, since the root file is regenerated and overwritten by CI.
