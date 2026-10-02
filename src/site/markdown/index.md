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
