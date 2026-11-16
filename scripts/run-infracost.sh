#!/usr/bin/env bash
# Infracost breakdown for infracost.yml projects (optional; not on pre-commit).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${ROOT}/infracost.yml"
CACHE="${ROOT}/.cache/infracost-baseline.json"

usage() {
  cat <<EOF
Usage: $0 [--diff] [--reset]

  infracost breakdown --config-file=${CONFIG}
  Baseline: .cache/infracost-baseline.json (gitignored)

  Set INFRACOST_API_KEY or use INFRACOST_CLOUD_API_KEY for CI.
EOF
}

DIFF=0
RESET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    --diff) DIFF=1; shift ;;
    --reset)
      RESET=1
      shift
      ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

if ! command -v infracost >/dev/null 2>&1; then
  echo "ERROR: infracost not in PATH. Install: brew install infracost" >&2
  exit 1
fi

mkdir -p "${ROOT}/.cache"
if [[ "${RESET}" -eq 1 && -f "${CACHE}" ]]; then
  rm -f "${CACHE}"
fi

echo "==> infracost breakdown"
out="$(mktemp)"
trap 'rm -f "${out}"' EXIT
infracost breakdown --config-file="${CONFIG}" --format json >"${out}"

if [[ "${DIFF}" -eq 1 ]] && [[ -f "${CACHE}" ]]; then
  infracost diff --path "${out}" --compare-to "${CACHE}" --format table
fi
infracost output --path "${out}" --format table
cp "${out}" "${CACHE}"
