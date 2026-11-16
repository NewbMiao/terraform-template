variable "team_name" {
  type        = string
  description = "Team slug."
}

variable "name" {
  type        = string
  description = "Workload slug."

  validation {
    condition     = !strcontains(var.name, "_")
    error_message = "name must not contain underscores."
  }
}

variable "workload_type" {
  type        = string
  description = "Cloud-neutral workload category."
}

variable "size_tier" {
  type        = string
  description = "Cloud-neutral sizing label."
}

variable "network_exposure" {
  type        = string
  description = "Whether the placeholder workload is public or private."

  validation {
    condition     = contains(["private", "public"], var.network_exposure)
    error_message = "network_exposure must be private or public."
  }
}

variable "network_id" {
  type        = string
  description = "Network identifier from the platform state."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet identifiers from the platform state."
}
