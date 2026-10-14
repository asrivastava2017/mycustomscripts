variable "project_id" {
  description = "GCP project ID that owns the VPC."
  type        = string
}

variable "region" {
  description = "Region for the subnet."
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network to create."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.network_name))
    error_message = "network_name must be a valid RFC 1035 name (lowercase letters, digits, hyphens; max 63 chars)."
  }
}

variable "subnet_name" {
  description = "Name of the subnet to create."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.subnet_name))
    error_message = "subnet_name must be a valid RFC 1035 name (lowercase letters, digits, hyphens; max 63 chars)."
  }
}

variable "subnet_cidr" {
  description = "Primary IPv4 range of the subnet."
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid IPv4 CIDR, e.g. 10.200.0.0/24."
  }
}

variable "reserved_cidrs" {
  description = "CIDRs already used elsewhere (existing VPCs, GKE, on-prem). subnet_cidr and additional_cidrs must not overlap any of them; plan fails if they do."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.reserved_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in reserved_cidrs must be a valid IPv4 CIDR."
  }
}

variable "additional_cidrs" {
  description = "Other ranges this deployment will use (e.g. the Pritunl VPN client range). Checked for overlap against reserved_cidrs and subnet_cidr."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.additional_cidrs : can(cidrhost(c, 0))])
    error_message = "Every entry in additional_cidrs must be a valid IPv4 CIDR."
  }
}

variable "routing_mode" {
  description = "VPC dynamic routing mode: REGIONAL or GLOBAL."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

variable "mtu" {
  description = "VPC MTU in bytes."
  type        = number
  default     = 1460
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs on the subnet."
  type        = bool
  default     = true
}

variable "flow_logs_sampling" {
  description = "Flow log sampling rate, 0.0 to 1.0."
  type        = number
  default     = 0.5
}

variable "peerings" {
  description = <<-EOT
    VPC peerings from this VPC to existing VPCs whose private resources VPN users must reach.
    peer_network is the peer VPC self link, e.g. projects/<project>/global/networks/<vpc>.
    Set create_remote_peering = true to also create the peer side (needs permissions on the peer VPC).
  EOT
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
