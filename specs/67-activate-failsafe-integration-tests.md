# Spec: activate failsafe behind `-DintegrationTests` (`#67`)

| | |
|---|---|
| Issue | [`#67`](https://github.com/MRISS-Projects/parent-poms/issues/67) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-67-activate-failsafe-integration-tests`, cut from `master` |
| Requesting project | `MRISS-Projects/dsh` — `#46`, Wave 0, `specs/product/PRD.md` §4 |
| Spins off | [`dsh#112`](https://github.com/MRISS-Projects/dsh/issues/112) and [`#74`](https://github.com/MRISS-Projects/parent-poms/issues/74) — see §6 |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This repository has no Java production or test source anywhere in the reactor, so nothing
> here can be proven by a unit test. Every task is verified by running Maven and reading the
> log, or by running a build in the consuming project. Those runs are specified exactly; do
> not substitute a different command and assume the same output.

**Goal.** `mvn clean install` runs unit tests only and the inherited 95% `jacoco:check` keeps
measuring unit-test coverage alone. `mvn clean install -DintegrationTests` additionally runs
`*IT.java` / `*IntegrationTest.java` through failsafe, and a failing one fails the build.
Staging builds pass the flag for every inheriting product, so integration tests become a
mandatory release gate without any product having to opt in.

**Architecture.** One new profile in the root `pom.xml`, `integration-tests`, activated by the
`integrationTests` property, promoting `maven-failsafe-plugin` out of `<pluginManagement>` into
`<build><plugins>`. The profile also adds a second JaCoCo agent writing to a separate exec file,
because without it failsafe silently contaminates the exec file the coverage gate reads (§1.2).
One line is added to the reusable staging workflow. This repository supplies the `-D` and
nothing else: what an integration test *starts* — an embedded server, a Spring context, a
container — is each product's decision, not this repository's.

**Tech stack.** Maven — **3.9.9 in CI**, pinned by `stCarolas/setup-maven` in every workflow
here. `maven-failsafe-plugin` 3.5.5, `jacoco-maven-plugin` 0.8.13, GitHub Actions reusable
workflows, POSIX shell.

---

## Global constraints

- Profiles are activated by `-D<name>`, never `-P`. **Never reintroduce `-P`.** The rationale is
  recorded as FR004/FR005 in `pom.xml` and `products/pom.xml`.
- Every profile carries an `FR###` comment naming its activation contract. The next free number
  is **FR015**; `FR001`–`FR006`, `FR008` and `FR012`–`FR014` are taken.
- The 95% `jacoco:check` gate (`element=BUNDLE`, LINE and BRANCH `>= 0.95`, bound to `verify`)
  is **not** re-tuned by this work and keeps measuring unit tests alone. Do not touch its
  `<rules>`.
- The `enforce-coverage-data-exists` guard in `<build><plugins>` is not modified, and must keep
  firing for a module with production sources that produces no `target/jacoco.exec`.
- The failsafe naming convention is already decided and stays: `**/*IT.java` and
  `**/*IntegrationTest.java`, configured in `<pluginManagement>` as FR013, with the matching
  surefire `<excludes>`.
- Java 17.

---

## 1. The defect

### 1.1 Failsafe is configured but never activated

`maven-failsafe-plugin` is declared in the root `pom.xml` `<pluginManagement>` (FR013) with the
correct `<includes>` and an `integration-tests` execution binding `integration-test` and
`verify`. `<pluginManagement>` only supplies version, configuration and executions to a plugin
that is *also* declared in `<build><plugins>` somewhere. No child of this hierarchy declares it.
So failsafe has never executed in any inheriting project, and there is no property or profile
that would make it execute.

The matching surefire `<excludes>` for `**/*IT.java` and `**/*IntegrationTest.java` *is* active,
inherited by every module. The net effect today is the worst of both: a test named `*IT.java`
is excluded from surefire and never picked up by failsafe. It runs nowhere, silently.

This repository's own `CLAUDE.md` documents the opposite, under "Common commands":

```
# Integration tests only (naming convention: *IT.java or *IntegrationTest.java)
mvn -B verify
# (unit tests via surefire exclude *IT/*IntegrationTest; failsafe runs only those, bound to integration-test+verify)
```

Both sentences are false. `mvn -B verify` runs no integration tests, and the flag is not `-B
verify` but `-DintegrationTests` once this work lands. Correcting that block is Task 4.

### 1.2 The naive activation contaminates the coverage gate

This is the part the issue body raises as an open question ("should `jacoco:check` count
integration-test coverage?"). It is not open — the naive profile answers it *yes*, silently, and
nothing in the POM would admit it.

Measured from `maven-failsafe-plugin-3.5.5.jar!/META-INF/maven/plugin.xml`:

| Line | Declaration | Consequence |
|---|---|---|
| 959 | `<argLine implementation="java.lang.String">${argLine}</argLine>` | failsafe's **default** `argLine` is the `argLine` property |

`jacoco:prepare-agent` (execution `prepare-code-coverage`, root `pom.xml`, no explicit phase, so
`initialize`) writes exactly that property, pointing at an agent whose `destFile` defaults to
`${project.build.directory}/jacoco.exec` with `append` defaulting to `true`.

So a profile that only promotes failsafe into `<build><plugins>` produces this ordering:

| Phase | What runs | Effect on `target/jacoco.exec` |
|---|---|---|
| `initialize` | `jacoco:prepare-agent` | sets `argLine` |
| `test` | surefire, agent attached | unit coverage written |
| `integration-test` | failsafe `integration-test`, **same** `argLine` | integration coverage **appended** |
| `verify` | `jacoco:check` reads `target/jacoco.exec` | gate measures unit **+** integration |
| `verify` | failsafe `verify` | fails the build on a failed IT |

The gate would then be satisfiable by adding integration tests instead of unit tests — exactly
the failure mode the issue warns against, reached by doing nothing.

### 1.3 Nothing here can prove any of this

The reactor is `infrastructure`, `framework` and `products`, all `<packaging>pom</packaging>`
plus archetypes, skins and announcement templates. There is no Java production source and no
Java test source anywhere: no module produces a `jacoco.exec`, and none ever runs surefire or
failsafe against real classes. Every behavioural acceptance criterion must therefore be proven
in a consuming project. DSH is that project (§5).

---

## 2. Decisions

These were settled before this spec was written. They are recorded here because the issue body
leaves three of them open and a later reader will otherwise reopen them.

### D1 — the 95% gate stays unit-only, enforced by a separate exec file

Rejected: configuring failsafe with an empty `<argLine/>` so no agent attaches. It gives the
same guarantee in one line, but it collects nothing, and an empty `<argLine/>` reads as a
mistake rather than a decision.

Chosen: a second JaCoCo execution, `prepare-agent-integration`, writing
`target/jacoco-it.exec`, with failsafe pointed at its own `argLine` property. Integration
coverage is **measured but ungated**. `jacoco:check` reads `dataFile`, which defaults to
`target/jacoco.exec`, and never sees the integration file.

The two halves are coupled and neither works alone. Adding the agent without redirecting
failsafe's `argLine` leaves the contamination in place; redirecting `argLine` without adding
the agent silently drops every JVM argument the integration tests were going to get.

### D2 — what counts as an integration test is the product's decision, with one shared rule

A test that starts a Spring context is an integration test. A unit test uses Mockito and no
context. That rule belongs to the products, and DSH will record it in its own
`.github/copilot/rules/testing-patterns.md`; this repository states only the mechanism and the
naming convention. What an integration test *starts* beyond that — an embedded server, a
container, nothing at all — is never this repository's business. That is the whole reason the
shared change is a `-D` and not a server.

### D3 — the `integration` package is a convention, not a rule

The failsafe `<includes>` are name-based and already separate the two kinds. Requiring an
`integration` package on top of that needs a second enforcement mechanism (a custom enforcer
rule, or ArchUnit) to mean anything, and buys nothing the naming does not already buy. Document
the convention in the README source; enforce nothing.

### D4 — staging passes the flag, for every product, unconditionally

`project-staging.yml` already stands up `mongo:6` and `rabbitmq:3-management` as job services,
already takes `mongo_host` / `mongo_port` / `mongo_user` / `mongo_password` / `mongo_database`
inputs, and already has a "Create MongoDB user and database" step. The shared staging workflow
is product-shaped today; adding `-DintegrationTests` to its one `clean deploy` invocation is
consistent with that and costs one line.

It is a no-op for a product with no `*IT.java`, so the blast radius across the other consuming
repositories is zero on the day it ships.

The intended consequence, stated so it is not discovered later: a product that adds an
integration test needing a service the staging runner does not host will break **its own**
staging. That is correct pressure. Since this repository supplies only the flag, a product's
integration tests must be self-contained or must use the two services already present.

Only `project-staging.yml` changes. `project-release.yml`, `project-hotfix.yml` and
`project-stage.yml` are deliberately left alone — staging is the gate.

The site deployment step in the same workflow (`mvn … site-deploy`) must **not** get the flag:
it is the site lifecycle, and adding it there would run the integration tests a second time.

### D5 — documentation splits by audience

The root `README.md` is generated and must never be hand-edited; the source is
`src/site/markdown/README.md`, filtered by the `readme-generation` profile. That source gets a
short **Build from sources** section: the plain build, and the same build with
`-DintegrationTests`, plus the naming and package convention in one sentence. It is for someone
who wants to build this from source and nothing more.

`CLAUDE.md` carries the detail that drives agents and the development process, and gets its
false "Common commands" block corrected.

`src/site/markdown/index.md` is two lines and wants reshaping, but not here — see §6.

---

## 3. Out of scope

- **Re-tuning the coverage thresholds.** Untouched.
- **Any integration test in DSH that survives this work.** The proof in §5 uses a temporary test
  that is deleted before the branch is pushed. DSH's real integration tests arrive with its own
  issues (§6).
- **Reclassifying DSH's existing Spring-context tests.** Measured and scoped in §6; it is DSH
  work with a coverage bill attached and must not ride along here.
- **An integration-coverage report.** `jacoco-it.exec` is produced and left alone. Reporting on
  it is a later decision, made cheap by D1 and not pre-empted by it.
- **`project-release.yml`, `project-hotfix.yml`, `project-stage.yml`.** See D4.

---

## 4. Tasks

### Task 1: Add the `integration-tests` profile

**Files:**

- Modify: `pom.xml` — insert a new `<profile>` as the last child of `<profiles>`, immediately
  before the closing `</profiles>` (currently line 1159, after the `release-deployment` profile)

**Interfaces:**

- Produces: profile id `integration-tests`; activation property `integrationTests`; JaCoCo
  execution id `prepare-agent-integration` writing `${project.build.directory}/jacoco-it.exec`
  and setting the property `failsafeArgLine`. Tasks 2 and 5 depend on the property name.

- [ ] **Step 1: Insert the profile**

```xml
        <profile>
            <id>integration-tests</id>
            <!-- FR015: activated by -DintegrationTests property instead of -P to avoid Maven hierarchy merge bugs.
                 Promotes maven-failsafe-plugin out of <pluginManagement> (FR013) into the build, which is the only
                 thing that makes it execute. The second JaCoCo agent is not optional: maven-failsafe-plugin's
                 argLine defaults to ${argLine} (its plugin descriptor, <argLine>${argLine}</argLine>), which is the
                 very property jacoco:prepare-agent writes, and that agent appends to target/jacoco.exec. Without a
                 separate agent and a separate exec file, integration coverage lands in the file jacoco:check reads
                 and the 95% gate stops being a unit-test gate. -->
            <activation>
                <property>
                    <name>integrationTests</name>
                </property>
            </activation>
            <build>
                <plugins>
                    <plugin>
                        <groupId>org.jacoco</groupId>
                        <artifactId>jacoco-maven-plugin</artifactId>
                        <executions>
                            <execution>
                                <id>prepare-agent-integration</id>
                                <goals>
                                    <goal>prepare-agent-integration</goal>
                                </goals>
                                <!-- propertyName is load-bearing, not decoration. This goal's descriptor documents
                                     its fallback as "argLine" for jar packaging - the very property the unit agent
                                     writes. Delete this line and the integration agent overwrites the unit argLine,
                                     which is precisely the contamination this profile exists to prevent. destFile
                                     below restates the goal's documented default and is kept only for symmetry. -->
                                <configuration>
                                    <destFile>${project.build.directory}/jacoco-it.exec</destFile>
                                    <propertyName>failsafeArgLine</propertyName>
                                </configuration>
                            </execution>
                        </executions>
                    </plugin>
                    <plugin>
                        <groupId>org.apache.maven.plugins</groupId>
                        <artifactId>maven-failsafe-plugin</artifactId>
                        <!-- @{...} is surefire/failsafe's late replacement, resolved when the mojo runs rather
                             than during model interpolation, and it is the form both plugins document. It is a
                             safe default rather than a fix for a failure observed here: measured on failsafe
                             3.5.5 with JaCoCo 0.8.13, ${failsafeArgLine} produces a byte-identical
                             jacoco-it.exec, because prepare-agent-integration sets a project property before
                             failsafe executes. -Djacoco.skip=true does not leave the property undefined either -
                             JaCoCo still runs the goal and logs "failsafeArgLine set to empty". Keep @{...} for
                             the case where the property arrives by a path interpolated earlier; the line that
                             actually guards the coverage gate is propertyName above. -->
                        <configuration>
                            <argLine>@{failsafeArgLine}</argLine>
                        </configuration>
                    </plugin>
                </plugins>
            </build>
        </profile>
```

- [ ] **Step 2: Prove the profile is inert when the flag is absent**

```bash
mkdir -p .logs
mvn -B clean install > .logs/mvn-install.log 2>&1
echo "maven exit=$?"
grep -c "maven-failsafe-plugin" .logs/mvn-install.log
```

Expected: exit `0`, and the `grep -c` prints `0`. Failsafe must not appear in a build that did
not ask for it.

- [ ] **Step 3: Prove the profile activates on the flag**

```bash
mvn -B clean install -DintegrationTests > .logs/mvn-install-it.log 2>&1
echo "maven exit=$?"
grep -n "maven-failsafe-plugin\|prepare-agent-integration" .logs/mvn-install-it.log | head
```

Expected: exit `0`, and both `maven-failsafe-plugin` and `prepare-agent-integration` appear.
Every module here is `pom` packaging with no tests, so failsafe will report nothing to run —
that is correct, and Task 5 is where it runs against real classes.

- [ ] **Step 4: Commit**

```bash
git add pom.xml
git commit -m "feat(#67): activate failsafe behind a -DintegrationTests profile"
```

---

### Task 2: Make staging pass the flag

**Files:**

- Modify: `.github/workflows/project-staging.yml` — the `Build and Deploy Staging Artifacts`
  step, the `mvn -B -U … clean deploy` invocation (currently line 202)

**Interfaces:**

- Consumes: the `integrationTests` activation property from Task 1.

- [ ] **Step 1: Add the flag to the build invocation**

Change:

```yaml
          output=$(mvn -B -U \
            -Ddeployment \
            -Drelease.type=rcs \
            -Dbuild.number=RC${BUILD_NUM} \
```

to:

```yaml
          output=$(mvn -B -U \
            -Ddeployment \
            -DintegrationTests \
            -Drelease.type=rcs \
            -Dbuild.number=RC${BUILD_NUM} \
```

- [ ] **Step 2: Confirm the site step was not touched**

```bash
grep -n "integrationTests" .github/workflows/project-staging.yml
```

Expected: exactly one line, inside the `Build and Deploy Staging Artifacts` step. If
`Deploy Staging Site` also matches, remove it — `site-deploy` would run the integration tests a
second time.

- [ ] **Step 3: Confirm no other workflow was touched**

```bash
grep -rn "integrationTests" .github/workflows/
```

Expected: the single line from Step 1. `project-release.yml`, `project-hotfix.yml` and
`project-stage.yml` must not match (D4).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/project-staging.yml
git commit -m "feat(#67): run integration tests on staging builds"
```

---

### Task 3: Document the build in the README source

**Files:**

- Modify: `src/site/markdown/README.md` — add a section between `## Version` and
  `## Code Based Site`

- [ ] **Step 1: Add the section**

````markdown
## Build from Sources

```bash
# Unit tests only. This is the ordinary build, and the one the 95% coverage gate measures.
mvn -B clean install

# Unit tests, then integration tests.
mvn -B clean install -DintegrationTests
```

Integration tests are the classes named `*IT.java` or `*IntegrationTest.java`; by convention
they live in an `integration` package under `src/test/java`. They run only when
`-DintegrationTests` is passed, and on every staging build. Their coverage is collected
separately, in `target/jacoco-it.exec`, and is deliberately not counted toward the coverage
gate — that gate measures unit tests.
````

- [ ] **Step 2: Confirm the generated README was not hand-edited**

```bash
git status --porcelain
```

Expected: `src/site/markdown/README.md` modified, and **no** change to the root `README.md`.
The root file is regenerated by the `readme-generation` profile and any hand edit is lost.

- [ ] **Step 3: Commit**

```bash
git add src/site/markdown/README.md
git commit -m "docs(#67): document the integration-test build in the README source"
```

---

### Task 4: Correct `CLAUDE.md`

**Files:**

- Modify: `CLAUDE.md` — the `## Common commands` block, and the surefire sentence below it

- [ ] **Step 1: Replace the false integration-test block**

Replace:

```
# Integration tests only (naming convention: *IT.java or *IntegrationTest.java)
mvn -B verify
# (unit tests via surefire exclude *IT/*IntegrationTest; failsafe runs only those, bound to integration-test+verify)
```

with:

```
# Unit tests plus integration tests (naming convention: *IT.java or *IntegrationTest.java)
mvn -B clean install -DintegrationTests
# Without the flag, failsafe does not execute at all: it is declared in <pluginManagement> and
# only the integration-tests profile (FR015) promotes it into the build. Surefire excludes
# *IT/*IntegrationTest either way, so a test named that way runs only under the flag.
```

- [ ] **Step 2: Add the gate's scope to the sentence about lint and gates**

After the existing "There is no separate lint step…" paragraph, add:

```markdown
Integration tests never count toward the 95% `jacoco:check` gate. The `integration-tests`
profile attaches a second JaCoCo agent writing `target/jacoco-it.exec`, and `jacoco:check` reads
`target/jacoco.exec`. This is load-bearing: `maven-failsafe-plugin` defaults its `argLine` to
`${argLine}`, the property `jacoco:prepare-agent` writes, so without the second agent the
integration run appends straight into the file the gate measures. `project-staging.yml` passes
`-DintegrationTests`, so staging is where integration tests are mandatory; what a product's
integration tests *start* is that product's decision, not this repository's.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(#67): correct the integration-test commands in CLAUDE.md"
```

---

## 5. Verification, end to end, in DSH

`#67`'s last acceptance criterion is "verified end to end from a consuming project pointed at the
new `-SNAPSHOT`". DSH's root `pom.xml` already names
`com.mriss.mriss-parent:products:3.9.0-SNAPSHOT`, so no temporary re-pin is needed — round-trip
step 4 is already satisfied.

DSH has no `*IT.java` today, so the proof needs a temporary one. It is deleted before anything is
pushed; DSH's real integration tests arrive with its own issues (§6).

- [ ] **Step 1: Install this branch's parent locally**

In the parent-poms working copy:

```bash
mkdir -p .logs
mvn -B install > .logs/mvn-install.log 2>&1
echo "maven exit=$?"
```

Expected: exit `0`. Without this the DSH runs below resolve the previously deployed
`3.9.0-SNAPSHOT` and prove nothing.

- [ ] **Step 2: Record the unit-coverage baseline in `dsh-data`**

In a DSH working copy, on a scratch branch (`git checkout -b scratch-67-proof`):

```bash
mkdir -p .logs
mvn -B -pl dsh-data -am clean install > .logs/mvn-baseline.log 2>&1
echo "maven exit=$?"
grep -n "Analyzed bundle\|coverage\|All coverage checks have been met" .logs/mvn-baseline.log | tail -5
ls -l dsh-data/target/jacoco*.exec
```

Expected: exit `0`, the coverage check passes, and `dsh-data/target/jacoco.exec` exists with no
`jacoco-it.exec` beside it. Write the reported LINE and BRANCH figures down — Step 5 compares
against them.

- [ ] **Step 3: Add a temporary passing integration test**

Create `dsh-data/src/test/java/com/mriss/dsh/data/integration/TemporaryProofIT.java`:

```java
package com.mriss.dsh.data.integration;

import static org.junit.Assert.assertNotNull;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.springframework.context.ApplicationContext;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.context.junit4.SpringRunner;

/**
 * Temporary. Exists only to prove parent-poms #67 end to end, and is deleted
 * before this branch is pushed. It starts a Spring context and nothing else,
 * so it needs no server, no database and no broker.
 */
@RunWith(SpringRunner.class)
@ContextConfiguration(classes = TemporaryProofIT.Config.class)
public class TemporaryProofIT {

    @Configuration
    static class Config {
    }

    @Autowired
    private ApplicationContext context;

    @Test
    public void contextStarts() {
        assertNotNull(context);
    }
}
```

- [ ] **Step 4: Prove the ordinary build still ignores it**

```bash
mvn -B -pl dsh-data -am clean install > .logs/mvn-no-flag.log 2>&1
echo "maven exit=$?"
grep -n "TemporaryProofIT" .logs/mvn-no-flag.log
```

Expected: exit `0`, and **no** match for `TemporaryProofIT`. This is acceptance criterion 1 —
`mvn clean install` runs unit tests only.

- [ ] **Step 5: Prove the flag runs it, and that the gate did not move**

```bash
mvn -B -pl dsh-data -am clean install -DintegrationTests > .logs/mvn-flag.log 2>&1
echo "maven exit=$?"
grep -n "TemporaryProofIT" .logs/mvn-flag.log
ls -l dsh-data/target/jacoco*.exec
grep -n "Analyzed bundle\|All coverage checks have been met" .logs/mvn-flag.log | tail -5
```

Expected: exit `0`; `TemporaryProofIT` runs under failsafe; **both** `jacoco.exec` and
`jacoco-it.exec` exist in `dsh-data/target/`; and the reported LINE and BRANCH figures are
**identical** to Step 2's. That identity is the proof of D1 — acceptance criterion 2, and the
answer to the issue's second open question.

- [ ] **Step 6: Prove a failing integration test fails the build**

Change the assertion in `TemporaryProofIT` to `assertNull(context)` (importing
`org.junit.Assert.assertNull`), then:

```bash
mvn -B -pl dsh-data -am clean install -DintegrationTests > .logs/mvn-flag-fail.log 2>&1
echo "maven exit=$?"
grep -n "TemporaryProofIT\|BUILD FAILURE" .logs/mvn-flag-fail.log | head
```

Expected: exit **non-zero**, with the failure attributed to failsafe's `verify` goal. This is
acceptance criterion 3. Restore the assertion to `assertNotNull` afterwards.

- [ ] **Step 7: Prove it on staging**

Push this branch's parent to the snapshot repository so a cloud runner can resolve it — in
parent-poms, dispatch `deploy.yml` with `release_type: snapshots`. Then push the DSH scratch
branch with `TemporaryProofIT` (passing) still on it, and run DSH's `Staging` workflow against
it.

Expected: the staging log shows `-DintegrationTests` on the `clean deploy` invocation and shows
`TemporaryProofIT` running. This is acceptance criterion 5, and the only proof of Task 2.

- [ ] **Step 8: Remove every trace of the proof**

```bash
rm dsh-data/src/test/java/com/mriss/dsh/data/integration/TemporaryProofIT.java
git status --porcelain
```

Expected: the DSH working copy is clean apart from the scratch branch itself, which is deleted
locally and on the remote. Nothing from this section is merged into DSH.

- [ ] **Step 9: Record the evidence**

Append a short "Verification" section to this spec with the exit codes and the two coverage
figures from Steps 2 and 5, and the staging run URL from Step 7. Commit it.

```bash
git add specs/67-activate-failsafe-integration-tests.md
git commit -m "docs(#67): record the end-to-end verification evidence"
```

---

## 6. What this spins off

Two issues came out of this work. Neither is on the `3.9.0-SNAPSHOT` milestone — that milestone is
being cleared so `3.9.0` can be released, and adding open issues to it works against that.
`3.10.0-SNAPSHOT` was opened here to hold the second one.

### 6.1 DSH `#112` — reclassify the existing Spring-context tests

Under D2, DSH already has integration tests in the wrong place. Measured:

| Module | Test classes | Spring-context | Production sources |
|---|---|---|---|
| `dsh-doc-indexer-worker` | 1 | 1 (`@SpringBootTest`) | 1 |
| `dsh-doc-analyser/dsh-keyword-extractor` | 1 | 1 (`@SpringBootTest`) | 1 |
| `dsh-doc-analyser/dsh-top-sentences-extractor` | 1 | 1 (`@SpringBootTest`) | 1 |
| `dsh-doc-analyser/dsh-doc-processor-worker` | 1 | 1 (`@SpringBootTest`) | 1 |
| `dsh-rest-api` | 7 | 3 | 14 |
| `dsh-data` | 8 | 1 (`SpringRunner` + `@ContextConfiguration`) | 13 |

Eight of DSH's twenty-five test classes start a context. Reclassifying them is not free:

- The four worker modules have exactly one test class each, and it *is* the `@SpringBootTest`
  smoke test. Move it out of surefire and the module produces no `target/jacoco.exec` at all,
  which trips `enforce-coverage-data-exists` and turns four modules red on every ordinary build.
- `dsh-rest-api` loses `DocumentResourceTest` (`@SpringBootTest` + MockMvc over the resource)
  and `DocumentHandlingServiceImplTest` from the unit measurement; `dsh-data` loses
  `DocumentTest`. The resulting percentages have not been measured.

The bill is paid with unit tests, never with a per-module `-Dcoverage.data.check.skip=true`
exemption. The four worker mains are each `SpringApplication.run(...)` plus a log line, so a
`Mockito.mockStatic(SpringApplication.class)` test covers both lines with no context, produces
the `jacoco.exec` the guard wants, and keeps the module in the gate. Only as a last resort, and
only for a genuinely untestable class, is a module-level JaCoCo `<excludes>` entry acceptable.

### 6.2 parent-poms `#74` — reshape `src/site/markdown/index.md`

It is two lines. It wants to say what this repository is and how the three levels relate. Out of
scope here; a milestone after `3.9.0`.

---

## 7. Risks

| Risk | Why it is acceptable |
|---|---|
| A product with an existing `*IT.java` starts running it on staging without warning | No such file exists in DSH. The flag is opt-in everywhere except staging, and staging is exactly where the gate is wanted (D4). |
| `@{failsafeArgLine}` resolves to nothing and integration tests run without the agent | They still run, and still gate the build. Only `jacoco-it.exec` is lost, which nothing reads today. Measured during review (§8.1): the property is never actually absent, because JaCoCo sets it even when skipped. |
| Plugin ordering inside `verify` puts `jacoco:check` after failsafe's `verify` | Irrelevant under D1: the two read different files. It is only load-bearing for the rejected single-exec design. |
| The staging proof (§5 Step 7) needs a snapshot deploy of an unmerged branch | `deploy.yml` with `release_type: snapshots` does not bump a version, tag, or touch a milestone. It is the documented way to make an in-progress parent visible to a consumer. |

---

## 8. Verification

Run 2026-09-20. Maven 3.9.16 locally (CI pins 3.9.9), JDK 17.0.20.1. DSH commit `fab55a69`
plus the temporary proof, on the scratch branch `scratch-67-proof`, against
`com.mriss.mriss-parent:products:3.9.0-SNAPSHOT` built from this branch.

### The defect, reproduced before the fix

With `TemporaryProofIT` present and the **unchanged** parent installed:
`mvn -B -pl dsh-data -am clean install -DintegrationTests` exited `0`, ran 51 unit tests, and
matched `TemporaryProofIT` **0 times** and `maven-failsafe-plugin` **0 times**. The test ran
nowhere and nothing said so — §1.1, observed rather than argued.

### Local runs

| Step | Command | Exit | Evidence |
|---|---|---|---|
| Task 1.2 | `mvn -B clean install` (parent-poms) | `0` | `maven-failsafe-plugin` matched **0** times |
| Task 1.3 | `mvn -B clean install -DintegrationTests` | `0` | `failsafe:3.5.5:integration-test`, `failsafe:3.5.5:verify` and `prepare-agent-integration` all present |
| Task 2.2 | `grep -n integrationTests .github/workflows/project-staging.yml` | — | exactly one line, 204, in `Build and Deploy Staging Artifacts` |
| Task 2.3 | `grep -rn integrationTests .github/workflows/` | — | that one line only; release, hotfix and stage untouched |
| Task 3.2 | `git status --porcelain` | — | only `src/site/markdown/README.md`; root `README.md` untouched |
| §5.1 | `mvn -B install` (parent-poms) | `0` | parent installed to `D:\.m2\repository` |
| §5.2 | `mvn -B -pl dsh-data -am clean install` | `0` | 28 classes, gate met, only `jacoco.exec` |
| §5.4 | same, no flag, IT present | `0` | `TemporaryProofIT` matched **0** times |
| §5.5 | same `-DintegrationTests` | `0` | IT ran under failsafe; **both** `jacoco.exec` and `jacoco-it.exec` present |
| §5.6 | same, assertion inverted to `assertNull` | **`1`** | `failsafe:3.5.5:verify (integration-tests) @ dsh-data`; the coverage gate passed immediately before it |
| extra | `mvn -B clean install -DintegrationTests` (full reactor) | `0` | all 13 modules SUCCESS; `jacoco-it.exec` produced **only** in `dsh-data` |

### D1: the gate did not move

Measured from `dsh-data/target/site/jacoco/jacoco.csv`, generated from `jacoco.exec` alone:

| | Baseline (§5.2) | With `-DintegrationTests` (§5.5) |
|---|---|---|
| LINE | 235/242 = `0.971074` | 235/242 = `0.971074` |
| BRANCH | 81/82 = `0.987805` | 81/82 = `0.987805` |

Identical. Integration coverage landed in `jacoco-it.exec` and `jacoco:check` never saw it —
acceptance criterion 2, and the answer to the issue's second open question.

### §5.7: staging

- parent-poms `deploy.yml`, `release_type: snapshots`, on this branch —
  [run 35540724375](https://github.com/MRISS-Projects/parent-poms/actions/runs/35540724375),
  success; published `mriss-parent-3.9.0-20260920.220906-3.pom` (62 kB).
- DSH `Staging` against `scratch-67-proof` —
  [run 35541203622](https://github.com/MRISS-Projects/dsh/actions/runs/35541203622), success.
  `-DintegrationTests` appears on the `clean deploy` invocation and **exactly once in the whole
  25 331-line log**, so `site-deploy` did not receive it (D4). `TemporaryProofIT` ran on the
  runner; 13 `failsafe:integration-test` executions; 8 modules reported
  `All coverage checks have been met`.

One caveat on the method, not the change: DSH pins `project-staging.yml@master`, so the staging
run could only exercise Task 2 by temporarily repointing DSH's `staging.yml` at this branch. That
pin lived on `scratch-67-proof` and died with it. Once this branch is merged and released, DSH
picks the flag up from `master` with no change of its own.

### 8.1 Correction found in review: the `@{...}` rationale was wrong

The comment originally shipped on the failsafe plugin claimed that `${failsafeArgLine}` "would
reach the forked JVM verbatim and fail it with an unrecognized option", citing
`-Djacoco.skip=true` as the case where the property is absent. Both halves are false, and the
measurement is cheap, so it was made rather than argued.

| Run | `argLine` form | `-Djacoco.skip` | Result |
|---|---|---|---|
| A | `@{failsafeArgLine}` | `true` | exit `0`, IT ran |
| B | `${failsafeArgLine}` | `true` | exit `0`, IT ran |
| B2 | `${failsafeArgLine}` | absent | exit `0`, IT ran, `jacoco-it.exec` **128 240 bytes — byte-identical to the `@{...}` run** |

Two things came out of it:

- **The property is never absent.** With `-Djacoco.skip=true` JaCoCo still executes the goal and
  logs `failsafeArgLine set to empty`, which is exactly the case the plugin's own skip path exists
  to cover. So neither form can degrade into a literal here.
- **`${...}` works.** Plugin parameters are resolved when the mojo executes, against project
  properties, and `prepare-agent-integration` has set the property by then. B2's agent attached
  and wrote the same exec file.

`@{...}` is kept, because it is the form surefire, failsafe and JaCoCo all document and it stays
correct if the property ever arrives by a path interpolated earlier. But it is a safe default, not
the thing holding the design up. **`<propertyName>` is.** Its descriptor documents the fallback as
`argLine` — the unit agent's property — so removing it as "redundant" would silently restore the
contamination in §1.2 while leaving every build green. The comment in Task 1 now says so, because
that is the line a future reviewer is most likely to delete.

### 8.2 Review round 1 — PR [`#75`](https://github.com/MRISS-Projects/parent-poms/pull/75)

2026-09-21. Pulled from GitHub, not from recollection.

| | |
|---|---|
| CI | `build` **SUCCESS**, 7m25s — [run 35548385585](https://github.com/MRISS-Projects/parent-poms/actions/runs/35548385585) |
| Review | `copilot-pull-request-reviewer`, state `COMMENTED`, "Approval recommended" |
| Effort | **Lite** — self-reported in the review body |
| Findings | none |
| Threads | 0 opened, so none to reply to or resolve |
| Commit reviewed | `0cc7f904`, which was `HEAD` — no finding could be stale |

Nothing to triage and nothing to fix, so this round changed no code.

**Read the zero-findings result for what it is.** The review arrived automatically about three
minutes after the PR opened, which means it ran at the repository or organization default rather
than at a level chosen for this PR; the body confirms **Lite**. Lite is described by GitHub as
cost-efficient and targeted. Zero findings at that level, on a change to shared build
infrastructure that every consuming product inherits, is weak evidence that there was nothing to
find — not strong evidence that the change is correct.

The substantive review of this change was the local one in §8.1, and it did find something: a
committed comment asserting a failure mode that measurement disproved. That is the calibration to
carry forward. If a later reader wants real review assurance on a change at this level of the
hierarchy, request **Balanced** explicitly on the PR; it is a human action at every layer and
cannot be selected from a workflow or a file in this repository.
