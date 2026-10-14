output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.this.name
}

output "network_id" {
  description = "VPC network ID."
  value       = google_compute_network.this.id
}

output "network_self_link" {
  description = "VPC network self link."
  value       = google_compute_network.this.self_link
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.this.name
}

output "subnet_self_link" {
  description = "Subnet self link."
  value       = google_compute_subnetwork.this.self_link
}

output "subnet_cidr" {
  description = "Subnet primary range."
  value       = google_compute_subnetwork.this.ip_cidr_range
}

output "peerings" {
  description = "Peering name -> state for the local side."
  value       = { for k, p in google_compute_network_peering.local : k => p.state }
}
