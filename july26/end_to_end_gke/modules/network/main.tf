# ---------------------------------------------------------------------------
# Address plan (memorise this - it is the exam question)
#
#   Subnet primary range   10.10.0.0/20    -> NODE IPs
#   Secondary "pods"       10.20.0.0/16    -> POD IPs   (alias range)
#   Secondary "services"   10.30.0.0/20    -> Service IPs
#   Master range           172.16.0.0/28   -> private control plane
#
# GKE VPC-native ("alias IP") is a THIRD model, different from both siblings:
#
#   AKS  CNI Overlay : pods live off-VNet entirely. Nodes cost VNet IPs; pods
#                      cost nothing from the VNet.
#   EKS  VPC CNI     : pods take real IPs from the NODE's subnet - one flat
#                      pool shared with everything else in that subnet.
#   GKE  VPC-native  : pods take real routable VPC IPs, but from a SEPARATE
#                      secondary range. Real addresses, own budget.
#
# The consequence students must internalise: the pod range is sized by
#   nodes x max_pods_per_node, and GKE rounds each node's allocation UP to a
#   power of two. max_pods_per_node = 50 means each node reserves a /25 (128
#   addresses), not 50. A /16 pod range therefore holds 512 nodes, not 1310.
#
# Get this wrong and nodes join the cluster but pods never get addresses.
# ---------------------------------------------------------------------------

resource "google_compute_network" "this" {
  name                    = "vpc-${var.suffix}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC for the GKE Store lab"
}

resource "google_compute_subnetwork" "this" {
  name          = "snet-${var.suffix}"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = var.subnet_cidr

  # Pods and Services get their own secondary ranges. The NAMES here are
  # referenced by the cluster's ip_allocation_policy - they are the contract
  # between this module and modules/gke.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }

  # Lets you see which flows were allowed/denied. Off by default because it
  # bills per GB of logs, which surprises people.
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }

  # Required for private nodes to reach Google APIs without a public IP.
  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# Cloud NAT - private nodes have no external IP, so without this they cannot
# pull images from Docker Hub, reach the internet, or run apt.
#
# The single most common "my private GKE cluster is broken" cause is a
# missing Cloud NAT. Nodes come up, they just cannot download anything.
# ---------------------------------------------------------------------------
resource "google_compute_router" "this" {
  count = var.private_nodes ? 1 : 0

  name    = "router-${var.suffix}"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count = var.private_nodes ? 1 : 0

  name                               = "nat-${var.suffix}"
  router                             = google_compute_router.this[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# Firewall
#
# GCP's default-allow-internal does not exist in a custom VPC, so the rules
# you need must be explicit. GKE creates its own rules for control-plane to
# node traffic; these cover the rest.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "allow_internal" {
  name        = "fw-${var.suffix}-allow-internal"
  network     = google_compute_network.this.name
  description = "Node-to-node and pod-to-pod traffic within the VPC ranges"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
}

# Google's health checkers live in these two well-known ranges. If you block
# them your Services never become healthy and the load balancer serves 502s
# while every pod looks perfectly fine. This is the GCP equivalent of the
# "AzureLoadBalancer probe" NSG rule in the AKS lab.
resource "google_compute_firewall" "allow_health_checks" {
  name        = "fw-${var.suffix}-allow-health-checks"
  network     = google_compute_network.this.name
  description = "Google Cloud load balancer health checkers"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]

  allow { protocol = "tcp" }
}

resource "google_compute_firewall" "allow_web" {
  name        = "fw-${var.suffix}-allow-web"
  network     = google_compute_network.this.name
  description = "HTTP/HTTPS from the internet to load balancers"
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}
