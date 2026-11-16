resource "terraform_data" "workload" {
  input = {
    team_name          = var.team_name
    name               = var.name
    workload_type      = var.workload_type
    size_tier          = var.size_tier
    network_exposure   = var.network_exposure
    network_id         = var.network_id
    private_subnet_ids = var.private_subnet_ids
  }
}
