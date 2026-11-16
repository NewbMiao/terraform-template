#!/usr/bin/env bash
# Pre-push: infracost scan from tf/infracost.yml (auth: `infracost auth login`, env key, or OS cache)
# TF_PRE_COMMIT_INFRACOST: optional (default) | required | 0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/tf/infracost.yml"
ROOT_CONFIG_LINK="${ROOT}/infracost.yml"
CONFIG_LINK_TARGET="tf/infracost.yml"
MODE="${TF_PRE_COMMIT_INFRICOST:-optional}"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
VERBOSE=0
if [ "${TF_PRE_COMMIT_INFRICOST_VERBOSE:-}" = "1" ] || [ "${1:-}" = "--verbose" ] || [ "${1:-}" = "-v" ]; then
  VERBOSE=1
fi

log() { echo "$@" >&2; }

die() {
  log "infracost: ERROR — $*"
  exit 1
}

skip() {
  log "infracost: optional skip — $*"
  printf 'infracost: skipped (%s)\n' "$*"
  exit 0
}

case "${MODE}" in
  0 | false | off | skip) skip "TF_PRE_COMMIT_INFRACOST=${MODE}" ;;
  required | require) MODE=required ;;
  optional | "") MODE=optional ;;
  *)
    die "unknown TF_PRE_COMMIT_INFRICOST=${MODE} (use optional, required, or 0)"
    ;;
esac

have_cli() { command -v infracost >/dev/null 2>&1; }

log_auth_probe() {
  log "infracost: auth probe (hook=${SCRIPT_PATH#"${ROOT}/"})"
  log "  HOME=${HOME}"
  log "  INFRACOST_API_KEY=$([ -n "${INFRACOST_API_KEY:-}" ] && echo set || echo unset)"
  log "  INFRACOST_CLOUD_API_KEY=$([ -n "${INFRACOST_CLOUD_API_KEY:-}" ] && echo set || echo unset)"
  if [ -f "${HOME}/.config/infracost/token.json" ]; then
    log "  ~/.config/infracost/token.json=present"
  else
    log "  ~/.config/infracost/token.json=missing (v2 may use OS keychain/cache instead)"
  fi
  if [ -n "${PRE_COMMIT:-}" ]; then
    log "  pre-commit=1 (stashes unstaged files — stage hook edits or test: ./tf/pre-commit-infracost.sh -v)"
  fi
}

if ! have_cli; then
  log_auth_probe
  if [ "${MODE}" = required ]; then
    die "infracost not in PATH (brew install infracost)"
  fi
  skip "not in PATH — brew install infracost"
fi

if [ ! -f "${CONFIG}" ]; then
  log_auth_probe
  if [ "${MODE}" = required ]; then
    die "${CONFIG#"${ROOT}/"} not found"
  fi
  skip "${CONFIG#"${ROOT}/"} not found"
fi

if [ -L "${ROOT_CONFIG_LINK}" ] && [ "$(readlink "${ROOT_CONFIG_LINK}")" = "${CONFIG_LINK_TARGET}" ]; then
  :
elif [ -e "${ROOT_CONFIG_LINK}" ] && [ ! -L "${ROOT_CONFIG_LINK}" ]; then
  die "remove regular file ${ROOT_CONFIG_LINK}, symlink must point to ${CONFIG_LINK_TARGET}"
else
  ln -sf "${CONFIG_LINK_TARGET}" "${ROOT_CONFIG_LINK}"
fi

[ "${VERBOSE}" -eq 1 ] && log_auth_probe

log "infracost: running scan (${CONFIG#"${ROOT}/"})"
printf 'infracost: scanning %s\n' "${CONFIG#"${ROOT}/"}"

# Do not pre-check token files — CLI may use keychain. Try run; fail → skip/die.
set +e
out="$(mktemp)"
trap 'rm -f "${out}"' EXIT
infracost breakdown --config-file="${CONFIG}" --format table >"${out}" 2>&1
rc=$?
set -e

if [ "${VERBOSE}" -eq 1 ] || [ "${rc}" -ne 0 ]; then
  cat "${out}" >&2
elif [ -s "${out}" ]; then
  cat "${out}" >&2
fi

if [ "${rc}" -ne 0 ]; then
  log_auth_probe
  if [ "${MODE}" = optional ]; then
    skip "scan failed (rc=${rc}) — run infracost auth login or set INFRACOST_API_KEY"
  fi
  die "scan failed (rc=${rc}); see output above"
fi

printf 'infracost: finished\n'
