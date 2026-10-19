output "vm_name" {
  description = "Pritunl VM name."
  value       = google_compute_per_instance_config.pritunl.name
}

output "external_ip" {
  description = "Reserved static external IP. Point the Namecheap A record here."
  value       = google_compute_address.external.address
}

output "internal_ip" {
  description = "Reserved internal IP. VPN traffic leaves the VM from this IP (NAT on), so use it in Atlas, Redis Cloud and peer-VPC firewall allow-lists."
  value       = google_compute_address.internal.address
}

output "instance_group_manager" {
  description = "Stateful MIG name."
  value       = google_compute_instance_group_manager.pritunl.name
}

output "data_disk" {
  description = "Stateful data disk name."
  value       = google_compute_disk.data.name
}

output "service_account_email" {
  description = "VM service account."
  value       = google_service_account.pritunl.email
}

output "admin_url" {
  description = "Pritunl web console (reachable only from admin_source_ranges)."
  value       = "https://${google_compute_address.external.address}"
}

output "ssh_command" {
  description = "SSH to the VM through IAP."
  value       = "gcloud compute ssh ${var.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap"
}

output "initial_setup_commands" {
  description = "Run once after first boot (~5-10 min) to get the setup key and default admin password."
  value = [
    "gcloud compute ssh ${var.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap --command 'sudo pritunl setup-key'",
    "gcloud compute ssh ${var.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap --command 'sudo pritunl default-password'",
  ]
}

output "startup_script" {
  description = "Rendered startup script, reused by modules/pritunl-restore."
  value       = local.startup_script
}

output "network_tag" {
  description = "Network tag the firewall rules target."
  value       = var.network_tag
}

output "data_device_name" {
  description = "Device name the startup script expects for the data disk."
  value       = local.data_device_name
}
