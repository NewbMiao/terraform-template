#!/bin/bash
# Usage:
#   ./terraform.sh base <scope> <command> [flags]
#   ./terraform.sh infra <team> <environment> <command> [flags]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Avoid verbose TF / shell tracing that can leak TF_VAR_* or provider config.
unset TF_LOG TF_LOG_PATH TF_LOG_PROVIDER TF_LOG_SDK 2>/dev/null || true
unset TF_CLI_ARGS TF_CLI_ARGS_plan TF_CLI_ARGS_apply 2>/dev/null || true
export TF_IN_AUTOMATION=1

log() { echo "$@" >&2; }

usage() {
  cat >&2 <<'EOF'
Usage:
  ./terraform.sh base <scope> <command> [flags]
  ./terraform.sh infra <team> <environment> <command> [flags]

Scopes: platform | permissions
Environments: staging | prod
Commands: init | plan | apply | validate | fmt | output | …

Secrets: use TF_VAR_* in gitignored .env only — not -var= on the CLI.
EOF
}

# Load only TF_VAR_* assignments; never echo values; ignore other keys.
load_tf_var_env() {
  local env_file="$1"
  [ -f "${env_file}" ] || return 0

  local line key val
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "${line}" in
      ''|\#*) continue ;;
      export\ TF_VAR_*) line="${line#export }" ;;
    esac
    case "${line}" in
      TF_VAR_*=*)
        key="${line%%=*}"
        val="${line#*=}"
        case "${val}" in
          \"*\") val="${val#\"}"; val="${val%\"}" ;;
          \'*\') val="${val#\'}"; val="${val%\'}" ;;
        esac
        case "${val}" in
          *\$\(* | *\`*) continue ;;
        esac
        if [[ "${key}" =~ ^TF_VAR_[A-Za-z0-9_]+$ ]]; then
          export "${key}=${val}"
        fi
        ;;
      *) ;;
    esac
  done < "${env_file}"
}

reject_cli_secrets() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -var=*|-var-file=*|--var-file=*)
        log "Error: pass config via config/<env>/*.auto.tfvars / .env (TF_VAR_*) — not ${arg%%=*}= on the CLI."
        exit 1
        ;;
    esac
  done
}

run_terraform() {
  local work_dir="$1"
  shift
  local command="$1"
  shift

  reject_cli_secrets "$@"

  cd "${work_dir}"
  if [ -f "${ROOT}/.terraform-version" ] && command -v tfenv >/dev/null 2>&1; then
    TFENV_AUTO_INSTALL=true tfenv use "$(cat "${ROOT}/.terraform-version")" >/dev/null 2>&1 || true
  fi

  case "${command}" in
    console)
      log "Error: terraform console is disabled in this wrapper (secret leakage risk)."
      exit 1
      ;;
    output)
      log "Note: mark sensitive values in Terraform outputs; prefer named outputs over -json in shared logs."
      ;;
  esac

  if [ "${command}" = "init" ]; then
    if [ -n "${BACKEND_CONFIG:-}" ] && [ -f "${BACKEND_CONFIG}" ]; then
      if [ "$#" -gt 0 ]; then
        terraform init -backend-config="${BACKEND_CONFIG}" "$@"
      else
        terraform init -backend-config="${BACKEND_CONFIG}"
      fi
    elif [ "$#" -gt 0 ]; then
      terraform init "$@"
    else
      terraform init
    fi
  elif [ "$#" -gt 0 ]; then
    terraform "${command}" "$@"
  else
    terraform "${command}"
  fi
}

if [ $# -lt 3 ]; then
  usage
  exit 1
fi

LAYER="$1"
FLAGS=()

case "${LAYER}" in
  base)
    SCOPE="$2"
    case "${SCOPE}" in
      platform | permissions) ;;
      *)
        log "Error: scope must be platform or permissions"
        exit 1
        ;;
    esac
    COMMAND="$3"
    if [ $# -gt 3 ]; then
      FLAGS=("${@:4}")
    fi
    WORK_DIR="${ROOT}/base/${SCOPE}"
    if [ -f "${WORK_DIR}/backend.hcl" ]; then
      BACKEND_CONFIG="${WORK_DIR}/backend.hcl"
    else
      BACKEND_CONFIG=""
    fi
    load_tf_var_env "${ROOT}/base/.env"
    ;;
  infra)
    if [ $# -lt 4 ]; then
      usage
      exit 1
    fi
    TEAM="$2"
    ENVIRONMENT="$3"
    if [[ ! "${TEAM}" =~ ^[a-z][a-z0-9-]*$ ]]; then
      log "Error: team must be a lowercase slug"
      exit 1
    fi
    case "${ENVIRONMENT}" in
      staging | prod) ;;
      *)
        log "Error: environment must be staging or prod"
        exit 1
        ;;
    esac
    COMMAND="$4"
    if [ $# -gt 4 ]; then
      FLAGS=("${@:5}")
    fi
    WORK_DIR="${ROOT}/infra/${TEAM}"
    CONFIG_DIR="${WORK_DIR}/config/${ENVIRONMENT}"
    if [ -f "${CONFIG_DIR}/backend.hcl" ]; then
      BACKEND_CONFIG="${CONFIG_DIR}/backend.hcl"
    else
      BACKEND_CONFIG=""
    fi
    load_tf_var_env "${ROOT}/infra/.env"
    load_tf_var_env "${CONFIG_DIR}/.env"
    ;;
  *)
    log "Error: layer must be base or infra"
    usage
    exit 1
    ;;
esac

if [ ! -d "${WORK_DIR}" ]; then
  log "Error: missing stack directory for layer=${LAYER}"
  exit 1
fi

if [ "${LAYER}" = "infra" ]; then
  if [ ! -d "${CONFIG_DIR}" ]; then
    log "Error: missing config directory config/${ENVIRONMENT}"
    exit 1
  fi
  var_args=()
  for tfvars in "${CONFIG_DIR}"/*.auto.tfvars; do
    [ -f "${tfvars}" ] || continue
    var_args+=("-var-file=${tfvars#"${WORK_DIR}"/}")
  done
  if [ "${#var_args[@]}" -gt 0 ]; then
    export TF_CLI_ARGS_plan="${var_args[*]}"
    export TF_CLI_ARGS_apply="${var_args[*]}"
  fi
fi

if [ "${#FLAGS[@]}" -gt 0 ]; then
  run_terraform "${WORK_DIR}" "${COMMAND}" "${FLAGS[@]}"
else
  run_terraform "${WORK_DIR}" "${COMMAND}"
fi
