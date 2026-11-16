# terraform-template

Starter layout: shared `base/`, team×env `infra/`. Skeleton uses `terraform_data` only — add your provider resources when you pick a cloud. Fictional names (`example-org`, `net-*` prefixes, sample teams `teama` / `teamb`).

## Layout

```
base/
  modules/network/
  platform/          # network.auto.tfvars, platform.auto.tfvars, backend.hcl
  permissions/       # permissions.auto.tfvars, roles.auto.tfvars, backend.hcl
infra/
  modules/workload/
  teama|teamb/config/staging|prod/   # *.auto.tfvars, backend.hcl
policies/            # tfpolicy (+ naming parity with TFLint OPA)
.tflint.d/policies/  # TFLint OPA Rego (layout naming on terraform_data.input)
```

- **State:** one backend per `base/<scope>` and per `infra/<team>/config/<env>/`.
- **base:** shared config; environments are tfvars keys, not extra folders.
- **infra:** one state file per team and env (`staging`, `prod`).

## Commands

```bash
./terraform.sh base platform init
./terraform.sh base platform plan -refresh=false
./terraform.sh infra teama staging plan -refresh=false
```

`terraform.sh` loads `TF_VAR_*` from `base/.env` or `infra/.env` (and stack-level `.env` if present). Do not pass secrets with `-var=` on the CLI.

**Backend:** partial `backend "local" {}` in each stack; path or Terraform Cloud block in `backend.hcl` (commented placeholders).

**Cross-stack reads:** `infra/*/data.tf` uses `terraform_remote_state` (local paths; remote variant in comments).

**Secrets:** copy `base/.env.example` / `infra/.env.example` → `.env`, or TFC workspace variables. Nothing sensitive in git.

## Dev tooling

Install (macOS):

```bash
brew install tfenv pre-commit checkov infracost go terraform-docs
brew install terraform-linters/tap/tflint
brew tap hashicorp/tap && brew install hashicorp/tap/tfpolicy
cd "$(git rev-parse --show-toplevel)" && tfenv install && tflint --init --config=.tflint.hcl
pre-commit install --hook-type pre-commit --hook-type pre-push
```

| Hook / script | When |
|---------------|------|
| YAML, merge markers, whitespace, private keys | commit |
| fmt, `terraform_docs` (stack `README.md`) | commit |
| validate (pre-commit-terraform), `scripts/tflint-env.sh` (tflint + OPA) | commit |
| `./scripts/run-tfpolicy.sh test` | commit |
| checkov (`.checkov.yaml`) | push |
| `./scripts/run-infracost.sh` | manual (needs API key) |

**Naming examples:** `data_naming.rego` and `data_naming.policy.hcl` — e.g. `input.resource_prefix` starts with `net-`, workload `input.name` without `_`.

Stack docs: keep `<!-- BEGIN_TF_DOCS -->` in each stack `README.md`; pre-commit regenerates the block from `.tf` files (config `.terraform-docs.yml`).
