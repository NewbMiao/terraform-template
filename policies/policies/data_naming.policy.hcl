# Mirrors .tflint.d/policies/data_naming.rego

resource_policy "terraform_data" "network_resource_prefix" {
  enforcement_level = "mandatory"
  filter            = core::try(attrs.input.resource_prefix, null) != null

  enforce {
    condition     = core::startswith(attrs.input.resource_prefix, "net-")
    error_message = "input.resource_prefix must start with net- (got ${attrs.input.resource_prefix})."
  }
}

resource_policy "terraform_data" "workload_name_slug" {
  enforcement_level = "mandatory"
  filter            = core::try(attrs.input.name, null) != null

  enforce {
    condition = !core::contains_substring(attrs.input.name, "_")
    error_message = "input.name must not contain _ (got ${attrs.input.name})."
  }
}
