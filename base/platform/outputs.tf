output "network_by_environment" {
  description = "Per-environment network outputs — copy into infra config platform_network.auto.tfvars (template does not use terraform_remote_state)."
  value = {
    for env, mod in module.network : env => {
      network_id         = mod.network_id
      private_subnet_ids = mod.private_subnet_ids
      public_subnet_ids  = mod.public_subnet_ids
    }
  }
}
