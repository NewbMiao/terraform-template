terraform {
  required_version = ">= 1.8.0, < 2.0.0"

  # Partial backend — init: terraform init -backend-config=backend.hcl
  backend "local" {}
}
