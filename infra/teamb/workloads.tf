module "workload" {
  source   = "../modules/workload"
  for_each = var.workloads

  environment        = var.environment
  team_name          = var.team_name
  name               = each.key
  workload_type      = each.value.workload_type
  size_tier          = each.value.size_tier
  network_exposure   = each.value.network_exposure
  network_id         = var.platform_network.network_id
  private_subnet_ids = var.platform_network.private_subnet_ids
}

output "workloads" {
  description = "Resolved placeholder workload configuration keyed by workload name."
  value       = { for k, m in module.workload : k => m.workload }
}
