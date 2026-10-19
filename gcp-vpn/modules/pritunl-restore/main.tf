# Pritunl restore server: a standalone VM rebuilt from boot + data disk snapshots, with its
# own static public IP, in the existing Pritunl subnet. Creates only new resources, so the
# running server (its MIG, disks, IPs and firewall rules) is never modified.
#
# The restored boot disk already has Pritunl, MongoDB and the mounts configured; the data
# disk has MongoDB (users, servers, certificates) and /var/lib/pritunl (host ID). The
# reused startup script is idempotent: it mounts the data disk and restarts the services.

locals {
  labels = merge(var.labels, { app = "pritunl", role = "restore" })
}

resource "google_compute_address" "external" {
  project      = var.project_id
  name         = "${var.name}-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"
  labels       = local.labels
}

resource "google_compute_address" "internal" {
  project      = var.project_id
  name         = "${var.name}-internal-ip"
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = var.subnetwork_self_link
  address      = var.internal_ip_address
  labels       = local.labels
}

resource "google_compute_disk" "boot" {
  project  = var.project_id
  name     = "${var.name}-boot"
  zone     = var.zone
  type     = var.boot_disk_type
  size     = var.boot_disk_size_gb
  snapshot = var.boot_snapshot
  labels   = local.labels

  dynamic "disk_encryption_key" {
    for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
    content {
      kms_key_self_link = disk_encryption_key.value
    }
  }

  dynamic "source_snapshot_encryption_key" {
    for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
    content {
      kms_key_self_link = source_snapshot_encryption_key.value
    }
  }
}

resource "google_compute_disk" "data" {
  project  = var.project_id
  name     = "${var.name}-data"
  zone     = var.zone
  type     = var.data_disk_type
  size     = var.data_disk_size_gb
  snapshot = var.data_snapshot
  labels   = local.labels

  dynamic "disk_encryption_key" {
    for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
    content {
      kms_key_self_link = disk_encryption_key.value
    }
  }

  dynamic "source_snapshot_encryption_key" {
    for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
    content {
      kms_key_self_link = source_snapshot_encryption_key.value
    }
  }
}

resource "google_compute_instance" "restore" {
  project                   = var.project_id
  name                      = var.name
  zone                      = var.zone
  machine_type              = var.machine_type
  can_ip_forward            = true # Pritunl routes VPN client traffic into the VPC
  tags                      = [var.network_tag]
  labels                    = local.labels
  allow_stopping_for_update = true

  boot_disk {
    source      = google_compute_disk.boot.self_link
    auto_delete = false # the disk is a Terraform resource of its own
  }

  attached_disk {
    source      = google_compute_disk.data.self_link
    device_name = var.data_device_name # startup script mounts /dev/disk/by-id/google-<this>
    mode        = "READ_WRITE"
  }

  network_interface {
    subnetwork = var.subnetwork_self_link
    network_ip = google_compute_address.internal.address

    access_config {
      nat_ip       = google_compute_address.external.address
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = var.enable_secure_boot
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    startup-script         = var.startup_script
  }
}
