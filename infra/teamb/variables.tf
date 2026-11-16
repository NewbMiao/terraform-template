variable "environment" {
  type        = string
  description = "Must match config/<environment>/."

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be staging or prod."
  }
}

variable "team_name" {
  type        = string
  description = "Team slug; used in names and state paths."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.team_name))
    error_message = "team_name must be a lowercase slug."
  }
}

variable "platform_network" {
  type = object({
    network_id         = string
    private_subnet_ids = list(string)
    public_subnet_ids  = optional(list(string), [])
  })
  description = "Platform network for this environment — copy from ./tf.sh b platform output -json network_by_environment or your IPAM."
}

variable "workloads" {
  type = map(object({
    workload_type    = string
    size_tier        = string
    network_exposure = string
  }))
  description = "Named workloads for this team in this environment."

  validation {
    condition = alltrue([
      for name, workload in var.workloads :
      can(regex("^[a-z][a-z0-9-]*$", name)) &&
      contains(["private", "public"], workload.network_exposure)
    ])
    error_message = "Workload keys must be lowercase slugs and network_exposure must be private or public."
  }
}
