variable "tags" {
  type        = map(string)
  default     = {}
  description = "Metadata copied into the placeholder role catalogue."
}

variable "role_catalogue" {
  type        = map(string)
  description = "Placeholder org-wide role names (wire to your IdP / cloud IAM later)."
}
