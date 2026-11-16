output "network_by_environment" {
  description = "Infra teams read this via remote_state (keyed by environment)."
  value = {
    for env, mod in module.network : env => {
      network_id         = mod.network_id
      private_subnet_ids = mod.private_subnet_ids
      public_subnet_ids  = mod.public_subnet_ids
    }
  }
}
