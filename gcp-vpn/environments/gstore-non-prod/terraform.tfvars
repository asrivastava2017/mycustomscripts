# gstore-non-prod: Pritunl open-source VPN
# To deploy in another project: copy this folder to environments/<new-env>/ and edit the values.

# --- Project & location (REPLACE the project ID; confirm region/zone) ------------------
project_id = "REPLACE-WITH-GCP-PROJECT-ID"
region     = "asia-south1"
zone       = "asia-south1-a"

labels = {
  environment = "non-prod"
  team        = "gstore"
  managed-by  = "terraform"
}

# --- Network --------------------------------------------------------------------------
vpc_name    = "gstore-non-prod-pritunl-vpc"
subnet_name = "gstore-non-prod-pritunl-subnet"

# Neither range overlaps reserved_cidrs (plan fails if one ever does).
subnet_cidr     = "10.200.0.0/24" # Pritunl VM subnet
vpn_client_cidr = "10.201.0.0/24" # use this as the Pritunl server "Virtual Network"

reserved_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
  "10.60.0.0/20",
  "10.127.0.0/16",
  "10.128.0.0/16",
  "10.1.0.0/20",
  "10.2.0.0/20",
  "10.64.0.0/14",
]

# Peer the Pritunl VPC with the VPCs that hold the private resources users need.
# Example:
# peerings = [
#   {
#     name                  = "pritunl-to-gstore-app-vpc"
#     peer_network          = "projects/REPLACE-PROJECT/global/networks/REPLACE-VPC"
#     create_remote_peering = true
#   },
# ]
peerings = []

# --- Pritunl VM -----------------------------------------------------------------------
vm_name           = "gstore-non-prod-pritunl"
machine_type      = "e2-small"
data_disk_size_gb = 20

# --- Encryption -----------------------------------------------------------------------
# true  = create a Cloud KMS key and encrypt the boot disk, data disk and snapshots with it.
# false = Google-managed encryption (no KMS resources created).
# Decide before the first apply: switching later replaces the data disk.
create_kms_key          = true
kms_key_ring_name       = "gstore-non-prod-pritunl-keyring"
kms_key_name            = "gstore-non-prod-pritunl-disk-key"
kms_key_rotation_period = "7776000s" # 90 days
kms_protection_level    = "SOFTWARE"

# --- Access ---------------------------------------------------------------------------
vpn_udp_ports = ["1194"]

# REPLACE with office / admin public IPs. 0.0.0.0/0 is rejected.
admin_source_ranges = [
  "203.0.113.10/32",
]

enable_http_for_letsencrypt = false

# --- Operations -----------------------------------------------------------------------
snapshot_start_time     = "02:00"
snapshot_retention_days = 14
