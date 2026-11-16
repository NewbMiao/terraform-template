# Layout naming on terraform_data.input (cloud-neutral scaffold).
# Layout naming (TFLint/OPA); tfpolicy uses terraform_data_input.policy.hcl as the resource_policy example.

package tflint

import rego.v1

deny_invalid_network_resource_prefix contains issue if {
	items := terraform.resources("terraform_data", {"input": "any"}, {})
	item := items[_]
	input_val := item.config.input.value
	is_object(input_val)
	prefix := input_val.resource_prefix
	is_string(prefix)
	not startswith(prefix, "net-")

	issue := tflint.issue(
		sprintf(`input.resource_prefix must start with "net-" (got %v)`, [prefix]),
		item.config.input.range,
	)
}

deny_invalid_workload_name contains issue if {
	items := terraform.resources("terraform_data", {"input": "any"}, {})
	item := items[_]
	input_val := item.config.input.value
	is_object(input_val)
	name := input_val.name
	is_string(name)
	contains(name, "_")

	issue := tflint.issue(
		sprintf(`input.name must not contain "_" (got %v)`, [name]),
		item.config.input.range,
	)
}
