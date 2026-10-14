terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
  }

  # Remote state in GCS. Bucket and prefix come from environments/<env>/backend.hcl:
  #   terraform init -backend-config=environments/<env>/backend.hcl
  backend "gcs" {}
}

provider "google" {
  project        = var.project_id
  region         = var.region
  zone           = var.zone
  default_labels = var.labels
}
