# What the template contains

New embergershared repositories start from
[embergershared/repo-template](https://github.com/embergershared/repo-template). It brings the
rules, tools, CI/CD and security settings shared by the projects, so each project doesn't
re-create them. Most of these projects are public: the template assumes it.

## Start a project

1. On GitHub: **embergershared/repo-template → Use this template → Create a new repository**
   (owner `embergershared`, public).
2. Clone it, then in its folder (PowerShell):
   ```powershell
   ./scripts/Initialize-Repo.ps1 -Description '<one line about the project>' -Stacks dotnet,python
   ```
   `-Stacks dotnet` or `-Stacks python` removes the other stack's files. `-WhatIf` shows what
   would change; `-SkipGitHub` only edits the files.
   The script replaces the placeholders `__PROJECT_NAME__`, `__REPO__`, `__DESCRIPTION__` and
   `__YEAR__` (this file keeps them), sets the repository (issues on, wiki off, branches
   deleted on merge, label `phase`) and, when it is public, its security features and the
   `main` ruleset (see [ci-cd.md](ci-cd.md#repository-settings)). Then it opens issue
   *Initialize the repository from repo-template*, commits on
   `emberger/chore/<issue>-initialize-from-template`, and opens the PR.
3. Merge that PR once its checks are green. Then see [After the first PR](#after-the-first-pr).

## Files

| Path | What it does |
|---|---|
| `.github/copilot-instructions.md` | **The rules** for people and AI coding assistants: authorship, customer data, issue → branch → PR, branch names, commits, secrets, feeds and age gate, safety, testing, database migrations, PowerShell, nano. Ends with a *This project* section to fill in. |
| `.github/instructions/*.instructions.md` | Copilot rules per file type: Terraform (added here), workflows. |
| `.github/workflows/ci.yml` | Build, lint, test (.NET, Python and, added here, Terraform, auto-detected), workflow lint, package age gate, one `CI result` check. |
| `.github/workflows/pr-rules.yml` | Branch name (no owner prefix from a fork), base branch, linked issue, no AI attribution, commit style warnings. |
| `.github/dependabot.yml` | GitHub Actions and (added here) Terraform updates with a 7-day cooldown (NuGet and Docker ready to uncomment). |
| `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/` | PR body (What, Database, Tests) and issue forms (feature, bug, phase). |
| `README.md` | Project page, with the "personal project, not an official Microsoft product" note. |
| `SECURITY.md`, `SUPPORT.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Private vulnerability reporting, as-is support, how to contribute, Contributor Covenant. |
| `.editorconfig`, `.gitattributes`, `.gitignore`, `.dockerignore` | Editor rules, line endings (LF for Linux files), ignored secrets/databases/build output. |
| `scripts/check_package_age.py` | CI gate: every locked NuGet/PyPI version is at least 7 days old. |
| `scripts/db/sqlite_backup.py` | WAL-safe SQLite backup, copy, verify, compare, restore. |
| `scripts/Initialize-Repo.ps1` | One-time setup of a new repository (removes itself). |
| `docs/` | CI/CD and repository settings, supply chain (and how to turn the approved feed off), database, decisions (ADR template). |
| `CHANGELOG.md`, `LICENSE` | Keep a Changelog; MIT. |

This repository removed the template's .NET and Python stack files when it was initialized
(#1): it deploys infrastructure with Terraform, whose tooling was added in #6.

The template has no agent-tool configuration beyond Copilot's instruction files: anything a
maintainer's own tools need stays in that maintainer's user settings, not in the repository.

## Add a stack

- **.NET or Python:** copy the stack's files back from
  [embergershared/repo-template](https://github.com/embergershared/repo-template) and follow
  its `docs/template.md`; CI picks the stack up once its solution or lock file is committed.
- **Terraform:** a root module per folder under `src/`, following
  `.github/instructions/terraform.instructions.md`; deploys go through OIDC (see
  [ci-cd.md](ci-cd.md#deploys)).

## After the first PR

- **Dependabot:** uncomment the `nuget` / `docker` blocks the project needs.
- **CodeQL:** once the project has code, check **Security → Code scanning** lists its
  languages (default setup picks them up on the next scan).
- Fill in the *This project* section of `.github/copilot-instructions.md`.

## Keep projects in step with the template

The template only copies files once. When it improves, port the change to existing projects
through an issue and PR in each.
