# platform

Shared network catalogue (`environment_networks` in tfvars).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.8.0, < 2.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| network | ../modules/network | n/a |

## Inputs

| Name | Description | Required |
| ---- | ----------- | :------: |
| environment\_networks | One network per environment key — keys live in tfvars, not base folder names. | yes |
| tags | Default tags echoed in derived names. | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| network\_by\_environment | Per-environment network outputs — copy into infra config platform\_network.auto.tfvars (template does not use terraform\_remote\_state). |
<!-- END_TF_DOCS -->
