# Spec: consumer-supplied Maven properties for the reusable workflows (`#76`)

| | |
|---|---|
| Issue | [`#76`](https://github.com/MRISS-Projects/parent-poms/issues/76) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-76-consumer-supplied-maven-properties`, cut from `master` at `035df5f4` |
| Requesting project | `MRISS-Projects/dsh` — `#114`, Wave 0, `specs/product/PRD.md` §4 |
| Found by | [`#72`](https://github.com/MRISS-Projects/parent-poms/issues/72), merged as PR `#77` |
| Splits off | [`#78`](https://github.com/MRISS-Projects/parent-poms/issues/78) — the rest of `project-staging.yml`'s consumer-specific content |
| Consuming twin | [`dsh#114`](https://github.com/MRISS-Projects/dsh/issues/114), whose spec `specs/stories/114-supply-build-properties-to-release-wrappers.md` is the other half of this round trip |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This repository has no Java source, so the only thing here provable by a unit test is the one
> shell script that carries logic — and it is written test-first, in the style `#71` and `#72`
> established under `.github/actions/`. Everything else is verified by rendering a real
> `settings.xml` and diffing it, or by dispatching a workflow in `MRISS-Projects/dsh` and reading
> the run. Those runs are specified exactly; do not substitute a different command and assume the
> same output.

**Goal.** `project-release.yml`, `project-hotfix.yml` and `project-staging.yml` accept one
`maven_properties` input — a multi-line `name=value` block, default empty — and render it into the
`<properties>` of the `github-packages` profile in the `settings.xml` they write. A consumer whose
build needs a project-specific property can supply it; this repository never learns what it is
called. With the input empty, the generated `settings.xml` is byte-identical to today's.

**Architecture.** One composite action, `.github/actions/maven-properties`, wrapping one POSIX
shell script that rewrites a marker line in a file already on disk. Each workflow keeps its
quoted heredoc unchanged except for one marker comment inside `<properties>`, and gains one step
after the settings are written. The script validates every line before it becomes XML, and deletes
the marker when there is nothing to render — which is what makes the byte-identical guarantee a
fact rather than a hope.

**Tech stack.** GitHub Actions composite actions, POSIX shell (`sh`, not `bash`), `awk`. Maven
**3.9.9** — what every workflow here pins via `stCarolas/setup-maven`. No new action dependency.

---

## Global constraints

- **With `maven_properties` empty, every generated `settings.xml` is byte-identical to today's.**
  Task 9 proves it by diff, not by reading. This is the property that lets a consumer upgrade
  without reading this spec.
- **No property name, service name or hostname belonging to one consumer enters this repository.**
  That is the rule `#67` set and this issue exists to extend. The three `mongo_*` inputs that
  survive in `project-staging.yml` are `#78`'s — see §4.3, which explains exactly why they cannot
  leave with this change.
- **The settings heredocs stay quoted** — `<< 'SETTINGS_EOF'`. They contain `${env.DEPLOY_TOKEN}`
  and `${env.GITHUB_ACTOR}`, which Maven resolves and the shell must not. Any design that
  interpolates the properties into the heredoc directly is wrong for this reason alone.
- **The script is `sh`, not `bash`**, matching `check-placeholders.sh` and the rehearsal scripts,
  and its test suite runs as `sh <file>` in `build.yml`.
- **Every `.sh` under `.github/actions/` is committed mode `100755`.** `build.yml`'s
  "Check the action scripts are executable" step enforces it uniformly and its comment explains
  why the rule is not narrowed. On a Windows checkout `chmod +x` records nothing, so use
  `git update-index --chmod=+x <file>`.
- **Nothing in this change alters what a release does.** No Maven command line changes, no step is
  reordered, and no existing step gains an `if:`.

---

## 1. The defect

Both release workflows write their own `settings.xml` and then run `clean install` through
`<preparationGoals>` inside `release:prepare` (`pom.xml:371`). A consumer whose build needs a
project-specific property at that point has nowhere to put it.

`MRISS-Projects/dsh` filters `dsh-data/src/main/resources/mongo.properties`, four lines of
`mongo.x=${mongo.x}`. Its own `ci.yml` supplies the four values from the settings profile it
writes; `project-release.yml` defines none of them. The placeholder survives filtering, and every
`dsh-rest-api` Spring context fails with
`Circular placeholder reference 'mongo.port' in property definitions`. The reactor dies at phase 10
of 17 — [run 35650261302](https://github.com/MRISS-Projects/parent-poms/actions/runs/35650261302).
Supplying the four properties and changing nothing else took the identical command through all 17
phases — [run 35651368119](https://github.com/MRISS-Projects/parent-poms/actions/runs/35651368119).

### 1.1 Why `-D` cannot be the mechanism

Measured in `#72`, not assumed. `release:prepare` forks `clean install` with only `<arguments>`,
and `<arguments>` is bound in `<configuration>` at `pom.xml:367`, so `-Darguments=…` is inert —
the same user-property trap as `#69`. Run 35651368119 recorded

```text
exec.additionalArguments=-Ddeployment -Drelease-deployment -Dproduct-release-deployment -Dsite.deployment.personal.main\=
```

carrying neither the `-Dbuild.*` flags nor the `-DdryRun` the outer `mvn` was given.

Settings-level properties **do** reach the fork, because it inherits the same
`~/.m2/settings.xml`. That is exactly what separated the two runs above.

### 1.2 Precedence, measured

`dsh#114` asked whether a settings-profile property still beats a POM `<properties>` default,
because if it did not, a consumer giving its POM defaults would silently shadow the live values its
CI supplies. Measured on Maven 3.9.9, a throwaway module with `${mongo.port}` filtered into a
resource:

| Where the value came from | Filtered result |
|---|---|
| POM `<properties>` default + active settings-profile property | `FROM_SETTINGS` |
| POM `<properties>` default, settings defining nothing | `POM_DEFAULT` |
| Both, plus `-Dmongo.port=FROM_CLI` | `FROM_CLI` |

**Command line > active settings profile > POM `<properties>`.** Two consequences for this spec:

1. Rendering into the settings profile is safe for a consumer that also has POM defaults, and
   safe for one that does not.
2. `project-staging.yml` may stop passing `-Dmongo.*` and let the same values arrive through the
   settings profile instead, because after that change nothing else defines them — the `-D` was
   outranking a value that will no longer exist. §4.3.

Full evidence and the commands that produced it are in `dsh`'s spec §4.

---

## 2. The mechanism

### 2.1 One input

Each of the three workflows gains, in `on.workflow_call.inputs`:

```yaml
      maven_properties:
        type: string
        required: false
        default: ''
        description: >-
          Build properties for this project, one `name=value` per line, rendered into the
          <properties> of the github-packages profile in the generated settings.xml. Empty
          means the settings file is unchanged.
```

`type: string` with a multi-line value is how a caller passes several: YAML block scalars work
through `workflow_call`, and `dsh`'s wrapper uses one.

### 2.2 One marker

Inside the `<properties>` block of each heredoc, directly under `<github.personal.token>`, at the
same 26-column indentation the surrounding XML uses in the workflow source:

```xml
                          <!-- MAVEN_PROPERTIES -->
```

The marker is a comment, so a `settings.xml` written but never post-processed is still valid XML.
It is replaced, or deleted, by the step in §2.3.

### 2.3 One step, one action

Immediately after each "Configure Maven settings" step:

```yaml
      - name: Render consumer Maven properties
        uses: MRISS-Projects/parent-poms/.github/actions/maven-properties@master
        with:
          properties: ${{ inputs.maven_properties }}
```

The action takes the properties and an optional `settings_file` (default `~/.m2/settings.xml`),
and runs `render-properties.sh`. The script is the only piece with logic, so it is the only piece
with tests.

### 2.4 What the script does

`render-properties.sh <settings-file>`, with the block in the `MAVEN_PROPERTIES` environment
variable — an environment variable, not an argument, so no quoting question arises for a value
containing newlines, spaces or shell metacharacters.

1. **Find the marker.** Exactly one line whose trimmed content is `<!-- MAVEN_PROPERTIES -->`.
   Zero occurrences is a fatal error: it means a workflow edit dropped it and the properties would
   be silently discarded. More than one is likewise fatal.
2. **Remember its indentation**, and render every element at that column. Reading the indentation
   from the marker rather than hard-coding 16 spaces keeps the script correct if a workflow ever
   indents differently.
3. **For each line of `MAVEN_PROPERTIES`:** strip a trailing `\r`, strip leading and trailing
   whitespace, skip the line if it is empty or begins with `#`.
4. **Validate.** The line must match `^[A-Za-z_][A-Za-z0-9._-]*=`. A line that does not is a
   fatal error naming **the line number and nothing else**. Two rules in one: this input
   becomes XML that a release build then trusts, so a name is rejected rather than escaped;
   and the start character must be one XML permits, or the tag is unparsable and Maven fails
   later on a file this script reported success for. A leading underscore is valid XML and
   stays allowed. The line itself is never quoted back — the block is where a consumer puts
   its passwords, and an Actions log is not the place to publish one.
5. **Split at the first `=` only**, so `flyway.url=jdbc:x?a=b` keeps its value intact.
6. **XML-escape the value** — `&` first, then `<` and `>`. Names need no escaping because step 4
   already restricted them to a safe alphabet.
7. **Rewrite the file in place:** the marker line is replaced by the rendered elements, or
   **removed entirely** when nothing was rendered, which restores the file to what it would have
   been without this feature.
8. **Report** what it did on stdout — the count, and each property *name*. Names only: a value may
   be a password, and `dsh` passes one today.

### 2.5 Failure modes, and why each is fatal rather than tolerated

| Situation | Behaviour | Why |
|---|---|---|
| Marker missing, duplicated, or carrying trailing content | exit non-zero, `::error::` | The properties would be dropped, and the build would fail later as an unresolved placeholder — the exact confusion `#76` exists to end. Matching is anchored to a whole line, so trailing text fails rather than being swallowed |
| Line without `=` | exit non-zero, names the line **number** | Almost always a caller pasting a `-D` flag or a stray word |
| Name outside `[A-Za-z_][A-Za-z0-9._-]*` | exit non-zero, names the line **number** | XML injection, or a tag no parser accepts, in a file the release build trusts |
| Settings file absent | exit non-zero | The step ran out of order |
| `MAVEN_PROPERTIES` empty or all blank lines | exit 0, marker deleted | The default path for every consumer that needs nothing |

---

## 3. Files

| File | Change |
|---|---|
| `.github/actions/maven-properties/action.yml` | **Create.** Composite action, two inputs. |
| `.github/actions/maven-properties/render-properties.sh` | **Create**, mode `100755`. §2.4. |
| `.github/actions/maven-properties/render-properties.test.sh` | **Create**, mode `100755`. §5. |
| `.github/workflows/project-release.yml` | Input (after `dry_run`, which ends at line 38), marker at line 129, step after line 153. |
| `.github/workflows/project-hotfix.yml` | Input (after `dry_run`, which ends at line 23), marker at line 110, step after line 134. |
| `.github/workflows/project-staging.yml` | Input, marker at line 141, step after line 165, and §4.3's removals. |
| `.github/workflows/build.yml` | Test loop generalised — §4.4. |
| `specs/github-actions-reusable-workflows.md` | Input tables — §4.5. |

---

## 4. What changes in each workflow

### 4.1 `project-release.yml`

Input, marker, step. Nothing else. `release:prepare`'s fork inherits the rendered
`~/.m2/settings.xml` because it inherits the same home directory — §1.1.

### 4.2 `project-hotfix.yml`

The same three edits. `project-hotfix.yml` runs the same `release:prepare` path, so a consumer that
needs properties for a release needs them for a hotfix.

### 4.3 `project-staging.yml`, and the input that cannot leave yet

Input, marker, step, plus two removals and one deliberate non-removal:

- **`mongo_host` and `mongo_port` are removed** (lines 29-38), and the `MONGO_FLAGS` construction
  in the build step (lines 196-199) goes with them, along with `$MONGO_FLAGS` on the `mvn` line.
  Both inputs feed nothing else. A consumer that needs them passes `mongo.host=…` and
  `mongo.port=…` through `maven_properties` like any other build property.
- **`mongo_user`, `mongo_password` and `mongo_database` stay**, and this is the one place this spec
  fails to reach `#76`'s AC003 in full. They are consumed by the "Create MongoDB user and database"
  step (lines 172-182) and its `if: ${{ inputs.mongo_user != '' }}` guard — setup logic, not build
  configuration. Removing the inputs without removing the step would break the only consumer using
  it.

  **This was found while specifying, and it corrects the issue body**, which said all four inputs
  would go. `#76`'s AC003 is therefore reworded: no consumer-specific name configures a *build* in
  this repository, and the three that remain are arguments to the setup step `#78` deletes. `#78`
  is where they leave.

  The cost, until `#78` lands, is that `dsh`'s staging wrapper names `dshuser` and `dshpass` twice
  — once in `maven_properties` for the build, once as inputs for the setup step. That duplication
  is visible, temporary and recorded in `dsh#114`'s spec, which is the right shape for a known
  interim state.

### 4.4 `build.yml`

The rehearsal test loop is globbed at `.github/actions/rehearsal-*/*.test.sh` (line 81), so a suite
under `maven-properties/` would never run. Generalise it to `.github/actions/*/*.test.sh`, which
then also covers `commit-readme/check-placeholders.test.sh` — so the dedicated step at line 73 is
removed as redundant, and the surviving step's comment carries both reasons, `#71`'s and `#72`'s,
plus this one.

The executable-bit check at line 100 needs no change and will cover the two new scripts
automatically. It will also fail the build if they are committed `100644`, which is the expected
outcome of committing them from a Windows checkout without `git update-index --chmod=+x`.

### 4.5 `specs/github-actions-reusable-workflows.md`

The per-workflow input tables in §6 are the documented contract and are already stale: `dry_run`
does not appear anywhere in the file, though `#72` shipped it on two workflows. Add
`maven_properties` to all three tables, and add the missing `dry_run` rows while in the same
tables — it is two rows, and leaving a known gap in a document this change is editing anyway would
be worse than the small scope creep.

---

## 5. The test suite

`render-properties.test.sh`, in the shape of `build-release-tag.test.sh`: a `check` helper, a
`$TMP` working directory removed by `trap`, one `pass`/`fail` line per case, non-zero exit if any
failed. Each case builds a small settings file containing the marker, sets `MAVEN_PROPERTIES`, runs
the script and asserts on the result.

| # | Case | Assertion |
|---|---|---|
| 1 | Empty `MAVEN_PROPERTIES` | Output is byte-identical to the same file with the marker line deleted |
| 2 | Only blank lines and `# comments` | Same as case 1 |
| 3 | One property | `<mongo.port>27017</mongo.port>` present, at the marker's indentation, marker gone |
| 4 | Four properties | All four rendered, in input order |
| 5 | Leading and trailing whitespace around a line | Trimmed, renders as case 3 |
| 6 | Trailing `\r` (CRLF input) | Stripped; no `\r` in the output file |
| 7 | Value containing `&`, `<`, `>` | Rendered as `&amp;`, `&lt;`, `&gt;`, and `&` not double-escaped |
| 8 | Value containing `=` (`flyway.url=jdbc:x?a=b`) | Split at the first `=` only |
| 9 | Empty value (`mongo.user=`) | Renders `<mongo.user></mongo.user>` |
| 10 | Line with no `=` | Exit non-zero; message names the line number |
| 11 | Name with a space or a `<` | Exit non-zero; message names the line number |
| 11a | Name starting with a digit, a dot or a hyphen | Exit non-zero — `<123foo>` is not an XML name |
| 11b | Name starting with an underscore | Accepted; XML permits it |
| 11c | A rejected line carrying a secret | The value appears nowhere in stdout or stderr |
| 12 | Marker missing | Exit non-zero; file unchanged |
| 13 | Marker duplicated | Exit non-zero; file unchanged |
| 13a | Marker line with trailing content | Exit non-zero; file unchanged |
| 13b | An unrelated line mentioning the marker, with a real marker present | Exit 0; the real marker is the one replaced |
| 14 | Settings file absent | Exit non-zero |
| 15 | A failing run leaves the file untouched | Render to a temp file and move on success only — asserted by comparing bytes after cases 10-13 |

Case 15 is the one worth stating as a design rule rather than a test: the script must not rewrite
in place incrementally. A half-rendered `settings.xml` would be valid XML with missing properties,
which fails later and further away.

---

## 6. Tasks

- [x] **Task 1 — the suite, red.** Write `render-properties.test.sh` with cases 1-3 from §5. Run
      `sh .github/actions/maven-properties/render-properties.test.sh`. Expected: fails, script not
      found. Commit the test alone.
- [x] **Task 2 — the script, green for 1-3.** Implement §2.4 far enough for the three cases. Run
      the suite. Expected: 3 passing. `git update-index --chmod=+x` both scripts, then commit.
- [x] **Task 3 — validation and escaping.** Add cases 4-15, run (red), implement, run (green).
      Commit.
- [x] **Task 4 — `action.yml`.** Composite action with `properties` (required, no default) and
      `settings_file` (default `~/.m2/settings.xml`), passing `properties` through the environment,
      never as an argument. Commit.
- [x] **Task 5 — `project-release.yml`.** Input, marker, step (§4.1). Commit.
- [x] **Task 6 — `project-hotfix.yml`.** The same (§4.2). Commit.
- [x] **Task 7 — `project-staging.yml`.** Input, marker, step, and the removals in §4.3. Commit.
- [x] **Task 8 — `build.yml`.** Generalise the test glob, remove the now-redundant step, rewrite the
      comment (§4.4). Commit.
- [x] **Task 9 — prove byte-identity.** Extract the settings heredoc from each of the three
      workflows as it stands on `master`, render the branch's version with `MAVEN_PROPERTIES`
      empty, and `diff` the two. Expected: no output, three times. Paste the commands and the
      empty diffs into the PR. **This is AC002, and reading the script is not a substitute.**
- [x] **Task 10 — docs.** `specs/github-actions-reusable-workflows.md` (§4.5). Commit.
- [ ] **Task 11 — validate against a real consumer.** With `dsh`'s wrappers pointed at
      `@issue-76-consumer-supplied-maven-properties`, dispatch `staging.yml` and confirm the
      Mongo-dependent tests pass with the values arriving through `maven_properties`; then
      dispatch `release.yml` with `dry_run: true` and confirm `release:prepare` completes its
      fork. Link both runs in the PR. This is AC004 and AC005, and it cannot be done from this
      repository alone.
- [x] **Task 12 — reconcile `#76`.** Update AC003 per §4.3 before the PR is reviewed, so the issue
      and the spec agree on what this change does and does not remove.

---

## 7. Acceptance criteria

- [ ] **AC001** — `project-release.yml`, `project-hotfix.yml` and `project-staging.yml` accept
      consumer-supplied Maven properties through one generic input.
- [ ] **AC002** — With the input empty, each generated `settings.xml` is byte-identical to today's.
      Proven by Task 9's three diffs.
- [ ] **AC003** — No consumer-specific name configures a build in this repository.
      `mongo_host`/`mongo_port` are gone and no `-Dmongo.*` is constructed anywhere. The three
      setup inputs that remain are `#78`'s, per §4.3.
- [ ] **AC004** — A release build of `dsh` that needs `mongo.*` completes `release:prepare` with
      the values supplied by `dsh`'s own wrapper.
- [ ] **AC005** — A dispatched `dsh` staging run still reaches its live MongoDB, with the four
      values arriving through the new input.
- [ ] **AC006** — An invalid `maven_properties` line fails the workflow at the rendering step, with
      a message naming the offending line. Covered by cases 10-11 and visible in the step's log.
- [ ] **AC007** — `build.yml` runs the new suite on every build, and the executable-bit check
      covers the new scripts.

---

## 8. Out of scope

- **`project-staging.yml`'s service containers, `mongo_database`, and the Mongo user-creation
  step.** [`#78`](https://github.com/MRISS-Projects/parent-poms/issues/78). A `name=value` input
  cannot reach them: a reusable workflow owns its own job, so a consumer cannot declare a service
  into it. §4.3 records the consequence for AC003.
- **`project-stage.yml` and `deploy.yml`.** Neither runs a build that filters resources.
  `project-stage.yml` runs `versions:set` and a commit. If a consumer ever needs properties there,
  the action added here is reusable in one step.
- **Consumer defaults of any kind.** This repository supplies the mechanism and never a value.
  `dsh` decided separately to add no POM defaults either; nothing here depends on that.
- **Releasing `3.9.0`.** The milestone still holds `#59`, `#65`, `#69`, `#70` and `#78`. `dsh`
  consumes these workflows at `@master` and its root POM already points at `3.9.0-SNAPSHOT`, so no
  release is needed for the consuming story to finish.

---

## 9. Build record

Written as the work was done, so a reviewer reads what happened rather than what was planned.

**Task 9's byte-identity proof, run on this branch.** The heredoc body is extracted from each
workflow on `master` and on this branch, the branch's copy is rendered with an empty block, and
the two are diffed:

```text
ok   - project-release: empty input renders byte-identical to master
ok   - project-hotfix: empty input renders byte-identical to master
ok   - project-staging: empty input renders byte-identical to master
ok   - project-release with two properties adds exactly: <mongo.host>localhost</mongo.host> <mongo.port>27017</mongo.port>
```

The fourth line is the positive control. Three empty diffs prove the feature is inert; without it
they would also pass for a script that does nothing at all.

**The test suite is 34 assertions**, all green, and `build.yml`'s generalised loop picks up all
seven suites under `.github/actions/` — verified by running the loop locally.

**Two findings recorded rather than silently fixed:**

1. **`project-staging.yml` can only lose two inputs, not four** (§4.3). `#76`'s body was corrected
   by Task 12 before review.
2. **The loop in `build.yml` would have skipped this action's suite entirely.** The glob was
   `rehearsal-*`. It is `*` now, with a guard that fails the step when the glob matches nothing —
   a silent zero-suite run is the failure mode that hid this in the first place.

**One deviation from §2.4 as written.** The rendering loop reads from a temporary file rather than
a pipe. In a pipeline the loop runs in a subshell, where `exit 1` on a rejected line ends the
subshell and lets the script render the rest of the block anyway — the validation would have
reported an error and then written the file. The test for a good line following a bad one is what
catches it.

---

## 10. Review round 1 — PR #79

Copilot raised three findings on `render-properties.sh`. **All three were valid**, each reproduced
at HEAD before being fixed, and each now has a test that would have caught it.

| Thread | Finding | Reproduction |
|---|---|---|
| [4082708674](https://github.com/MRISS-Projects/parent-poms/pull/79#discussion_r4082708674) | The rejection message quoted the whole line, which may hold a password | `MAVEN_PROPERTIES='mongo password=supersecret'` printed the secret into the log |
| [4082708735](https://github.com/MRISS-Projects/parent-poms/pull/79#discussion_r4082708735) | Marker matched as a substring, in the count and the rewrite | `<!-- MAVEN_PROPERTIES --> trailing` was accepted, rendered at column 0, trailing text destroyed |
| [4082708779](https://github.com/MRISS-Projects/parent-poms/pull/79#discussion_r4082708779) | Names that XML does not permit were accepted | `123foo=bar` rendered `<123foo>`; `javax.xml` rejects the result as unparsable |

**The first one is the one worth remembering.** §2.4 step 8 already said "names only: a value may
be a password" — for the *success* path. The error path was written without that thought, and
then a test was written asserting the message "names the offending line", with `mongo port=1` as
the needle. The suite did not merely miss the leak; it required it. The assertion is now inverted:
the message must name the line number, and a case feeds `supersecret` and greps both streams for
it.

That is the general lesson for this repository's shell suites. A test that asserts on a
diagnostic's *content* pins whatever the diagnostic happened to say when it was written. Assert
what must be there (a line number) and what must not (the value), not the sentence.

The suite went from 34 assertions to 51. Byte-identity was re-proven on all three workflows after
the change, because a fix to the marker matching is exactly the kind of change that could have
broken AC002 silently.

**One deviation from §6's "commit per fix".** The three fixes landed in one commit: two of them
are the same two lines of code, and splitting them would have produced an intermediate state where
the validation rejects a name while the message still quotes it. The commit message names all
three threads.
