---
description: Generate the Maven site locally without publishing to gh-pages
---

Run the following command in the repo root and report whether it succeeds, summarizing any errors
(especially "clashes with existing" — see the `generatedSiteDirectory` note in CLAUDE.md):

```bash
mvn -B -Ddeployment -Drelease-deployment -Dcommit.readme.phase=none \
  -Dsite.deployment.personal.main=file:///tmp/sites site
```

This mirrors the Build GitHub Actions workflow's site-generation step. It does not publish anything
(no gh-pages push, no README.md commit).
