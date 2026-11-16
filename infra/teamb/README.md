# teamb

Team B infra — one state per `config/staging` and `config/prod`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.8.0, < 2.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| workload | ../modules/workload | n/a |

## Inputs

| Name | Description | Required |
| ---- | ----------- | :------: |
| environment | Must match config/<environment>/ and a key in the platform state. | yes |
| team\_name | Team slug; used in names and state paths. | yes |
| workloads | Named workloads for this team in this environment. | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| workloads | Resolved placeholder workload configuration keyed by workload name. |
<!-- END_TF_DOCS -->
