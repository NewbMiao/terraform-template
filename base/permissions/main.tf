resource "terraform_data" "roles" {
  input = {
    catalogue = var.role_catalogue
    tags      = var.tags
  }
}

output "role_catalogue" {
  description = "Placeholder role names keyed by function."
  value       = terraform_data.roles.input.catalogue
}
