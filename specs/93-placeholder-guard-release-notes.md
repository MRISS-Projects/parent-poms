# Spec: let the README placeholder guard accept substituted text (`#93`)

| | |
|---|---|
| Issue | [`#93`](https://github.com/MRISS-Projects/parent-poms/issues/93) |
| Milestone | `3.9.1-SNAPSHOT`, a hotfix milestone holding only this issue |
| Branch | `issue-93-placeholder-guard-release-notes`, cut from `master` |
| Consuming issue | `MRISS-Projects/dsh#143`, whose post-merge staging run found it |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** `check-placeholders.sh` rejects a `${name}` in a generated `README.md` only when it is a
placeholder the README source left unresolved, not when it arrived as text inside a substituted
value.

**Architecture.** The script takes the README source as a second, required argument. A `${name}`
counts as unresolved only when it appears in both the generated file and the source. The three
callers pass `src/site/markdown/README.md`.

**Tech stack.** POSIX shell, run under dash on the runners and Git Bash locally; GitHub Actions
composite action; `build.yml`'s `*.test.sh` glob.

## 1. The defect

DSH staging run [36574918380](https://github.com/MRISS-Projects/dsh/actions/runs/36574918380)
built green and then failed the check:

```text
check-placeholders: unresolved placeholder in README.md:
425:| [115](https://github.com/MRISS-Projects/dsh/issues/115) | bug | [STORY] version.properties ships an unresolved ${jenkins.build.number} in two modules | null | mriss | 9/28/26 |
```

Line 425 is DSH `#115`'s title, written into the release notes by `maven-changes-plugin` through
the `${issues.text.list}` property. The script's header assumed a literal `${...}` could only come
from the README source, where the consumer would have to escape it. A property *value* is never
re-filtered and never escaped, so any substituted text can carry one.

## 2. Design

**Why the source is the right reference.** Filtering replaces `${name}` in the source with the
property's value, or, when the property is undefined, leaves `${name}` as it was. So an unresolved
placeholder is always a `${name}` present in the source. A `${name}` that appears only in the
output came from a value. Both the regression the guard exists for (`#71`'s `${timestamp}`) and a
`${issues.text.list}` left behind by `generate-list-of-issues`'s `failOnError=false` stay caught.

**Known limit.** A value that quotes a placeholder the source also uses, such as an issue title
mentioning `${project.build.version}`, is still flagged. The check stays fail-closed: the error is a
false alarm, never a missed placeholder. A title can be reworded; a line-level comparison would
cost more than that case is worth.

**Required, not defaulted.** A missing or unreadable source fails the check, as a missing generated
file already does. Defaulting to `src/site/markdown/README.md` would let a caller in the wrong
working directory compare against nothing and pass everything.

## 3. Files

| File | Change |
|---|---|
| `.github/actions/commit-readme/check-placeholders.sh` | Second argument; intersection of names |
| `.github/actions/commit-readme/check-placeholders.test.sh` | Source passed to every case; new cases |
| `.github/actions/commit-readme/action.yml` | Passes `src/site/markdown/README.md` |
| `.github/workflows/deploy.yml` | Both invocations pass it |

## 4. Tasks

### Task 1 — Tests first, red

- [ ] `expect_exit` takes the source as a fourth argument. Every existing case gets a source
  holding the placeholder it tests, so it still asserts what it asserted.
- [ ] New cases:
  - DSH `#115`'s line in the release notes, with a source that has no `${jenkins.build.number}`,
    passes (AC003).
  - A source placeholder left unresolved fails even when the release notes carry an unrelated
    literal (AC002).
  - `${issues.text.list}` left unresolved fails.
  - A missing source fails; no second argument fails.
- [ ] `sh .github/actions/commit-readme/check-placeholders.test.sh` fails, on the new cases.

### Task 2 — The script, green

- [ ] Implement §2. Keep the exit-code split that tells no match from a read error, for both files.
- [ ] Rewrite the header's reasoning to match.
- [ ] The test suite passes.

### Task 3 — Callers

- [ ] `action.yml` and both `deploy.yml` invocations pass `src/site/markdown/README.md`.
- [ ] `grep -rn 'check-placeholders.sh' .github` shows no single-argument call.

### Task 4 — Verify

- [ ] `build.yml` green on the PR.
- [ ] After the merge, DSH staging on `staging-0.3.0-SNAPSHOT-RC` passes the step on the README
  that failed it (AC006). Record the run URL in §5.

## 5. Verification

Recorded as tasks complete.
