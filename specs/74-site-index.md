# Spec: a landing page that says what this repository is (`#74`)

| | |
|---|---|
| Issue | [`#74`](https://github.com/MRISS-Projects/parent-poms/issues/74): reshape `src/site/markdown/index.md`, which is two lines and says almost nothing |
| Milestone | `3.10.0-SNAPSHOT` |
| Branch | `issue-74-site-index`, cut from `master` at `93522671` |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** Someone arriving at the published site learns what `mriss-parent` is, which POM a product
inherits from, how to point at it, and where to go next.

**Architecture.** One Markdown file, `src/site/markdown/index.md`, rewritten. No POM, workflow or
site descriptor changes.

## 1. What the page must and must not do

- **Audience.** A developer of a consuming project, arriving from a link or a search. Not a
  maintainer of this repository: that reader has `CLAUDE.md`.
- **It covers** the issue's four points: what the project is, the three levels and which one a
  product inherits from, how a consumer points at it and where artifacts are published, and where to
  go next.
- **It does not repeat `src/site/markdown/README.md`** (AC003). That page, rendered on the site as
  `README.html`, already holds the build commands, the snapshot and release site addresses, the
  current version and the release notes. The landing page links to it for all four.
- **No version number is written into the page.** Site Markdown is not filtered, so a literal
  version would go stale at the next release. The example uses a placeholder, and the page says
  where the current version is listed.
- **`infrastructure` is described as what it is: two levels of aggregator over separately versioned
  software.** The issue lists three levels: the root, `framework` and `products`. The reactor has a
  fourth module, `infrastructure`, and it is a different kind of thing (review, 2026-10-02):
  - `infrastructure` aggregates four groups: `skins`, `announcement-templates`, `maven-archetypes`
    and `maven-plugins`. Each group is itself an aggregator. All five follow the hierarchy's version.
  - The modules inside each group are separate pieces of software, "infrastructure products". Each
    has its own version (`2.0.0-SNAPSHOT` today, against the hierarchy's `3.10.0-SNAPSHOT`), and
    names its group at a released version as its parent.
  - A release of the parent POMs does not release them. `deploy.yml`'s release recursion stops at
    the four groups, with the note "released independently".

  The page must not present them as part of the inheritance hierarchy, or as versioned with it.

## 2. The page

The whole of the new `src/site/markdown/index.md`:

````markdown
# MRISS Parent POMs

`com.mriss:mriss-parent` is the parent POM hierarchy shared by the MRISS-Projects Java and Maven
repositories. It holds no application code. It is packaging-only (`pom`): what a project gets from
it is build configuration, inherited.

## What a project inherits

- Plugin and dependency versions, managed in one place.
- A Java 17 build with unit tests, integration tests and a coverage gate. The
  [README](README.html) says how they run and what the gate measures.
- Maven site generation, with this site's skins and reports.
- The staging, release and hotfix pipelines, as reusable GitHub Actions workflows.

## The hierarchy

```text
com.mriss:mriss-parent                    the root POM
|-- com.mriss.mriss-parent:framework      parent for framework-level modules
`-- com.mriss.mriss-parent:products       parent for product repositories
```

**A product repository inherits from `products`, not from the root.** `products` inherits from the
root, so a product gets everything above, plus the release configuration that products share.
`framework` plays the same part for framework-level modules.

## Infrastructure

The repository has one more module, `infrastructure`. No project inherits from it. It gathers the
tooling the hierarchy itself uses, in four groups:

```text
infrastructure
|-- skins                     company-skin, product-module-skin, products-skin
|-- announcement-templates    default-announcement-template
|-- maven-archetypes          module-standard, product-parent, maven-plugin
`-- maven-plugins             no module yet
```

`infrastructure` and the four groups are aggregators only. The modules inside each group are
separate pieces of software: each has its own version, independent of the parent POMs' version, and
a release of the parent POMs does not release them.

## Using it

Name `products` as the parent in the project's root `pom.xml`:

```xml
<parent>
    <groupId>com.mriss.mriss-parent</groupId>
    <artifactId>products</artifactId>
    <version><!-- a released version --></version>
</parent>
```

The current version, and what changed in each release, is on the [README](README.html) page.

The artifacts are published to GitHub Packages, at
`https://maven.pkg.github.com/MRISS-Projects/maven-repo`. GitHub Packages requires authentication
even to read, and Maven resolves a parent before it reads any `<repositories>` from the project's
own POM. So both the repository and its credentials go in `~/.m2/settings.xml`: a `<server>` with a
GitHub user and a token that has the `read:packages` scope, and a profile, active by default, that
declares the repository under the same id.

## Where to go next

- [README](README.html): how to build this repository from sources, where its snapshot and release
  sites are, and the release notes.
- [Releases History](releases-history.html).
- The module pages, under "Project Modules" in the menu: [Infrastructure](infrastructure/),
  [Framework](framework/) and [Products](products/).
- The reports, under "Project Reports" in the menu.
- [`CLAUDE.md`](https://github.com/MRISS-Projects/parent-poms/blob/master/CLAUDE.md), in the
  repository, for the development detail: the profiles, the workflows and how they fit together.
````

## 3. Facts the page states, and where each comes from

| Statement | Source |
|---|---|
| The three coordinates of the hierarchy and `pom` packaging | each module's `pom.xml` |
| Java 17 | `<java.version>` in the root `pom.xml` |
| Products inherit from `products` | `CLAUDE.md`, "Module layout"; DSH's root `pom.xml` |
| `infrastructure` and its four groups are aggregators; the seven modules below them have their own version | each `pom.xml` under `infrastructure/`: the groups inherit the root version, the leaf modules declare `2.0.0-SNAPSHOT` with a released group as parent |
| A release of the parent POMs does not release those modules | `deploy.yml`'s release step, which skips recursion into the four groups ("released independently") |
| GitHub Packages at `MRISS-Projects/maven-repo`, and the `settings.xml` requirement | `<repositories>` in the root `pom.xml`; `build.yml`'s "Configure Maven settings" step and its comment |

Each is checked again against the tree in task 1, before the page is written.

## 4. Verification

- **Local render.** `mvn -B -N site` at the root. Check `target/site/index.html`: the headings, the
  hierarchy block, the XML block with its angle brackets intact, and every relative link naming a
  file or directory that the site has (`README.html`, `releases-history.html`, `infrastructure/`,
  `framework/`, `products/`).
- **No duplication (AC003).** The page holds no build command, no site address and no version, and
  links to `README.html` for them.
- **On `gh-pages` (AC002).** After the merge, the routine snapshot deploy, `deploy.yml` on `master`
  with `release_type: snapshots`, publishes it. Check
  `https://mriss-projects.github.io/parent-poms/snapshots/index.html`. That same deploy is the
  `3.10.0-SNAPSHOT` that `dsh#127` needs, with `#89` in it, if `#89` is merged first.

## 5. Tasks

- [x] **Task 1.** Re-check §3's facts against the tree.
- [x] **Task 2.** Replace `src/site/markdown/index.md` with §2.
- [x] **Task 3.** Render it locally (§4) and record what was checked.
- [x] **Task 4.** Open a PR into `master` that references `#74`.
- [ ] **Task 5, after the merge.** Check the page on `gh-pages` after the snapshot deploy, and record
      it on the PR.

## 6. Acceptance criteria

| AC | Covered by |
|---|---|
| AC001: `index.md` describes the repository, the three-level hierarchy, and how a consumer inherits from it | §2 |
| AC002: the generated site's landing page renders it correctly on `gh-pages` | §4, task 5 |
| AC003: nothing is duplicated from `README.md`; where they overlap, `index.md` links | §1, §4 |

## 7. Verification results

On 2026-10-02, on the development machine.

- **Facts (task 1).** §3's sources were re-read. One correction came from review before the page
  was written: `infrastructure` is two levels of aggregator over seven separately versioned
  modules, not part of the inheritance hierarchy (§1).
- **The page (task 2).** `src/site/markdown/index.md` is §2's block, extracted from this file, not
  retyped. A `cmp` of the two matches.
- **Local render (task 3).** `mvn -B -N site` at the root, then `target/site/index.html`:
  - six headings: the title, "What a project inherits", "The hierarchy", "Infrastructure",
    "Using it" and "Where to go next";
  - three code blocks. The XML block keeps its angle brackets, as `&lt;parent&gt;`;
  - `README.html` and `releases-history.html` exist in the rendered site. `infrastructure/`,
    `framework/` and `products/` are the module sites, which answer 200 on the live snapshot site;
  - the `CLAUDE.md` link is the address GitHub's API gives for the file on `master`.
- **No duplication (AC003).** The page holds no `mvn` command, no site address and no version
  number.
- **A defect found by the render, and fixed.** The two tree diagrams were first drawn with
  box-drawing characters. In the local render they came out garbled: the POM sets no source
  encoding, so the site plugin read the UTF-8 file in the platform's encoding, Windows-1252 here.
  A Linux runner would probably have rendered them, but the page should not depend on the machine
  that builds it. The diagrams are now plain ASCII, and the page has no non-ASCII character.
- **On `gh-pages` (AC002).** Task 5, after the merge.

### 7.1 Review round 1, 2026-10-02

Copilot reviewed `78ca86a5` and raised one finding, on the page and on this file's copy of it. It
was valid.

- **The finding.** Two bullets under "What a project inherits" restated what the README's "Build
  from Sources" section says: that unit tests and integration tests run separately, and that the
  95% coverage gate measures unit tests. AC003 asks for a link where the two overlap.
- **Why the build's own check missed it.** That check looked for build commands, site addresses and
  version numbers. It did not look for prose making the same statements.
- **The fix.** One bullet replaces the two: a Java 17 build with unit tests, integration tests and a
  coverage gate, linking to the README for how they run and what the gate measures. §2's block and
  `index.md` were changed together and still match. §3 no longer lists the coverage figures, because
  the page no longer states them.
