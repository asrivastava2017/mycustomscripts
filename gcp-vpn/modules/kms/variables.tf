variable "project_id" {
  description = "GCP project that owns the key ring."
  type        = string
}

variable "location" {
  description = "Key ring location. Must be the region of the disks it encrypts (e.g. us-central1)."
  type        = string
}

variable "key_ring_name" {
  description = "Key ring name. Key rings can never be deleted in GCP, so pick a stable name."
  type        = string
}

variable "key_name" {
  description = "Crypto key name."
  type        = string
}

variable "rotation_period" {
  description = "Automatic rotation period, in seconds with an 's' suffix. Default 90 days."
  type        = string
  default     = "7776000s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.rotation_period))
    error_message = "rotation_period must be seconds with an 's' suffix, e.g. 7776000s."
  }
}

variable "protection_level" {
  description = "SOFTWARE or HSM. HSM costs more per key version and per operation."
  type        = string
  default     = "SOFTWARE"

  validation {
    condition     = contains(["SOFTWARE", "HSM"], var.protection_level)
    error_message = "protection_level must be SOFTWARE or HSM."
  }
}

variable "destroy_scheduled_duration" {
  description = "How long a destroyed key version stays recoverable, e.g. 2592000s (30 days)."
  type        = string
  default     = "2592000s"
}

variable "encrypter_decrypter_members" {
  description = "IAM members that may encrypt/decrypt with the key, e.g. the Compute Engine service agent."
  type        = list(string)
}

variable "labels" {
  description = "Labels for the crypto key."
  type        = map(string)
  default     = {}
}
