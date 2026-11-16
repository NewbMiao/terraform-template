policytest {
  targets = ["../policies/module_source_local.policy.hcl"]
}

module "../modules/network" "ok" {
  meta = {
    source = "../modules/network"
  }
}

module "../../shared/modules/network" "bad" {
  expect_failure = true

  meta = {
    source = "../../shared/modules/network"
  }
}
