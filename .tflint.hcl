# TFLint: Terraform language + OPA naming (experimental).
#   tflint --init --config=.tflint.hcl
#   export TFLINT_OPA_POLICY_DIR="$(git rev-parse --show-toplevel)/.tflint.d/policies"

config {
  call_module_type = "local"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "opa" {
  enabled = true
  version = "0.11.0"
  source  = "github.com/terraform-linters/tflint-ruleset-opa"
}
