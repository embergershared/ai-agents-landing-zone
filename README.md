# __PROJECT_NAME__

__DESCRIPTION__

<!-- template:start -->
> [!IMPORTANT]
> **This is embergershared/repo-template**, the starting point for new embergershared
> projects. Create a repository with **Use this template**, clone it, then run once
> (PowerShell, in its folder):
> ```powershell
> ./scripts/Initialize-Repo.ps1 -Description '<one line about the project>' -Stacks dotnet,python
> ```
> It fills in the placeholders, removes the stack you don't use, sets the repository and its
> security features up, and opens the first issue and PR. See
> [docs/template.md](docs/template.md) for everything the template contains.
<!-- template:end -->

> [!NOTE]
> This is a personal project, shared as is to help others. It is not an official Microsoft
> product and is not supported by Microsoft. Review and test it before using any part of it
> in your environment. See [SUPPORT.md](SUPPORT.md).

## Getting started

<!-- How to build, run and test the project locally (PowerShell), e.g.:
```powershell
dotnet build; dotnet test
```
-->

## How work is done here

Every change starts with an issue, gets its own `<type>/<issue>-<slug>` branch, and reaches
`main` only through a PR that closes the issue. The full rules, for people and AI coding
assistants alike, are in [.github/copilot-instructions.md](.github/copilot-instructions.md);
[CONTRIBUTING.md](CONTRIBUTING.md) has the short version.

| Topic | Where |
|---|---|
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) |
| Reporting a vulnerability | [SECURITY.md](SECURITY.md) |
| CI/CD workflows, ruleset, security settings, repository variables | [docs/ci-cd.md](docs/ci-cd.md) |
| Package feeds, age gate, lock files | [docs/supply-chain.md](docs/supply-chain.md) |
| Database migrations, backups, rollback | [docs/database.md](docs/database.md) |
| Decisions | [docs/decisions/](docs/decisions/) |
| Changes | [CHANGELOG.md](CHANGELOG.md) |

## License

[MIT](LICENSE)
