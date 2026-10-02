# Spec: make a consumer site's "Products" parent link resolve (`#89`)

| | |
|---|---|
| Issue | [`#89`](https://github.com/MRISS-Projects/parent-poms/issues/89): consumer sites link to their parent "Products" page with a relative URL that 404s |
| Milestone | `3.10.0-SNAPSHOT` |
| Branch | `issue-89-parent-menu-link`, cut from `master` at `93522671` |
| Consumer | DSH. Its RC and release sites both carry the broken link today |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** On a consumer's site, the parent menu's "Products" entry leads to the published `products`
page, with no change to any consumer's `site.xml`.

**Architecture.** The link cannot be changed from here, so its target is made to exist. When a
consumer's root module stages its site, `products/pom.xml` also writes a one-page redirect at the
address the link points to. The redirect goes to the `products` site in parent-poms' Pages.

**Tech stack.** One `maven-antrun-plugin` execution in `products/pom.xml`, using core Ant only. It
is a POM change, so consumers get it by re-pinning to 3.10.0.

## 1. The cause, confirmed

The issue's "likely cause" names the projects' `<url>`. The mechanism is the one it describes, but
the URLs are different ones.

- **What the plugin uses.** `doxia-integration-tools` 2.0.0, which `maven-site-plugin` 3.21.0 runs,
  resolves `<menu ref="parent"/>` in `DefaultSiteTool.populateParentMenu`. That method takes the
  **`distributionManagement` site URL** of the parent and of the child, and writes the relative
  path between them. It was read from the disassembled class. `<url>` is not consulted.
- **What those URLs are.** The root `pom.xml` declares the site URL as
  `${site.deployment}/${release.type}/`, and Maven appends each child's artifactId. Every workflow
  passes `-Dsite.deployment.personal.main=file:///tmp/sites`. For DSH's RC that gives:

  | Project | `distributionManagement` site URL |
  |---|---|
  | `products`, DSH's parent | `file:///tmp/sites/rcs/products` |
  | `dsh` | `file:///tmp/sites/rcs/products/dsh` |

- **The result.** The two are one level apart on the same base, so the link is `../index.html`.
  The live release site shows it: `<a href="../index.html">Products</a>`, which is
  `https://mriss-projects.github.io/dsh/releases/products/index.html`, a 404.
- **Where the entry comes from.** `<menu ref="parent"/>` is in each consumer's own `site.xml`. DSH's
  root and every module have one.
- **Only one link per consumer site is wrong.** A DSH module's parent is DSH's root, in the same
  site, so its `../index.html` is right. Only the root's link, to `products`, crosses into another
  repository's Pages.

## 2. Options

| Option | Verdict |
|---|---|
| **Make the link absolute.** | Not possible from here. A child's site URL is its parent's plus its artifactId, so the pair always shares a base and the plugin always writes a relative path. |
| **Remove the entry.** The plugin drops the menu when the parent has no site URL. | Not possible either: `products` needs its site URL to stage its own site. |
| **Edit each consumer's `site.xml`.** | Ruled out by the issue. |
| **Make the target exist: a redirect page at `<type>/products/index.html` in the consumer's own Pages.** | **Chosen.** |

## 3. Design

### 3.1 What is written, and where

When a consumer's root module stages its site at `…/<type>/products/<consumer>/`, one more file is
written beside it: `…/<type>/products/index.html`. It is a small static page that redirects to the
`products` site in parent-poms' Pages, and carries a plain link for a browser that does not follow
the redirect.

- **Target.** `${parent.poms.site.url}/releases/products/`. `parent.poms.site.url` is a new root
  property, `https://mriss-projects.github.io/parent-poms`. It is separate from `sites.server`,
  which a consumer may override for its own site.
- **Always `releases`.** A consumer normally pins a released parent, and `releases/products/` is
  the page that describes one. A consumer on a `-SNAPSHOT` parent still lands on a real page.

### 3.2 How it is written

An execution of `maven-antrun-plugin` in `products/pom.xml`, inside a profile activated by
`-Ddeployment`, as site staging is.

- **Which module.** The execution is inherited by every descendant, but acts only where
  `${project.parent.artifactId}` is `products`. That is a consumer's root module, and nothing else.
  In a consumer's sub-modules and in `products` itself it does nothing.
- **Which directory.** The module's own staging directory, from
  `${project.distributionManagement.site.url}`, with the `file://` prefix removed. The page goes one
  level above it. If the URL is not a `file:` URL, the execution does nothing: it cannot write to a
  remote deployment.
- **When.** The `post-site` phase, which comes before `site-deploy`. So the page is in the staged
  tree before any publish, whether the publish is the workflows' separate step (`#88`) or a
  by-hand `site-deploy`.
- **Core Ant only.** `<condition>`, `<loadresource>` with a `replaceregex` filter, and the
  `if:set` attribute. No ant-contrib.

### 3.3 Effect on `#88`'s check

None. `verify-staged-site` treats a directory as a module site only if it holds
`project-info.html`. The `products/` directory in a consumer's staged tree holds only the redirect
page, so it is not counted, and not required to be a full site.

### 3.4 Not in scope

- **Sites already published.** DSH's `releases/products/dsh` (0.3.2) and its `rcs` site keep the
  404 until DSH next publishes with a parent that has this fix.
- **`framework` and `infrastructure` consumers.** No consumer inherits from them today. The same
  execution can be added there when one does.

## 4. Verification design

### 4.1 Local, before the PR

1. `mvn -B clean install` in parent-poms, so the local repository holds `3.10.0-SNAPSHOT` with the
   change.
2. **A consumer.** A scratch clone of DSH `DEVELOP`, with its parent re-pointed to
   `3.10.0-SNAPSHOT`, runs
   `mvn -B -Ddeployment -Drelease.type=rcs -Dsite.deployment.personal.main=file:///tmp/sites
   -Dscmpublish.skipDeploy=true site-deploy` on the root and one module (`-pl . ,dsh-test-dataset`).
   Check that:
   - `/tmp/sites/rcs/products/index.html` exists and redirects to
     `https://mriss-projects.github.io/parent-poms/releases/products/`;
   - `/tmp/sites/rcs/products/dsh/index.html` still links "Products" to `../index.html`, which now
     exists;
   - no redirect page is written above `dsh-test-dataset`, so `…/products/dsh/index.html` is still
     DSH's real home page;
   - `verify-staged-site` passes on the tree, counting 2 module sites.
3. **parent-poms itself.** The same staging command on the parent-poms root and `products`. Check
   that no redirect page appears anywhere, and that `products`' own site is unchanged.
4. **Red first.** Step 2 is run once before the POM change, to record that the page is absent.

### 4.2 The issue's third criterion: a DSH staging run

The issue asks for "a DSH staging run against a `-SNAPSHOT` containing the fix". A real staging run
has no dry-run mode. It needs an RC branch, deploys `-RC` artifacts, and publishes DSH's `rcs` site.
DSH has no RC branch at the moment.

**Decided on 2026-10-01: defer it, and close `#89` on the local evidence.**

- §4.1 proves what the staged tree holds. The PR records it.
- The live URL is checked at DSH's next real staging, the 0.4.0 RC, after DSH is re-pinned to
  3.10.0 (task 5). `#89` does not wait for it.
- **Not chosen:** a real staging run now, from a scratch RC branch cut from `DEVELOP`. It would
  meet the criterion to the letter, but it overwrites DSH's public `rcs` site with
  `0.4.0-SNAPSHOT` content and deploys RC packages.

## 5. Files to change

| File | Change |
|---|---|
| `pom.xml` | the `parent.poms.site.url` property |
| `products/pom.xml` | the `deployment`-activated profile with the antrun execution (§3.2) |
| `CLAUDE.md` | one row or paragraph on the redirect page, in the Profiles section |

## 6. Tasks

- [ ] **Task 1 (red).** Run §4.1 step 2 against the unchanged `3.10.0-SNAPSHOT`. Record that
      `/tmp/sites/rcs/products/index.html` is absent.
- [ ] **Task 2.** Add the property and the execution. Run `mvn -B clean install` until it is green.
- [ ] **Task 3 (green).** Run §4.1 steps 2 and 3, and record the results.
- [ ] **Task 4.** Update `CLAUDE.md`. Open a PR into `master` that references `#89`.
- [ ] **Task 5, later.** Check the live link at DSH's first staging on a parent with this fix (§4.2).

## 7. Acceptance criteria

| Criterion (from the issue) | Covered by |
|---|---|
| On a staged consumer site, the parent menu's "Products" entry resolves to a published `products` page | §3.1, §4.1 step 2 |
| The fix is made here, not by a per-consumer override in `site.xml` | §3.2: `products/pom.xml` only |
| Verified by a DSH staging run against a `-SNAPSHOT` containing the fix | Deferred to the 0.4.0 RC, by decision (§4.2). §4.1 stands in for it until then |

## 8. Verification results

To be filled in during the build.
