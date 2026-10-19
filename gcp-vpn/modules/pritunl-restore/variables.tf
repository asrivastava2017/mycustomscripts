variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the new static IP."
  type        = string
}

variable "zone" {
  description = "Zone for the restore VM and its disks."
  type        = string
}

variable "name" {
  description = "Restore VM name (also prefixes its disks and IP). Must differ from the running server."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,52}[a-z0-9])?$", var.name))
    error_message = "name must be RFC 1035 (lowercase letters, digits, hyphens), max 54 chars."
  }
}

variable "boot_snapshot" {
  description = "Snapshot of the Pritunl boot disk (name or projects/<p>/global/snapshots/<name>)."
  type        = string
}

variable "data_snapshot" {
  description = "Snapshot of the Pritunl data disk (name or projects/<p>/global/snapshots/<name>)."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Subnet of the existing Pritunl VPC."
  type        = string
}

variable "network_tag" {
  description = "Network tag of the existing Pritunl firewall rules (VPN port, admin 443, IAP SSH)."
  type        = string
}

variable "service_account_email" {
  description = "Service account for the VM (reuse the existing Pritunl one)."
  type        = string
}

variable "startup_script" {
  description = "Startup script (reuse the existing Pritunl one; it is idempotent on restored disks)."
  type        = string
}

variable "data_device_name" {
  description = "Device name the startup script expects for the data disk."
  type        = string
  default     = "pritunl-data"
}

variable "machine_type" {
  description = "Machine type for the restore VM."
  type        = string
  default     = "e2-standard-2"
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_type" {
  description = "Data disk type."
  type        = string
  default     = "pd-balanced"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size; null = the snapshot's size."
  type        = number
  default     = null
}

variable "data_disk_size_gb" {
  description = "Data disk size; null = the snapshot's size."
  type        = number
  default     = null
}

variable "internal_ip_address" {
  description = "Fixed internal IP for the restore VM, or null to pick a free one. It must differ from the running server's."
  type        = string
  default     = null
}

variable "kms_key_self_link" {
  description = "Cloud KMS key for the new disks (and to read CMEK snapshots); null = Google-managed."
  type        = string
  default     = null
}

variable "enable_secure_boot" {
  description = "Shielded VM Secure Boot."
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels for the VM, disks and IPs."
  type        = map(string)
  default     = {}
}
