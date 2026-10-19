output "vm_name" {
  description = "Restore VM name."
  value       = google_compute_instance.restore.name
}

output "external_ip" {
  description = "New static public IP of the restore server."
  value       = google_compute_address.external.address
}

output "internal_ip" {
  description = "Internal IP of the restore server (NAT source for VPN traffic; add to Atlas/Redis/peer allow-lists if users will use it)."
  value       = google_compute_address.internal.address
}

output "admin_url" {
  description = "Pritunl console on the restore server (reachable from admin_source_ranges)."
  value       = "https://${google_compute_address.external.address}"
}

output "ssh_command" {
  description = "SSH to the restore VM through IAP."
  value       = "gcloud compute ssh ${google_compute_instance.restore.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap"
}
