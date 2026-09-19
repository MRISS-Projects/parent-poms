---
description: Generate the Maven site locally without publishing to gh-pages
---

Run the following command in the repo root and report whether it succeeds, summarizing any errors
(especially "clashes with existing" — see the `generatedSiteDirectory` note in CLAUDE.md):

```bash
mvn -B -Ddeployment -Drelease-deployment \
  -Dsite.deployment.personal.main=file:///tmp/sites site
```

This mirrors the Build GitHub Actions workflow's site-generation step. It does not publish anything
(no gh-pages push, no README.md commit).

It will rewrite `README.md` in your working tree — the site build forks the default lifecycle and
replays `copy-readme-md` — so expect `git status` to show it modified. Nothing is committed: `#71`
moved the commit out of Maven into `.github/actions/commit-readme`. `-Dcommit.readme.phase=none` used
to be required here to prevent a commit *and push*; it is now inert and has been dropped.
