environment_networks = {
  staging = {
    resource_prefix         = "net-staging"
    cidr_block              = "10.10.0.0/16"
    availability_zone_count = 2
    nat_gateway_enabled     = true
  }
  prod = {
    resource_prefix         = "net-prod"
    cidr_block              = "10.20.0.0/16"
    availability_zone_count = 2
    nat_gateway_enabled     = true
  }
}
