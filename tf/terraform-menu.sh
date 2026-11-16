#!/usr/bin/env bash
# Interactive -i / -ip / -ia / -iv / -it (fzf step-by-step; numbered fallback without fzf).
# Sourced after tf/terraform-lib.sh from ../tf.sh.

MENU_TRAIL=()
MENU_PICKED_TARGET_FLAG=
MENU_IT_UNIT_LABEL=
MENU_BATCH_TARGET_PICKED=

menu_format_it_unit_label() {
  local label=$1
  case "${label}" in
    base/*) printf '%s' "${label#base/}" ;;
    infra/*)
      local rest="${label#infra/}"
      printf '%s:%s' "${rest%%/*}" "${rest##*/}"
      ;;
    *) printf '%s' "${label}" ;;
  esac
}

# Parent tf pattern: display "module.foo · teama:prod" (fzf only); -target uses addr before · .
menu_target_strip_stack_suffix() {
  local line=$1
  case "${line}" in
    *" · "*) printf '%s' "${line%% · *}" ;;
    *) printf '%s' "${line}" ;;
  esac
}

# module.* roots from infra/<team>/*.tf (team-level, not per-env).
menu_list_team_module_roots() {
  local team=$1
  local dir="${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}"
  local f line
  local -a addrs=()

  [ -d "${dir}" ] || return 0
  shopt -s nullglob
  for f in "${dir}"/*.tf; do
    while IFS= read -r line || [ -n "${line}" ]; do
      if [[ "${line}" =~ ^[[:space:]]*module[[:space:]]+\"([^\"]+)\" ]]; then
        addrs+=("module.${BASH_REMATCH[1]}")
      fi
    done < "${f}"
  done
  shopt -u nullglob
  if [ "${#addrs[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${addrs[@]}" | LC_ALL=C sort -u
}

menu_list_scope_module_roots() {
  local scope=$1
  local dir="${ROOT}/${TF_WRAPPER_BASE_DIR}/${scope}"
  local f line
  local -a addrs=()

  [ -d "${dir}" ] || return 0
  shopt -s nullglob
  for f in "${dir}"/*.tf; do
    while IFS= read -r line || [ -n "${line}" ]; do
      if [[ "${line}" =~ ^[[:space:]]*module[[:space:]]+\"([^\"]+)\" ]]; then
        addrs+=("module.${BASH_REMATCH[1]}")
      fi
    done < "${f}"
  done
  shopt -u nullglob
  if [ "${#addrs[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${addrs[@]}" | LC_ALL=C sort -u
}

# Batch -it: module.workload · teama, teamb (parent tf pattern).
menu_list_batch_modules_grouped() {
  local team addr
  {
    for team in "$@"; do
      while IFS= read -r addr; do
        [ -n "${addr}" ] || continue
        printf '%s\t%s\n' "${addr}" "${team}"
      done < <(menu_list_team_module_roots "${team}")
    done
  } | LC_ALL=C sort -t "$(printf '\t')" -k1,1 | awk -F "$(printf '\t')" '
    {
      if ($1 == prev) {
        if (index(stacks, $2) == 0) stacks = stacks ", " $2
      } else {
        if (prev != "") print prev " · " stacks
        prev = $1
        stacks = $2
      }
    }
    END { if (prev != "") print prev " · " stacks }
  '
}

menu_list_batch_modules_grouped_base() {
  local scope addr
  {
    for scope in "$@"; do
      while IFS= read -r addr; do
        [ -n "${addr}" ] || continue
        printf '%s\t%s\n' "${addr}" "${scope}"
      done < <(menu_list_scope_module_roots "${scope}")
    done
  } | LC_ALL=C sort -t "$(printf '\t')" -k1,1 | awk -F "$(printf '\t')" '
    {
      if ($1 == prev) {
        if (index(stacks, $2) == 0) stacks = stacks ", " $2
      } else {
        if (prev != "") print prev " · " stacks
        prev = $1
        stacks = $2
      }
    }
    END { if (prev != "") print prev " · " stacks }
  '
}

menu_pick_terraform_target_from_options() {
  local prompt=${1:-module -target (batch)}
  local -a options=("(no -target)")
  local choice addr target_line

  shift 2>/dev/null || true
  while IFS= read -r addr; do
    [ -n "${addr}" ] || continue
    options+=("${addr}")
  done

  options+=("(custom address…)")

  if [ "${#options[@]}" -le 2 ]; then
    log "No targets in state/config — enter address manually."
    printf "❯ terraform -target: " >&2
    read -r target_line </dev/tty || return 130
    [ -n "${target_line}" ] || return 0
    MENU_PICKED_TARGET_FLAG="-target=${target_line}"
    return 0
  fi

  choice="$(menu_fzf_one "${prompt}" "${options[@]}")" || return $?

  case "${choice}" in
    "(no -target)")
      return 0
      ;;
    "(custom address…)")
      printf "❯ terraform -target: " >&2
      read -r target_line </dev/tty || return 130
      [ -n "${target_line}" ] || return 0
      MENU_PICKED_TARGET_FLAG="-target=${target_line}"
      ;;
    *)
      MENU_PICKED_TARGET_FLAG="-target=$(menu_target_strip_stack_suffix "${choice}")"
      ;;
  esac
}

menu_pick_terraform_target_infra_batch() {
  MENU_PICKED_TARGET_FLAG=
  menu_pick_terraform_target_from_options "module -target (batch)" < <(menu_list_batch_modules_grouped "$@")
}

menu_pick_terraform_target_base_batch() {
  MENU_PICKED_TARGET_FLAG=
  menu_pick_terraform_target_from_options "module -target (batch)" < <(menu_list_batch_modules_grouped_base "$@")
}

# Addresses for -it (state list, else module/resource hints from .tf).
menu_list_workdir_target_addresses() {
  local addr f line stack_tag=""
  local -a addrs=()

  if [ -n "${MENU_IT_UNIT_LABEL:-}" ]; then
    stack_tag=" · ${MENU_IT_UNIT_LABEL}"
  fi

  while IFS= read -r addr; do
    [ -n "${addr}" ] || continue
    case "${addr}" in
      data.*) continue ;;
    esac
    addrs+=("${addr}${stack_tag}")
  done < <(
  (
    if [ -f "${ROOT}/${TF_WRAPPER_INFRA_DIR}/.env" ]; then
      set -a
      # shellcheck source=/dev/null
      source "${ROOT}/${TF_WRAPPER_INFRA_DIR}/.env"
      set +a
    fi
    if [ -n "${CONFIG_DIR:-}" ] && [ -f "${CONFIG_DIR}/.env" ]; then
      set -a
      # shellcheck source=/dev/null
      source "${CONFIG_DIR}/.env"
      set +a
    fi
    if [ -n "${BACKEND_CONFIG:-}" ] && [ -f "${BACKEND_CONFIG}" ]; then
      terraform_init_backend "${WORK_DIR}" "${BACKEND_CONFIG}" 1 \
        && terraform -chdir="${WORK_DIR}" state list 2>/dev/null
    else
      terraform -chdir="${WORK_DIR}" state list 2>/dev/null
    fi
  ) || true
  )

  if [ "${#addrs[@]}" -eq 0 ]; then
    shopt -s nullglob
    for f in "${WORK_DIR}"/*.tf; do
      [ -f "${f}" ] || continue
      while IFS= read -r line || [ -n "${line}" ]; do
        if [[ "${line}" =~ ^[[:space:]]*module[[:space:]]+\"([^\"]+)\" ]]; then
          addrs+=("module.${BASH_REMATCH[1]}${stack_tag}")
        elif [[ "${line}" =~ ^[[:space:]]*resource[[:space:]]+\"([^\"]+)\"[[:space:]]+\"([^\"]+)\" ]]; then
          addrs+=("${BASH_REMATCH[1]}.${BASH_REMATCH[2]}${stack_tag}")
        fi
      done < "${f}"
    done
    shopt -u nullglob
  fi

  if [ "${#addrs[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${addrs[@]}" | LC_ALL=C sort -u
}

# Sets MENU_PICKED_TARGET_FLAG (caller shell). Call after WORK_DIR + ensure_init.
menu_pick_terraform_target() {
  local -a options=("(no -target)")
  local choice addr target_line

  MENU_PICKED_TARGET_FLAG=
  while IFS= read -r addr; do
    [ -n "${addr}" ] || continue
    options+=("${addr}")
  done < <(menu_list_workdir_target_addresses)
  options+=("(custom address…)")

  if [ "${#options[@]}" -le 2 ]; then
    log "No targets in state/config — enter address manually."
    printf "❯ terraform -target: " >&2
    read -r target_line </dev/tty || return 130
    [ -n "${target_line}" ] || return 0
    MENU_PICKED_TARGET_FLAG="-target=${target_line}"
    return 0
  fi

  choice="$(menu_fzf_one "terraform -target" "${options[@]}")" || return $?

  case "${choice}" in
    "(no -target)")
      return 0
      ;;
    "(custom address…)")
      printf "❯ terraform -target: " >&2
      read -r target_line </dev/tty || return 130
      [ -n "${target_line}" ] || return 0
      MENU_PICKED_TARGET_FLAG="-target=${target_line}"
      ;;
    *)
      MENU_PICKED_TARGET_FLAG="-target=$(menu_target_strip_stack_suffix "${choice}")"
      ;;
  esac
}

menu_confirm_step() {
  MENU_TRAIL+=("$1: $2")
}

menu_show_trail() {
  if [ "${#MENU_TRAIL[@]}" -eq 0 ]; then
    return 0
  fi
  log "Confirmed:"
  local line
  for line in "${MENU_TRAIL[@]}"; do
    log "  ✓ ${line}"
  done
  log
}

menu_banner() {
  local step=$1
  clear >/dev/tty 2>/dev/null || true
  log "tf.sh · template wrapper"
  log
  menu_show_trail
  log "Step: ${step}"
  log "  ↑/↓ navigate · type to filter · Enter select · Esc cancel"
  log
}

menu_require_fzf_or_fallback() {
  if [ -n "${MENU_USE_FZF:-}" ]; then
    [ "${MENU_USE_FZF}" = "1" ]
    return $?
  fi
  if command -v fzf >/dev/null 2>&1; then
    MENU_USE_FZF=1
    return 0
  fi
  MENU_USE_FZF=0
  log "Note: fzf not found — numbered menu (brew install fzf)"
  return 1
}

menu_sanitize_choice() {
  local raw=$1
  raw="$(printf '%s\n' "$raw" | tr -d '\r' | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | sed '/^$/d' | head -n1)"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

menu_numbered_one() {
  local -a items=("$@")
  local i=1 item choice
  for item in "${items[@]}"; do
    printf "%3d. %s\n" "$i" "$item" >&2
    i=$((i + 1))
  done
  log
  printf "❯ " >&2
  read -r choice </dev/tty || true
  if [[ ! "${choice}" =~ ^[0-9]+$ ]] || [ "${choice}" -lt 1 ] || [ "${choice}" -gt "${#items[@]}" ]; then
    log "Cancelled."
    return 130
  fi
  printf '%s\n' "${items[$((choice - 1))]}"
}

menu_numbered_multi() {
  local -a items=("$@")
  local i=1 item choice part
  local -a picked=()
  for item in "${items[@]}"; do
    printf "%3d. %s\n" "$i" "$item" >&2
    i=$((i + 1))
  done
  log
  log "Enter numbers (space/comma-separated):"
  printf "❯ " >&2
  read -r choice </dev/tty || true
  [ -n "${choice}" ] || {
    log "Cancelled."
    return 130
  }
  choice="${choice//,/ }"
  for part in ${choice}; do
    if [[ "${part}" =~ ^[0-9]+$ ]] && [ "${part}" -ge 1 ] && [ "${part}" -le "${#items[@]}" ]; then
      picked+=("${items[$((part - 1))]}")
    fi
  done
  [ "${#picked[@]}" -gt 0 ] || {
    log "Cancelled."
    return 130
  }
  printf '%s\n' "${picked[@]}"
}

menu_fzf_one() {
  local prompt=$1
  shift
  local -a items=("$@")
  menu_banner "${prompt}"

  local choice
  if menu_require_fzf_or_fallback; then
    choice="$(
      printf '%s\n' "${items[@]}" | fzf \
        --height=80% \
        --reverse \
        --prompt="❯ " \
        --pointer="▶" \
        --header="${prompt}" \
        --bind="esc:abort" \
        --color="prompt:cyan,pointer:green,header:blue" \
        --exit-0
    )" || true
  else
    choice="$(menu_numbered_one "${items[@]}")" || return $?
  fi

  choice="$(menu_sanitize_choice "${choice}")"
  [ -n "${choice}" ] || {
    log "Cancelled."
    return 130
  }
  printf '%s\n' "${choice}"
}

menu_fzf_multi() {
  local prompt=$1
  shift
  local -a items=("$@")
  menu_banner "${prompt}"

  local choice line cleaned=""
  if menu_require_fzf_or_fallback; then
    choice="$(
      printf '%s\n' "${items[@]}" | fzf \
        --multi \
        --height=80% \
        --reverse \
        --prompt="❯ " \
        --pointer="▶" \
        --marker="✓" \
        --header="${prompt} · Tab toggle · Enter confirm" \
        --bind="esc:abort" \
        --color="prompt:cyan,pointer:green,header:blue" \
        --exit-0
    )" || true
  else
    choice="$(menu_numbered_multi "${items[@]}")" || return $?
  fi

  [ -n "${choice}" ] || {
    log "Cancelled."
    return 130
  }
  while IFS= read -r line; do
    line="$(menu_sanitize_choice "${line}")"
    [ -n "${line}" ] || continue
    cleaned+="${line}"$'\n'
  done <<< "${choice}"
  printf '%s' "${cleaned}"
}

menu_flags_from_preset() {
  local preset=$1
  case "${preset}" in
    none* | "" ) ;;
    "-refresh=false (default)" | "-refresh=false")
      printf '%s\n' -refresh=false
      ;;
    "-refresh=false -lock=false")
      printf '%s\n' -refresh=false
      printf '%s\n' -lock=false
      ;;
    "-json")
      printf '%s\n' -json
      ;;
    *)
      printf '%s\n' "${preset}"
      ;;
  esac
}

menu_pick_flag_preset() {
  local command=$1
  case "${command}" in
    plan|apply)
      menu_fzf_one "flags (then run)" \
        "-refresh=false (default)" \
        "-refresh=false -lock=false" \
        "none"
      ;;
    output)
      menu_fzf_one "flags (then run)" "none" "-json"
      ;;
    *)
      menu_fzf_one "flags (then run)" "none"
      ;;
  esac
}

menu_collect_units() {
  local -a out=()
  local team env dir
  while IFS= read -r team; do
    [ -n "${team}" ] || continue
    for env in ${TF_WRAPPER_INFRA_ENVS}; do
      dir="${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config/${env}"
      [ -d "${dir}" ] || continue
      out+=("${team}:${env}")
    done
  done < <(discover_infra_teams)
  printf '%s\n' "${out[@]}"
}

menu_array_join() {
  local out="" item
  for item in "$@"; do
    [ -n "${item}" ] || continue
    out+="${item} "
  done
  printf '%s' "${out%"${out##*[![:space:]]}"}"
}

menu_require_nonempty() {
  local label=$1
  shift
  if [ $# -lt 1 ]; then
    log "Error: no ${label} selected — try again or use: ./tf.sh b|i …"
    exit 1
  fi
}

menu_assign_infra_preselect_csv() {
  local a=$1
  local b=$2
  if is_infra_env_token "${a}"; then
    MENU_PRESELECT_ENVS="${a}"
    MENU_PRESELECT_TEAMS="${b}"
  else
    MENU_PRESELECT_TEAMS="${a}"
    MENU_PRESELECT_ENVS="${b}"
  fi
}

# ./tf.sh -i [base|i] [preselect…] · strips flags; optional layer + scope or team×env CSV.
interactive_menu_parse_invocation() {
  local arg
  MENU_PRESELECT_LAYER=
  MENU_PRESELECT_SCOPES=
  MENU_PRESELECT_TEAMS=
  MENU_PRESELECT_ENVS=
  local -a passthrough=()

  for arg in "$@"; do
    case "${arg}" in
      -ip|-ia|-iv|-it|-i) ;;
      b|base|i|infra)
        if [ -z "${MENU_PRESELECT_LAYER:-}" ]; then
          MENU_PRESELECT_LAYER="$(normalize_layer_arg "${arg}")"
        fi
        ;;
      *)
        passthrough+=("${arg}")
        ;;
    esac
  done

  case "${MENU_PRESELECT_LAYER:-}" in
    base)
      if [ "${#passthrough[@]}" -ge 1 ]; then
        MENU_PRESELECT_SCOPES="${passthrough[0]}"
      fi
      ;;
    infra)
      if [ "${#passthrough[@]}" -ge 2 ]; then
        menu_assign_infra_preselect_csv "${passthrough[0]}" "${passthrough[1]}"
      fi
      ;;
  esac
}

interactive_menu() {
  set +u

  local default_cmd=""
  local arg command layer flags_preset choice scope team environment unit
  local -a scopes=()
  local -a team_tokens=()
  local -a env_tokens=()
  local -a unit_opts=()
  local -a flags=()
  local rc=0

  MENU_PICK_TARGET=
  MENU_BATCH_TARGET_PICKED=
  for arg in "$@"; do
    case "${arg}" in
      -ip) default_cmd=plan ;;
      -ia) default_cmd=apply ;;
      -iv) default_cmd=validate ;;
      -it) MENU_PICK_TARGET=1 ;;
      -i) ;;
    esac
  done
  if [ -n "${MENU_PICK_TARGET:-}" ] && [ -z "${default_cmd}" ]; then
    default_cmd=apply
  fi

  interactive_menu_parse_invocation "$@"

  MENU_TRAIL=()
  MENU_USE_FZF=
  menu_require_fzf_or_fallback || true

  if [ -n "${default_cmd}" ]; then
    command="${default_cmd}"
    menu_confirm_step "command" "${command}"
  else
    command="$(menu_fzf_one "command" plan apply validate init fmt output)" || exit $?
    menu_confirm_step "command" "${command}"
  fi

  if [ -n "${MENU_PRESELECT_LAYER:-}" ]; then
    layer="${MENU_PRESELECT_LAYER}"
    menu_confirm_step "layer" "${layer}"
  else
    layer="$(menu_fzf_one "layer" base infra)" || exit $?
    menu_confirm_step "layer" "${layer}"
  fi

  case "${layer}" in
    base)
      flags=()
      if [ -n "${MENU_PRESELECT_SCOPES:-}" ]; then
        choice="${MENU_PRESELECT_SCOPES}"
        menu_confirm_step "scope" "${choice}"
      else
        scope_opts=()
        for scope in ${TF_WRAPPER_BASE_SCOPES}; do
          scope_opts+=("${scope}")
        done
        scope_opts+=(all)
        choice="$(menu_fzf_one "scope" "${scope_opts[@]}")" || exit $?
        menu_confirm_step "scope" "${choice}"
      fi
      scopes=()
      while IFS= read -r scope; do
        scopes+=("${scope}")
      done < <(split_csv "$(expand_csv_token scopes "${choice}")")
      menu_require_nonempty scope "${scopes[@]}"

      flags_preset="$(menu_pick_flag_preset "${command}")" || exit $?
      menu_confirm_step "flags" "${flags_preset}"
      while IFS= read -r line; do
        [ -n "${line}" ] && flags+=("${line}")
      done < <(menu_flags_from_preset "${flags_preset}")

      if [ "${#scopes[@]}" -gt 1 ] && [ -n "${MENU_PICK_TARGET:-}" ] && command_supports_target "${command}"; then
        menu_pick_terraform_target_base_batch "${scopes[@]}" || exit $?
        MENU_BATCH_TARGET_PICKED=1
        if [ -n "${MENU_PICKED_TARGET_FLAG:-}" ]; then
          menu_confirm_step "target" "${MENU_PICKED_TARGET_FLAG#-target=}"
          flags+=("${MENU_PICKED_TARGET_FLAG}")
        fi
      fi

      COMMAND="${command}"
      FLAGS=("${flags[@]}")
      log
      for scope in "${scopes[@]}"; do
        log "Running: ./tf.sh b ${scope} ${command} ${flags[*]:-}"
        run_base_unit "${scope}" || rc=1
      done
      ;;
    infra)
      flags=()

      if [ -n "${MENU_PRESELECT_TEAMS:-}" ] && [ -n "${MENU_PRESELECT_ENVS:-}" ]; then
        menu_confirm_step "batch" "${MENU_PRESELECT_TEAMS} × ${MENU_PRESELECT_ENVS}"
        team_tokens=()
        while IFS= read -r team; do
          team_tokens+=("${team}")
        done < <(split_csv "$(expand_csv_token teams "${MENU_PRESELECT_TEAMS}")")
        env_tokens=()
        while IFS= read -r environment; do
          env_tokens+=("${environment}")
        done < <(split_csv "$(expand_csv_token envs "${MENU_PRESELECT_ENVS}")")
        menu_require_nonempty team "${team_tokens[@]}"
        menu_require_nonempty environment "${env_tokens[@]}"
      else
        unit_opts=()
        while IFS= read -r unit; do
          unit_opts+=("${unit}")
        done < <(menu_collect_units)
        unit_opts+=(all)

        choice="$(menu_fzf_one "unit (team:env)" "${unit_opts[@]}")" || exit $?
        menu_confirm_step "unit" "${choice}"

        if [ "${choice}" = "all" ]; then
          team_tokens=()
          while IFS= read -r team; do
            team_tokens+=("${team}")
          done < <(discover_infra_teams)
          env_tokens=()
          for environment in ${TF_WRAPPER_INFRA_ENVS}; do
            env_tokens+=("${environment}")
          done
        else
          team_tokens=("${choice%%:*}")
          env_tokens=("${choice##*:}")
        fi
      fi

      flags_preset="$(menu_pick_flag_preset "${command}")" || exit $?
      menu_confirm_step "flags" "${flags_preset}"
      while IFS= read -r line; do
        [ -n "${line}" ] && flags+=("${line}")
      done < <(menu_flags_from_preset "${flags_preset}")

      unit_count=0
      for team in "${team_tokens[@]}"; do
        for environment in "${env_tokens[@]}"; do
          [ -d "${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config/${environment}" ] && unit_count=$((unit_count + 1))
        done
      done
      if [ "${unit_count}" -gt 1 ] && [ -n "${MENU_PICK_TARGET:-}" ] && command_supports_target "${command}"; then
        menu_pick_terraform_target_infra_batch "${team_tokens[@]}" || exit $?
        MENU_BATCH_TARGET_PICKED=1
        if [ -n "${MENU_PICKED_TARGET_FLAG:-}" ]; then
          menu_confirm_step "target" "${MENU_PICKED_TARGET_FLAG#-target=}"
          flags+=("${MENU_PICKED_TARGET_FLAG}")
        fi
      fi

      COMMAND="${command}"
      FLAGS=("${flags[@]}")
      log

      for team in "${team_tokens[@]}"; do
        for environment in "${env_tokens[@]}"; do
          [ -d "${ROOT}/${TF_WRAPPER_INFRA_DIR}/${team}/config/${environment}" ] || continue
          log "Running: ./tf.sh i ${team} ${environment} ${command} ${flags[*]:-}"
          run_infra_unit "${team}" "${environment}" || rc=1
        done
      done
      ;;
  esac

  exit "${rc}"
}
