# Spec: filter classpath resources with `@…@` only (`#110`)

| | |
|---|---|
| Issue | [`#110`](https://github.com/MRISS-Projects/parent-poms/issues/110): Filter classpath resources with `@…@` only, as spring-boot-starter-parent does |
| Milestone | `3.11.1-SNAPSHOT`, a hotfix: the only issue on it |
| Branch | `issue-110-filter-classpath-resources-with-at-delimiter`, cut from `master` at `ae7aaf83` |
| Asked for by | [`MRISS-Projects/dsh#158`](https://github.com/MRISS-Projects/dsh/issues/158), whose spec is `specs/stories/158-stop-maven-filtering-spring-placeholders.md` in DSH |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** In a product, a `${…}` in a filtered file on the classpath reaches the jar as written,
for Spring to resolve at run time, while `@name@` is still replaced by Maven.

**Architecture.** One `maven-resources-plugin` entry in `products/pom.xml` `pluginManagement`
configures the two lifecycle executions, `default-resources` and `default-testResources`, with
`useDefaultDelimiters=false` and the single delimiter `@`. No other execution changes. No workflow
changes.

## 1. What is true today

1. **`products` is the Spring Boot parent of every product, without being
   `spring-boot-starter-parent`.** It imports `spring-boot-dependencies` and manages
   `spring-boot-maven-plugin`. `spring-boot-starter-parent` also sets `resource.delimiter=@` and
   configures `maven-resources-plugin` with `useDefaultDelimiters=false`. A product of `products`
   does not get that.
2. **So a product filters with both default delimiters, `${…}` and `@…@`.** Neither the root POM
   nor `products` declares `<build><resources>` or a delimiter. `${…}` is also Spring's placeholder
   syntax, so a Spring placeholder in a filtered `application.properties` is replaced at build time
   by any Maven property of the same name. DSH measured it (dsh `#48`, finding M1, probes P18 to
   P20): the jar held the build-time value, and the run-time value was ignored, with no warning.
3. **Products also filter Markdown with `${…}`, on purpose, in `copy-resources` executions.** DSH's
   `copy-site-resources-for-pdf` filters its site Markdown, and the `readme-generation` profile's
   `copy-readme-md` execution, in the root POM here, fills the README's `${…}` tokens. Those must
   keep both delimiters.
4. **`master` holds nothing beyond 3.11.0.** `git log mriss-parent-3.11.0..origin/master` is empty.

## 2. Design

### 2.1 The rule

In `products/pom.xml`, `<build><pluginManagement><plugins>`, after `spring-boot-maven-plugin`. The
version comes from the root `pluginManagement` (`${resources.plugin.version}`, 3.3.1):

```xml
<!-- Classpath resources are filtered with @...@ only, as spring-boot-starter-parent does:
     ${...} is Spring's placeholder syntax, and Maven must leave it for Spring to resolve
     at run time. Only the two lifecycle executions are configured, so a copy-resources
     execution, such as the ones that filter site Markdown with ${...}, keeps both
     delimiters. A product turns filtering on per resource; this sets only what is replaced. -->
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-resources-plugin</artifactId>
    <executions>
        <execution>
            <id>default-resources</id>
            <configuration>
                <useDefaultDelimiters>false</useDefaultDelimiters>
                <delimiters>
                    <delimiter>@</delimiter>
                </delimiters>
            </configuration>
        </execution>
        <execution>
            <id>default-testResources</id>
            <configuration>
                <useDefaultDelimiters>false</useDefaultDelimiters>
                <delimiters>
                    <delimiter>@</delimiter>
                </delimiters>
            </configuration>
        </execution>
    </executions>
</plugin>
```

`pluginManagement` executions merge into the lifecycle's executions by ID, so a product gets the
rule without declaring anything.

### 2.2 Rejected alternatives

- **The rule in the plugin's own `<configuration>`, as `spring-boot-starter-parent` writes it.**
  Every execution inherits plugin-level configuration, so `copy-readme-md` and every product's
  Markdown `copy-resources` would lose `${…}` (§1.3).
- **The rule in the root POM.** Only products are Spring Boot applications; the infrastructure
  modules have no Spring configuration to protect.
- **No filtering at all.** It removes the hazard just as well, but shuts a door a product may need:
  stamping a build value with `@name@`.

### 2.3 The release

Hotfix 3.11.1. `master` is re-versioned from `3.12.0-SNAPSHOT` to `3.11.1-SNAPSHOT`, as for 3.9.2
(`d5a80948`). Only the eight POMs at `3.12.0-SNAPSHOT` change. `set-version.sh` is not used, for the
reason `d5a80948` gives: `release:update-versions` also moves the independently released modules'
parents and reformats every POM. Run on this branch, it changed 15 files, 49 lines in and 71 out.
Releasing with `deploy.yml` (`release_type: releases`) advances `master` to `3.12.0-SNAPSHOT` again.

## 3. Acceptance criteria

- **AC001.** Against `3.11.1-SNAPSHOT`, DSH's `ClasspathResourceFilteringTest` passes; against
  3.10.0 it fails on `${project.version}` being replaced. (Task 2.)
- **AC002.** In a product's effective POM, `default-resources` and `default-testResources` carry
  the `@` delimiter only, and `copy-resources` executions do not. (Task 2.)
- **AC003.** DSH's site Markdown and generated README are unchanged. (Task 2.)
- **AC004.** `mvn -B clean install` is green here. (Task 1.)
- **AC005.** 3.11.1 is released, and milestone `3.11.1-SNAPSHOT` has no open issue. (Task 3.)

## 4. Tasks

### Task 1: the re-version and the rule (AC004)

- [ ] **Step 1:** re-version the eight POMs to `3.11.1-SNAPSHOT` (§2.3). `git grep -n
  '3.12.0-SNAPSHOT' -- '*pom.xml'` finds nothing. Commit `build(#110): re-version master to
  3.11.1-SNAPSHOT for the hotfix line`.
- [ ] **Step 2:** add the entry of §2.1 to `products/pom.xml`, then `mvn -B clean install`.
  Expected: exit 0, and `products/3.11.1-SNAPSHOT` in the local repository. Commit
  `build(#110): filter classpath resources with @...@ only`.

### Task 2: verified in DSH (AC001–AC003)

DSH's story `#158` pins DSH on `3.11.1-SNAPSHOT` and runs its red/green test, its effective-POM
check and its site and README comparison. The results are recorded in DSH's spec, §7.

### Task 3: the release (AC005)

- [ ] **Step 1:** after the pull request is merged, dispatch `deploy.yml` with
  `release_type: snapshots`, so DSH's CI resolves `3.11.1-SNAPSHOT`.
- [ ] **Step 2:** after DSH's check passes in CI and the owner closes `#110`, dispatch `deploy.yml`
  with `release_type: releases`. Check that tag `mriss-parent-3.11.1` exists and that `master` is
  at `3.12.0-SNAPSHOT`.

## 5. Out of scope

- Turning filtering on or off in any product: that is each product's `<resources>`. DSH does it in
  `#158`.
- `resource.delimiter` as a property. Nothing here reads it.
