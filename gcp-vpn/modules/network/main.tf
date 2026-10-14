locals {
  # Ranges this deployment introduces; each must avoid reserved_cidrs and each other.
  new_cidrs = distinct(concat([var.subnet_cidr], var.additional_cidrs))

  # IPv4 CIDR -> first address as an integer, and block size, for overlap maths.
  cidr_bounds = {
    for c in distinct(concat(local.new_cidrs, var.reserved_cidrs)) : c => {
      start = sum([for i, octet in split(".", cidrhost(c, 0)) : tonumber(octet) * pow(256, 3 - i)])
      size  = pow(2, 32 - tonumber(split("/", c)[1]))
    }
  }

  overlaps_with_reserved = [
    for pair in setproduct(local.new_cidrs, var.reserved_cidrs) : "${pair[0]} overlaps reserved ${pair[1]}"
    if local.cidr_bounds[pair[0]].start < local.cidr_bounds[pair[1]].start + local.cidr_bounds[pair[1]].size &&
    local.cidr_bounds[pair[1]].start < local.cidr_bounds[pair[0]].start + local.cidr_bounds[pair[0]].size
  ]

  overlaps_with_each_other = flatten([
    for i, a in local.new_cidrs : [
      for j, b in local.new_cidrs : "${a} overlaps ${b}"
      if j > i &&
      local.cidr_bounds[a].start < local.cidr_bounds[b].start + local.cidr_bounds[b].size &&
      local.cidr_bounds[b].start < local.cidr_bounds[a].start + local.cidr_bounds[a].size
    ]
  ])

  peerings = { for p in var.peerings : p.name => p }
}

resource "google_compute_network" "this" {
  project                         = var.project_id
  name                            = var.network_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  mtu                             = var.mtu
  delete_default_routes_on_create = false

  lifecycle {
    precondition {
      condition     = length(local.overlaps_with_reserved) == 0 && length(local.overlaps_with_each_other) == 0
      error_message = "CIDR overlap detected: ${join("; ", concat(local.overlaps_with_reserved, local.overlaps_with_each_other))}"
    }
  }
}

resource "google_compute_subnetwork" "this" {
  project                  = var.project_id
  name                     = var.subnet_name
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_MIN"
      flow_sampling        = var.flow_logs_sampling
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_network_peering" "local" {
  for_each = local.peerings

  name                 = each.value.name
  network              = google_compute_network.this.self_link
  peer_network         = each.value.peer_network
  import_custom_routes = each.value.import_custom_routes
  export_custom_routes = each.value.export_custom_routes

  depends_on = [google_compute_subnetwork.this]
}

resource "google_compute_network_peering" "remote" {
  for_each = { for k, p in local.peerings : k => p if p.create_remote_peering }

  name                 = coalesce(each.value.remote_peering_name, "${each.value.name}-remote")
  network              = each.value.peer_network
  peer_network         = google_compute_network.this.self_link
  import_custom_routes = each.value.export_custom_routes
  export_custom_routes = each.value.import_custom_routes

  depends_on = [google_compute_network_peering.local]
}
