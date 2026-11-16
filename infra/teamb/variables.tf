variable "environment" {
  type        = string
  description = "Must match config/<environment>/ and a key in the platform state."

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
