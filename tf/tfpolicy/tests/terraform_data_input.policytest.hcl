policytest {
  targets = ["../policies/terraform_data_input.policy.hcl"]
}

resource "terraform_data" "ok" {
  attrs = {
    input = {
      environment = "staging"
    }
  }
}

resource "terraform_data" "bad" {
  expect_failure = true

  attrs = {}
}
