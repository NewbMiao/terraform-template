# terraform-template

Portable **base + infra** Terraform starter (cloud-neutral `terraform_data` scaffold). Sample teams `teama` / `teamb` — rename dirs and run `./tf.sh conf -g` when you fork.

```mermaid
flowchart LR
  S["Shared foundation\nbase/"]
  T["Team workloads\ninfra/"]
  E["Wrapper + guardrails\ntf.sh · tf/"]

  S -->|"apply first · then hand off\nplatform facts to teams"| T
  E --> S
  E --> T
```

Shared and team layers use **separate state**. Platform context reaches teams through **checked-in config**, not `terraform_remote_state`. Sample `.tf` is placeholder until you wire your cloud; secrets stay in gitignored `.env`.

```
base/<scope>/          one state per scope (e.g. platform, permissions)
infra/<team>/          team .tf + config/<env>/ (*.auto.tfvars, backend.hcl)
tf.sh                  entrypoint wrapper
tf/                    wrapper, policies, linters, infracost catalogue
```

## Commands

```bash
./tf.sh conf
./tf.sh b platform init
./tf.sh i teama staging plan -refresh=false
./tf.sh -i              # menu (fzf)
```

| Pattern | Meaning |
|---------|---------|
| `b <scope> <cmd>` | shared stack under `base/` |
| `i <team> <env> <cmd>` | team stack + env tfvars |

## Tooling

```bash
tfenv install && tflint --init --config=tf/.tflint.hcl
pre-commit install --hook-type pre-commit --hook-type pre-push
```

Tooling configs live under `tf/`; optional root `infracost.yml` → `tf/infracost.yml` symlink.

**Deeper setup** (pre-commit, tflint OPA, tfpolicy, checkov, infracost): see the Terraform on Azure book on Leanpub — **<https://leanpub.com/terraform-on-azure>**.
