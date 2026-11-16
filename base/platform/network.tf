module "network" {
  source   = "../modules/network"
  for_each = var.environment_networks

  environment             = each.key
  resource_prefix         = each.value.resource_prefix
  cidr_block              = each.value.cidr_block
  availability_zone_count = each.value.availability_zone_count
  nat_gateway_enabled     = each.value.nat_gateway_enabled
  tags                    = var.tags
}
