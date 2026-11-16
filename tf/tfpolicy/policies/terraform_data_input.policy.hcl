# Enforced by ./tf/run-tfpolicy.sh test.
# Kind: resource_policy  |  Phase: Plan  |  Data: attrs (paired pass/fail in tests/)

resource_policy "terraform_data" "require_input" {
  enforcement_level = "mandatory"

  enforce {
    condition     = core::try(attrs.input, null) != null
    error_message = "terraform_data must define input = { ... } (layout placeholders)."
  }
}
