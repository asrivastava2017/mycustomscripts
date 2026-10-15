# gstore-non-prod: Pritunl open-source VPN
# To deploy in another project: copy this folder to environments/<new-env>/ and edit the values.

# --- Project & location (REPLACE the project ID; confirm region/zone) ------------------
project_id = "gstore-development"
region     = "us-central1"
zone       = "us-central1-a"

labels = {
  environment = "non-prod"
  team        = "gstore"
  managed-by  = "terraform"
}

# --- Terraform state bucket (used by `make bootstrap` only) ---------------------------
# Defaults: name "<project_id>-pritunl-tfstate", location = region. Uncomment to override.
# state_bucket_name     = "my-company-gstore-non-prod-tfstate"
# state_bucket_location = "US"

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
vm_name      = "gstore-non-prod-pritunl"
machine_type = "e2-standard-2"
# Rocky Linux 9: Pritunl's tested OS family. Ubuntu 24.04 currently cannot run MongoDB 8.0 (kernel 6.19+).
source_image      = "projects/rocky-linux-cloud/global/images/family/rocky-linux-9"
data_disk_size_gb = 80

# --- Encryption -----------------------------------------------------------------------
# true  = create a Cloud KMS key and encrypt the boot disk, data disk and snapshots with it.
# false = Google-managed encryption (no KMS resources created).
# Decide before the first apply: switching later replaces the data disk.
create_kms_key          = false
kms_key_ring_name       = "gstore-non-prod-pritunl-keyring"
kms_key_name            = "gstore-non-prod-pritunl-disk-key"
kms_key_rotation_period = "7776000s" # 90 days
kms_protection_level    = "SOFTWARE"

# --- Access ---------------------------------------------------------------------------
# Must match the Pritunl server port. Not 1194: SELinux reserves it for the system OpenVPN service.
vpn_udp_ports = ["15194"]

# REPLACE with office / admin public IPs. 0.0.0.0/0 is rejected.
admin_source_ranges = [
  "203.0.113.10/32",
  "104.28.0.0/16",
  "14.99.194.90/32",
  "34.27.195.8/32"
]

# Let's Encrypt certificate for the Pritunl web console / profile pages.
# Set to the Namecheap hostname (e.g. "vpn.example.com") to get a trusted certificate:
# opens TCP 80 (needed for issuance and renewal) and the VM requests the certificate
# within an hour of the A record pointing at the static IP. null = self-signed.
letsencrypt_domain = "gstoredevvpn.kalama.cloud"

# Who can SSH to the VM (IAP + OS Login, with their own Google identity and SSH key).
# Terraform grants: IAP tunnel access, OS Login (sudo if admin_sudo = true), and
# serviceAccountUser on the VM's service account only. Prefer a group.
# REPLACE with your admin group or users.
admin_members = [
  # "group:gstore-vpn-admins@company.com",
  "user:animesh.s@greyorange.com",
]
admin_sudo = true

# --- Operations -----------------------------------------------------------------------
# Grace period before autohealing judges a new VM. First boot measured ~12.5 min on
# e2-small (package install ~10 min), so 20 min leaves margin for slow mirrors.
autohealing_initial_delay_sec = 1200

snapshot_start_time     = "02:00"
snapshot_retention_days = 14

# Take a data-disk snapshot automatically before any apply that recreates the VM
# (machine type, image, startup script...) and before terraform destroy. Needs gcloud
# on the machine running Terraform. These snapshots are kept until deleted manually.
snapshot_before_vm_replace = true
