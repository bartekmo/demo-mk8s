provider "google" {}

resource "google_compute_network" "mk8s" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "mk8s" {
  name                     = "${var.prefix}-subnet"
  ip_cidr_range            = var.node_cidr
  region                   = var.region
  network                  = google_compute_network.mk8s.name
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "mlb"
    ip_cidr_range = var.mlb_cidr
  }
}

resource "google_compute_router" "mk8s" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.mk8s.id
}

resource "google_compute_router_nat" "mk8s" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.mk8s.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_firewall" "mk8s" {
  name    = "${var.prefix}-iap-ssh"
  network = google_compute_network.mk8s.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
}

locals {
  zone = "${var.region}-a"

  # one /24 from the mlb secondary range per node, by index
  node_mlb_ranges = [
    for i in range(var.node_count) :
    cidrsubnet(var.mlb_cidr, 24 - tonumber(split("/", var.mlb_cidr)[1]), i)
  ]

  # static address for Traefik's LoadBalancer service (lives in node 0's /24)
  //traefik_ip    = cidrhost(local.node_mlb_ranges[0], 10)
  traefik_ip_q4 = 10

  lb_ports = { http = 80, https = 443 }
}

resource "google_compute_instance" "mk8s" {
  count        = var.node_count
  name         = "${var.prefix}-node-${count.index}"
  machine_type = "e2-standard-4"
  zone         = local.zone
  tags         = ["${var.prefix}-node"]

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-minimal-2604-lts-amd64"
      //image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2604-lts-amd64"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mk8s.name

    alias_ip_range {
      subnetwork_range_name = "mlb"
      ip_cidr_range         = local.node_mlb_ranges[count.index]
    }
  }

  metadata_startup_script = templatefile("${path.module}/node.tftpl", {
    admin_username = var.admin_username,
    mlb_range      = local.node_mlb_ranges[count.index]
    traefik_ip     = cidrhost(local.node_mlb_ranges[count.index], local.traefik_ip_q4)
  })

  # don't recreate the node when the image family moves on
  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}

# --- Global external proxy Network Load Balancer -> Traefik (mlb IP) ---

resource "google_compute_firewall" "lb" {
  name    = "${var.prefix}-lb-to-traefik"
  network = google_compute_network.mk8s.name

  allow {
    protocol = "tcp"
    ports    = [for p in values(local.lb_ports) : tostring(p)]
  }

  # Google Front Ends: proxied traffic and health checks
  source_ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
  destination_ranges = [for i in range(var.node_count) : cidrhost(local.node_mlb_ranges[i], local.traefik_ip_q4)]
  target_tags        = ["${var.prefix}-node"]
}

resource "google_compute_global_address" "lb" {
  name = "${var.prefix}-lb-ip"
}

resource "google_compute_health_check" "traefik" {
  name = "${var.prefix}-traefik-hc"

  tcp_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

resource "google_compute_network_endpoint_group" "traefik" {
  for_each              = local.lb_ports
  name                  = "${var.prefix}-traefik-${each.key}"
  zone                  = local.zone
  network               = google_compute_network.mk8s.id
  subnetwork            = google_compute_subnetwork.mk8s.id
  network_endpoint_type = "GCE_VM_IP_PORT"
  default_port          = each.value
}

resource "google_compute_network_endpoint" "traefik_http" {
  count = var.node_count

  network_endpoint_group = google_compute_network_endpoint_group.traefik["http"].name
  zone                   = local.zone
  instance               = google_compute_instance.mk8s[count.index].name
  ip_address             = cidrhost(local.node_mlb_ranges[count.index], local.traefik_ip_q4)
  port                   = 80
}
resource "google_compute_network_endpoint" "traefik_https" {
  count = var.node_count

  network_endpoint_group = google_compute_network_endpoint_group.traefik["https"].name
  zone                   = local.zone
  instance               = google_compute_instance.mk8s[count.index].name
  ip_address             = cidrhost(local.node_mlb_ranges[count.index], local.traefik_ip_q4)
  port                   = 443
}

resource "google_compute_backend_service" "traefik" {
  for_each              = local.lb_ports
  name                  = "${var.prefix}-traefik-${each.key}"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.traefik.id]

  backend {
    group                        = google_compute_network_endpoint_group.traefik[each.key].id
    balancing_mode               = "CONNECTION"
    max_connections_per_endpoint = 1000
  }
}

resource "google_compute_target_tcp_proxy" "traefik" {
  for_each        = local.lb_ports
  name            = "${var.prefix}-traefik-${each.key}"
  backend_service = google_compute_backend_service.traefik[each.key].id
}

resource "google_compute_global_forwarding_rule" "traefik" {
  for_each              = local.lb_ports
  name                  = "${var.prefix}-traefik-${each.key}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  port_range            = tostring(each.value)
  target                = google_compute_target_tcp_proxy.traefik[each.key].id
}
