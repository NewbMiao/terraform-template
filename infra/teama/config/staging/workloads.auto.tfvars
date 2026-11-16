workloads = {
  api = {
    workload_type    = "container_service"
    size_tier        = "small"
    network_exposure = "public"
  }
  jobs = {
    workload_type    = "background_jobs"
    size_tier        = "small"
    network_exposure = "private"
  }
}
