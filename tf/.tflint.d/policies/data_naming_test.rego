package tflint

import rego.v1

net_bad(type, schema, options) := terraform.mock_resources(type, schema, options, {"main.tf": `
resource "terraform_data" "network" {
  input = {
    resource_prefix = "vpc-staging"
  }
}
`})

test_deny_invalid_network_resource_prefix_failed if {
	issues := deny_invalid_network_resource_prefix with terraform.resources as net_bad
	count(issues) == 1
	issues[_].msg == `input.resource_prefix must start with "net-" (got vpc-staging)`
}

net_ok(type, schema, options) := terraform.mock_resources(type, schema, options, {"main.tf": `
resource "terraform_data" "network" {
  input = {
    resource_prefix = "net-staging"
  }
}
`})

test_deny_invalid_network_resource_prefix_passed if {
	issues := deny_invalid_network_resource_prefix with terraform.resources as net_ok
	count(issues) == 0
}

workload_bad(type, schema, options) := terraform.mock_resources(type, schema, options, {"main.tf": `
resource "terraform_data" "workload" {
  input = {
    name = "api_v2"
  }
}
`})

test_deny_invalid_workload_name_failed if {
	issues := deny_invalid_workload_name with terraform.resources as workload_bad
	count(issues) == 1
}
