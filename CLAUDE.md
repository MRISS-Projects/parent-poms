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

# Integration tests only (naming convention: *IT.java or *IntegrationTest.java)
mvn -B verify
# (unit tests via surefire exclude *IT/*IntegrationTest; failsafe runs only those, bound to integration-test+verify)

# Generate the Maven site locally without publishing (mirrors the Build workflow)
mvn -B -Ddeployment -Drelease-deployment -Dcommit.readme.phase=none \
  -Dsite.deployment.personal.main=file:///tmp/sites site

# Suppress the README.md SCM commit during local/CI builds that activate the deployment profile
mvn ... -Dcommit.readme.phase=none ...
```

There is no separate lint step; `maven-compiler-plugin` (Java 17 source/target) and `maven-surefire-plugin`
are the only gates run on a plain `mvn install`.

## Profiles (the core mechanism in this repo)

Profiles are activated by **`-D<name>` property flags, not `-P`** (deliberate — see FR004/FR005 notes in
`pom.xml` and `products/pom.xml`: `-P` with multi-module inheritance caused profile-merge bugs). When
adding or editing a profile, follow the existing convention and never reintroduce `-P`.

| Profile | Activated by | Defined at | Purpose |
|---|---|---|---|
| `deployment` | `-Ddeployment` | root `pom.xml` | Timestamped build version, `clean-site-temporary-folder`, `maven-scm-publish-plugin` site-deploy to `gh-pages`, `copy-readme-md` + `commit-readme-md` (README.md regeneration/commit) |
| `release-deployment` | `-Drelease-deployment` | root `pom.xml` | Sets `release.type=releases` (site goes to `releases/` instead of `snapshots/` on gh-pages); binds `attach-descriptor` |
| `product-release-deployment` | `-Dproduct-release-deployment` | `products/pom.xml` | `maven-changes-plugin:github-text-list` (closed-milestone issue list), copies `src/site` → `target/generated-site` for PDF, patches the PDF's fluido skin version, generates + attaches `README.pdf` |
| `update-readme` | `-Dupdate-readme` | product-specific (e.g. `dsh/pom.xml`) | Lightweight README-only refresh, independent of the full `deployment` flow |

Two Maven lifecycles are involved and are **not interchangeable**:
- `mvn ... site-deploy` → site lifecycle: renders the site and pushes it to `gh-pages`. Does **not** run
  the `copy-readme-md`/`commit-readme-md` executions (those are bound to `process-resources` in the
  default lifecycle).
- `mvn ... process-resources` → default lifecycle: regenerates and commits root `README.md`. Does **not**
  publish the site.

`release:perform` only runs `deploy` (per the release plugin's `<goals>`), so a real release requires
both an explicit `site-deploy` **and** an explicit `process-resources` invocation afterward against the
post-release `master` checkout — see `specs/github-actions-reusable-workflows.md` §3 for the full
rationale if you touch release automation.

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
  publishing disabled (`install`/`site` instead of `deploy`/`site-deploy`, `-Dcommit.readme.phase=none`).
- `.github/workflows/deploy.yml` — manual (`workflow_dispatch`), `release_type` input of `snapshots` or
  `releases`. Snapshot path deploys artifacts + site (tolerating 409 Conflict as non-fatal). Release path
  computes the next version, recursively deploys every module (skipping independently-released children:
  `skins`, `announcement-templates`, `maven-archetypes`, `maven-plugins`), then commits and tags.
- `ProjectStageJenkinsfile` / `ProjectStagingJenkinsfile` / `ProjectReleaseJenkinsfile` /
  `ProjectHotfixJenkinsfile` / `ReleaseJenkinsfile` — legacy Jenkins pipelines for the stage → staging →
  release/hotfix flow used by downstream product repos; being replaced by reusable
  `project-stage.yml` / `project-staging.yml` / `project-release.yml` / `project-hotfix.yml` workflows
  called from each product repo via `uses: MRISS-Projects/parent-poms/.github/workflows/<name>.yml@ref`.

Required secret: `DEPLOY_TOKEN` (a cross-repo PAT — the default `GITHUB_TOKEN` cannot read/write
`MRISS-Projects/maven-repo`, which is a separate repository from this one). JDK 17 (Temurin) +
Maven 3.9.9 (pinned via `stCarolas/setup-maven@v5`, installed after `setup-java`) are standard across
all workflows.

## Versioning

Root `pom.xml` version and `README.md`'s "Version" section are kept in sync by the `deployment` profile's
`copy-readme-md`/`commit-readme-md` executions filtering `src/site/markdown/README.md` with
`${project.version}` / `${project.build.version}`. Don't hand-edit the root `README.md` directly — edit
`src/site/markdown/README.md` instead, since the root file is regenerated and overwritten by CI.
