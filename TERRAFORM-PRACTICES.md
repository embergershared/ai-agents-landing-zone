# Working with Terraform safely

Back to the [README](README.md).

From the upstream Terraform guide, and this repository's own rules:

- **State is sensitive.** State and plan files can hold secrets: never commit them. Keep
  state in an Azure Storage backend with Entra ID authentication, locking, versioning and
  one state per environment, set up before the first `terraform init`.
- **Sign-in:** `az login` and `az account set` on a workstation; OIDC (workload identity
  federation) in pipelines. No client secrets in `.tf` files, shell history or variables.
- **Plan, review, apply:** `terraform init`, `terraform validate`,
  `terraform plan -out=<file>`, `terraform show <file>`, then `terraform apply <file>` after
  review. Review additions, replacements, deletions, role assignments, public access and
  recurring costs. A saved plan applies without prompting, so get approval first.
- **Lock file:** commit `.terraform.lock.hcl`; don't run `terraform init -upgrade` as a
  generic fix.
- **Verify after apply:** list the resources, check the Foundry project and model
  deployments, check diagnostics, and check data-plane access with the intended identity,
  not just that the resources exist.
- **Common failures:** missing role-assignment rights (`AuthorizationFailed`), resource
  provider not registered, model or quota not available in the region, a resource that
  already exists in another state, and a Foundry account name still held by soft delete.
- **Changes and retirement:** renaming or moving regions can replace resources and lose data.
  Retire with `terraform plan -destroy -out=<file>`, review it, and apply only after
  approval. Don't delete things to work around a failed apply.
