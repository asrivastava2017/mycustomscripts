output "state_bucket" {
  description = "Terraform state bucket."
  value       = google_storage_bucket.state.name
}

output "state_prefix" {
  description = "State path inside the bucket for this environment."
  value       = local.state_path
}

output "backend_config_file" {
  description = "Generated backend config for the main stack."
  value       = local_file.backend_config.filename
}
