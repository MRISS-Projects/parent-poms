# GitHub Actions Reusable Workflows — Analysis & Specification

**GitHub Issue:** [#55 — Convert jenkins files for every stage of deployment](https://github.com/MRISS-Projects/parent-poms/issues/55)  
**Date:** 2026-06-06  
**Status:** Draft — Analysis Complete, Ready for Implementation

---

## Table of Contents

1. [Overview](#1-overview)
2. [Codebase Analysis](#2-codebase-analysis)
   - 2.1 [Jenkinsfile Inventory](#21-jenkinsfile-inventory)
   - 2.2 [Maven Profile Hierarchy](#22-maven-profile-hierarchy)
   - 2.3 [DSH Module Structure](#23-dsh-module-structure)
   - 2.4 [mail-processor-service Reference Profile Flow](#24-mail-processor-service-reference-profile-flow)
3. [The `process-resources` Question — Lines 158–162](#3-the-process-resources-question--lines-158162)
4. [GCP Decoupling Strategy](#4-gcp-decoupling-strategy)
5. [Secrets & Tooling Standards](#5-secrets--tooling-standards)
6. [Reusable Workflow Specifications](#6-reusable-workflow-specifications)
   - 6.1 [project-stage.yml](#61-project-stageyml)
   - 6.2 [project-staging.yml](#62-project-stagingyml)
   - 6.3 [project-release.yml](#63-project-releaseyml)
   - 6.4 [project-hotfix.yml](#64-project-hotfixyml)
7. [Caller Workflow Examples for DSH](#7-caller-workflow-examples-for-dsh)
8. [Maven Settings Template](#8-maven-settings-template)
9. [Version Calculation Shell Reference](#9-version-calculation-shell-reference)
10. [Acceptance Criteria Mapping](#10-acceptance-criteria-mapping)
11. [Implementation Notes](#11-implementation-notes)

---

## 1. Overview

This document specifies four reusable GitHub Actions workflows that replace the four
`Project*Jenkinsfile` pipeline templates hosted in `parent-poms`. The new workflows must be:

- Consumed by any MRISS-Projects repository via `uses: MRISS-Projects/parent-poms/.github/workflows/<name>.yml@<ref>`
- Functionally equivalent to their Jenkinsfile counterparts
- **Compatible with DSH immediately**, even though DSH is not attached to Google Cloud Platform
- Reusable by `mail-processor-service` in the future (GCP-attached) with minimal caller-side additions

---

## 2. Codebase Analysis

### 2.1 Jenkinsfile Inventory

| File | Maps to workflow | Trigger style |
|------|-----------------|---------------|
| `ProjectStageJenkinsfile` | `project-stage.yml` | Manual (parameters) |
| `ProjectStagingJenkinsfile` | `project-staging.yml` | Manual (branch name) |
| `ProjectReleaseJenkinsfile` | `project-release.yml` | Manual (many params + user confirmation dialog) |
| `ProjectHotfixJenkinsfile` | `project-hotfix.yml` | Manual (branch name, fully automatic) |
| `ReleaseJenkinsfile` | `deploy.yml` (already implemented) | Out of scope |

### 2.2 Maven Profile Hierarchy

The profile chain for a product project like DSH is:

```
parent-poms/pom.xml  (mriss-parent)
  └─ products/pom.xml
       └─ dsh/pom.xml
```

#### Profile: `deployment` (activated by `-Ddeployment`)

| Level | What it adds |
|-------|-------------|
| `parent-poms/pom.xml` | `project.scm.id=github`; `project.build.version` with timestamp; `clean-site-temporary-folder` (cleans `/tmp/sites`); `maven-scm-publish-plugin` → `site-deploy` phase pushing `/tmp/sites` → `gh-pages`; `copy-readme-md` (copies `src/site/markdown/README.md` → root `README.md` with filtering); `commit-readme-md` (`scm:checkin` of README.md) |
| `products/pom.xml` | Profile removed at this level (FR001 — inherited from root, no duplication) |
| `dsh/pom.xml` | `maven-pdf-plugin` → `prepare-package` (generates PDF from `generated-site`); `build-helper-maven-plugin` → `package` (attaches `README.pdf` as artifact) |

Key: `maven-scm-publish-plugin` is bound only to the `site-deploy` phase. Running `mvn deploy` (the default `release:perform` goal) does NOT trigger site publication — the site publication is a separate explicit invocation.

#### Profile: `release-deployment` (activated by `-Drelease-deployment`)

| Level | What it adds |
|-------|-------------|
| `parent-poms/pom.xml` | Sets `release.type=releases` → causes `distributionManagement/site/url` to resolve to `.../releases/` instead of `.../snapshots/`; `maven-site-plugin` → `attach-descriptor` at `install` |

This profile must be combined with `deployment` whenever publishing the release site to ensure it goes to the `releases/` path on gh-pages.

#### Profile: `product-release-deployment` (activated by `-Dproduct-release-deployment`)

| Level | What it adds |
|-------|-------------|
| `products/pom.xml` | `maven-changes-plugin` → `github-text-list` at `generate-sources` (fetches closed milestone issues); `copy-site-resources-for-pdf` (copies `src/site` → `generated-site`); `fix-pdf-skin-version` antrun (patches `generated-site/site.xml` fluido skin from 2.0.0 → 1.12.0 for PDF compatibility); `maven-pdf-plugin` → `prepare-package`; `build-helper-maven-plugin` → `attach-readme` |
| `dsh/pom.xml` | `maven-pdf-plugin` → `prepare-package` (uses `generated-site` as siteDirectory — DSH-specific path) |

This profile is activated during `release:perform` via the `<arguments>` in `products/pom.xml`:
```xml
<arguments>-Ddeployment -Drelease-deployment -Dproduct-release-deployment -Dsite.deployment.personal.main=${site.deployment.personal.main}</arguments>
```

#### Profile: `update-readme` (activated by `-Dupdate-readme`) — DSH-specific

Present only in `dsh/pom.xml`. Runs `maven-changes-plugin:github-text-list`, `copy-readme-md`, and `commit-readme-md`. This is a DSH-specific alternative to the `deployment`-profile README flow, intended for situations where only the README needs refreshing.

### 2.3 DSH Module Structure

```
dsh (root pom, packaging=pom)
├── dsh-test-dataset
├── dsh-data
├── dsh-rest-api
├── dsh-solr
├── dsh-doc-indexer-worker
├── dsh-doc-analyser
│   ├── dsh-keyword-extractor
│   ├── dsh-top-sentences-extractor
│   └── dsh-doc-processor-worker
└── dsh-coverage-report
```

- `dsh` parent (`groupId`: `com.mriss.products`, `artifactId`: `dsh`)
- Maven release plugin uses `<scmCommentPrefix>[maven-release-plugin][skip]</scmCommentPrefix>` — push-triggered builds are skipped
- `release:branch` uses `branchName: staging-${project.version}-RC` (e.g. `staging-0.3.0-SNAPSHOT-RC`)
- Tag format: `v@{project.version}` (e.g. `v0.3.0`)
- DSH SCM: `scm:git:https://github.com/MRISS-Projects/dsh.git`

### 2.4 mail-processor-service Reference Profile Flow

`mail-processor-service` was the first project to use these Jenkins templates. Key observations for comparison:

| Pipeline stage | mail-processor-service flags | DSH equivalent |
|---------------|------------------------------|----------------|
| Staging deploy | `-Ddeployment -Drelease.type=rcs -Dappengine.project.version=... -Dcloudrun.project.version=...` | `-Ddeployment -Drelease.type=rcs` (no GCP flags) |
| Staging site | `-Ddeployment -Drelease.type=rcs` | same |
| Release perform args | `deployment + release-deployment + product-release-deployment` | same (inherited from `products/pom.xml`) |
| Post-release site | `-Ddeployment -Drelease-deployment site-deploy` | same |
| Post-release README | `-Ddeployment -Drelease-deployment process-resources` | same |

In `mail-processor-service/pom.xml`:
- `deployment` profile: adds `buildnumber-maven-plugin:create-timestamp`, `maven-scm-plugin:commit-readme-md`, `maven-resources-plugin:copy-readme-md`
- `product-release-deployment` profile: adds `build-helper-maven-plugin:attach-readme`, `maven-resources-plugin:copy-readme-md`; PDF plugin is **commented out** (inactive for mail-processor-service)

This confirms that `product-release-deployment` is defined in `products/pom.xml` (which handles the PDF + issue list generation) and each product can further customize it without re-defining the base behaviour.

---

## 3. The `process-resources` Question — Lines 158–162

### The code in question

`ProjectReleaseJenkinsfile`, lines 158–162 (Post Release stage, after master merge and push):

```groovy
configFileProvider([configFile(fileId: "${mavenConfigurationId}", variable: 'MAVEN_SETTINGS')]) {
    sh "cd target/checkout; pwd; mvn -gs $MAVEN_SETTINGS -B -Dsite.deployment.personal.main=file:///tmp/sites -Ddeployment -Drelease-deployment site-deploy"
    sh "cd target/checkout; pwd; mvn -gs $MAVEN_SETTINGS -B -Ddeployment -Drelease-deployment process-resources"
}
```

The same two lines appear in `ProjectHotfixJenkinsfile` at lines 98–101.

### Why they are needed

#### Why `site-deploy`?

- `release:perform` runs the goals defined in the release plugin `<goals>` element, which is **`deploy`** (not `site-deploy`)
- This means **`release:perform` deploys artifacts but does NOT publish the Maven site**
- After `release:perform` and the post-release merge to master, `site-deploy -Ddeployment -Drelease-deployment` is the **only** invocation that:
  1. Generates the HTML site (`mvn site` phase is part of the site lifecycle triggered by `site-deploy`)
  2. Stages it into `/tmp/sites`
  3. Has `maven-scm-publish-plugin` push `/tmp/sites` to the `gh-pages` branch under `releases/` path (because `release-deployment` sets `release.type=releases`)

#### Why `process-resources`?

- The `deployment` profile in `parent-poms/pom.xml` binds two executions to the `process-resources` phase of the **default** lifecycle:
  - `copy-readme-md`: copies `src/site/markdown/README.md` → root `README.md` with Maven filtering applied (substituting `${project.version}`, `${project.build.version}`, etc.)
  - `commit-readme-md`: runs `maven-scm-plugin:checkin` to commit `README.md` to the SCM
- These executions do **NOT** run during the site lifecycle (`site-deploy` invocation above)
- Running `mvn process-resources -Ddeployment -Drelease-deployment` from the master checkout ensures:
  - README.md at root is regenerated with the **released version** (since `release-deployment` sets `project.build.version=${project.version}`, removing snapshot identifiers)
  - The updated README.md is committed to the master branch

#### Why `target/checkout`?

- `release:perform` checks out the release tag into `target/checkout` of the RC branch workspace
- The Post Release stage checks out the `master` branch **into** `target/checkout` (overwriting the tag checkout)
- All subsequent Maven commands run from this `target/checkout` directory, which is the master branch state after the merge

#### Conclusion

**Both invocations are required and must be preserved in the GitHub Actions equivalents.** The `process-resources` goal is not redundant with `site-deploy` — they operate on different Maven lifecycles and serve distinct purposes:

| Maven call | Lifecycle | Purpose |
|-----------|-----------|---------|
| `mvn site-deploy -Ddeployment -Drelease-deployment` | Site lifecycle | Generate site → stage to `/tmp/sites` → push to `gh-pages/releases/` |
| `mvn process-resources -Ddeployment -Drelease-deployment` | Default lifecycle (partial) | Copy + filter README.md → commit README.md to master |

---

## 4. GCP Decoupling Strategy

### Current situation

All four Jenkinsfiles wrap the Maven release/deploy commands in a `withCredentials` block that binds:

| Jenkins credential | Env var | Usage |
|-------------------|---------|-------|
| `gcloud-project-id` | `GCLOUD_PROJECT_ID` | App Engine / Cloud Run project |
| `allowed-account` | `ALLOWED_ACCOUNT_VAR` | App Engine allowed accounts |
| `allowed-sender-list` | `ALLOWED_SENDER_LIST_VAR` | App Engine allowed senders |
| `gcloud-service-account-1` | `GCLOUD_SERVICE_ACCOUNT` | GCP service account JSON |
| `github-personal-token` | `PERSONAL_TOKEN_VAR` | GitHub API access |

Additionally, `ProjectStagingJenkinsfile` passes GCP-specific Maven flags:
```
-Dappengine.project.version=... -Dcloudrun.project.version=...
```

### DSH situation

- DSH is **not** attached to GCP
- The `appengine-maven-plugin` is present in `parent-poms/pom.xml` `pluginManagement` but is never bound to a lifecycle phase in any DSH `build` or `profile` section
- GCP flags passed to Maven are silently ignored if no plugin uses them
- GCP service account credentials are not available as GitHub secrets in the DSH repository

### Strategy

1. **GCP credentials**: Declare as optional secrets in the reusable workflows. GitHub Actions secrets that are not defined in the caller's repository are resolved as empty strings, not as errors. The workflows must be designed so the build succeeds even when these secrets are empty.

2. **GCP Maven flags** (`appengine.project.version`, `cloudrun.project.version`): Expose as optional workflow inputs with empty defaults. When not provided, the flags are omitted from the Maven command line. DSH callers simply do not pass them.

3. **GCP steps**: Do not include any `gcloud` CLI steps in the reusable workflows. If a product (future `mail-processor-service` migration) needs GCP deployment, it adds a separate job step after calling the reusable workflow.

4. **Minimum success criterion for DSH**: The workflow succeeds if:
   - Maven artifacts are correctly published to `MRISS-Projects/maven-repo` (GitHub Packages)
   - The Maven site is correctly deployed to the `gh-pages` branch of the project repository
   - Git tags and branches are created as expected
   - README.md is committed to the appropriate branch

---

## 5. Secrets & Tooling Standards

### Required Secrets (caller repository)

| Secret name | Description | Scope |
|------------|-------------|-------|
| `DEPLOY_TOKEN` | GitHub PAT (classic) with `repo` + `read:packages` + `write:packages` scopes | All four workflows |

### Optional Secrets (caller repository, GCP only)

| Secret name | Description |
|------------|-------------|
| `GCLOUD_PROJECT_ID` | GCP project ID |
| `GCLOUD_SERVICE_ACCOUNT` | GCP service account JSON (file contents) |

### Java & Maven Tooling

| Tool | Version | Setup |
|------|---------|-------|
| JDK | 17 (Temurin) | `actions/setup-java@v4` with `distribution: temurin`, `java-version: '17'` |
| Maven | **3.9.9** (pinned) | `stCarolas/setup-maven@v5` with `maven-version: 3.9.9` — must run **after** `setup-java` |

**Why 3.9.9?** Maven 3.9.9 is the latest stable Maven 3 release, is fully backward-compatible with
`maven-release-plugin:3.1.1` (which requires Maven 3.6.3+), and is the canonical version for all
MRISS-Projects GitHub Actions pipelines. Explicit pinning ensures reproducible builds regardless of
which Maven version ships on the `ubuntu-latest` runner image at any given time.

Setup snippet used in every workflow:
```yaml
- name: Set up JDK 17
  uses: actions/setup-java@v4
  with:
    java-version: '17'
    distribution: 'temurin'
    cache: 'maven'

- name: Set up Maven 3.9.9
  uses: stCarolas/setup-maven@v5
  with:
    maven-version: 3.9.9
```

### Git Configuration

All workflows that perform SCM commits/pushes must configure Git identity:
```bash
git config --global user.name  "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
```

---

## 6. Reusable Workflow Specifications

### 6.1 `project-stage.yml`

**Purpose:** Create the RC (release candidate) branch from the `DEVELOPMENT` branch.
Replaces `ProjectStageJenkinsfile`.

#### Trigger, Inputs & Secrets Declaration

```yaml
on:
  workflow_call:
    inputs:
      git_project:
        type: string
        required: true
        description: 'Target repository name, e.g. dsh'
      next_development_version:
        type: string
        required: true
        description: 'SNAPSHOT version for the RC branch, e.g. 0.4.0-SNAPSHOT'
      maven_artifact_id:
        type: string
        required: true
        description: 'Root artifact ID, e.g. dsh'
      maven_group_id:
        type: string
        required: true
        description: 'Root group ID, e.g. com.mriss.products'
    secrets:
      DEPLOY_TOKEN:
        required: true
```

#### Job-level Skeleton

```yaml
jobs:
  stage:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

#### Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `git_project` | string | yes | Target repository name, e.g. `dsh` |
| `next_development_version` | string | yes | SNAPSHOT version for the RC branch, e.g. `0.4.0-SNAPSHOT` |
| `maven_artifact_id` | string | yes | Root artifact ID, e.g. `dsh` |
| `maven_group_id` | string | yes | Root group ID, e.g. `com.mriss.products` |

#### Secrets

| Name | Required |
|------|----------|
| `DEPLOY_TOKEN` | yes |

#### Steps

1. **Checkout** — `DEVELOPMENT` branch of `MRISS-Projects/{git_project}` with full history:
   ```yaml
   - uses: actions/checkout@v4
     with:
       repository: MRISS-Projects/${{ inputs.git_project }}
       ref: DEVELOPMENT
       fetch-depth: 0
       token: ${{ secrets.DEPLOY_TOKEN }}
   ```
2. **Setup Java 17 / Temurin**:
   ```yaml
   - uses: actions/setup-java@v4
     with:
       java-version: '17'
       distribution: 'temurin'
       cache: 'maven'
   ```
3. **Setup Maven 3.9.9** — must run after `setup-java`:
   ```yaml
   - uses: stCarolas/setup-maven@v5
     with:
       maven-version: 3.9.9
   ```
4. **Configure Maven settings** — write `~/.m2/settings.xml` from the template in §8:
   ```yaml
   - name: Configure Maven settings
     run: |
       mkdir -p ~/.m2
       cat > ~/.m2/settings.xml << 'SETTINGS_EOF'
       # ... full settings.xml from §8 ...
       SETTINGS_EOF
   ```
5. **Configure Git identity**:
   ```bash
   git config --global user.name  "github-actions[bot]"
   git config --global user.email "github-actions[bot]@users.noreply.github.com"
   ```
6. **Create RC branch**:
   ```bash
   mvn -B \
     -DdevelopmentVersion=${{ inputs.next_development_version }} \
     "-Dproject.dev.${{ inputs.maven_group_id }}:${{ inputs.maven_artifact_id }}=${{ inputs.next_development_version }}" \
     -DautoVersionSubmodules=true \
     release:branch
   ```

#### Jenkinsfile mapping

| Groovy | GitHub Actions equivalent |
|--------|--------------------------|
| `release:branch` with `-DdevelopmentVersion` | Same Maven goal, same flags |
| `configFileProvider` + `mavenConfigurationId` | Inline `settings.xml` generated in step 4 |
| RC branch name `staging-${project.version}-RC` | Controlled by `<branchName>` in product `pom.xml` (already configured) |

#### Version calculation note

In `ProjectStageJenkinsfile`, `getNextDevelopmentVersionNumber()` computes the RC branch development
version automatically:
- `MAJOR.MINOR.0-SNAPSHOT` → `MAJOR.(MINOR+1).0-SNAPSHOT`
- `MAJOR.MINOR.FIX-SNAPSHOT` (FIX > 0) → `MAJOR.MINOR.(FIX+1)-SNAPSHOT`

This calculation is moved to the **caller workflow** (product project). The caller computes the value
and passes it as `next_development_version`. The shell helper at §9 provides the calculation.

---

### 6.2 `project-staging.yml`

**Purpose:** Build and deploy a release candidate snapshot (artifacts + Maven site) to the RCS area.
Can be triggered multiple times. Replaces `ProjectStagingJenkinsfile`.

#### Trigger, Inputs & Secrets Declaration

```yaml
on:
  workflow_call:
    inputs:
      git_project:
        type: string
        required: true
      branch_name:
        type: string
        required: true
      appengine_project_version:
        type: string
        required: false
        default: ''
      cloudrun_project_version:
        type: string
        required: false
        default: ''
      build_number:
        type: string
        required: false
        default: ''    # falls back to GITHUB_RUN_NUMBER in shell
    secrets:
      DEPLOY_TOKEN:
        required: true
      GCLOUD_PROJECT_ID:
        required: false
```

#### Job-level Skeleton

```yaml
jobs:
  staging:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

#### Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `git_project` | string | yes | — | Target repository name |
| `branch_name` | string | yes | — | RC branch name, e.g. `staging-0.3.0-SNAPSHOT-RC` |
| `appengine_project_version` | string | no | `""` | GCP App Engine version suffix (empty = skip flag) |
| `cloudrun_project_version` | string | no | `""` | GCP Cloud Run version suffix (empty = skip flag) |
| `build_number` | string | no | `GITHUB_RUN_NUMBER` | Build number; resolved to `RC<n>` in the step |

#### Secrets

| Name | Required |
|------|----------|
| `DEPLOY_TOKEN` | yes |
| `GCLOUD_PROJECT_ID` | no |

#### Steps

1. **Checkout** — `branch_name` of `MRISS-Projects/{git_project}` with full history:
   ```yaml
   - uses: actions/checkout@v4
     with:
       repository: MRISS-Projects/${{ inputs.git_project }}
       ref: ${{ inputs.branch_name }}
       fetch-depth: 0
       token: ${{ secrets.DEPLOY_TOKEN }}
   ```
2. **Setup Java 17 / Temurin**:
   ```yaml
   - uses: actions/setup-java@v4
     with:
       java-version: '17'
       distribution: 'temurin'
       cache: 'maven'
   ```
3. **Setup Maven 3.9.9** — must run after `setup-java`:
   ```yaml
   - uses: stCarolas/setup-maven@v5
     with:
       maven-version: 3.9.9
   ```
4. **Configure Maven settings** — write `~/.m2/settings.xml` from the template in §8.
5. **Configure Git identity**.
6. **Build and deploy artifacts** — 409 Conflict is treated as a warning (idempotent RC re-deploy):
   ```bash
   BUILD_NUM="${{ inputs.build_number }}"
   BUILD_NUM="${BUILD_NUM:-${GITHUB_RUN_NUMBER}}"

   GCP_FLAGS=""
   if [ -n "${{ inputs.appengine_project_version }}" ]; then
     GCP_FLAGS="$GCP_FLAGS -Dappengine.project.version=${{ inputs.appengine_project_version }}"
   fi
   if [ -n "${{ inputs.cloudrun_project_version }}" ]; then
     GCP_FLAGS="$GCP_FLAGS -Dcloudrun.project.version=${{ inputs.cloudrun_project_version }}"
   fi

   set +e
   output=$(mvn -B -U \
     -Ddeployment \
     -Drelease.type=rcs \
     -Dbuild.number=RC${BUILD_NUM} \
     $GCP_FLAGS \
     clean deploy 2>&1)
   rc=$?
   echo "$output"
   if [ $rc -ne 0 ]; then
     if echo "$output" | grep -qE "status code: 409|HTTP 409|Conflict \(409\)"; then
       echo "WARNING: Artifact already exists (409 Conflict). Continuing."
     else
       exit $rc
     fi
   fi
   set -e
   ```
   > **Note on GCP flags:** `appengine_project_version` and `cloudrun_project_version` are GCP-specific.
   > DSH callers omit them; the flags are not added to the Maven command line.
   > The `VERSION_INFO` string (`major-minor-fix`) from `getVersionInfo()` in the Jenkinsfile is only
   > needed when building these version strings — compute it at the caller level if needed.
7. **Deploy site**:
   ```bash
   BUILD_NUM="${{ inputs.build_number }}"
   BUILD_NUM="${BUILD_NUM:-${GITHUB_RUN_NUMBER}}"

   mvn -B -U \
     -Ddeployment \
     -Drelease.type=rcs \
     -Dbuild.number=RC${BUILD_NUM} \
     -Dsite.deployment.personal.main=file:///tmp/sites \
     site-deploy
   ```

#### Jenkinsfile mapping

| Groovy | GitHub Actions equivalent |
|--------|--------------------------|
| `mvn clean deploy -Ddeployment -Drelease.type=rcs -Dappengine.project.version=... -Dcloudrun.project.version=... -Djenkins.build.number=RC${BUILD_NUMBER}` | Step 6 (GCP flags conditional; 409 ignored) |
| `mvn site-deploy -Ddeployment -Drelease.type=rcs -Djenkins.build.number=RC${BUILD_NUMBER}` | Step 7 |
| Jenkins `BUILD_NUMBER` | `GITHUB_RUN_NUMBER` (via `BUILD_NUM` shell fallback) |
| `getVersionInfo()` → `major-minor-fix` | Caller-computed; only needed for GCP version inputs |

#### DSH considerations

- DSH does not pass `appengine_project_version` or `cloudrun_project_version` → GCP flags are omitted
- `appengine-maven-plugin` is not bound to any DSH lifecycle phase → even if flags were passed, no GCP deployment would occur
- The `deployment` profile in `dsh/pom.xml` adds PDF generation and README attachment — these run automatically when `-Ddeployment` is present

---

### 6.3 `project-release.yml`

**Purpose:** Perform the official Maven release for a `MAJOR.MINOR.0-SNAPSHOT` version. Creates the
hotfix branch, merges the release tag to master, deploys the release site, and removes the RC branch.
Replaces `ProjectReleaseJenkinsfile`.

#### Trigger, Inputs & Secrets Declaration

```yaml
on:
  workflow_call:
    inputs:
      git_project:
        type: string
        required: true
      branch_name:
        type: string
        required: true
      current_version:
        type: string
        required: true
      next_development_version:
        type: string
        required: true
      hotfix_branch:
        type: string
        required: true
      initial_hotfix_version:
        type: string
        required: true
      site_deployment_url:
        type: string
        required: false
        default: 'file:///tmp/sites'
    secrets:
      DEPLOY_TOKEN:
        required: true
```

#### Job-level Skeleton

```yaml
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    concurrency:
      group: ${{ github.workflow }}-${{ inputs.git_project }}-release
      cancel-in-progress: false   # never cancel an in-progress release
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

#### Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `git_project` | string | yes | Target repository name |
| `branch_name` | string | yes | RC branch name, e.g. `staging-0.3.0-SNAPSHOT-RC` |
| `current_version` | string | yes | Release version (no `-SNAPSHOT`), e.g. `0.3.0` |
| `next_development_version` | string | yes | Next dev SNAPSHOT after release, e.g. `0.4.0-SNAPSHOT` |
| `hotfix_branch` | string | yes | Name of the hotfix branch to create, e.g. `0.3.x` |
| `initial_hotfix_version` | string | yes | Initial SNAPSHOT for hotfix branch, e.g. `0.3.1-SNAPSHOT` |
| `site_deployment_url` | string | no | Site staging path. Default: `file:///tmp/sites` |

#### Secrets

| Name | Required |
|------|----------|
| `DEPLOY_TOKEN` | yes |

#### Validations (fail-fast)

Before any Maven command:
```bash
# Validate that this is a MAJOR.MINOR.0-SNAPSHOT (FIX component must be 0)
FULL_VERSION=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
IFS='.' read -r _ _ FIX <<< "${FULL_VERSION%-SNAPSHOT}"
if [ "$FIX" != "0" ]; then
  echo "ERROR: project-release.yml is only for MAJOR.MINOR.0-SNAPSHOT versions."
  echo "       FIX component is '$FIX'. Use project-hotfix.yml for FIX > 0."
  exit 1
fi
```

#### Steps

1. **Checkout** — `branch_name` of `MRISS-Projects/{git_project}` with full history:
   ```yaml
   - uses: actions/checkout@v4
     with:
       repository: MRISS-Projects/${{ inputs.git_project }}
       ref: ${{ inputs.branch_name }}
       fetch-depth: 0
       token: ${{ secrets.DEPLOY_TOKEN }}
   ```
2. **Setup Java 17 / Temurin**:
   ```yaml
   - uses: actions/setup-java@v4
     with:
       java-version: '17'
       distribution: 'temurin'
       cache: 'maven'
   ```
3. **Setup Maven 3.9.9** — must run after `setup-java`:
   ```yaml
   - uses: stCarolas/setup-maven@v5
     with:
       maven-version: 3.9.9
   ```
4. **Configure Maven settings** — write `~/.m2/settings.xml` from the template in §8.
5. **Configure Git identity**:
   ```bash
   git config --global user.name  "github-actions[bot]"
   git config --global user.email "github-actions[bot]@users.noreply.github.com"
   ```
6. **Validate FIX == 0** (see validation block above).
7. **Maven release**:
   ```bash
   SITE_URL="${{ inputs.site_deployment_url }}"

   mvn -B \
     -Dbuild.NEXT_DEVELOPMENT_VERSION=${{ inputs.next_development_version }} \
     -Dbuild.CURRENT_VERSION_NUMBER=${{ inputs.current_version }} \
     release:clean

   mvn -B \
     -Dbuild.NEXT_DEVELOPMENT_VERSION=${{ inputs.next_development_version }} \
     -Dbuild.CURRENT_VERSION_NUMBER=${{ inputs.current_version }} \
     release:prepare

   mvn -B \
     -Dsite.deployment.personal.main="${SITE_URL}" \
     release:perform
   ```

   > `release:perform` internally uses the `<arguments>` from `products/pom.xml`:
   > `-Ddeployment -Drelease-deployment -Dproduct-release-deployment -Dsite.deployment.personal.main=...`
   > These activate PDF generation, issue list, artifact deployment. **Not** site-deploy (see §3).

8. **Create hotfix branch** — from `target/checkout` (the released tag state left by `release:perform`):
   ```bash
   cd target/checkout
   mvn -B -Dbranch=${{ inputs.hotfix_branch }} scm:branch
   ```
9. **Checkout hotfix branch and set initial version**:
   ```bash
   # Remove the entire target/checkout tree (including hidden .git) before re-using the path
   rm -rf target/checkout

   # Checkout the hotfix branch into target/checkout
   # -DcheckoutDirectory makes the destination explicit and reliable
   mvn -B \
     -DscmVersion=${{ inputs.hotfix_branch }} \
     -DscmVersionType=branch \
     -DcheckoutDirectory=target/checkout \
     scm:checkout

   cd target/checkout

   # Set initial hotfix SNAPSHOT version on all modules
   mvn -B -DprocessAllModules=true -DnewVersion=${{ inputs.initial_hotfix_version }} versions:set

   # Commit the version change to the hotfix branch
   mvn -B -Dmessage="[maven-release-plugin] set hotfix version ${{ inputs.initial_hotfix_version }}" scm:checkin
   ```
10. **Post-release: merge release tag to master**:
    ```bash
    CURRENT_TAG="v${{ inputs.current_version }}"
    REPO_URL="https://x-access-token:${DEPLOY_TOKEN}@github.com/MRISS-Projects/${{ inputs.git_project }}.git"

    # Remove the entire checkout tree (including hidden .git) before cloning master
    rm -rf target/checkout

    git clone --branch master "$REPO_URL" target/checkout

    cd target/checkout

    # Fetch the release tag explicitly — --branch master clone does not include remote tags
    git fetch origin "refs/tags/${CURRENT_TAG}:refs/tags/${CURRENT_TAG}"

    git merge -s recursive -X theirs "$CURRENT_TAG"
    git push "$REPO_URL" master
    ```
11. **Post-release: deploy site to gh-pages `releases/` area** (see §3 — site-deploy is separate from `release:perform`):
    ```bash
    cd target/checkout
    mvn -B \
      -Dsite.deployment.personal.main="${{ inputs.site_deployment_url }}" \
      -Ddeployment \
      -Drelease-deployment \
      site-deploy
    ```
12. **Post-release: update and commit README.md to master** (see §3 — default lifecycle, not site lifecycle):
    ```bash
    cd target/checkout
    mvn -B \
      -Ddeployment \
      -Drelease-deployment \
      process-resources
    ```
    > Do **not** add `-Dcommit.readme.phase=none` here — the intent is to commit README.md to master.
    > That flag is only used in non-deployment CI builds to suppress the SCM checkin.
13. **Remove RC branch**:
    ```bash
    REPO_URL="https://x-access-token:${DEPLOY_TOKEN}@github.com/MRISS-Projects/${{ inputs.git_project }}.git"
    git push "$REPO_URL" --delete ${{ inputs.branch_name }}
    ```

#### Jenkinsfile mapping

| Groovy stage | GitHub Actions step |
|-------------|---------------------|
| Checkout RC branch | Step 1 |
| Read pom.xml Info | Computed by caller / validation in step 6 |
| Ask User Confirmation | Replaced by workflow `inputs` — caller provides values explicitly |
| Build and Deploy Maven Release | Step 7 (release:clean + prepare + perform) |
| Creates Hotfix Branch | Step 8 |
| Generates Version at Hotfix Branch | Step 9 (versions:set + scm:checkin) |
| Post Release | Steps 10–12 |
| Remove RC Branch | Step 13 |

#### GCP note

The original Jenkinsfile wraps `release:clean/prepare/perform` in a `withCredentials` block for GCP.
For DSH this is not needed. In GitHub Actions, GCP-related secrets (`GCLOUD_PROJECT_ID`, etc.) are
simply not passed. If a future product needs GCP deployment, it adds those secrets and any `gcloud`
steps outside the `release:perform` scope in its own caller workflow.

---

### 6.4 `project-hotfix.yml`

**Purpose:** Perform the official Maven release for a hotfix (`MAJOR.MINOR.FIX` where FIX ≠ 0).
Fully automatic (no user confirmation). Merges release tag to master, deploys site.
Replaces `ProjectHotfixJenkinsfile`.

#### Trigger, Inputs & Secrets Declaration

```yaml
on:
  workflow_call:
    inputs:
      git_project:
        type: string
        required: true
      branch_name:
        type: string
        required: true
      site_deployment_url:
        type: string
        required: false
        default: 'file:///tmp/sites'
    secrets:
      DEPLOY_TOKEN:
        required: true
```

#### Job-level Skeleton

```yaml
jobs:
  hotfix:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      packages: write
    concurrency:
      group: ${{ github.workflow }}-${{ inputs.git_project }}-hotfix
      cancel-in-progress: false   # never cancel an in-progress release
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

#### Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `git_project` | string | yes | Target repository name |
| `branch_name` | string | yes | Hotfix branch name, e.g. `0.3.x` |
| `site_deployment_url` | string | no | Site staging path. Default: `file:///tmp/sites` |

#### Secrets

| Name | Required |
|------|----------|
| `DEPLOY_TOKEN` | yes |

#### Validations (fail-fast)

```bash
# Validate FIX > 0 (hotfix, not a minor release)
FULL_VERSION=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
IFS='.' read -r _ _ FIX_PART <<< "${FULL_VERSION%-SNAPSHOT}"
if [ "$FIX_PART" = "0" ]; then
  echo "ERROR: project-hotfix.yml is only for MAJOR.MINOR.FIX-SNAPSHOT where FIX > 0."
  echo "       FIX component is '0'. Use project-release.yml for MAJOR.MINOR.0 releases."
  exit 1
fi
```

#### Steps

1. **Checkout** — `branch_name` of `MRISS-Projects/{git_project}` with full history:
   ```yaml
   - uses: actions/checkout@v4
     with:
       repository: MRISS-Projects/${{ inputs.git_project }}
       ref: ${{ inputs.branch_name }}
       fetch-depth: 0
       token: ${{ secrets.DEPLOY_TOKEN }}
   ```
2. **Setup Java 17 / Temurin**:
   ```yaml
   - uses: actions/setup-java@v4
     with:
       java-version: '17'
       distribution: 'temurin'
       cache: 'maven'
   ```
3. **Setup Maven 3.9.9** — must run after `setup-java`:
   ```yaml
   - uses: stCarolas/setup-maven@v5
     with:
       maven-version: 3.9.9
   ```
4. **Configure Maven settings** — write `~/.m2/settings.xml` from the template in §8.
5. **Configure Git identity**:
   ```bash
   git config --global user.name  "github-actions[bot]"
   git config --global user.email "github-actions[bot]@users.noreply.github.com"
   ```
6. **Read hotfix release number** and export for subsequent steps:
   ```bash
   HOTFIX_RELEASE_NUMBER=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N \
     | sed 's/-SNAPSHOT//')
   echo "HOTFIX_RELEASE_NUMBER=${HOTFIX_RELEASE_NUMBER}" >> $GITHUB_ENV
   ```
7. **Validate FIX > 0** (see validation block above).
8. **Maven release** — hotfix uses pom defaults for version parameters:
   ```bash
   mvn -B release:clean
   mvn -B release:prepare
   mvn -B \
     -Dsite.deployment.personal.main="${{ inputs.site_deployment_url }}" \
     release:perform
   ```
9. **Post-release: merge release tag to master**:
   ```bash
   CURRENT_TAG="v${HOTFIX_RELEASE_NUMBER}"
   REPO_URL="https://x-access-token:${DEPLOY_TOKEN}@github.com/MRISS-Projects/${{ inputs.git_project }}.git"

   # Remove the entire checkout tree (including hidden .git) before cloning master
   rm -rf target/checkout

   git clone --branch master "$REPO_URL" target/checkout

   cd target/checkout

   # Fetch the release tag explicitly — branch-only clone does not include remote tags
   git fetch origin "refs/tags/${CURRENT_TAG}:refs/tags/${CURRENT_TAG}"

   git merge -s recursive -X theirs --allow-unrelated-histories "$CURRENT_TAG"
   git push "$REPO_URL" master
   ```
10. **Post-release: deploy site** (same rationale as §3):
    ```bash
    cd target/checkout
    mvn -B \
      -Dsite.deployment.personal.main="${{ inputs.site_deployment_url }}" \
      -Ddeployment \
      -Drelease-deployment \
      site-deploy
    ```
11. **Post-release: update and commit README.md** (same rationale as §3):
    ```bash
    cd target/checkout
    mvn -B \
      -Ddeployment \
      -Drelease-deployment \
      process-resources
    ```
    > Do **not** add `-Dcommit.readme.phase=none` here — the intent is to commit README.md to master.

> **Note:** Unlike `project-release.yml`, there is **no RC branch removal** step — hotfix branches
> are long-lived and remain active for future patch releases.

#### Jenkinsfile mapping

| Groovy stage | GitHub Actions step |
|-------------|---------------------|
| Checkout hotfix branch | Step 1 |
| Read pom.xml Info | Step 6 |
| Build and Deploy Maven Release (no params) | Step 8 |
| Post Release (merge → site-deploy → process-resources) | Steps 9–11 |

---

## 7. Caller Workflow Examples for DSH

### Stage (create RC branch)

```yaml
# .github/workflows/stage.yml  (in dsh repository)
name: Stage
on:
  workflow_dispatch:
    inputs:
      next_development_version:
        description: 'Next SNAPSHOT version for RC branch (e.g. 0.4.0-SNAPSHOT)'
        required: true

jobs:
  stage:
    uses: MRISS-Projects/parent-poms/.github/workflows/project-stage.yml@master
    with:
      git_project: dsh
      next_development_version: ${{ inputs.next_development_version }}
      maven_artifact_id: dsh
      maven_group_id: com.mriss.products
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

### Staging (RC snapshot build + deploy)

```yaml
# .github/workflows/staging.yml  (in dsh repository)
name: Staging
on:
  workflow_dispatch:
    inputs:
      branch_name:
        description: 'RC branch name (e.g. staging-0.3.0-SNAPSHOT-RC)'
        required: true

jobs:
  staging:
    uses: MRISS-Projects/parent-poms/.github/workflows/project-staging.yml@master
    with:
      git_project: dsh
      branch_name: ${{ inputs.branch_name }}
      # No GCP inputs — DSH is not on GCP
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

### Release (official Maven release)

```yaml
# .github/workflows/release.yml  (in dsh repository)
name: Release
on:
  workflow_dispatch:
    inputs:
      branch_name:
        description: 'RC branch (e.g. staging-0.3.0-SNAPSHOT-RC)'
        required: true
      current_version:
        description: 'Release version (e.g. 0.3.0)'
        required: true
      next_development_version:
        description: 'Next dev SNAPSHOT (e.g. 0.4.0-SNAPSHOT)'
        required: true
      hotfix_branch:
        description: 'Hotfix branch name (e.g. 0.3.x)'
        required: true
      initial_hotfix_version:
        description: 'Initial hotfix SNAPSHOT (e.g. 0.3.1-SNAPSHOT)'
        required: true

jobs:
  release:
    uses: MRISS-Projects/parent-poms/.github/workflows/project-release.yml@master
    with:
      git_project: dsh
      branch_name: ${{ inputs.branch_name }}
      current_version: ${{ inputs.current_version }}
      next_development_version: ${{ inputs.next_development_version }}
      hotfix_branch: ${{ inputs.hotfix_branch }}
      initial_hotfix_version: ${{ inputs.initial_hotfix_version }}
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

### Hotfix

```yaml
# .github/workflows/hotfix.yml  (in dsh repository)
name: Hotfix
on:
  workflow_dispatch:
    inputs:
      branch_name:
        description: 'Hotfix branch (e.g. 0.3.x)'
        required: true

jobs:
  hotfix:
    uses: MRISS-Projects/parent-poms/.github/workflows/project-hotfix.yml@master
    with:
      git_project: dsh
      branch_name: ${{ inputs.branch_name }}
    secrets:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
```

---

## 8. Maven Settings Template

All four workflows use an identical Maven `settings.xml` generated inline. This mirrors the pattern
already established in the existing `build.yml` and `deploy.yml`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
                              https://maven.apache.org/xsd/settings-1.0.0.xsd">
    <servers>
        <!-- Artifact release repository -->
        <server>
            <id>releases</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.DEPLOY_TOKEN}</password>
        </server>
        <!-- Maven package registry (read + write) -->
        <server>
            <id>MRISS-Projects-maven-repo</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.DEPLOY_TOKEN}</password>
        </server>
        <server>
            <id>MRISS-Projects-maven-repo-plugins</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.DEPLOY_TOKEN}</password>
        </server>
        <!-- SCM server (for maven-scm-publish-plugin gh-pages push and scm:checkin) -->
        <server>
            <id>github.com</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.DEPLOY_TOKEN}</password>
        </server>
        <server>
            <id>github</id>
            <username>${env.GITHUB_ACTOR}</username>
            <password>${env.DEPLOY_TOKEN}</password>
        </server>
    </servers>
    <profiles>
        <profile>
            <id>github-packages</id>
            <properties>
                <!-- Used by maven-changes-plugin (personalToken) -->
                <github.personal.token>${env.DEPLOY_TOKEN}</github.personal.token>
            </properties>
            <repositories>
                <repository>
                    <id>MRISS-Projects-maven-repo</id>
                    <url>https://maven.pkg.github.com/MRISS-Projects/maven-repo</url>
                    <releases><enabled>true</enabled></releases>
                    <snapshots><enabled>true</enabled></snapshots>
                </repository>
            </repositories>
            <pluginRepositories>
                <pluginRepository>
                    <id>MRISS-Projects-maven-repo-plugins</id>
                    <url>https://maven.pkg.github.com/MRISS-Projects/maven-repo</url>
                    <releases><enabled>true</enabled></releases>
                    <snapshots><enabled>true</enabled></snapshots>
                </pluginRepository>
            </pluginRepositories>
        </profile>
    </profiles>
    <activeProfiles>
        <activeProfile>github-packages</activeProfile>
    </activeProfiles>
</settings>
```

---

## 9. Version Calculation Shell Reference

These shell functions translate the Groovy helper functions from the Jenkinsfiles.
Callers can embed them in their `workflow_dispatch` input descriptions or pre-compute
values before calling the reusable workflow.

```bash
# Read raw version from pom.xml (requires Maven)
FULL_VERSION=$(mvn -q help:evaluate -Dexpression=project.version -DforceStdout -N)
# e.g. 0.3.0-SNAPSHOT

CURRENT_VERSION="${FULL_VERSION%-SNAPSHOT}"
# e.g. 0.3.0

IFS='.' read -r MAJOR MINOR FIX <<< "$CURRENT_VERSION"

# ---- getNextDevelopmentVersionNumber() [for ProjectStageJenkinsfile] ----
# If FIX == 0: bump MINOR (this is a normal MAJOR.MINOR release series)
# If FIX > 0 : bump FIX   (this is a hotfix series)
if [ "$FIX" -eq 0 ]; then
  NEXT_DEV_VERSION="${MAJOR}.$((MINOR + 1)).0-SNAPSHOT"
else
  NEXT_DEV_VERSION="${MAJOR}.${MINOR}.$((FIX + 1))-SNAPSHOT"
fi
# e.g. 0.3.0-SNAPSHOT → 0.4.0-SNAPSHOT
# e.g. 0.3.1-SNAPSHOT → 0.3.2-SNAPSHOT

# ---- getNextDevelopmentVersionNumber() [for ProjectReleaseJenkinsfile] ----
# For release workflow: always bump MINOR (only called for FIX == 0 versions)
RELEASE_NEXT_DEV="${MAJOR}.$((MINOR + 1)).0-SNAPSHOT"
# e.g. 0.3.0-SNAPSHOT → 0.4.0-SNAPSHOT

# ---- getHotFixBranch() ----
HOTFIX_BRANCH="${MAJOR}.${MINOR}.x"
# e.g. 0.3.x

# ---- getInitialVersionHotFix() ----
INITIAL_HOTFIX_VERSION="${MAJOR}.${MINOR}.$((FIX + 1))-SNAPSHOT"
# e.g. 0.3.0-SNAPSHOT → 0.3.1-SNAPSHOT

# ---- getVersionInfo() [for ProjectStagingJenkinsfile] ----
VERSION_INFO="${MAJOR}-${MINOR}-${FIX}"
# e.g. 0-3-0  (used as appengine/cloudrun version suffix)
```

---

## 10. Acceptance Criteria Mapping

| AC | Description | Workflow | Implementation note |
|----|-------------|----------|---------------------|
| AC1 | `project-stage.yml` with `workflow_call` | §6.1 | `release:branch` with inputs |
| AC1 | Java 17 Temurin + Maven | §5 | `actions/setup-java@v4` + `stCarolas/setup-maven@v5` |
| AC1 | Checks out DEVELOPMENT branch | §6.1 step 1 | `repository:` + `ref: DEVELOPMENT` |
| AC1 | `release:branch` with `-DdevelopmentVersion` | §6.1 step 6 | Direct Maven invocation |
| AC2 | `project-staging.yml` with `workflow_call` | §6.2 | |
| AC2 | `mvn clean deploy` with RCS flags | §6.2 step 6 | `-Drelease.type=rcs`; 409 ignored |
| AC2 | `mvn site-deploy` with RCS flags | §6.2 step 7 | `-Drelease.type=rcs` |
| AC2 | Idempotent (multiple runs) | §6.2 step 6 | `set +e` + 409 grep pattern |
| AC3 | `project-release.yml` with `workflow_call` | §6.3 | |
| AC3 | Fails fast if FIX ≠ 0 | §6.3 step 6 | Shell validation before Maven commands |
| AC3 | `release:clean/prepare/perform` | §6.3 step 7 | |
| AC3 | Creates hotfix branch + sets version | §6.3 steps 8–9 | `scm:branch` + `versions:set` |
| AC3 | Merges tag to master | §6.3 step 10 | `git merge -s recursive -X theirs` + tag fetch |
| AC3 | Deploys site with `-Drelease-deployment` | §6.3 step 11 | `site-deploy` from master checkout |
| AC3 | Updates README.md on master | §6.3 step 12 | `process-resources` (no `-Dcommit.readme.phase=none`) |
| AC3 | Deletes RC branch | §6.3 step 13 | `git push --delete` |
| AC4 | `project-hotfix.yml` with `workflow_call` | §6.4 | |
| AC4 | Fails fast if FIX == 0 | §6.4 step 7 | Shell validation |
| AC4 | No user confirmation | §6.4 | All automatic |
| AC4 | Merges tag to master | §6.4 step 9 | `--allow-unrelated-histories` + tag fetch |
| AC4 | Deploys site | §6.4 step 10 | |
| AC4 | Updates README.md on master | §6.4 step 11 | `process-resources` (no `-Dcommit.readme.phase=none`) |
| AC5 | README.md update | Out of scope (separate issue) | |
| AC6 | Java 17 Temurin | §5 | `actions/setup-java@v4` |
| AC6 | Maven 3.9.9 pinned | §5 | `stCarolas/setup-maven@v5` with `maven-version: 3.9.9` |
| AC6 | Maven settings for GitHub Packages | §8 | |
| AC6 | `DEPLOY_TOKEN` secret | §5 | |

---

## 11. Implementation Notes

The following decisions were resolved during spec authoring and are applied directly in §6.

| # | Decision | Applied where |
|---|----------|---------------|
| 1 | `rm -rf target/checkout` (not `/*`) to also remove the hidden `.git` directory before re-using the path | §6.3 steps 9 & 10; §6.4 step 9 |
| 2 | Explicit `git fetch origin "refs/tags/v...:refs/tags/v..."` after `git clone --branch master` to make the release tag locally available for `git merge` | §6.3 step 10; §6.4 step 9 |
| 3 | `DEPLOY_TOKEN` declared as job-level `env:` in every workflow so shell scripts can reference `${DEPLOY_TOKEN}` in git push URLs | §6.1–6.4 job skeletons |
| 4 | `permissions: contents: write, packages: write` declared on every job | §6.1–6.4 job skeletons |
| 5 | `repository: MRISS-Projects/${{ inputs.git_project }}` on every `actions/checkout@v4` step | §6.1–6.4 step 1 |
| 6 | `stCarolas/setup-maven@v5` with `maven-version: 3.9.9` added as an explicit step after `setup-java` in every workflow | §6.1–6.4 step 3 |
| 7 | Maven settings generation step is listed explicitly in each workflow (step 4) referencing the §8 template | §6.1–6.4 step 4 |
| 8 | `on.workflow_call.secrets:` block with `DEPLOY_TOKEN: required: true` (and optional GCP secrets where relevant) added to every workflow | §6.1–6.4 trigger blocks |
| 9 | `concurrency: cancel-in-progress: false` added to `project-release.yml` and `project-hotfix.yml` to prevent cancellation of in-progress releases | §6.3 & §6.4 job skeletons |
| 10 | `fetch-depth: 0` on all checkout steps for full tag history | §6.1–6.4 step 1 |
| 11 | 409 Conflict on `mvn deploy` treated as warning (idempotent RC re-deploy) using `set +e` + grep pattern | §6.2 step 6 |
| 12 | `-DcheckoutDirectory=target/checkout` added to `mvn scm:checkout` to make the destination explicit | §6.3 step 9 |
| 13 | `post-release process-resources` step must **not** include `-Dcommit.readme.phase=none` — the SCM checkin of README.md is intentional | §6.3 step 12; §6.4 step 11 |
| 14 | `site_deployment_url` exposed as optional input (default `file:///tmp/sites`) in `project-release.yml` and `project-hotfix.yml` | §6.3 & §6.4 inputs |
| 15 | Caller examples in §7 use `@master` ref; production callers should pin to a version tag (e.g. `@v3.8.0`) once workflows are stable | §7 |


