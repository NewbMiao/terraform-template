# policies

Template layout rules checked with **Terraform Policy** (`tfpolicy`).

```bash
brew tap hashicorp/tap && brew install hashicorp/tap/tfpolicy
./scripts/run-tfpolicy.sh validate
./scripts/run-tfpolicy.sh test
```

| Policy | Intent |
|--------|--------|
| `terraform_data_input` | Placeholder `terraform_data` must set `input` |
| `module_source_local` | Callers use `../modules/` or `./modules/` only |
| `data_naming` | `terraform_data.input` layout naming (mirrors `.tflint.d/policies/data_naming.rego`) |

Pre-commit runs `test` when `tfpolicy` is on PATH. Same policies can attach to **Terraform Cloud** policy sets later.
