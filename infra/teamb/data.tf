data "terraform_remote_state" "platform" {
  backend = "local"

  config = {
    path = abspath("${path.module}/../../base/platform/terraform.tfstate")
  }
}

# Terraform Cloud (replace block above when platform state is remote):
#
# data "terraform_remote_state" "platform" {
#   backend = "remote"
#   config = {
#     organization = "example-org"
#     workspaces = {
#       name = "example-base-platform"
#     }
#   }
# }
