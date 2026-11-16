#!/usr/bin/env bash
# Core wrapper — sourced from ../tf.sh (sets TEMPLATE_WRAPPER_ROOT, TEMPLATE_TF_DIR).
# Interactive menu: tf/terraform-menu.sh

: "${TEMPLATE_WRAPPER_ROOT:?TEMPLATE_WRAPPER_ROOT not set}"
ROOT="${TEMPLATE_WRAPPER_ROOT}"
TF_DIR="${TEMPLATE_TF_DIR:-${ROOT}/tf}"

# --- globals (menu + batch set COMMAND / FLAGS) ---
COMMAND=""
FLAGS=()
MENU_PICK_TARGET=
BACKEND_CONFIG=""
WORK_DIR=""
CONFIG_DIR=""

log() { echo "$@" >&2; }

wrapper_scopes_csv() {
  echo "${TF_WRAPPER_BASE_SCOPES// /,}"
}

wrapper_envs_csv() {
  echo "${TF_WRAPPER_INFRA_ENVS// /,}"
}

is_valid_base_scope() {
  local want=$1
  local scope
  for scope in ${TF_WRAPPER_BASE_SCOPES}; do
    [ "${scope}" = "${want}" ] && return 0
  done
  return 1
}

is_valid_infra_env() {
  local want=$1
  local env
  for env in ${TF_WRAPPER_INFRA_ENVS}; do
    [ "${env}" = "${want}" ] && return 0
  done
  return 1
}

usage() {
  cat >&2 <<EOF
Usage:
  ./tf.sh base|b <scope> <command> [flags]
  ./tf.sh infra|i <team> <environment> <command> [flags]

Shorthand:
  b / i                     base / infra layer
  -ip / -ia / -iv           plan / apply / validate (instead of command word)
  -it                       plan/apply/… + fzf -target menu (per stack; after init)
  -i                        fzf step menu (optional -ip/-ia/-iv/-it); brew install fzf
  <scope|team|env>          comma list, multiple args, or all
  (no args)                 -i menu · b|i without command → -i with preselect

Examples:
  ./tf.sh b platform validate
  ./tf.sh i teama,teamb prod,staging -ip
  ./tf.sh i all all -ip
  ./tf.sh -i -ip -it

Scopes: ${TF_WRAPPER_BASE_SCOPES} | all
Environments: ${TF_WRAPPER_INFRA_ENVS} | all
Config: ${TF_DIR}/terraform.config.sh

Secrets: TF_VAR_* in gitignored .env — not -var= on the CLI.

Auto-init: like root tf — \`init -reconfigure -backend-config=backend.hcl\` before validate/plan/apply/output/state (not fmt).
State rm/mv/push/pull: TF_STATE_CONFIRM=yes (same as root tf).
EOF
}

# --- env / CLI guardrails ---
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

reject_unsupported_cli_flags() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -var=*|-var-file=*|--var-file=*)
        log "Error: use *.auto.tfvars / .env (TF_VAR_*) — not ${arg%%=*}= on the CLI."
        exit 1
        ;;
      -backend-config=*|--backend-config=*)
        log "Error: use stack backend.hcl — not ${arg%%=*}= on the CLI."
        exit 1
        ;;
    esac
  done
}

apply_auto_tfvars() {
  local search_dir="$1"
  local strip_prefix="$2"
  local -a var_args=()
  local tfvars

  shopt -s nullglob
  for tfvars in "${search_dir}"/*.auto.tfvars; do
    var_args+=("-var-file=${tfvars#"${strip_prefix}"/}")
  done
  shopt -u nullglob

  if [ "${#var_args[@]}" -eq 0 ]; then
    return 0
  fi

  local joined="${var_args[*]}"
  export TF_CLI_ARGS_plan="${joined}"
  export TF_CLI_ARGS_apply="${joined}"
  export TF_CLI_ARGS_validate="${joined}"
  export TF_CLI_ARGS_destroy="${joined}"
}

ensure_tf_version() {
  [ -f "${ROOT}/.terraform-version" ] || return 0
  command -v tfenv >/dev/null 2>&1 || return 0
  TFENV_AUTO_INSTALL=true tfenv use "$(tr -d '[:space:]' < "${ROOT}/.terraform-version")" >/dev/null 2>&1 || true
}

# --- terraform invoke (mirror tf/tf-base.sh: init -reconfigure -backend-config) ---
terraform_init_backend() {
  local work_dir=$1
  local backend_config=$2
  local quiet=$3
  shift 3
  local -a cmd=(terraform -chdir="${work_dir}" init -input=false -reconfigure)
  [ -n "${backend_config}" ] && [ -f "${backend_config}" ] && cmd+=(-backend-config="${backend_config}")
  if [ $# -gt 0 ]; then
    cmd+=("$@")
  fi
  if [ "${quiet}" -eq 1 ]; then
    "${cmd[@]}" >/dev/null 2>&1
  else
    "${cmd[@]}"
  fi
}

run_stack_init() {
  terraform_init_backend "${WORK_DIR}" "${BACKEND_CONFIG}" 0 "$@"
}

# Parent pattern for -it / dependency probes: init + state list (init may be quiet).
terraform_init_then_state_list() {
  local work_dir=$1
  local backend_config=$2
  local shared_env=${3:-}

  if [ -n "${shared_env}" ] && [ -f "${shared_env}" ]; then
    set -a
    # shellcheck source=/dev/null
    source "${shared_env}"
    set +a
  fi

  terraform_init_backend "${work_dir}" "${backend_config}" 1 \
    && terraform -chdir="${work_dir}" state list 2>/dev/null
}

ensure_init() {
  run_stack_init || return 1
}

guard_state_mutation() {
  local command=$1
  shift
  local -a flags=("$@")
  local help_cmd="${TF_HELP_CMD:-./tf.sh}"

  [ "${command}" = "state" ] || return 0
  [ ${#flags[@]} -gt 0 ] || return 0

  case "${flags[0]}" in
    rm | mv | push | pull)
      if [ "${TF_STATE_CONFIRM:-}" != "yes" ]; then
        log "Error: terraform state ${flags[0]} blocked — set TF_STATE_CONFIRM=yes after explicit approval"
        log "  Example: TF_STATE_CONFIRM=yes ${help_cmd} … state ${flags[0]} …"
        exit 1
      fi
      ;;
  esac
}

command_needs_init() {
  case "$1" in
    init|fmt|output) return 1 ;;
    *) return 0 ;;
  esac
}

run_terraform() {
  local command="$1"
  shift

  reject_unsupported_cli_flags "$@"
  guard_state_mutation "${command}" "$@"
  ensure_tf_version

  case "${command}" in
    console)
      log "Error: terraform console is disabled in this wrapper (secret leakage risk)."
      exit 1
      ;;
    output)
      log "Note: mark sensitive values in Terraform outputs; prefer named outputs over -json in shared logs."
      ;;
  esac

  local -a tf=(terraform -chdir="${WORK_DIR}")

  if [ "${command}" = "init" ]; then
    run_stack_init "$@"
    return
  fi

  if [ "$#" -gt 0 ]; then
    "${tf[@]}" "${command}" "$@"
  else
    "${tf[@]}" "${command}"
  fi
}

# --- discovery / CSV batch tokens ---
slug_ok() {
  [[ "$1" =~ ^[a-z][a-z0-9-]*$ ]]
}

base_dir_is_stack() {
  local dir=$1
  [ -f "${dir}/backend.hcl" ] && return 0
  shopt -s nullglob
  local -a tfs=("${dir}"/*.tf)
  shopt -u nullglob
  [ "${#tfs[@]}" -gt 0 ]
}

discover_base_scopes() {
  local d name skip
  for d in "${ROOT}/${TF_WRAPPER_BASE_DIR}"/*/; do
    [ -d "${d}" ] || continue
    name="$(basename "${d%/}")"
    for skip in ${TF_WRAPPER_BASE_SKIP}; do
      [ "${name}" = "${skip}" ] && continue 2
    done
    base_dir_is_stack "${d%/}" || continue
    printf '%s\n' "${name}"
  done | LC_ALL=C sort -u
}

discover_infra_envs() {
  local team epath env
  while IFS= read -r team; do
    [ -n "${team}" ] || continue
    for epath in "${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config"/*/; do
      [ -d "${epath}" ] || continue
      env="$(basename "${epath%/}")"
      printf '%s\n' "${env}"
    done
  done < <(discover_infra_teams) | LC_ALL=C sort -u
}

# Disk discovery wins; else keep defaults from terraform.config.sh / .auto.sh.
wrapper_refresh_catalog() {
  local discovered="" team

  discovered="$(discover_base_scopes | tr '\n' ' ')"
  discovered="${discovered%"${discovered##*[![:space:]]}"}"
  if [ -n "${discovered}" ]; then
    TF_WRAPPER_BASE_SCOPES="${discovered}"
  elif [ -z "${TF_WRAPPER_BASE_SCOPES// }" ]; then
    log "Error: no base scopes under ${ROOT}/${TF_WRAPPER_BASE_DIR}/ (need stack dir with backend.hcl or *.tf)"
    exit 1
  fi

  discovered="$(discover_infra_envs | tr '\n' ' ')"
  discovered="${discovered%"${discovered##*[![:space:]]}"}"
  if [ -n "${discovered}" ]; then
    TF_WRAPPER_INFRA_ENVS="${discovered}"
  elif [ -z "${TF_WRAPPER_INFRA_ENVS// }" ]; then
    while IFS= read -r team; do
      [ -n "${team}" ] || continue
      log "Error: no infra envs under ${ROOT}/${TF_WRAPPER_INFRA_DIR}/*/config/ (team ${team} has config/ but no env dirs)"
      exit 1
    done < <(discover_infra_teams)
    TF_WRAPPER_INFRA_ENVS=""
  fi
}

wrapper_config_sh_content() {
  local reason=${1:-bootstrap}
  cat <<EOF
# Generated by: ./tf.sh (${reason}) — edit paths, skips, fallbacks; teams stay auto-discovered.
# Regenerate catalog snapshot: ./tf.sh conf -g

TF_WRAPPER_BASE_DIR="${TF_WRAPPER_BASE_DIR}"
TF_WRAPPER_INFRA_DIR="${TF_WRAPPER_INFRA_DIR}"
TF_WRAPPER_BASE_SKIP="${TF_WRAPPER_BASE_SKIP}"
TF_WRAPPER_INFRA_SKIP="${TF_WRAPPER_INFRA_SKIP}"

TF_WRAPPER_BASE_SCOPES="\${TF_WRAPPER_BASE_SCOPES:-${TF_WRAPPER_BASE_SCOPES}}"
TF_WRAPPER_INFRA_ENVS="\${TF_WRAPPER_INFRA_ENVS:-${TF_WRAPPER_INFRA_ENVS}}"
TF_WRAPPER_INFRA_TEAMS="\${TF_WRAPPER_INFRA_TEAMS:-}"
EOF
}

wrapper_config_auto_sh_content() {
  local reason=${1:-auto}
  cat <<EOF
# Generated by: ./tf.sh (${reason})
# Snapshot of scopes/envs. Teams discovered at runtime. Disable sync: TF_WRAPPER_AUTO_CONF=0

TF_WRAPPER_BASE_DIR="${TF_WRAPPER_BASE_DIR}"
TF_WRAPPER_INFRA_DIR="${TF_WRAPPER_INFRA_DIR}"
TF_WRAPPER_BASE_SKIP="${TF_WRAPPER_BASE_SKIP}"
TF_WRAPPER_INFRA_SKIP="${TF_WRAPPER_INFRA_SKIP}"
TF_WRAPPER_BASE_SCOPES="${TF_WRAPPER_BASE_SCOPES}"
TF_WRAPPER_INFRA_ENVS="${TF_WRAPPER_INFRA_ENVS}"
EOF
}

wrapper_write_config_sh() {
  local out="${TF_DIR}/terraform.config.sh"
  wrapper_config_sh_content "${1:-bootstrap}" >"${out}"
  log "Created ${out}"
}

wrapper_ensure_config_bootstrap() {
  if [ ! -f "${TF_DIR}/terraform.config.sh" ]; then
    wrapper_write_config_sh "bootstrap"
    # shellcheck source=terraform.config.sh
    source "${TF_DIR}/terraform.config.sh"
    wrapper_refresh_catalog
  fi
  wrapper_ensure_config_auto
}

wrapper_auto_saved_scopes() {
  local file="${TF_DIR}/terraform.config.auto.sh"
  [ -f "${file}" ] || return 0
  grep -E '^TF_WRAPPER_BASE_SCOPES=' "${file}" 2>/dev/null | head -1 | sed -E 's/^TF_WRAPPER_BASE_SCOPES="([^"]*)".*/\1/'
}

wrapper_auto_saved_envs() {
  local file="${TF_DIR}/terraform.config.auto.sh"
  [ -f "${file}" ] || return 0
  grep -E '^TF_WRAPPER_INFRA_ENVS=' "${file}" 2>/dev/null | head -1 | sed -E 's/^TF_WRAPPER_INFRA_ENVS="([^"]*)".*/\1/'
}

# Create/update terraform.config.auto.sh when missing or catalog drifted (default on).
wrapper_ensure_config_auto() {
  local out="${TF_DIR}/terraform.config.auto.sh"
  local reason saved_scopes saved_envs

  if [ "${TF_WRAPPER_AUTO_CONF:-1}" = "0" ]; then
    return 0
  fi

  saved_scopes="$(wrapper_auto_saved_scopes)"
  saved_envs="$(wrapper_auto_saved_envs)"

  if [ ! -f "${out}" ]; then
    wrapper_config_auto_sh_content "bootstrap" >"${out}"
    log "Created ${out} from current catalog"
    return 0
  fi

  if [ "${saved_scopes}" != "${TF_WRAPPER_BASE_SCOPES}" ] || [ "${saved_envs}" != "${TF_WRAPPER_INFRA_ENVS}" ]; then
    wrapper_config_auto_sh_content "catalog sync" >"${out}"
    log "Updated ${out} (scopes/envs changed — review or commit)"
  fi
}

wrapper_write_config_auto() {
  local out="${TF_DIR}/terraform.config.auto.sh"
  wrapper_refresh_catalog
  wrapper_config_auto_sh_content "${1:-conf -g}" >"${out}"
  log "Wrote ${out}"
}

# ./tf.sh conf -g → terraform.config.auto.sh (does not overwrite terraform.config.sh).
wrapper_gen_config_auto() {
  wrapper_write_config_auto "conf -g"
}

wrapper_cmd_conf() {
  local arg generate=0
  for arg in "$@"; do
    case "${arg}" in
      -g|--generate|generate) generate=1 ;;
      -h|--help|help)
        cat >&2 <<EOF
Usage: ./tf.sh conf [-g]
  (default)  show scopes, envs, teams, units from disk
  -g         force-write terraform.config.auto.sh
Auto: missing terraform.config.sh → generate; missing/stale .auto.sh → sync (TF_WRAPPER_AUTO_CONF=0 to disable).
EOF
        return 0
        ;;
      *)
        log "Error: unknown conf option '${arg}' (use -g)"
        return 1
        ;;
    esac
  done
  if [ "${generate}" -eq 1 ]; then
    wrapper_gen_config_auto
    # shellcheck source=terraform.config.auto.sh
    source "${TF_DIR}/terraform.config.auto.sh"
  fi
  wrapper_refresh_catalog
  wrapper_show_catalog
}

# Show effective catalog (after wrapper_refresh_catalog). ./tf.sh conf
wrapper_show_catalog() {
  local team units="" t e
  log "base  scopes   ${TF_WRAPPER_BASE_SCOPES} | all"
  log "infra envs    ${TF_WRAPPER_INFRA_ENVS} | all"
  log "infra teams   $(discover_infra_teams | tr '\n' ' ')"
  log "infra units   (team:env)"
  while IFS= read -r team; do
    [ -n "${team}" ] || continue
    for e in ${TF_WRAPPER_INFRA_ENVS}; do
      [ -d "${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config/${e}" ] || continue
      units+="${team}:${e} "
    done
  done < <(discover_infra_teams)
  log "  ${units%"${units##*[![:space:]]}"}"
  log
  log "Paths: ${TF_WRAPPER_BASE_DIR}/ ${TF_WRAPPER_INFRA_DIR}/  (config: tf/terraform.config.sh)"
  log "Override: TF_WRAPPER_BASE_SCOPES / TF_WRAPPER_INFRA_ENVS / TF_WRAPPER_INFRA_TEAMS"
}

discover_infra_teams() {
  local t name skip
  if [ -n "${TF_WRAPPER_INFRA_TEAMS:-}" ]; then
    for name in ${TF_WRAPPER_INFRA_TEAMS}; do
      printf '%s\n' "${name}"
    done
    return 0
  fi
  for t in "${ROOT}/${TF_WRAPPER_INFRA_DIR}"/*/; do
    [ -d "${t}" ] || continue
    name="$(basename "${t%/}")"
    [ -d "${t}config" ] || continue
    for skip in ${TF_WRAPPER_INFRA_SKIP}; do
      [ "${name}" = "${skip}" ] && continue 2
    done
    printf '%s\n' "${name}"
  done
}

expand_csv_token() {
  local kind="$1"
  local token="$2"

  case "${token}" in
    all)
      case "${kind}" in
        scopes) wrapper_scopes_csv ;;
        envs) wrapper_envs_csv ;;
        teams)
          local out="" t
          while IFS= read -r t; do
            out+="${t},"
          done < <(discover_infra_teams)
          echo "${out%,}"
          ;;
      esac
      ;;
    *)
      echo "${token}"
      ;;
  esac
}

split_csv() {
  local csv="$1"
  local part
  while IFS= read -r part; do
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [ -n "${part}" ] || continue
    printf '%s\n' "${part}"
  done < <(printf '%s\n' "${csv}" | tr ',' '\n')
}

is_command_token() {
  case "$1" in
    init|plan|apply|validate|fmt|output|destroy|import|taint|untaint|refresh|providers|version|workspace|state)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_meta_token() {
  case "$1" in
    -ip|-ia|-iv|-i|-it|-h|--help)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# staging | prod | all | prod,staging (order-independent with team CSV in batch).
is_infra_env_token() {
  local token="$1"
  local part
  case "${token}" in
    all) return 0 ;;
  esac
  if is_valid_infra_env "${token}"; then
    return 0
  fi
  [[ "${token}" == *","* ]] || return 1
  while IFS= read -r part; do
    [ "${part}" = "all" ] || is_valid_infra_env "${part}" || return 1
  done < <(split_csv "${token}")
  return 0
}

batch_args_have_command() {
  local arg
  for arg in "$@"; do
    if is_command_token "${arg}"; then
      return 0
    fi
    case "${arg}" in
      -ip|-ia|-iv) return 0 ;;
    esac
  done
  return 1
}

command_supports_target() {
  case "$1" in
    plan|apply|destroy|refresh|import) return 0 ;;
    *) return 1 ;;
  esac
}

flags_include_target() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      -target|-target=*) return 0 ;;
    esac
  done
  return 1
}

resolve_command_and_flags() {
  local -a rest=("$@")
  COMMAND=""
  FLAGS=()
  MENU_PICK_TARGET=
  MENU_BATCH_TARGET_PICKED=
  local arg

  for arg in "${rest[@]}"; do
    case "${arg}" in
      -ip) COMMAND=plan ;;
      -ia) COMMAND=apply ;;
      -iv) COMMAND=validate ;;
      -i)
        if [ -z "${COMMAND}" ]; then
          COMMAND=apply
        fi
        ;;
      -it)
        MENU_PICK_TARGET=1
        if [ -z "${COMMAND}" ]; then
          COMMAND=apply
        fi
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        FLAGS+=("${arg}")
        ;;
      *)
        if [ -z "${COMMAND}" ]; then
          COMMAND="${arg}"
        else
          FLAGS+=("${arg}")
        fi
        ;;
    esac
  done

  if [ -z "${COMMAND}" ]; then
    log "Error: missing command (plan, apply, … or -ip / -ia / -iv / -it)"
    exit 1
  fi
}

# --- stack prep + unit runs ---
prepare_base_stack() {
  local scope="$1"
  if ! is_valid_base_scope "${scope}"; then
    log "Error: scope must be one of: ${TF_WRAPPER_BASE_SCOPES} (got ${scope})"
    return 1
  fi
  WORK_DIR="${ROOT}/${TF_WRAPPER_BASE_DIR}/${scope}"
  CONFIG_DIR=""
  if [ -f "${WORK_DIR}/backend.hcl" ]; then
    BACKEND_CONFIG="${WORK_DIR}/backend.hcl"
  else
    BACKEND_CONFIG=""
  fi
  load_tf_var_env "${ROOT}/${TF_WRAPPER_BASE_DIR}/.env"
  apply_auto_tfvars "${WORK_DIR}" "${WORK_DIR}"
  [ -d "${WORK_DIR}" ]
}

prepare_infra_stack() {
  local team="$1"
  local environment="$2"

  if ! slug_ok "${team}"; then
    log "Error: team must be a lowercase slug (got ${team})"
    return 1
  fi
  if ! is_valid_infra_env "${environment}"; then
    log "Error: environment must be one of: ${TF_WRAPPER_INFRA_ENVS} (got ${environment})"
    return 1
  fi

  WORK_DIR="${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}"
  CONFIG_DIR="${WORK_DIR}/config/${environment}"
  if [ -f "${CONFIG_DIR}/backend.hcl" ]; then
    BACKEND_CONFIG="${CONFIG_DIR}/backend.hcl"
  else
    BACKEND_CONFIG=""
  fi
  load_tf_var_env "${ROOT}/${TF_WRAPPER_INFRA_DIR}/.env"
  load_tf_var_env "${CONFIG_DIR}/.env"
  apply_auto_tfvars "${CONFIG_DIR}" "${WORK_DIR}"
  [ -d "${WORK_DIR}" ] && [ -d "${CONFIG_DIR}" ]
}

run_prepared_stack() {
  local label="$1"
  local -a run_flags=()

  log "==> ${label}"
  if [ "${COMMAND}" = "output" ]; then
    terraform_init_backend "${WORK_DIR}" "${BACKEND_CONFIG}" 1 || return 1
  elif command_needs_init "${COMMAND}"; then
    ensure_init || return 1
  fi

  if [ "${#FLAGS[@]}" -gt 0 ]; then
    run_flags=("${FLAGS[@]}")
  fi
  if [ -n "${MENU_PICK_TARGET:-}" ] && command_supports_target "${COMMAND}"; then
    if ! flags_include_target "${run_flags[@]}" && [ -z "${MENU_BATCH_TARGET_PICKED:-}" ]; then
      MENU_IT_UNIT_LABEL="$(menu_format_it_unit_label "${label}")"
      MENU_PICKED_TARGET_FLAG=
      menu_pick_terraform_target || return $?
      if [ -n "${MENU_PICKED_TARGET_FLAG:-}" ]; then
        run_flags+=("${MENU_PICKED_TARGET_FLAG}")
      fi
    fi
  fi

  if [ "${#run_flags[@]}" -gt 0 ]; then
    run_terraform "${COMMAND}" "${run_flags[@]}"
  else
    run_terraform "${COMMAND}"
  fi
}

run_base_unit() {
  local scope="$1"
  if ! prepare_base_stack "${scope}"; then
    return 1
  fi
  run_prepared_stack "base/${scope}"
}

run_infra_unit() {
  local team="$1"
  local environment="$2"
  if ! prepare_infra_stack "${team}" "${environment}"; then
    return 1
  fi
  run_prepared_stack "infra/${team}/${environment}"
}

# --- batch (CLI cartesian) ---
run_base_batch() {
  local -a scope_tokens=()
  local -a rest=()
  local token

  while [ $# -gt 0 ]; do
    token="$1"
    shift
    if is_meta_token "${token}" || is_command_token "${token}" || [[ "${token}" == -* ]]; then
      rest+=("${token}" "$@")
      break
    fi
    while IFS= read -r scope; do
      scope_tokens+=("${scope}")
    done < <(split_csv "$(expand_csv_token scopes "${token}")")
  done

  [ "${#scope_tokens[@]}" -gt 0 ] || {
    log "Error: specify at least one base scope (platform, permissions, all)"
    return 1
  }

  resolve_command_and_flags "${rest[@]}"
  if [ "${#scope_tokens[@]}" -gt 1 ] && [ -n "${MENU_PICK_TARGET:-}" ] && command_supports_target "${COMMAND}"; then
    menu_pick_terraform_target_base_batch "${scope_tokens[@]}" || return 1
    MENU_BATCH_TARGET_PICKED=1
    if [ -n "${MENU_PICKED_TARGET_FLAG:-}" ]; then
      FLAGS+=("${MENU_PICKED_TARGET_FLAG}")
    fi
  fi
  local scope rc=0
  for scope in "${scope_tokens[@]}"; do
    if ! run_base_unit "${scope}"; then
      rc=1
    fi
  done
  return "${rc}"
}

run_infra_batch() {
  local -a team_tokens=()
  local -a env_tokens=()
  local -a rest=()
  local token

  while [ $# -gt 0 ]; do
    token="$1"
    shift
    if is_meta_token "${token}" || is_command_token "${token}" || [[ "${token}" == -* ]]; then
      rest+=("${token}" "$@")
      break
    fi
    if is_infra_env_token "${token}"; then
      while IFS= read -r env; do
        env_tokens+=("${env}")
      done < <(split_csv "$(expand_csv_token envs "${token}")")
    else
      while IFS= read -r team; do
        team_tokens+=("${team}")
      done < <(split_csv "$(expand_csv_token teams "${token}")")
    fi
  done

  [ "${#team_tokens[@]}" -gt 0 ] || {
    log "Error: specify at least one team (teama, teamb, all, …)"
    return 1
  }
  [ "${#env_tokens[@]}" -gt 0 ] || {
    log "Error: specify at least one environment (staging, prod, all)"
    return 1
  }

  resolve_command_and_flags "${rest[@]}"
  local team env unit_count=0 rc=0
  for team in "${team_tokens[@]}"; do
    for env in "${env_tokens[@]}"; do
      [ -d "${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config/${env}" ] && unit_count=$((unit_count + 1))
    done
  done
  if [ "${unit_count}" -gt 1 ] && [ -n "${MENU_PICK_TARGET:-}" ] && command_supports_target "${COMMAND}"; then
    menu_pick_terraform_target_infra_batch "${team_tokens[@]}" || return 1
    MENU_BATCH_TARGET_PICKED=1
    if [ -n "${MENU_PICKED_TARGET_FLAG:-}" ]; then
      FLAGS+=("${MENU_PICKED_TARGET_FLAG}")
    fi
  fi
  for team in "${team_tokens[@]}"; do
    for env in "${env_tokens[@]}"; do
      if ! run_infra_unit "${team}" "${env}"; then
        rc=1
      fi
    done
  done
  return "${rc}"
}

# Layer alias: b|base, i|infra
normalize_layer_arg() {
  case "$1" in
    b|base) echo base ;;
    i|infra) echo infra ;;
    *) echo "$1" ;;
  esac
}
