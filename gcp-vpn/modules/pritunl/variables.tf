variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the static IPs and snapshot policy."
  type        = string
}

variable "zone" {
  description = "Zone for the VM, MIG and data disk. Must be in var.region."
  type        = string
}

variable "name" {
  description = "VM name. Also the prefix for every resource this module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,50}[a-z0-9])?$", var.name))
    error_message = "name must be RFC 1035 (lowercase letters, digits, hyphens) and at most 52 chars, leaving room for suffixes."
  }
}

variable "network_self_link" {
  description = "Self link of the VPC the VM joins."
  type        = string
}

variable "subnetwork_self_link" {
  description = "Self link of the subnet the VM joins."
  type        = string
}

# --- VM -------------------------------------------------------------------------------

variable "machine_type" {
  description = "Machine type. e2-small suits ~50 users, e2-medium ~150."
  type        = string
  default     = "e2-small"
}

variable "source_image" {
  description = "Boot image or image family. RHEL-family (Rocky/Alma 9) is Pritunl's tested platform. Ubuntu 24.04 currently fails: its 6.19+ kernel stops MongoDB 8.0 from starting (MongoDB SERVER-121912)."
  type        = string
  default     = "projects/rocky-linux-cloud/global/images/family/rocky-linux-9"
}

variable "boot_disk_size_gb" {
  description = "Boot disk size. The boot disk is disposable; it is rebuilt on autoheal."
  type        = number
  default     = 20
}

variable "boot_disk_type" {
  description = "Boot disk type."
  type        = string
  default     = "pd-balanced"
}

variable "data_disk_size_gb" {
  description = "Stateful data disk size (MongoDB, Pritunl config). Can be increased later in place."
  type        = number
  default     = 20
}

variable "data_disk_type" {
  description = "Stateful data disk type."
  type        = string
  default     = "pd-balanced"
}

variable "kms_key_self_link" {
  description = "Cloud KMS key for the boot and data disks (snapshots inherit it). null = Google-managed encryption. Changing it later replaces the data disk, so set it before the first apply."
  type        = string
  default     = null
}

variable "internal_ip_address" {
  description = "Fixed internal IP for the VM inside the subnet. null = pick a free one. It is reserved either way, so allow-lists (Atlas, Redis Cloud, peer firewalls) stay valid."
  type        = string
  default     = null
}

variable "service_account_id" {
  description = "Account ID for the VM service account. null = \"<name>-sa\" (truncated to 30 chars)."
  type        = string
  default     = null
}

variable "labels" {
  description = "Labels applied to the VM, disks and IPs."
  type        = map(string)
  default     = {}
}

variable "network_tag" {
  description = "Network tag on the VM; firewall rules target it."
  type        = string
  default     = "pritunl"
}

variable "enable_secure_boot" {
  description = "Shielded VM Secure Boot."
  type        = bool
  default     = true
}

# --- Software -------------------------------------------------------------------------

variable "mongodb_version" {
  description = "MongoDB major.minor package repo to install. Pin it: the data on the stateful disk must match this version."
  type        = string
  default     = "8.0"
}

variable "ship_logs_to_cloud_logging" {
  description = "Configure the Ops Agent to send Pritunl's logs (/var/log/pritunl_journal.log as JSON, pritunl.log, startup log) to Cloud Logging. Needs install_ops_agent = true."
  type        = bool
  default     = true
}

variable "install_ops_agent" {
  description = "Install the Google Cloud Ops Agent for logs and metrics."
  type        = bool
  default     = true
}

# --- Admin SSH access -----------------------------------------------------------------

variable "admin_members" {
  description = "Principals allowed to SSH to the VM via IAP + OS Login, e.g. \"group:vpn-admins@company.com\" or \"user:alice@company.com\". Prefer groups."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.admin_members : can(regex("^(user|group|serviceAccount|domain):.+", m))])
    error_message = "Each admin_members entry must start with user:, group:, serviceAccount: or domain:."
  }
}

variable "admin_sudo" {
  description = "true = roles/compute.osAdminLogin (sudo). false = roles/compute.osLogin (no sudo)."
  type        = bool
  default     = true
}

# --- Firewall -------------------------------------------------------------------------

variable "vpn_udp_ports" {
  description = "UDP ports of the Pritunl servers (OpenVPN and/or WireGuard) opened to vpn_source_ranges. Must match the ports set in the Pritunl UI. Avoid 1194 on SELinux systems (Rocky/RHEL): it is reserved for the system OpenVPN service (openvpn_port_t), so Pritunl gets \"Permission denied\" binding it."
  type        = list(string)
  default     = ["15194"]
}

variable "vpn_source_ranges" {
  description = "Who can reach the VPN ports. Usually the whole internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_source_ranges" {
  description = "Public CIDRs allowed to reach the Pritunl web console on TCP 443. Never 0.0.0.0/0."
  type        = list(string)

  validation {
    condition     = length(var.admin_source_ranges) > 0 && !contains(var.admin_source_ranges, "0.0.0.0/0")
    error_message = "admin_source_ranges must list specific admin/office IPs and must not contain 0.0.0.0/0."
  }
}

variable "letsencrypt_domain" {
  description = "Domain (e.g. vpn.example.com) for a Let's Encrypt certificate on the Pritunl web server. When set, TCP 80 is opened to the internet (needed for issuance and automatic renewal) and the VM requests the certificate once the domain's A record points at the static IP. null = self-signed certificate, port 80 closed."
  type        = string
  default     = null

  validation {
    condition     = var.letsencrypt_domain == null || can(regex("^([a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.letsencrypt_domain))
    error_message = "letsencrypt_domain must be a lowercase fully qualified domain name, e.g. vpn.example.com."
  }
}

variable "iap_ssh_source_ranges" {
  description = "Source range for SSH via Identity-Aware Proxy."
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

variable "health_check_source_ranges" {
  description = "Google health-check probe ranges used by MIG autohealing."
  type        = list(string)
  default     = ["35.191.0.0/16", "130.211.0.0/22"]
}

# --- Health check & autohealing -------------------------------------------------------

variable "health_check_port" {
  description = "TCP port probed by the autohealing health check (Pritunl web service)."
  type        = number
  default     = 443
}

variable "health_check_interval_sec" {
  description = "Seconds between probes."
  type        = number
  default     = 10
}

variable "health_check_timeout_sec" {
  description = "Probe timeout."
  type        = number
  default     = 5
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures before the VM is recreated."
  type        = number
  default     = 3
}

variable "autohealing_initial_delay_sec" {
  description = "Grace period after (re)creation before health checks count. Covers a full package install on a fresh boot disk."
  type        = number
  default     = 900
}

variable "update_policy_type" {
  description = "PROACTIVE applies instance-template changes on apply (brief VPN outage). OPPORTUNISTIC waits for the next recreate."
  type        = string
  default     = "PROACTIVE"

  validation {
    condition     = contains(["PROACTIVE", "OPPORTUNISTIC"], var.update_policy_type)
    error_message = "update_policy_type must be PROACTIVE or OPPORTUNISTIC."
  }
}

# --- Snapshots ------------------------------------------------------------------------

variable "snapshot_start_time" {
  description = "Daily snapshot start time, UTC, HH:00."
  type        = string
  default     = "02:00"
}

variable "snapshot_retention_days" {
  description = "Days to keep data-disk snapshots."
  type        = number
  default     = 14
}

variable "snapshot_storage_locations" {
  description = "Where snapshots are stored. null = the region."
  type        = list(string)
  default     = null
}

variable "snapshot_boot_disk" {
  description = "Also snapshot the boot disk on the same daily schedule and retention as the data disk (whole-VM coverage)."
  type        = bool
  default     = true
}

variable "snapshot_before_vm_replace" {
  description = "Snapshot the data disk (via gcloud on the machine running Terraform) before any apply that recreates the VM, and before terraform destroy. If the snapshot fails, the apply stops before the VM is touched. Snapshots are kept until deleted manually."
  type        = bool
  default     = true
}
