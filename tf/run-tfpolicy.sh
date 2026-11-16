#!/bin/bash
# Run tf/tfpolicy/ with HashiCorp Terraform Policy CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
POLICIES="${ROOT}/tf/tfpolicy/policies"
TESTS="${ROOT}/tf/tfpolicy/tests"

usage() {
  echo "Usage: $0 [validate|test]" >&2
}

cmd="${1:-test}"
case "${cmd}" in
  -h | --help | help)
    usage
    exit 0
    ;;
  validate | test) ;;
  *)
    usage
    exit 1
    ;;
esac

if ! command -v tfpolicy >/dev/null 2>&1; then
  echo "ERROR: tfpolicy not in PATH. Install: brew tap hashicorp/tap && brew install hashicorp/tap/tfpolicy" >&2
  exit 1
fi

case "${cmd}" in
  validate)
    tfpolicy validate --policies="${POLICIES}"
    ;;
  test)
    tfpolicy validate --policies="${POLICIES}"
    tfpolicy test --policies="${POLICIES}" --tests="${TESTS}"
    ;;
esac
