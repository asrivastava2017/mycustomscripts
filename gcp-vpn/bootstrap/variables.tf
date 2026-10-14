# Reads environments/<env>/terraform.tfvars (the same file as the main stack).
# Variables the bootstrap does not use are ignored with a warning.

variable "environment" {
  description = "Environment folder name under environments/ (passed by the Makefile)."
  type        = string
}

variable "project_id" {
  description = "GCP project that will own the state bucket."
  type        = string
}

variable "region" {
  description = "Default bucket location."
  type        = string
}

variable "labels" {
  description = "Labels for the bucket."
  type        = map(string)
  default     = {}
}

variable "state_bucket_name" {
  description = "State bucket name (globally unique). null = \"<project_id>-pritunl-tfstate\"."
  type        = string
  default     = null
}

variable "state_bucket_location" {
  description = "Bucket location: a region (e.g. us-central1) or multi-region (e.g. US). null = region."
  type        = string
  default     = null
}

variable "state_versions_to_keep" {
  description = "Older state versions kept for recovery; older ones are deleted."
  type        = number
  default     = 20
}
