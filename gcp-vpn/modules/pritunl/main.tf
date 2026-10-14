locals {
  data_device_name = "pritunl-data"
  data_mount_path  = "/mnt/pritunl-data"
  nic_name         = "nic0"

  service_account_id = coalesce(
    var.service_account_id,
    trimsuffix(substr("${var.name}-sa", 0, 30), "-")
  )

  labels = merge(var.labels, { app = "pritunl" })
}

# --- Identity -------------------------------------------------------------------------

resource "google_service_account" "pritunl" {
  project      = var.project_id
  account_id   = local.service_account_id
  display_name = "Pritunl VPN VM (${var.name})"
}

# Least privilege: the VM only ships its own logs and metrics.
resource "google_project_iam_member" "pritunl" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.pritunl.email}"
}

# --- Admin SSH access (IAP + OS Login) ------------------------------------------------
# Project-level, because MIG-managed VMs lose instance-level IAM when they are recreated.
# Note: these roles also apply to any other OS Login VM in the project.

locals {
  admin_project_roles = [
    "roles/iap.tunnelResourceAccessor",
    var.admin_sudo ? "roles/compute.osAdminLogin" : "roles/compute.osLogin",
  ]

  admin_project_bindings = {
    for pair in setproduct(var.admin_members, local.admin_project_roles) :
    "${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
  }
}

resource "google_project_iam_member" "admin" {
  for_each = local.admin_project_bindings

  project = var.project_id
  role    = each.value.role
  member  = each.value.member
}

# Required by OS Login because the VM runs as this service account. Scoped to this
# service account only; it does not hand out its keys.
resource "google_service_account_iam_member" "admin_sa_user" {
  for_each = toset(var.admin_members)

  service_account_id = google_service_account.pritunl.name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value
}

# --- Addresses ------------------------------------------------------------------------

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

# --- Stateful data disk + daily snapshots ---------------------------------------------

resource "google_compute_disk" "data" {
  project = var.project_id
  name    = "${var.name}-data"
  zone    = var.zone
  type    = var.data_disk_type
  size    = var.data_disk_size_gb
  labels  = local.labels

  # Scheduled snapshots of a CMEK disk are encrypted with the same key automatically.
  dynamic "disk_encryption_key" {
    for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
    content {
      kms_key_self_link = disk_encryption_key.value
    }
  }
}

resource "google_compute_resource_policy" "snapshots" {
  project = var.project_id
  name    = "${var.name}-daily-snapshots"
  region  = var.region

  snapshot_schedule_policy {
    schedule {
      daily_schedule {
        days_in_cycle = 1
        start_time    = var.snapshot_start_time
      }
    }

    retention_policy {
      max_retention_days    = var.snapshot_retention_days
      on_source_disk_delete = "KEEP_AUTO_SNAPSHOTS"
    }

    snapshot_properties {
      labels            = local.labels
      storage_locations = coalesce(var.snapshot_storage_locations, [var.region])
    }
  }
}

resource "google_compute_disk_resource_policy_attachment" "data_snapshots" {
  project = var.project_id
  name    = google_compute_resource_policy.snapshots.name
  disk    = google_compute_disk.data.name
  zone    = var.zone
}

# --- Firewall -------------------------------------------------------------------------

resource "google_compute_firewall" "vpn" {
  project       = var.project_id
  name          = "${var.name}-allow-vpn"
  network       = var.network_self_link
  direction     = "INGRESS"
  source_ranges = var.vpn_source_ranges
  target_tags   = [var.network_tag]

  allow {
    protocol = "udp"
    ports    = var.vpn_udp_ports
  }
}

resource "google_compute_firewall" "admin" {
  project       = var.project_id
  name          = "${var.name}-allow-admin-https"
  network       = var.network_self_link
  direction     = "INGRESS"
  source_ranges = var.admin_source_ranges
  target_tags   = [var.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

resource "google_compute_firewall" "health_check" {
  project       = var.project_id
  name          = "${var.name}-allow-health-check"
  network       = var.network_self_link
  direction     = "INGRESS"
  source_ranges = var.health_check_source_ranges
  target_tags   = [var.network_tag]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.health_check_port)]
  }
}

resource "google_compute_firewall" "iap_ssh" {
  project       = var.project_id
  name          = "${var.name}-allow-iap-ssh"
  network       = var.network_self_link
  direction     = "INGRESS"
  source_ranges = var.iap_ssh_source_ranges
  target_tags   = [var.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "letsencrypt" {
  # Stays open while a domain is set: Pritunl renews the certificate automatically.
  count = var.letsencrypt_domain == null ? 0 : 1

  project       = var.project_id
  name          = "${var.name}-allow-http-letsencrypt"
  network       = var.network_self_link
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.network_tag]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

# --- Instance template ----------------------------------------------------------------

resource "google_compute_instance_template" "pritunl" {
  project        = var.project_id
  name_prefix    = "${var.name}-"
  machine_type   = var.machine_type
  region         = var.region
  can_ip_forward = true # Pritunl routes VPN client traffic into the VPC
  tags           = [var.network_tag]
  labels         = local.labels

  disk {
    boot         = true
    auto_delete  = true
    source_image = var.source_image
    disk_size_gb = var.boot_disk_size_gb
    disk_type    = var.boot_disk_type

    dynamic "disk_encryption_key" {
      for_each = var.kms_key_self_link == null ? [] : [var.kms_key_self_link]
      content {
        kms_key_self_link = disk_encryption_key.value
      }
    }
  }

  # The external IP here is a placeholder; the per-instance config pins the reserved one.
  network_interface {
    subnetwork = var.subnetwork_self_link

    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.pritunl.email
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
    startup-script = templatefile("${path.module}/templates/startup.sh.tftpl", {
      data_device_name   = local.data_device_name
      data_mount_path    = local.data_mount_path
      mongodb_version    = var.mongodb_version
      install_ops_agent  = var.install_ops_agent
      letsencrypt_domain = var.letsencrypt_domain == null ? "" : var.letsencrypt_domain
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- Health check + stateful MIG of size 1 --------------------------------------------

resource "google_compute_health_check" "pritunl" {
  project             = var.project_id
  name                = "${var.name}-hc"
  check_interval_sec  = var.health_check_interval_sec
  timeout_sec         = var.health_check_timeout_sec
  healthy_threshold   = 2
  unhealthy_threshold = var.health_check_unhealthy_threshold

  tcp_health_check {
    port = var.health_check_port
  }

  log_config {
    enable = true
  }
}

resource "google_compute_instance_group_manager" "pritunl" {
  project            = var.project_id
  name               = "${var.name}-mig"
  zone               = var.zone
  base_instance_name = var.name

  # Starts empty: the per-instance config below creates the single VM with its exact name,
  # static IPs and data disk, and raises the size to 1.
  target_size        = 0
  wait_for_instances = false

  version {
    instance_template = google_compute_instance_template.pritunl.self_link_unique
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.pritunl.id
    initial_delay_sec = var.autohealing_initial_delay_sec
  }

  # Stateful VMs keep their name, IPs and disks only when recreated in place.
  update_policy {
    type                           = var.update_policy_type
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    replacement_method             = "RECREATE"
    max_surge_fixed                = 0
    max_unavailable_fixed          = 1
  }

  instance_lifecycle_policy {
    force_update_on_repair = "YES"
  }

  lifecycle {
    # Size is owned by the per-instance config; never let Terraform scale it back to 0.
    ignore_changes = [target_size]
  }

  depends_on = [google_compute_firewall.health_check]
}

resource "google_compute_per_instance_config" "pritunl" {
  project                = var.project_id
  zone                   = var.zone
  instance_group_manager = google_compute_instance_group_manager.pritunl.name
  name                   = var.name

  minimal_action                   = "REPLACE"
  most_disruptive_allowed_action   = "REPLACE"
  remove_instance_on_destroy       = true
  remove_instance_state_on_destroy = true

  preserved_state {
    disk {
      device_name = local.data_device_name
      source      = google_compute_disk.data.id
      mode        = "READ_WRITE"
      delete_rule = "NEVER"
    }

    external_ip {
      interface_name = local.nic_name
      auto_delete    = "NEVER"
      ip_address {
        address = google_compute_address.external.self_link
      }
    }

    internal_ip {
      interface_name = local.nic_name
      auto_delete    = "NEVER"
      ip_address {
        address = google_compute_address.internal.self_link
      }
    }
  }

  depends_on = [
    google_project_iam_member.pritunl,
    google_compute_disk_resource_policy_attachment.data_snapshots,
  ]
}
