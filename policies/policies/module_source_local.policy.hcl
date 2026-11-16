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
