---
description: Run integration tests (*IT.java / *IntegrationTest.java) via the failsafe plugin
---

Run the following command in the repo root and report the result, summarizing any failures:

```bash
mvn -B verify
```

Unit tests (surefire) run first and exclude `*IT.java` / `*IntegrationTest.java`; failsafe then runs
only those integration test classes, bound to the `integration-test` and `verify` phases.
