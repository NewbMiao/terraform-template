policytest {
  targets = ["../policies/data_naming.policy.hcl"]
}

resource "terraform_data" "net_ok" {
  attrs = {
    input = {
      resource_prefix = "net-staging"
    }
  }
}

resource "terraform_data" "net_bad" {
  expect_failure = true

  attrs = {
    input = {
      resource_prefix = "vpc-staging"
    }
  }
}

resource "terraform_data" "workload_ok" {
  attrs = {
    input = {
      name      = "api"
      team_name = "teama"
    }
  }
}

resource "terraform_data" "workload_bad" {
  expect_failure = true

  attrs = {
    input = {
      name = "api_v2"
    }
  }
}
