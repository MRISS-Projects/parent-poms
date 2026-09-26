# Spec: convert the remaining APT site pages to Markdown (`#70`)

| | |
|---|---|
| Issue | [`#70`](https://github.com/MRISS-Projects/parent-poms/issues/70) |
| Milestone | `3.9.0-SNAPSHOT` |
| Branch | `issue-70-convert-apt-site-pages-to-markdown`, cut from `master` |
| Pilot | `#57`, landed in 3708e450 — `infrastructure/src/site/{apt → markdown}/{maven,java}` |
| Raised from | `MRISS-Projects/dsh#85`, spec §7.3-7.6 |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.
> There is no test harness for site content, so the checks are rendered-output comparisons,
> specified exactly in §4. Do not replace one with "the build was green" — the pilot showed
> a green `mvn site` alongside every contents link on the page dead.

**Goal.** The 15 APT site pages listed in `#70` become Markdown, with their content unchanged. After
that, no `.apt` file is left under any `src/site/` outside `archetype-resources/`.

**Architecture.** No build change is needed for the conversion. Doxia renders
`src/site/apt/<name>.apt` and `src/site/markdown/<name>.md` to the same `<name>.html`, and each
`site.xml` links by output name. Each page moves in two commits. The first is a pure rename, so git
keeps the history. The second is the markup conversion, so the diff shows only markup.

**Tech stack.** `maven-site-plugin` 3.21.0 with Doxia 2.0.0 (`doxia-module-markdown`). Maven 3.9.16,
which every workflow here pins since `#59`. Java 17, and POSIX shell for the checks.

---

## Global constraints

- **Markup only.** No prose is added, removed or corrected — not typos, not stale product names
  (Subversion, subclipse, Ubuntu 14.04, `production/`), not empty link targets. That is `#70`'s AC006,
  and it is what makes the diff reviewable as a conversion. The one sanctioned structural change is
  the contents list in §2.2, which replaces a macro that cannot be carried across.
- **Doxia anchors, on every page.** Contents links use Doxia's generated ids
  (`#Download_and_Installation`), not GitHub's (`#download-and-installation`). Decided once for all
  15 pages. See §2.3.
- **Dead image references are carried across unchanged.** See §2.4.
- **No `site.xml` is edited.** If one needs editing, the conversion of that page is wrong (AC004).
- **`maven-pdf-plugin`'s `doxia-module-apt` stays.** See §1.2.
- Profiles are activated by `-D<name>`, never `-P`.
- Every local Maven run is redirected to `.logs/`, with a `tail -f` command printed first and the
  exit code reported explicitly. Never pipe `mvn` into `tail`.

---

## 1. Corrections to the issue

Two claims in `#70`'s body do not hold. Both are posted back to the issue in Task 6, so the issue
and this spec agree.

### 1.1 The completion criterion cannot fail

`#70` says the migration is done when "`doxia-module-apt` can be dropped from `maven-site-plugin`'s
dependency list in `pom.xml`, and the site still builds". That test cannot fail:

- `maven-site-plugin` 3.21.0 (`pom.xml:95`) already declares `doxia-module-apt` as its **own**
  runtime dependency, at its own `doxiaVersion` 2.0.0 (plugin POM, lines 200 and 351).
- The dependency this repository declares (`pom.xml:219-223`) resolves `${doxia.tools.version}`, which
  is also 2.0.0. It duplicates what the plugin already brings.

So removing it changes nothing on the classpath. APT still parses, and the site would still build
with all 15 pages left in APT. Task 5 still removes it, as redundant configuration, but its commit
message calls the change a no-op, not evidence. The real completion check is AC001's file check,
run as §4.1.

This is also why the archetype templates are safe. The 39 `.apt` files under `archetype-resources/`
are out of scope, and any consumer with APT pages keeps rendering them whatever this spec does to the
parent's dependency list. Making the criterion "real" would mean excluding the module from the
plugin, which would break every archetype-generated project's site. That was considered and
rejected.

`doxia-module-markdown` (`pom.xml:224-228`) is redundant for the same reason. It is out of scope
here, and this spec leaves it alone.

### 1.2 `maven-pdf-plugin` keeps its APT module

`pom.xml:417-421` declares `doxia-module-apt` for `maven-pdf-plugin` too, at
`${doxia.pdf.tools.version}` 1.11.1. That plugin predates the bundling (the comment at
`pom.xml:115-124` explains why it stays on Doxia 1.x). Both archetype templates that generate
projects with APT pages configure `maven-pdf-plugin`: `module-standard` and `product-parent`. Task 5
does not touch it.

### 1.3 Four pages use `%{toc}`, not six

`#70` says six of the 15 pages use the TOC macro. Four do:

    infrastructure/src/site/apt/os.apt:6
    infrastructure/src/site/apt/svn.apt:6
    infrastructure/src/site/apt/tomcat.apt:6
    infrastructure/src/site/apt/writing-projects-documentation.apt:6

---

## 2. Design

### 2.1 Markup mapping

| APT | Markdown |
|---|---|
| First unindented line (document title) | `# Title` |
| `* Section` | `## Section` |
| `** Sub` | `### Sub` |
| `*** Subsub` | `#### Subsub` |
| `<<bold>>` | `**bold**` |
| `<<<mono>>>` | `` `mono` `` |
| `<italic>` | `*italic*` |
| `{{{url}text}}` | `[text](url)` — the URL kept byte for byte, `.html` targets included |
| `+---+` verbatim block | fenced block with a language (`bash`, `text`, `ini`, `xml`), or `text` when unsure |
| `[[1]]` ordered list | `1.` list, numbered as in the source |
| `[[a]]` nested list | nested `1.` list, indented under its parent item |
| `[images/x.png]` figure, no caption | `![](images/x.png)` |
| `[images/x.png] Caption` figure | raw HTML: `<figure><img src="images/x.png" /><figcaption>Caption</figcaption></figure>` |

A captioned APT figure renders a visible `<figcaption>`. Markdown's `![Caption](…)` would move the text
into `alt`, where it is not visible, so the caption would disappear from the page. That breaks
AC006. So a captioned figure is written as the same HTML the baseline renders. The three `os`
figures (§2.4) are the only captioned ones. Task 3 checks that Doxia's Markdown parser passes the
raw `<figure>` through. If it does not, stop and bring it back to the human; do not fall back to
`alt`.

A verbatim block nested under a list item is indented so it stays inside the item, the way
`maven.md` does it. Watch the rendered HTML for it — see §4.2.

### 2.2 Replacing `%{toc}`

Each of the four pages in §1.3 has a `* Table of Contents` heading holding the macro. Replace both
with the pilot's form:

    ## Contents

    * [Section title](#Section_title)
    * [Another section](#Another_section)

The list has one entry per `##` and `###` heading, matching the macro's `fromDepth=2|toDepth=3` at
`section=1`. `###` entries are indented under their parent. Renaming the heading from
`Table of Contents` to `Contents` follows `java.md` and `maven.md`, so the four pages match the two
pilot pages. This is the one sanctioned deviation from AC006. §4.2 allows for it explicitly.

### 2.3 Anchors

Doxia derives an id from the heading text: spaces become `_`, letter case is kept, and `.` is kept.
Do not work the id out from the heading by eye. Build the list, render the page, and let §4.3 prove
every link. The pilot's lists were written in GitHub's style first, every one of their links was
dead, and the build still passed.

The trade-off, decided: the links resolve in the generated site and not when the `.md` is browsed
on GitHub. That is not a regression, because GitHub never rendered the APT originals at all. The
choice holds for all 15 pages.

### 2.4 The five dead image references

These are referenced and were never committed. `git log --all --diff-filter=D` finds no deletion.

    infrastructure/src/site/apt/os.apt:21,25,30
        images/Ubuntu-Settings.jpg, images/Ubuntu-Network.png, images/Ubuntu-Proxy-Settings.jpg
    infrastructure/src/site/apt/writing-projects-documentation.apt:61,63
        images/apt-editor-edit.png, images/apt-editor-view.png

They are carried across as `![…](images/…)`, still dead. Recreating them or dropping them is a
content change, and would break AC006. The follow-up question is bigger than five images. These
pages document tooling that is partly obsolete: an Ubuntu 14.04 proxy setup, Subversion, and an
editor for the very format this issue retires. So the follow-up asks whether the `infrastructure`
pages should be kept at all, and what generic guidance should replace them, both for projects
inheriting from parent-poms and for contributors to parent-poms itself. Task 6 drafts that issue.

`images/test-image.png` (`writing-projects-documentation.apt:82`) is not an image reference. It is
text inside a verbatim block, showing the reader APT's figure syntax, and the baseline renders it as
`<pre><code>[images/test-image.png]`. It is carried across as a fenced `text` block, unchanged. That
example teaches the very syntax this issue retires, which is a content question for the follow-up.

### 2.5 Two commits per page group

A commit that renames a file and rewrites most of its lines falls below git's 50% rename-similarity
threshold, and then `git log --follow` loses the history. So each task commits twice:

1. `git mv src/site/apt/<name>.apt src/site/markdown/<name>.md`, one commit, content untouched.
2. The markup conversion, a second commit.

Between the two commits, the site renders that page as raw APT text. That is acceptable on a task
branch, and the PR merges both commits together.

`src/site/markdown/` does not exist yet in any of the three archetype sub-modules. `git mv` into it
needs `mkdir -p` first. `infrastructure/src/site/markdown/` and
`infrastructure/maven-archetypes/src/site/markdown/` already exist.

---

## 3. File structure

| Module | Moves from `src/site/apt/` to `src/site/markdown/` | Task |
|---|---|---|
| `infrastructure/maven-archetypes/maven-plugin` | `index`, `usage` | 1 |
| `infrastructure/maven-archetypes/module-standard` | `index`, `usage` | 1 |
| `infrastructure/maven-archetypes/product-parent` | `index`, `usage` | 1 |
| `infrastructure/maven-archetypes` | `after-running`, `archetype-index`, `auto-subversion-add`, `before-running` | 2 |
| `infrastructure` | `os`, `setup`, `svn`, `tomcat`, `writing-projects-documentation` | 3 |

Each emptied `src/site/apt/` directory disappears with its last file. Git does not track empty
directories, so no step deletes them.

`pom.xml` changes at `pom.xml:219-223` only (Task 5). No other file changes, apart from this spec.

---

## 4. Checks

Each rendered page is at `<module>/target/site/<name>.html`. `$SCRATCH` is a directory outside the
repository, holding the baseline taken in Task 0.

### 4.1 AC001: no APT left in any site source

```bash
find . -path '*/src/site/*' -name '*.apt' -not -path '*/archetype-resources/*' -not -path '*/target/*'
```

Expected: no output. Also confirm that each of the 15 `.md` files exists (Task 5 Step 3 lists them).

### 4.2 AC002 and AC006: rendered content is unchanged

Reduce each page to its visible text, inside the content container only, so the skin's header and
footer (which carry a `Last Published` date) stay out of the diff. Then diff the baseline against the
new render:

```bash
totext() {
  sed -n '/<main/,/<\/main>/p' "$1" |
    sed -e 's/<[^>]*>/ /g' -e 's/&nbsp;/ /g' -e 's/[[:space:]]\+/ /g' -e 's/^ //;s/ $//' |
    grep -v '^$'
}
diff <(totext "$SCRATCH/baseline/<module>/<name>.html") <(totext "<module>/target/site/<name>.html")
```

Task 0 Step 3 confirms that `<main` / `</main>` bound the content in this skin, **before** anything
relies on it. If they do not, it substitutes the container the skin really uses, then records the
change here.

The diff may show only the following:

- whitespace redistribution the reduction did not absorb,
- on the four pages of §1.3, `Table of Contents` becoming `Contents`, plus the new list's link texts,
- differences that come from how Doxia renders the same element in each format. Any of these is
  looked at in both HTML files and accepted only if the content is equal. Each one is recorded under
  Task 5.

Anything else is lost or rewritten content, and it fails the page.

Also check two things the text diff cannot see. The number of `<pre` blocks must be the same in both
renders (a verbatim block that fell out of its list item shows up as a count change or as merged
text). The `<img` `src` values and `<figcaption>` texts inside `<main>` must be identical, including
the five dead images. Both are scoped to `<main>` because the skin's footer carries its own `<img>`,
the "Built by Maven" logo.

```bash
for f in "$SCRATCH/baseline/<module>/<name>.html" "<module>/target/site/<name>.html"; do
  printf '%s pre=%s\n' "$f" "$(grep -o '<pre' "$f" | wc -l)"
  sed -n '/<main/,/<\/main>/p' "$f" | grep -oE '<img [^>]*src="[^"]*"|<figcaption>[^<]*' |
    grep -oE 'src="[^"]*"|<figcaption>.*'
done
```

### 4.3 AC003: every in-page link resolves

This is the corrected script from `#70`'s first comment. It matches fixed strings, with no
id-shape filter and no word splitting:

```bash
check_anchors() {  # $1 = rendered .html
  ids=$(grep -oE 'id="[^"]*"' "$1" | sed 's/^id="//;s/"$//' | sort -u)
  grep -oE 'href="#[^"]*"' "$1" | sed 's/^href="#//;s/"$//' | sort -u |
    while IFS= read -r l; do
      printf '%s\n' "$ids" | grep -qxF -- "$l" || echo "BROKEN -> $1 #$l"
    done
}
```

Run it on all 15 rendered pages. Expected: no output. Before relying on it, prove it can fail:
point one contents link on a scratch copy of a rendered page at a missing id, and check that the
script reports it.

### 4.4 AC004: no `site.xml` touched

```bash
git diff --name-only master... | grep 'site\.xml$'
```

Expected: no output.

### 4.5 The site build

The same goal CI runs (`build.yml:267`), after an install so the reactor resolves:

```bash
mkdir -p .logs
mvn -B -DskipTests install > .logs/mvn-install.log 2>&1 &
MVN_PID=$!; echo "Monitor with:  tail -f .logs/mvn-install.log"
wait $MVN_PID; echo "maven exit=$?"

mvn -B -Ddeployment -Drelease-deployment \
    -Dsite.deployment.personal.main=file:///tmp/sites site > .logs/mvn-site.log 2>&1 &
MVN_PID=$!; echo "Monitor with:  tail -f .logs/mvn-site.log"
wait $MVN_PID; echo "maven exit=$?"
```

`-Ddeployment` regenerates `README.md` in the working tree. After each run, `git status --short`
must show nothing except that file, which is restored with `git checkout -- README.md`. Anything
else the run left behind is a finding, and is not committed.

---

## 5. Tasks

### Task 0: Baseline on `master`

**Files:** none changed.

- [x] **Step 1: render the site from `master`**

  On this branch, before any conversion — it differs from `master` only by this spec — run §4.5.
  Expected: both exit codes `0`.

- [x] **Step 2: keep the 15 rendered pages**

  Copy each page listed in §3 to `$SCRATCH/baseline/<module>/<name>.html`, and also
  `infrastructure/target/site/{java,maven}.html` for §4.3's negative test. Check the count is 15
  plus 2.

- [x] **Step 3: confirm the content container**

  Open one rendered page and confirm that `<main` … `</main>` wraps the page content and excludes
  the `Last Published` line. If the skin uses a different container, fix `totext` in §4.2 and note
  it there.

  Confirmed: `<main id="bodyColumn" class="span10">` wraps the content, and `Last Published` sits
  in the header, outside it. `totext` stands as written.

- [x] **Step 4: prove the anchor check can fail**

  On a scratch copy of `java.html`, change one `href="#…"` to a missing id, and run
  `check_anchors`. Expected: exactly one `BROKEN` line. On the unmodified `java.html` and
  `maven.html`: no output.

- [x] **Step 5: restore the working tree** — `git checkout -- README.md`, then `git status --short`
  shows nothing.

### Task 1: The three archetype sub-modules (6 pages)

**Files:** `infrastructure/maven-archetypes/{maven-plugin,module-standard,product-parent}/src/site/{apt → markdown}/{index,usage}`.

The three `index.apt` files are one line each, `Introduction`, with no trailing newline. The
Markdown is `# Introduction` plus a trailing newline. The three `usage.apt` files are nearly
identical; convert one, then apply the same structure to the others, keeping each file's own
differences (archetype id, catalog option number).

- [ ] **Step 1: rename** — `mkdir -p <module>/src/site/markdown` and `git mv` for all six files.
  Then commit, as `docs(#70): move the archetype sub-module site pages from apt/ to markdown/`,
  with the body stating that the content is still APT and is converted in the next commit.
- [ ] **Step 2: convert** — apply §2.1 to all six files.
- [ ] **Step 3: render and check** — run §4.5, then §4.2 and §4.3 for these six pages. The `usage`
  pages nest verbatim blocks under `[[a]]`/`[[b]]` items inside a `[[2]]` item. Check the `<pre`
  count in particular.
- [ ] **Step 4: commit** — `docs(#70): convert the archetype sub-module site pages to Markdown`.

### Task 2: `maven-archetypes` (4 pages)

**Files:** `infrastructure/maven-archetypes/src/site/{apt → markdown}/{after-running,archetype-index,auto-subversion-add,before-running}`.

- [ ] **Step 1: rename** — `git mv` for all four files, then commit, with the same message shape as
  Task 1 Step 1.
- [ ] **Step 2: convert** — apply §2.1.
- [ ] **Step 3: render and check** — run §4.5, §4.2, §4.3.
- [ ] **Step 4: commit** — `docs(#70): convert the maven-archetypes site pages to Markdown`.

### Task 3: `infrastructure` (5 pages)

**Files:** `infrastructure/src/site/{apt → markdown}/{os,setup,svn,tomcat,writing-projects-documentation}`.

This is the only group with `%{toc}` (four pages) and dead images (two pages).

- [ ] **Step 1: rename** — `git mv` for all five files, then commit, with the same message shape as
  Task 1 Step 1.
- [ ] **Step 2: convert** — apply §2.1. On the four pages of §1.3, replace the TOC as in §2.2. Carry
  the figures of §2.4 across as §2.1 maps them, and do not touch their paths.
- [ ] **Step 3: render and check** — run §4.5, §4.2, §4.3. Also confirm that the three `os.html`
  figures still carry `<figcaption>System Settings</figcaption>`, and that `[images/test-image.png]`
  is still text inside a `<pre>` on `writing-projects-documentation.html` (§2.4).
- [ ] **Step 4: commit** — `docs(#70): convert the infrastructure site pages to Markdown`. The body
  must name the `Contents` headings and the five dead image references carried across, and point
  at §2.4.

### Task 4: Confirm `apt/` is gone everywhere in scope

- [ ] **Step 1** — run §4.1. Expected: no output.
- [ ] **Step 2** — `find . -type d -path '*/src/site/apt' -not -path '*/archetype-resources/*' -not -path '*/target/*'`.
  Expected: no output. An empty directory left on disk does not matter to git, but delete it
  locally so later renders cannot pick up a stale file.

### Task 5: Remove the redundant dependency, and do the final verification

**Files:** `pom.xml:219-223`.

- [ ] **Step 1: delete the `doxia-module-apt` dependency from `maven-site-plugin` only.** Leave
  `pom.xml:417-421` (`maven-pdf-plugin`) alone.
- [ ] **Step 2: full render** — `mvn -B clean`, then §4.5. Expected: both exit codes `0`.
- [ ] **Step 3: all checks, all 15 pages** — §4.1 to §4.4, plus
  `git ls-files '*/src/site/markdown/*.md' | wc -l`, which must be 29: the 14 already on
  `master` at c8e75441, plus the 15. Record in this spec, under this
  step: the exit codes, the output of each check, and every accepted rendering difference from
  §4.2, one line each.
- [ ] **Step 3b: confirm no consumer impact** — run `mvn -B dependency:resolve-plugins`
  (redirected to `.logs/`) and confirm that `doxia-module-apt` 2.0.0 still resolves for
  `maven-site-plugin`, through the plugin's own dependency. This is §1.1's claim, checked by running
  it rather than by reading a POM. If that goal does not list plugin dependencies, re-run the
  `infrastructure/maven-archetypes/maven-plugin` site alone with `-X` into `.logs/mvn-site-debug.log`
  and find `doxia-module-apt` in the `maven-site-plugin` realm.
- [ ] **Step 4: commit** — `build(#70): drop maven-site-plugin's redundant doxia-module-apt`. The
  body must state that the plugin already declares the module at the same version, so the removal
  changes nothing on the classpath and does not prove the migration is complete. It must also state
  that the pdf plugin's copy stays, and why. The spec's evidence goes in a separate
  `docs(#70): record the verification evidence` commit.

### Task 6: Post back to GitHub — only after the human approves each text

- [ ] **Step 1: a comment on `#70`** — correcting the completion criterion (§1.1) and the TOC
  count (§1.3), and stating that the AC005 evidence is AC001's file check, not the build.
- [ ] **Step 2: the follow-up issue** — whether the `infrastructure` documentation pages are still
  worth keeping, what generic guidance should replace them (for consuming projects and for
  parent-poms contributors), and the five dead images of §2.4 as the case that raised it. It is a
  plain issue with no milestone unless the human assigns one. Link it from `#70`.

---

## 6. Acceptance criteria — where each is met

| AC | Met by |
|---|---|
| AC001 — 15 `.md` files, no `.apt` outside `archetype-resources/` | §4.1; Task 4; Task 5 Step 3 |
| AC002 — `mvn site` builds, content intact | §4.5 exit codes; §4.2 on every page |
| AC003 — every `href="#…"` resolves | §4.3 on every page, after its negative test |
| AC004 — no `site.xml` edited | §4.4 |
| AC005 — `doxia-module-apt` removed, site builds | Task 5 — a no-op by §1.1; completion is shown by AC001 |
| AC006 — no prose rewritten | §4.2 text diff, with the §2.2 deviation named |

## 7. Out of scope

- The 39 `.apt` files under `archetype-resources/` (`#70`, *Explicitly out of scope*).
- Any content fix, including the five dead images (§2.4 — the follow-up issue).
- `.fml` files.
- The equally redundant `doxia-module-markdown` declaration (§1.1).
- `maven-pdf-plugin`'s dependency list (§1.2).
