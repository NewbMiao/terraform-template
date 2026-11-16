#!/usr/bin/env bash
# Fail if staged files include common secret, state, or plan paths.
set -euo pipefail

blocked=0
while IFS= read -r -d '' path; do
  case "${path}" in
    *.env | *.env.*)
      case "${path}" in
        *.env.example) ;;
        *)
          echo "blocked: ${path} (environment file)" >&2
          blocked=1
          ;;
      esac
      ;;
    *.tfstate|*.tfstate.*)
      echo "blocked: ${path} (terraform state)" >&2
      blocked=1
      ;;
    *.tfplan | *.plan)
      echo "blocked: ${path} (terraform plan)" >&2
      blocked=1
      ;;
    *.key | *.pem | *.p12 | *.pfx | credentials*.json)
      echo "blocked: ${path} (credential or private key file)" >&2
      blocked=1
      ;;
  esac
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

exit "${blocked}"
