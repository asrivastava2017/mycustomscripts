# Every environment-specific value lives in environments/<env>/terraform.tfvars.
# Defaults here are sensible production values; override them per environment.

# --- Project & location ---------------------------------------------------------------

variable "project_id" {
  description = "GCP project to deploy into."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "zone" {
  description = "GCP zone for the VM and its data disk (inside region)."
  type        = string
}

variable "labels" {
  description = "Labels applied to all supported resources."
  type        = map(string)
  default     = {}
}

# --- State bucket ---------------------------------------------------------------------
# Read only by bootstrap/ (make bootstrap). Declared here so the shared tfvars file
# does not trigger "undeclared variable" warnings in the main stack.

variable "state_bucket_name" {
  description = "Terraform state bucket name, used by bootstrap/. null = \"<project_id>-pritunl-tfstate\"."
  type        = string
  default     = null
}

variable "state_bucket_location" {
  description = "State bucket location, used by bootstrap/. null = region."
  type        = string
  default     = null
}

variable "state_versions_to_keep" {
  description = "Older state versions kept, used by bootstrap/."
  type        = number
  default     = 20
}

# --- Network --------------------------------------------------------------------------

variable "vpc_name" {
  description = "Name of the new VPC."
  type        = string
}

variable "subnet_name" {
  description = "Name of the new subnet."
  type        = string
}

variable "subnet_cidr" {
  description = "Subnet range for the Pritunl VM. Must not overlap reserved_cidrs."
  type        = string
}

variable "vpn_client_cidr" {
  description = "Range Pritunl hands out to VPN clients (set the same value as the Pritunl server's 'Virtual Network'). Checked for overlap only; Terraform does not configure Pritunl."
  type        = string
}

variable "reserved_cidrs" {
  description = "Ranges already in use (existing VPCs, GKE, on-prem). Plan fails if subnet_cidr or vpn_client_cidr overlaps any of them."
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on the subnet."
  type        = bool
  default     = true
}

variable "peerings" {
  description = "VPC peerings to existing VPCs whose private resources VPN users must reach. See modules/network/variables.tf."
  type = list(object({
    name                  = string
    peer_network          = string
    import_custom_routes  = optional(bool, false)
    export_custom_routes  = optional(bool, false)
    create_remote_peering = optional(bool, false)
    remote_peering_name   = optional(string)
  }))
  default = []
}

# --- Pritunl VM -----------------------------------------------------------------------

variable "vm_name" {
  description = "Pritunl VM name (also prefixes its IPs, disk, MIG, firewall rules)."
  type        = string
}

variable "machine_type" {
  description = "VM machine type."
  type        = string
  default     = "e2-small"
}

variable "source_image" {
  description = "Boot image or image family."
  type        = string
  default     = "projects/rocky-linux-cloud/global/images/family/rocky-linux-9"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size (GB)."
  type        = number
  default     = 20
}

variable "data_disk_size_gb" {
  description = "Stateful data disk size (GB)."
  type        = number
  default     = 20
}

variable "internal_ip_address" {
  description = "Fixed internal IP for the VM, or null to pick one."
  type        = string
  default     = null
}

variable "mongodb_version" {
  description = "MongoDB apt repo version. Keep pinned."
  type        = string
  default     = "8.0"
}

variable "install_ops_agent" {
  description = "Install the Google Cloud Ops Agent."
  type        = bool
  default     = true
}

# --- Encryption -----------------------------------------------------------------------

variable "create_kms_key" {
  description = "true = create a Cloud KMS key and encrypt the VM disks and snapshots with it (CMEK). false = Google-managed encryption. Decide before the first apply: switching later replaces the data disk."
  type        = bool
  default     = false
}

variable "kms_key_ring_name" {
  description = "Key ring name (used when create_kms_key = true). Key rings can never be deleted, so keep it stable."
  type        = string
  default     = "pritunl-keyring"
}

variable "kms_key_name" {
  description = "Crypto key name (used when create_kms_key = true)."
  type        = string
  default     = "pritunl-disk-key"
}

variable "kms_key_rotation_period" {
  description = "Automatic key rotation period, seconds with an 's' suffix. Default 90 days."
  type        = string
  default     = "7776000s"
}

variable "kms_protection_level" {
  description = "SOFTWARE or HSM."
  type        = string
  default     = "SOFTWARE"
}

# --- Access ---------------------------------------------------------------------------

variable "vpn_udp_ports" {
  description = "UDP ports of the Pritunl servers, as configured in the Pritunl UI. Avoid 1194 on SELinux systems (reserved for the system OpenVPN service)."
  type        = list(string)
  default     = ["15194"]
}

variable "admin_source_ranges" {
  description = "Public CIDRs allowed to reach the Pritunl console (TCP 443)."
  type        = list(string)
}

variable "admin_members" {
  description = "Principals allowed to SSH to the VM via IAP + OS Login (e.g. group:vpn-admins@company.com). Terraform grants them the IAP tunnel role, the OS Login role and serviceAccountUser on the VM service account."
  type        = list(string)
  default     = []
}

variable "admin_sudo" {
  description = "Give admin_members sudo on the VM (osAdminLogin) instead of plain login (osLogin)."
  type        = bool
  default     = true
}

variable "letsencrypt_domain" {
  description = "Domain for a Let's Encrypt certificate on the Pritunl web server (e.g. vpn.example.com). Opens TCP 80 for issuance/renewal. null = self-signed certificate."
  type        = string
  default     = null
}

# --- Operations -----------------------------------------------------------------------

variable "autohealing_initial_delay_sec" {
  description = "Grace period before autohealing checks a new VM."
  type        = number
  default     = 900
}

variable "update_policy_type" {
  description = "PROACTIVE or OPPORTUNISTIC rollout of template changes."
  type        = string
  default     = "PROACTIVE"
}

variable "snapshot_start_time" {
  description = "Daily snapshot time (UTC, HH:00)."
  type        = string
  default     = "02:00"
}

variable "snapshot_boot_disk" {
  description = "Also snapshot the boot disk daily, with the same schedule and retention as the data disk."
  type        = bool
  default     = true
}

variable "snapshot_before_vm_replace" {
  description = "Snapshot the data disk (via gcloud) before any apply that recreates the VM, and before terraform destroy."
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  description = "Days to keep snapshots."
  type        = number
  default     = 14
}

# --- Restore server -------------------------------------------------------------------

variable "restore" {
  description = <<-EOT
    Launch a separate Pritunl restore server from snapshots (null = none). Creates a new VM,
    new disks from the snapshots and a new static IP in the same subnet; the running server
    is not modified. Set back to null to remove the restore server and its disks/IP.
  EOT
  type = object({
    boot_snapshot = string           # snapshot of the boot disk (name or projects/<p>/global/snapshots/<name>)
    data_snapshot = string           # snapshot of the data disk
    name          = optional(string) # default "<vm_name>-restore"
    machine_type  = optional(string) # default: same as machine_type
    zone          = optional(string) # default: same as zone
  })
  default = null
}
