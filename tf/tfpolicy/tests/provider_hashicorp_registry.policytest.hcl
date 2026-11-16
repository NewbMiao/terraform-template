policytest {
  targets = ["../policies/provider_hashicorp_registry.policy.hcl"]
}

provider "random" "hashicorp_ok" {
  meta = {
    source  = "registry.terraform.io/hashicorp/random"
    version = "3.6.3"
  }
}

provider "random" "fork_bad" {
  expect_failure = true

  meta = {
    source  = "registry.terraform.io/acme/random"
    version = "1.0.0"
  }
}
