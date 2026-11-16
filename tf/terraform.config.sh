# Hand-edited per repo. Disk discovery wins when stacks exist; defaults apply for empty/partial trees.
# Regenerate snapshot: ./tf.sh conf -g  → terraform.config.auto.sh

TF_WRAPPER_BASE_DIR="${TF_WRAPPER_BASE_DIR:-base}"
TF_WRAPPER_INFRA_DIR="${TF_WRAPPER_INFRA_DIR:-infra}"
TF_WRAPPER_BASE_SKIP="${TF_WRAPPER_BASE_SKIP:-modules}"
TF_WRAPPER_INFRA_SKIP="${TF_WRAPPER_INFRA_SKIP:-modules}"

# Fallbacks (this template). Overridden by discovery, terraform.config.auto.sh, or env.
TF_WRAPPER_BASE_SCOPES="${TF_WRAPPER_BASE_SCOPES:-permissions platform}"
TF_WRAPPER_INFRA_ENVS="${TF_WRAPPER_INFRA_ENVS:-prod staging}"
TF_WRAPPER_INFRA_TEAMS="${TF_WRAPPER_INFRA_TEAMS:-}"
