output "vpc_name" {
  description = "VPC name."
  value       = module.network.network_name
}

output "subnet_name" {
  description = "Subnet name."
  value       = module.network.subnet_name
}

output "subnet_cidr" {
  description = "Subnet range. Allow it in peer-VPC firewall rules."
  value       = module.network.subnet_cidr
}

output "vm_name" {
  description = "Pritunl VM name."
  value       = module.pritunl.vm_name
}

output "external_ip" {
  description = "Static public IP. Create the Namecheap A record for it."
  value       = module.pritunl.external_ip
}

output "internal_ip" {
  description = "Static internal IP; source of all VPN traffic (NAT on). Use in Atlas/Redis Cloud allow-lists."
  value       = module.pritunl.internal_ip
}

output "admin_url" {
  description = "Pritunl web console."
  value       = module.pritunl.admin_url
}

output "ssh_command" {
  description = "SSH via IAP."
  value       = module.pritunl.ssh_command
}

output "initial_setup_commands" {
  description = "Commands to fetch the setup key and default password."
  value       = module.pritunl.initial_setup_commands
}

output "disk_encryption" {
  description = "Key encrypting the VM disks and snapshots, or Google-managed."
  value       = var.create_kms_key ? module.kms[0].crypto_key_id : "Google-managed"
}

output "peerings" {
  description = "Peering states."
  value       = module.network.peerings
}

output "restore_server" {
  description = "Restore server details (null when var.restore is not set)."
  value = var.restore == null ? null : {
    vm_name     = module.pritunl_restore[0].vm_name
    external_ip = module.pritunl_restore[0].external_ip
    internal_ip = module.pritunl_restore[0].internal_ip
    admin_url   = module.pritunl_restore[0].admin_url
    ssh_command = module.pritunl_restore[0].ssh_command
  }
}

output "log_archive_bucket" {
  description = "Cloud Storage bucket holding archived Pritunl logs (null if disabled)."
  value       = var.enable_log_archive ? module.log_archive[0].bucket_name : null
}
