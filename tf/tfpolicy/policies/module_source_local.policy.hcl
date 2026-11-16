# Enforced by ./tf/run-tfpolicy.sh test (pre-commit when tfpolicy is on PATH).
# Kind: module_policy  |  Phase: Setup  |  Data: meta.source (not Sentinel resources.*)

module_policy "*" "local_modules_only" {
  enforcement_level = "mandatory"
  filter            = meta.source != null

  enforce {
    condition = (
      core::startswith(meta.source, "./modules/") ||
      core::startswith(meta.source, "../modules/")
    )
    error_message = "Module source must be ./modules/ or ../modules/ (got ${meta.source})."
  }
}
