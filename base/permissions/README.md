# permissions

Placeholder role catalogue stack.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.8.0, < 2.0.0 |



## Inputs

| Name | Description | Required |
| ---- | ----------- | :------: |
| role\_catalogue | Placeholder org-wide role names (wire to your IdP / cloud IAM later). | yes |
| tags | Metadata copied into the placeholder role catalogue. | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| role\_catalogue | Placeholder role names keyed by function. |
<!-- END_TF_DOCS -->
