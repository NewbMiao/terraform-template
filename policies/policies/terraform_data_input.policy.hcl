# Layout scaffold: terraform_data placeholders must carry an input map (no empty shells).

resource_policy "terraform_data" "require_input" {
  enforcement_level = "mandatory"

  enforce {
    condition     = core::try(attrs.input, null) != null
    error_message = "terraform_data must define input = { ... } (layout placeholders)."
  }
}
