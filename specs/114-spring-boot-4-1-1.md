# Spec: move `products` to Spring Boot 4.1.1 and drop what Boot 4 leaves dead (`#114`)

| | |
|---|---|
| Issue | [`#114`](https://github.com/MRISS-Projects/parent-poms/issues/114): Move products to Spring Boot 4.1.1 and drop what Boot 4 leaves dead |
| Milestone | `3.11.2-SNAPSHOT`, the hotfix line `#112` opened. 3.11.2 is released when this is done |
| Branch | `issue-114-spring-boot-4-1-1`, cut from `master` at `dfe8ecb2` |
| Asked for by | [`MRISS-Projects/dsh#120`](https://github.com/MRISS-Projects/dsh/issues/120), whose spec is `specs/stories/120-upgrade-spring-boot.md` in DSH |

> **For agentic workers:** implement this task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal.** A product of `products` builds on Spring Boot 4.1.1, with springdoc-openapi managed in
place of Springfox, and no managed entry left that Boot 4 makes dead.

**Architecture.** `products/pom.xml` only: two properties change, five go, and the
`dependencyManagement` entries follow them. No plugin, profile or workflow changes. No re-version:
`master` is already `3.11.2-SNAPSHOT`.

## 1. What is true today

1. **Spring Boot is 2.7.18**, set by `spring-boot.version` in `products/pom.xml`, which imports
   `spring-boot-dependencies` and sets `spring-boot-maven-plugin`'s version from it. Boot 2.7's
   open-source support ended on 2023-11-24.
2. **`products/pom.xml` also manages** `springfox-swagger2` and `springfox-swagger-ui`
   (`spring-fox.version` 3.0.0), `io.swagger:swagger-annotations` 1.6.14, `javax.xml.bind:jaxb-api`
   2.4.0-b180830.0359, `spring-data-solr` 4.3.15, and a `byte-buddy`/`byte-buddy-agent` override at
   1.14.5 whose comment ties it to Boot 2.7's 1.12.x.
3. **Springfox does not start on Boot 3 or later**, and has no release since 3.0.0 (2020).
   `spring-data-solr` is discontinued, and DSH removed Solr in `MRISS-Projects/dsh#177`. Boot 4.1.1
   manages Byte Buddy 1.18.11, so the 1.14.5 override would now hold it back.
4. **DSH is the only product on the current `products`.** `mail-processor-service` is pinned to
   `products` 3.6.3; the translator and DSD-SlideShow use other parents. Nothing else uses the
   entries above (a search of the MRISS repositories on 2026-10-21).

## 2. Design

### 2.1 The version

Spring Boot 4.1.1: the 4.1 line is supported to 2027-07-31, and Spring Cloud GCP 8.x, which DSH's
Waves 2-3 build on, is built against it. DSH `#120`'s spec, §2.2, holds the analysis.

### 2.2 The change, in `products/pom.xml`

- `dependencyManagement`: delete the `byte-buddy` and `byte-buddy-agent` entries and their comment,
  the two `io.springfox` entries, `swagger-annotations`, `jaxb-api` with its `FR006` comment, and
  `spring-data-solr` with its comment. After the Boot BOM import, add:

  ```xml
              <dependency>
                  <groupId>org.springdoc</groupId>
                  <artifactId>springdoc-openapi-starter-webmvc-api</artifactId>
                  <version>${springdoc.version}</version>
              </dependency>
              <dependency>
                  <groupId>org.springdoc</groupId>
                  <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
                  <version>${springdoc.version}</version>
              </dependency>
  ```

- `properties`: delete `spring-fox.version`, `swagger-annotations.version`, `jaxb-api.version`,
  `spring-data-solr.version` and `byte-buddy.version` with their comments. Replace the `FR005`
  comment and the Boot version with:

  ```xml
          <!-- #114: Spring Boot 4.1.1, open-source support to 2027-07-31 (Spring Cloud GCP 8.x) -->
          <spring-boot.version>4.1.1</spring-boot.version>
          <springdoc.version>3.1.1</springdoc.version>
  ```

The UI starter is managed though DSH does not use it yet, so that DSH `#144`, serving the Swagger UI,
is one dependency in DSH and no change here.

### 2.3 The release

No snapshot deploy: DSH `#120` validates against the `SNAPSHOT` installed locally, and its pull
request builds against the released 3.11.2. With this issue closed, milestone `3.11.2-SNAPSHOT`
has nothing open; it is renamed `3.11.2` and released with `deploy.yml`, `release_type: releases`,
after DSH `#120`'s local review. That release tags `mriss-parent-3.11.2` and moves `master` to
`3.12.0-SNAPSHOT`.

## 3. Acceptance criteria

- **AC001.** `mvn -B install` is green here, and the installed
  `products-3.11.2-SNAPSHOT.pom` shows `spring-boot.version` 4.1.1 and the two `springdoc` entries,
  and none of `springfox`, `solr`, `byte-buddy`, `jaxb` or `swagger-annotations`. (Task 1.)
- **AC002.** DSH builds green against `3.11.2-SNAPSHOT`, its gates 1 and 3 included, with every
  `org.springframework.boot` artifact at 4.1.1. (Task 2.)

## 4. Tasks

### Task 1: the change (AC001)

- [x] **Step 1:** make §2.2's change, then `mvn -B install`. Expected: exit 0, and the installed POM
  as AC001 says. Commit `build(#114): move products to Spring Boot 4.1.1 and manage springdoc`.

### Task 2: verified in DSH (AC002)

DSH's story `#120` builds against the installed `SNAPSHOT` and runs its gates. The results are
recorded in DSH's spec, §7.

## 5. Out of scope

- Mockito: the root still forces 5.17.0 over Boot 4.1.1's 5.23.0. Bumping it changes the root every
  consumer inherits.
- `junit:junit`'s managed version, as in `#112`.
- Any Spring Cloud or Spring Cloud GCP BOM. DSH's Wave 2 adds it when it needs it.

## 6. Results

- **Task 1.** `98d2c84b`, 9 lines in and 48 out. `mvn -B install` exited 0, and the installed
  `products-3.11.2-SNAPSHOT.pom` holds `spring-boot.version` 4.1.1, `springdoc.version` 3.1.1 and
  both `springdoc` entries, and none of the removed names.
- **Task 2.** DSH `#120` on 2026-10-28, against the installed `SNAPSHOT`: gate 1 and gate 3 exited
  0, 66 `org.springframework.boot` artifacts all at 4.1.1, no `io.springfox` and no
  `spring-data-solr`. Recorded in DSH's spec, §7.4.
