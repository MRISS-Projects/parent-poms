# Parent POMs Structure Project

![GitHub](https://img.shields.io/github/license/MRISS-Projects/parent-poms?color=blue&label=License) [![Deploy Status](https://github.com/MRISS-Projects/parent-poms/actions/workflows/deploy.yml/badge.svg)](https://github.com/MRISS-Projects/parent-poms/actions/workflows/deploy.yml)

## Version

${project.build.version}

## Build from Sources

```bash
# Unit tests only. This is the ordinary build, and the one the 95% coverage gate measures.
mvn -B clean install

# Unit tests, then integration tests.
mvn -B clean install -DintegrationTests
```

Integration tests are the classes named `*IT.java` or `*IntegrationTest.java`; by convention
they live in an `integration` package under `src/test/java`. They run only when
`-DintegrationTests` is passed, and on every staging build. Their coverage is collected
separately, in `target/jacoco-it.exec`, and is deliberately not counted toward the coverage
gate — that gate measures unit tests.

## Code Based Site

Snapshot: https://mriss-projects.github.io/parent-poms/snapshots

Release: https://mriss-projects.github.io/parent-poms/releases

## Release Notes

${issues.text.list}
