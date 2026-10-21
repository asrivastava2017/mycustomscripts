variable "project_id" {
  description = "GCP project whose logs are archived (and that owns the bucket)."
  type        = string
}

variable "name" {
  description = "Prefix for the sink name."
  type        = string
}

variable "bucket_name" {
  description = "Archive bucket name (globally unique)."
  type        = string
}

variable "location" {
  description = "Bucket location (region or multi-region)."
  type        = string
}

variable "log_filter" {
  description = "Cloud Logging filter selecting the entries to archive."
  type        = string
}

variable "retention_days" {
  description = "Delete archived log files after this many days."
  type        = number
  default     = 365

  validation {
    condition     = var.retention_days >= 1
    error_message = "retention_days must be at least 1."
  }
}

variable "coldline_after_days" {
  description = "Move archived log files to Coldline storage after this many days (cheaper; 90-day minimum storage charge). 0 = never."
  type        = number
  default     = 30
}

variable "labels" {
  description = "Labels for the bucket."
  type        = map(string)
  default     = {}
}
