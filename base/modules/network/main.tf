resource "terraform_data" "network" {
  input = {
    environment             = var.environment
    resource_prefix         = var.resource_prefix
    cidr_block              = var.cidr_block
    availability_zone_count = var.availability_zone_count
    nat_gateway_enabled     = var.nat_gateway_enabled
    tags                    = var.tags
  }
}
