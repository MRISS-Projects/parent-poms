# Spec: manage `mockito-junit-jupiter` at `mockito-core`'s version (`#112`)

| | |
|---|---|
| Issue | [`#112`](https://github.com/MRISS-Projects/parent-poms/issues/112): Manage mockito-junit-jupiter at mockito-core's version |
| Milestone | `3.11.2-SNAPSHOT`, a hotfix. DSH's `#120` adds its own issue to it, and 3.11.2 is released when that one is done |
| Branch | `issue-112-manage-mockito-junit-jupiter`, cut from `master` at `1dab0893` |
| Asked for by | [`MRISS-Projects/dsh#119`](https://github.com/MRISS-Projects/dsh/issues/119), whose spec is `specs/stories/119-migrate-tests-to-junit-5.md` in DSH |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** In a product, `mockito-junit-jupiter` resolves to the same version as `mockito-core`.

**Architecture.** One `dependencyManagement` entry in the root `pom.xml`, beside `mockito-core`'s,
at `${mockito.version}`. No property, plugin or workflow changes.

## 1. What is true today

1. **The root `pom.xml` manages `mockito-core` alone**, at `${mockito.version}` (5.17.0), test
   scope. Nothing manages `mockito-junit-jupiter`.
2. **So a product gets the extension from Spring Boot's BOM**, which `products/pom.xml` imports:
   `mockito-junit-jupiter` 4.5.1 under Boot 2.7.18. An explicit entry inherited from the root beats
   an imported one, which is why `mockito-core` is 5.17.0 and its extension is not. DSH measured it
   on 2026-10-21 with `mvn dependency:tree -Dincludes=org.mockito`.
3. **The pair works, mismatched, but by accident.** In a scratch product of `products:3.11.1`, a
   `MockitoExtension` test passed with the extension at 4.5.1 and at 5.17.0, both on Boot 2.7.18's
   Jupiter 5.8.2 (DSH `#119` spec, §2.2). Nothing ties the two versions together.

## 2. Design

### 2.1 The entry

In the root `pom.xml`'s `dependencyManagement`, after `mockito-core`:

```xml
            <dependency>
                <groupId>org.mockito</groupId>
                <artifactId>mockito-junit-jupiter</artifactId>
                <version>${mockito.version}</version>
                <scope>test</scope>
            </dependency>
```

One property then sets both artifacts, whatever the Spring Boot line's BOM says. That matters for
DSH `#120`'s Spring Boot upgrade: the newer BOM manages its own Mockito, and the explicit pair keeps
winning over it.

### 2.2 Rejected alternatives

- **Importing `mockito-bom`.** It would manage every Mockito artifact, but an import's precedence
  against `spring-boot-dependencies`, imported by `products`, depends on declaration order across
  two POMs. Two explicit entries win without that subtlety.
- **Managing it in DSH.** The gap is here: this POM pins one Mockito artifact and not its sibling,
  so every product using `MockitoExtension` has it.

### 2.3 The release

Hotfix 3.11.2. `master` is re-versioned from `3.12.0-SNAPSHOT` to `3.11.2-SNAPSHOT`, as for 3.11.1
(`efe85b4e`) and 3.9.2 (`d5a80948`): only the eight POMs at `3.12.0-SNAPSHOT` change, by hand, not
with `set-version.sh`. `master` holds nothing past tag `mriss-parent-3.11.1` but two `docs(#110)`
commits. 3.11.2 is released after DSH `#120`'s issue in the same milestone is done, not in this
issue; that release advances `master` to `3.12.0-SNAPSHOT` again.

## 3. Acceptance criteria

- **AC001.** Against `3.11.2-SNAPSHOT`, DSH's `mvn dependency:tree -Dincludes=org.mockito` lists
  `mockito-junit-jupiter:5.17.0` beside `mockito-core:5.17.0`; against 3.11.1, `4.5.1`. (Task 2.)
- **AC002.** DSH's `mvn -B clean install`, its tests on `MockitoExtension`, is green against
  `3.11.2-SNAPSHOT`. (Task 2.)
- **AC003.** `mvn -B clean install` is green here. (Task 1.)

## 4. Tasks

### Task 1: the re-version and the entry (AC003)

- [ ] **Step 1:** re-version the eight POMs to `3.11.2-SNAPSHOT` (§2.3). `git grep -n
  '3.12.0-SNAPSHOT' -- '*pom.xml'` finds nothing. Commit `build(#112): re-version master to
  3.11.2-SNAPSHOT for the hotfix line`.
- [ ] **Step 2:** add the entry of §2.1, then `mvn -B clean install`. Expected: exit 0, and
  `products/3.11.2-SNAPSHOT` in the local repository. Commit
  `build(#112): manage mockito-junit-jupiter at mockito-core's version`.

### Task 2: verified in DSH (AC001, AC002)

DSH's story `#119` pins DSH on `3.11.2-SNAPSHOT`, compares the Mockito tree before and after, and
runs its gates with every test on `MockitoExtension`. The results are recorded in DSH's spec, §7.

### Task 3: the snapshot

- [ ] **Step 1:** after the pull request is merged, dispatch `deploy.yml` with
  `release_type: snapshots`, so DSH's CI resolves `3.11.2-SNAPSHOT`.

## 5. Out of scope

- The release of 3.11.2: after DSH `#120`.
- `junit:junit`'s managed version. Other products may still use JUnit 4; DSH bans it in its own
  POM.
- Any JUnit 5 version. Spring Boot's BOM manages it.

## 6. Results

Filled in by the tasks.
