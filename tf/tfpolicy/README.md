# Terraform Policy (`tfpolicy`)

One **enforced** example per policy kind (cloud-neutral). Kind selects Setup / Plan timing — not a custom `stage` field.

```bash
brew tap hashicorp/tap && brew install hashicorp/tap/tfpolicy
./tf/run-tfpolicy.sh validate
./tf/run-tfpolicy.sh test
```

| File | Kind |
|------|------|
| [`provider_hashicorp_registry.policy.hcl`](policies/provider_hashicorp_registry.policy.hcl) | `provider_policy` (Setup) |
| [`module_source_local.policy.hcl`](policies/module_source_local.policy.hcl) | `module_policy` (Setup) |
| [`terraform_data_input.policy.hcl`](policies/terraform_data_input.policy.hcl) | `resource_policy` (Plan) |

Each has a matching `tests/*.policytest.hcl`. Pre-commit runs `test` when `tfpolicy` is on PATH. [Policy docs](https://developer.hashicorp.com/terraform/policy).
