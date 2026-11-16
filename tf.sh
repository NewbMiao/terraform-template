#!/bin/bash
# Terraform wrapper — entry only. Logic: tf/terraform-lib.sh · menu: tf/terraform-menu.sh
#
# Usage:
#   ./tf.sh base|b <scope> <command> [flags]
#   ./tf.sh infra|i <team> <environment> <command> [flags]
#   ./tf.sh -i [-ip|-ia|-iv|-it]
set -euo pipefail

# macOS /bin/bash is 3.2 — re-exec Homebrew bash when available (parent tf.sh pattern).
if [ -z "${TF_SH_REEXECED:-}" ] && [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  for _bash in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [ -x "${_bash}" ]; then
      export TF_SH_REEXECED=1
      exec "${_bash}" "$0" "$@"
    fi
  done
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="${ROOT}/tf"
export TEMPLATE_WRAPPER_ROOT="${ROOT}"
export TEMPLATE_TF_DIR="${TF_DIR}"

unset TF_LOG TF_LOG_PATH TF_LOG_PROVIDER TF_LOG_SDK 2>/dev/null || true
unset TF_CLI_ARGS TF_CLI_ARGS_plan TF_CLI_ARGS_apply TF_CLI_ARGS_validate TF_CLI_ARGS_destroy 2>/dev/null || true
export TF_IN_AUTOMATION=1

cleanup() {
  unset TF_CLI_ARGS TF_CLI_ARGS_plan TF_CLI_ARGS_apply TF_CLI_ARGS_validate TF_CLI_ARGS_destroy 2>/dev/null || true
}
trap cleanup EXIT

# Defaults until config exists (fresh repo: no terraform.config.sh yet).
TF_WRAPPER_BASE_DIR="${TF_WRAPPER_BASE_DIR:-base}"
TF_WRAPPER_INFRA_DIR="${TF_WRAPPER_INFRA_DIR:-infra}"
TF_WRAPPER_BASE_SKIP="${TF_WRAPPER_BASE_SKIP:-modules}"
TF_WRAPPER_INFRA_SKIP="${TF_WRAPPER_INFRA_SKIP:-modules}"
TF_WRAPPER_BASE_SCOPES="${TF_WRAPPER_BASE_SCOPES:-}"
TF_WRAPPER_INFRA_ENVS="${TF_WRAPPER_INFRA_ENVS:-}"
TF_WRAPPER_INFRA_TEAMS="${TF_WRAPPER_INFRA_TEAMS:-}"

if [ -f "${TF_DIR}/terraform.config.sh" ]; then
  # shellcheck source=tf/terraform.config.sh
  source "${TF_DIR}/terraform.config.sh"
fi
if [ -f "${TF_DIR}/terraform.config.auto.sh" ]; then
  # shellcheck source=tf/terraform.config.auto.sh
  source "${TF_DIR}/terraform.config.auto.sh"
fi

# shellcheck source=tf/terraform-lib.sh
source "${TF_DIR}/terraform-lib.sh"
# shellcheck source=tf/terraform-menu.sh
source "${TF_DIR}/terraform-menu.sh"

wrapper_refresh_catalog
wrapper_ensure_config_bootstrap

# --- main ---

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "help" ]; then
  usage
  exit 0
fi

case "${1:-}" in
  conf|config)
    shift
    wrapper_cmd_conf "$@"
    exit $?
    ;;
esac

if [ $# -eq 0 ]; then
  set -- -i
fi

case "$1" in
  -i|-ip|-ia|-iv|-it)
    interactive_menu "$@"
    exit $?
    ;;
esac

LAYER="$(normalize_layer_arg "$1")"
shift

BATCH_FAIL=0
case "${LAYER}" in
  base)
    if [ $# -eq 0 ] || ! batch_args_have_command "$@"; then
      interactive_menu -i base ${1+"$@"}
      exit $?
    fi
    run_base_batch "$@" || BATCH_FAIL=$?
    ;;
  infra)
    if [ $# -lt 2 ] || ! batch_args_have_command "$@"; then
      interactive_menu -i infra ${1+"$@"}
      exit $?
    fi
    run_infra_batch "$@" || BATCH_FAIL=$?
    ;;
  *)
    log "Error: layer must be base|b or infra|i"
    usage
    exit 1
    ;;
esac

exit "${BATCH_FAIL}"
