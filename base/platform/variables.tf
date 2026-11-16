variable "tags" {
  type        = map(string)
  default     = {}
  description = "Default tags echoed in derived names."
}

variable "environment_networks" {
  type = map(object({
    resource_prefix         = string
    cidr_block              = string
    availability_zone_count = number
    nat_gateway_enabled     = bool
  }))
  description = "One network per environment key — keys live in tfvars, not base folder names."
}
