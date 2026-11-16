#!/usr/bin/env bash
# tflint with stack var-files + OPA Rego tests (validate → pre-commit terraform_validate hook)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${ROOT}/.tflint.hcl"
export TFLINT_OPA_POLICY_DIR="${ROOT}/.tflint.d/policies"

var_files_for() {
  local abs="$1"
  local env="${2:-}"
  local vf
  if [[ -n "${env}" && -d "${abs}/config/${env}" ]]; then
    for vf in "${abs}/config/${env}"/*.auto.tfvars; do
      [[ -f "${vf}" ]] || continue
      printf '%s\n' "--var-file=${vf#"${abs}"/}"
    done
    return 0
  fi
  for vf in "${abs}"/*.auto.tfvars; do
    [[ -f "${vf}" ]] || continue
    printf '%s\n' "--var-file=${vf#"${abs}"/}"
  done
}

run_one() {
  local dir="$1"
  local env="${2:-}"
  local abs="${ROOT}/${dir}"
  local -a var_args=()
  local line

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    var_args+=("${line}")
  done < <(var_files_for "${abs}" "${env}")

  echo "tflint ${dir}${env:+ (${env})}"
  (
    cd "${abs}"
    terraform init -backend=false -input=false >/dev/null
    if [[ "${#var_args[@]}" -gt 0 ]]; then
      tflint --config="${CFG}" "${var_args[@]}"
    else
      tflint --config="${CFG}"
    fi
  )
}

run_dir() {
  local dir="$1"
  local abs="${ROOT}/${dir}"
  local ran=0
  local env rc=0

  for env in staging prod; do
    if [[ -f "${abs}/config/${env}/environment.auto.tfvars" || -f "${abs}/config/${env}/workloads.auto.tfvars" ]]; then
      if ! run_one "${dir}" "${env}"; then
        rc=1
      fi
      ran=1
    fi
  done
  if [[ "${ran}" -eq 0 ]]; then
    if ! run_one "${dir}"; then
      rc=1
    fi
  fi
  return "${rc}"
}

run_opa_rego_tests() {
  echo "OPA Rego tests (.tflint.d/policies)"
  TFLINT_OPA_POLICY_DIR="${TFLINT_OPA_POLICY_DIR}" \
    TFLINT_OPA_TEST=1 \
    tflint --config="${CFG}" --chdir="${ROOT}/base/platform"
}

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <path> [path ...]" >&2
  exit 2
fi

dir_list=""
run_opa=false
for f in "$@"; do
  case "${f}" in
    .tflint.hcl | .tflint.d/policies/* | scripts/tflint-env.sh)
      run_opa=true
      continue
      ;;
    *.tf | *.tfvars | *.hcl | *.rego) ;;
    *) continue ;;
  esac
  d="$(dirname "${f}")"
  case "${d}" in
    */config/staging | */config/prod)
      d="$(dirname "$(dirname "${d}")")"
      ;;
  esac
  dir_list="${dir_list}${d}"$'\n'
done

status=0
while IFS= read -r d; do
  [[ -n "${d}" ]] || continue
  if ! run_dir "${d}"; then
    status=1
  fi
done < <(printf '%s' "${dir_list}" | LC_ALL=C sort -u)

if [[ -n "${dir_list//[[:space:]]/}" ]] || [[ "${run_opa}" == true ]]; then
  if ! command -v tflint >/dev/null 2>&1; then
    echo "Error: tflint not in PATH (brew install terraform-linters/tap/tflint)" >&2
    exit 1
  fi
  if ! run_opa_rego_tests; then
    status=1
  fi
fi

exit "${status}"
