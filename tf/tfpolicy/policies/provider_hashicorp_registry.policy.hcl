# Enforced — scaffold stacks should only declare hashicorp/* providers (no third-party forks).
# Kind: provider_policy  |  Phase: Setup  |  azurerm/azuread still pass when you add a cloud later.

provider_policy "*" "hashicorp_registry" {
  enforcement_level = "mandatory"
  filter            = meta.source != null

  enforce {
    condition = core::startswith(
      meta.source,
      "registry.terraform.io/hashicorp/",
    )
    error_message = "Provider source must be registry.terraform.io/hashicorp/* (got ${meta.source})."
  }
}
