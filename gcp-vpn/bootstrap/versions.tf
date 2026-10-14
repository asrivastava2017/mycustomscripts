terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0, < 8.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4, < 3.0"
    }
  }

  # Local state, one file per environment:
  #   terraform init -backend-config=path=../environments/<env>/bootstrap.tfstate
  backend "local" {}
}

provider "google" {
  project        = var.project_id
  region         = var.region
  default_labels = var.labels
}
