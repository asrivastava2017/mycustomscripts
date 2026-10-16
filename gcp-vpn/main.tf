resource "google_project_service" "required" {
  for_each = toset(concat(
    [
      "compute.googleapis.com",
      "iam.googleapis.com",
      "iap.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com",
      "oslogin.googleapis.com",
    ],
    var.create_kms_key ? ["cloudkms.googleapis.com"] : [],
  ))

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {
  project_id = var.project_id
}

# Customer-managed key for the VM disks and their snapshots.
# create_kms_key = false -> no key; disks use Google-managed encryption.
module "kms" {
  source = "./modules/kms"
  count  = var.create_kms_key ? 1 : 0

  project_id       = var.project_id
  location         = var.region
  key_ring_name    = var.kms_key_ring_name
  key_name         = var.kms_key_name
  rotation_period  = var.kms_key_rotation_period
  protection_level = var.kms_protection_level
  labels           = var.labels

  # Compute Engine encrypts/decrypts the disks on the VM's behalf through its service agent.
  encrypter_decrypter_members = [
    "serviceAccount:service-${data.google_project.this.number}@compute-system.iam.gserviceaccount.com",
  ]

  depends_on = [google_project_service.required]
}

module "network" {
  source = "./modules/network"

  project_id       = var.project_id
  region           = var.region
  network_name     = var.vpc_name
  subnet_name      = var.subnet_name
  subnet_cidr      = var.subnet_cidr
  reserved_cidrs   = var.reserved_cidrs
  additional_cidrs = [var.vpn_client_cidr]
  enable_flow_logs = var.enable_flow_logs
  peerings         = var.peerings

  depends_on = [google_project_service.required]
}

module "pritunl" {
  source = "./modules/pritunl"

  project_id           = var.project_id
  region               = var.region
  zone                 = var.zone
  name                 = var.vm_name
  network_self_link    = module.network.network_self_link
  subnetwork_self_link = module.network.subnet_self_link

  machine_type        = var.machine_type
  source_image        = var.source_image
  boot_disk_size_gb   = var.boot_disk_size_gb
  data_disk_size_gb   = var.data_disk_size_gb
  internal_ip_address = var.internal_ip_address
  kms_key_self_link   = var.create_kms_key ? module.kms[0].crypto_key_id : null
  labels              = var.labels

  mongodb_version   = var.mongodb_version
  install_ops_agent = var.install_ops_agent

  vpn_udp_ports       = var.vpn_udp_ports
  admin_source_ranges = var.admin_source_ranges
  admin_members       = var.admin_members
  admin_sudo          = var.admin_sudo
  letsencrypt_domain  = var.letsencrypt_domain

  autohealing_initial_delay_sec = var.autohealing_initial_delay_sec
  update_policy_type            = var.update_policy_type

  snapshot_start_time     = var.snapshot_start_time
  snapshot_retention_days = var.snapshot_retention_days

  snapshot_before_vm_replace = var.snapshot_before_vm_replace
  snapshot_boot_disk         = var.snapshot_boot_disk

  depends_on = [google_project_service.required]
}
