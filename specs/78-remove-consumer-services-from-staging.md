# Spec: remove the consumer-specific services and setup from `project-staging.yml` (`#78`)

| | |
|---|---|
| Issue | [`#78`](https://github.com/MRISS-Projects/parent-poms/issues/78) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-78-remove-consumer-services-from-staging`, cut from `master` at `7e46ccb8` |
| Requesting project | `MRISS-Projects/dsh` — Wave 0, `specs/product/PRD.md` §4 |
| Split off from | [`#76`](https://github.com/MRISS-Projects/parent-poms/issues/76) — see `specs/76-consumer-supplied-maven-properties.md` §4.3 and §8 |
| Consuming twin | [`dsh#123`](https://github.com/MRISS-Projects/dsh/issues/123) — drops the three inputs from `dsh`'s `staging.yml` (§5). Merges first |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> This change deletes workflow content and adds one guard; nothing here carries logic a unit test
> could reach. It is proven by a local reactor run, the guard's own positive control, and
> dispatched `dsh` staging runs. Those runs are specified exactly; do not substitute a different
> command and assume the same output.

**Goal.** `project-staging.yml` declares no service containers, creates no database user, and
takes no `mongo_*` input. A consumer whose integration tests need live infrastructure starts it
from its own tests. A consumer that needs nothing pays for nothing.

**Architecture.** Deletion, not a new extension point. The job loses its `services:` block, the
"Create MongoDB user and database" step and the three inputs that feed only that step. `build.yml`
gains one check that fails when any `project-*.yml` declares `services:`, so the decision cannot
quietly be undone.

**Tech stack.** GitHub Actions, POSIX shell for the guard. No new action dependency.

---

## Global constraints

- **No service, hostname, credential or database name belonging to one consumer stays in this
  repository.** That extends the rule `#67` set and `#76` applied to build properties.
- **No replacement mechanism is added.** No `setup_command` input, no `.github/staging-setup.sh`
  convention. §2 says why. What an integration test starts is the product's decision; that is
  already the rule in `CLAUDE.md`'s description of `-DintegrationTests`.
- **Nothing else in `project-staging.yml` changes.** The Maven command lines, the README steps and
  the site deploy are untouched. **`maven_properties` stays.** It is how a consumer supplies build
  properties (`#76`), and `dsh` still needs it (§5).
- **`dsh` drops the three inputs before this merges** (§5). A caller that passes an input the
  called workflow does not declare fails at once, so the order is forced.

---

## 1. The problem, and what checking it found

`project-staging.yml` carries three pieces of one consumer, `MRISS-Projects/dsh`:

| What | Where, on `7e46ccb8` |
|---|---|
| `services:` — `mongodb: mongo:6` and `rabbitmq: rabbitmq:3-management` | lines 68-79, with a comment naming `dsh-rest-api` |
| Inputs `mongo_user`, `mongo_password`, `mongo_database` | lines 29-47, with a comment already naming `#78` |
| "Create MongoDB user and database" (`docker run … mongosh … createUser`) | lines 183-192 |

Every consumer pays both containers' startup on every staging run, and a consumer that needs a
different service has nowhere to put it.

### 1.1 The issue body is stale in three ways

1. **Line numbers.** `#76` rewrote the file after the issue was filed.
2. **One input became three.** The issue names only `mongo_database`. Since `#76`, `mongo_user` and
   `mongo_password` also feed nothing but the setup step, and go with it.
3. **AC004 rests on a false premise.** It asks for proof that `dsh` still runs staging "against a
   live MongoDB". `dsh`'s staging build does not need one, as §1.2 shows.

### 1.2 `dsh` needs neither service — measured

The issue's design questions assumed the services were load-bearing for `dsh` and asked where
their replacement should live. That assumption was checked before designing anything.

Run on 2026-09-25 against `dsh` `staging-0.3.0-SNAPSHOT-RC` at `aad71bfb8`, on a machine with
nothing listening on 27017 or 5672 and no containers running, with the same `mongo.*` values
`dsh`'s `staging.yml` supplies:

```bash
mvn -B clean install -DintegrationTests \
  -Dmongo.host=localhost -Dmongo.port=27017 -Dmongo.user=dshuser -Dmongo.password=dshpass
```

Result: **BUILD SUCCESS**, with all six integration tests passing and `jacoco:check` met in every
module:

| IT | Module | Tests |
|---|---|---|
| `DocumentResourceIT` | `dsh-rest-api` | 6 |
| `DshRestApplicationIT` | `dsh-rest-api` | 2 |
| `DshDocIndexerApplicationIT` | `dsh-doc-indexer-worker` | 1 |
| `DshKeywordExtractorApplicationIT` | `dsh-keyword-extractor` | 2 |
| `DshTopSentencesExtractorApplicationIT` | `dsh-top-sentences-extractor` | 2 |
| `DshDocProcessorWorkerApplicationIT` | `dsh-doc-processor-worker` | 2 |

Every one starts a Spring context (`@SpringBootTest`). They pass without the servers because
neither client connects when the context starts:

- **`dsh-rest-api`'s two ITs** replace the only beans that talk to the servers with
  `@MockBean DocumentDao` and `@MockBean DocumentQueueService`.
- **The four worker ITs mock nothing.** Spring AMQP's `CachingConnectionFactory` connects only on
  the first send, or when a listener container starts. No worker declares a listener or sends
  anything, and the log shows no AMQP connection attempt. The Mongo driver's `MongoClient` runs a
  background monitor that tries the server and only logs a failure. The whole log has six
  `MongoSocketOpenException` lines, one per context, and no failure.

So the "real connection to the MongoDB service container" that `dsh#114`'s staging run observed
was that monitor thread, not a test dependency. **RabbitMQ has never been needed**, which answers
the issue's third design question. MongoDB is not needed either.

This is true of `dsh`'s tests **today**, not by design. The first IT that calls a real DAO or sends
a real message needs a live server. `dsh#46`, which runs ITs against the packaged application over
HTTP, is the likely first. §2 covers where that goes.

One aside, so it is not mistaken for a finding here: a first attempt resumed a failed build with
`-rf` and no `clean`, and `jacoco:check` then reported 0.50 line coverage on `dsh-rest-api`. A clean
rerun of that module met the gate. It was a stale-exec artifact of the resume, not a defect.

---

## 2. The decision: delete, and add no extension point

Three shapes were considered:

| Option | Verdict |
|---|---|
| **1. Delete the services, the step and the inputs. Nothing replaces them.** | **Chosen** |
| 2. Delete, and run `.github/staging-setup.sh` from the consumer checkout if it exists | Rejected |
| 3. Delete, and add a `setup_command` input | Rejected |

**Why 1.** No consumer needs the services today (§1.2), so any extension point would be designed
against a need nobody has yet. When one arrives, the product's tests can start what they need
themselves. Testcontainers does that, and Docker is available on `ubuntu-latest`. That keeps the
dependency next to the test that has it, and it runs the same in staging, in `ci.yml`, and on a
laptop. It also matches the rule this repository already states: `-DintegrationTests` is
supplied here, and what an integration test *starts* is the product's decision.

**Why not 2.** It is cheap and takes no input. But it is an interface with no user, and it would
exist in staging only. Release and hotfix would lack it, so the same tests would have different
infrastructure depending on which workflow ran them. If a product ever needs setup that cannot live
in its tests, this is the shape to revisit, with that product's requirement in hand.

**Why not 3.** It puts consumer shell into a `run:` body through a workflow input, the exact
pattern [`#81`](https://github.com/MRISS-Projects/parent-poms/issues/81) exists to remove.

**One side benefit.** The deleted step interpolates `inputs.mongo_user`, `inputs.mongo_password`
and `inputs.mongo_database` straight into a `run:` body, which is `#81`'s pattern. Deleting it
removes one instance from `project-staging.yml` without touching `#81`'s scope.

---

## 3. Files

| File | Change |
|---|---|
| `.github/workflows/project-staging.yml` | Delete the `services:` block and its comment, the three `mongo_*` inputs and their comment, and the "Create MongoDB user and database" step |
| `.github/workflows/build.yml` | Add one step: fail if any `.github/workflows/project-*.yml` declares `services:` (§4) |
| `specs/github-actions-reusable-workflows.md` | Delete the three `mongo_*` rows from `project-staging.yml`'s input table (lines 505-507) |
| `specs/76-consumer-supplied-maven-properties.md` | None. It is a record of `#76` as built, and §4.3 correctly describes the state `#78` then ends |

---

## 4. The guard

A reusable workflow that declares `services:` imposes them on every consumer. The guard keeps
this change from being undone by accident. It is a positive assertion rather than reliance on
review, the same reasoning as `#69`'s `verify-reactor-version`.

In `build.yml`, beside the existing `commit-readme@master` pin check:

```yaml
      # #78: a reusable workflow owns its job, so services declared there run for every
      # consumer. Products start their own test infrastructure; see specs/78-*.md §2.
      - name: Check the reusable workflows declare no service containers
        run: |
          if grep -nE '^[[:space:]]+services:' .github/workflows/project-*.yml; then
            echo "::error::A reusable project workflow declares services: (see #78)"
            exit 1
          fi
```

**Positive control, required.** Run the guard's `grep` against `project-staging.yml` as it stands
on `master`. It must match line 70 and exit non-zero. On this branch it must match nothing. A guard
that passes on both would also pass if its pattern were wrong.

---

## 5. The consuming half, and the order

**`maven_properties` is not affected.** `#76`'s input for consumer build properties stays exactly
as it is, and consumers keep using it. Only the three setup inputs go.

`dsh`'s `.github/workflows/staging.yml` passes those three: `mongo_user`, `mongo_password` and
`mongo_database`. Once this merges, `project-staging.yml` no longer declares them. GitHub rejects a
call that passes an undeclared input before any job starts, so a `dsh` staging run that still
passes the three would fail. So `dsh` changes first, under its own issue:

- Delete the three inputs and the comment above them (`staging.yml` lines 24-30 at `aad71bfb8`).
- **Keep `maven_properties`.** `dsh-data`'s `mongo.properties` is filtered from those four values.
  Without them the placeholders survive and every `dsh-rest-api` context fails to start, which is
  `#76`'s original defect. The client needs the values even though it never connects.
- Rewrite the comment above `maven_properties`. "a live MongoDB runs behind these values here" is
  no longer true.

Dropping the inputs is safe against both versions of this workflow. Against `master` the setup
step's `if: inputs.mongo_user != ''` skips it and the idle services still start. Against this
branch the inputs no longer exist. Order:

1. **Validate.** Push the `dsh` task branch with the inputs dropped and the wrapper pointed at
   `@issue-78-remove-consumer-services-from-staging`. Dispatch `staging.yml` against it (Task 6).
2. **Merge `dsh` first,** with the wrapper pointed back at `@master`. Staging keeps working: the
   services are still there, and nothing uses the user that is no longer created.
3. **Merge this PR.**
4. **Confirm the end state** by dispatching `dsh` `staging.yml` on the RC branch against `@master`
   (Task 7).

This is the reverse of `#65`/`dsh#117`, where the caller had to wait for the input to exist.

---

## 6. Tasks

- [ ] **Task 1 — guard, red.** Add the `build.yml` step from §4. Run its `grep` locally against the
      unchanged `project-staging.yml`. Expected: one match at line 70, exit 1. Commit.
- [ ] **Task 2 — delete the services.** Remove lines 68-79 of `project-staging.yml`, the comment
      included. Rerun the guard's `grep`. Expected: no match, exit 0. Commit.
- [ ] **Task 3 — delete the step and the inputs.** Remove the "Create MongoDB user and database"
      step and the three `mongo_*` inputs with their `#78` comment. Then
      `grep -niE 'mongo|rabbit' .github/workflows/*.yml`. Expected: no output. Commit.
- [ ] **Task 4 — docs.** Delete the three rows in `specs/github-actions-reusable-workflows.md`.
      `grep -n mongo_ specs/github-actions-reusable-workflows.md`. Expected: no output. Commit.
- [x] **Task 5 — reconcile `#78`.** Update the issue body to match §1.1: three inputs, current line
      numbers, and AC004 restated as below. Do this before the PR is reviewed, so the issue and the
      spec agree. **This edits a GitHub issue; show the new body to the owner first.**
- [ ] **Task 6 — validate against `dsh`, pre-merge.** Order step 1 from §5. From the run, record:
      the run URL; that the job log has **no "Initialize containers" section**; the six
      `Tests run:` lines for the ITs; `All coverage checks have been met.` for every module; and the
      conclusion `success`. This is AC004 and AC005.
- [ ] **Task 7 — confirm the end state, post-merge.** Order step 4 from §5. Record the same
      evidence as Task 6. Paste both runs into §8 and comment them on `#78`.

---

## 7. Acceptance criteria

These restate the issue's ACs as Task 5 will reword them.

- [ ] **AC001** — `project-staging.yml` declares no service containers, and `build.yml` fails any
      `project-*.yml` that declares `services:`. The guard's positive control is recorded.
- [ ] **AC002** — `project-staging.yml` has no consumer-specific setup step. The Mongo user is no
      longer created anywhere, because nothing needs it (§1.2).
- [ ] **AC003** — `project-staging.yml` has no `mongo_user`, `mongo_password` or `mongo_database`
      input, and no workflow here mentions Mongo or RabbitMQ.
- [ ] **AC004** — *Restated.* A dispatched `dsh` staging run is green with no service containers:
      all six ITs pass and every module meets the coverage gate. (Was: "still runs a staging build
      against a live MongoDB", a premise §1.2 disproved.)
- [ ] **AC005** — A consumer needing no services pays no container startup. The Task 6 run's log
      has no "Initialize containers" section.

---

## 8. Build record

Filled in as the work is done.

---

## 9. Out of scope

- **`dsh`'s own `ci.yml` and `api-testing.yml`,** which also start `mongo:6` and `rabbitmq`.
  They belong to `dsh`. `ci.yml` runs unit tests only since `dsh#112`, so its services are idle
  too. Whether to drop them is a `dsh` decision and a candidate `dsh` follow-up, not part of this
  change.
- **An extension point for consumer infrastructure.** Rejected in §2. Revisit when a product has
  a need its own tests cannot meet.
- **`#81`.** This change removes one of its interpolations as a side effect (§2) and does not audit
  the rest.
- **Releasing `3.9.0`.** The milestone still holds `#59` and `#70`. `dsh` consumes these workflows
  at `@master`, so no release is needed for either half of this change to take effect.
