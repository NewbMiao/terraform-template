output "network_id" {
  description = "Derived placeholder network identifier."
  value       = "${terraform_data.network.input.resource_prefix}-network-${terraform_data.network.input.environment}"
}

output "private_subnet_ids" {
  description = "Derived placeholder private subnet identifiers."
  value = [
    for i in range(terraform_data.network.input.availability_zone_count) :
    "${terraform_data.network.input.resource_prefix}-private-${terraform_data.network.input.environment}-${i}"
  ]
}

output "public_subnet_ids" {
  description = "Derived placeholder public subnet identifiers."
  value = [
    for i in range(terraform_data.network.input.availability_zone_count) :
    "${terraform_data.network.input.resource_prefix}-public-${terraform_data.network.input.environment}-${i}"
  ]
}
