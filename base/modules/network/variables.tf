variable "environment" {
  type        = string
  description = "Environment key this network belongs to (staging, prod, …)."
}

variable "resource_prefix" {
  type        = string
  description = "Prefix for derived network and subnet names."

  validation {
    condition     = startswith(var.resource_prefix, "net-")
    error_message = "resource_prefix must start with net-."
  }
}

variable "cidr_block" {
  type        = string
  description = "Example network CIDR."

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 or IPv6 CIDR."
  }
}

variable "availability_zone_count" {
  type        = number
  description = "Number of placeholder private and public subnet IDs."

  validation {
    condition     = var.availability_zone_count >= 1 && floor(var.availability_zone_count) == var.availability_zone_count
    error_message = "availability_zone_count must be a positive whole number."
  }
}

variable "nat_gateway_enabled" {
  type        = bool
  description = "Whether the placeholder network records outbound gateway use."
}

variable "tags" {
  type        = map(string)
  description = "Metadata copied into the placeholder output."
}
