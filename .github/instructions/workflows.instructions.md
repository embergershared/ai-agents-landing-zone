---
applyTo: ".github/workflows/**"
---

# GitHub Actions workflows

- **Pin actions by commit SHA** with the version in a comment
  (`actions/checkout@<sha> # v7.0.1`), and only releases at least 7 days old. Dependabot
  (`.github/dependabot.yml`, 7-day cooldown) proposes the bumps.
- **Least privilege:** top-level `permissions: contents: read`; widen per job only.
  `persist-credentials: false` on checkout unless the job pushes.
- **Every job** has `timeout-minutes`. Concurrency: cancel superseded PR runs; never cancel
  runs on `main`, image pushes, deploys or teardowns.
- **Untrusted input** (PR titles, bodies, branch names) goes through `env:`, never straight
  into `run:` with `${{ }}`.
- **GitHub-hosted runners only.** This repository is public: a self-hosted runner would run
  code from fork PRs on that machine.
- **Deploys:** behind a GitHub environment and an on/off repository variable; Azure through
  OIDC (`id-token: write`, `azure/login`), IDs from repository variables, never secrets in
  logs.
- **`CI result`** in `ci.yml` is the single check to require: add new CI jobs to its `needs`.
- actionlint (with shellcheck) runs in CI on every workflow change.
