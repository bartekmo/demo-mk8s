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

  # node-0 is the control plane; other nodes join it as workers
  primary_ip     = cidrhost(var.node_cidr, 100)
  join_token_ttl = 315360000 # 10 years: same token works for later scale-out

  # Fixed MetalLB addresses in node-0's /24, each fronted by the external LB
  traefik_ip    = cidrhost(local.node_mlb_ranges[0], local.traefik_ip_q4)
  gitlab_ssh_ip = cidrhost(local.node_mlb_ranges[0], 11)

  # LB frontend name -> backend address:port ("backend" is used in names)
  lb_services = {
    http  = { port = 80, ip = local.traefik_ip, backend = "traefik" }
    https = { port = 443, ip = local.traefik_ip, backend = "traefik" }
    ssh   = { port = 22, ip = local.gitlab_ssh_ip, backend = "gitlab" } # git over SSH
  }
}

# Pre-shared microk8s join token: node-0 registers it (add-node --token),
# workers use it (join --worker). 32 alphanumeric chars as microk8s requires.
resource "random_password" "join_token" {
  length  = 32
  special = false
}

# All node-to-node traffic (join 25000, API 16443, kubelet 10250,
# dqlite 19001, Calico VXLAN udp/4789, ...)
resource "google_compute_firewall" "node_internal" {
  name    = "${var.prefix}-node-internal"
  network = google_compute_network.mk8s.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_tags = ["${var.prefix}-node"]
  target_tags = ["${var.prefix}-node"]
}

# --- Node identity: only what the PD CSI driver needs ---
# Project-wide grant, so run this in a dedicated project.

data "google_client_config" "current" {}

resource "google_service_account" "node" {
  account_id   = "${var.prefix}-node"
  display_name = "mk8s node (PD CSI driver)"
}

resource "google_project_iam_custom_role" "csi_disk" {
  role_id     = "${replace(var.prefix, "-", "_")}_csi_disk"
  title       = "${var.prefix} PD CSI driver"
  description = "Minimal permissions for the GCE PD CSI driver on ${var.prefix} nodes"
  permissions = [
    "compute.disks.create",
    "compute.disks.createSnapshot",
    "compute.disks.delete",
    "compute.disks.get",
    "compute.disks.list",
    "compute.disks.resize",
    "compute.disks.setLabels",
    "compute.disks.update",
    "compute.disks.use",
    "compute.disks.useReadOnly",
    "compute.instances.attachDisk",
    "compute.instances.detachDisk",
    "compute.instances.get",
    "compute.instances.list",
    "compute.snapshots.create",
    "compute.snapshots.delete",
    "compute.snapshots.get",
    "compute.snapshots.list",
    "compute.snapshots.setLabels",
    "compute.snapshots.useReadOnly",
    "compute.zoneOperations.get",
    "compute.zoneOperations.list",
    "compute.zones.get",
    "compute.zones.list",
    "compute.regionOperations.get",
    "compute.regions.get",
    "compute.regions.list",
  ]
}

resource "google_project_iam_member" "node_csi_disk" {
  project = data.google_client_config.current.project
  role    = google_project_iam_custom_role.csi_disk.name
  member  = "serviceAccount:${google_service_account.node.email}"
}

# attaching a disk to an instance that runs as this SA requires actAs on it
resource "google_service_account_iam_member" "node_act_as_self" {
  service_account_id = google_service_account.node.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.node.email}"
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
      # container images + microk8s data live here; the image default (10 GB)
      # fills up and triggers kubelet DiskPressure evictions
      size = var.boot_disk_gb
      type = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.mk8s.name
    network_ip = cidrhost(var.node_cidr, count.index + 100)

    alias_ip_range {
      subnetwork_range_name = "mlb"
      ip_cidr_range         = local.node_mlb_ranges[count.index]
    }
  }

  metadata = {
    # IAM-based SSH (roles/compute.osAdminLogin); gcloud compute ssh then
    # stops writing ssh-keys into metadata, which caused in-place drift
    enable-oslogin = "false"

    # Bootstrap script, re-run on every boot (idempotent). Kept in metadata
    # rather than metadata_startup_script: changes update in place and take
    # effect at the next boot, instead of forcing a new VM (= new cluster).
    startup-script = templatefile("${path.module}/node.tftpl", {
      admin_username = var.admin_username,
      is_primary     = count.index == 0
      primary_ip     = local.primary_ip
      join_token     = random_password.join_token.result
      join_token_ttl = local.join_token_ttl
      mlb_range      = local.node_mlb_ranges[count.index]
      traefik_ip     = cidrhost(local.node_mlb_ranges[count.index], local.traefik_ip_q4)
      argocd_version = var.argocd_version
      cluster_issuer = templatefile("${path.module}/../k8s-bootstrap/cluster-issuer.yaml.tftpl", {
        acme_email = var.acme_email
      })
      argocd_ingress = templatefile("${path.module}/../k8s-bootstrap/argocd-ingress.yaml.tftpl", {
        dns_root = var.dns_root
      })
      argocd_cm_patch = templatefile("${path.module}/../k8s-bootstrap/argocd-cm-patch.yaml.tftpl", {
        dns_root = var.dns_root
      })
      argocd_rbac_cm_patch = file("${path.module}/../k8s-bootstrap/argocd-rbac-cm-patch.yaml")
      argocd_appset = templatefile("${path.module}/../k8s-bootstrap/argocd-appset.yaml.tftpl", {
        repo_url      = var.gitops_repo_url
        repo_path     = var.gitops_repo_path
        repo_revision = var.gitops_repo_revision
        dns_root      = var.dns_root
        gitlab_ssh_ip = local.gitlab_ssh_ip
      })
      metadata_concealment = file("${path.module}/../k8s-bootstrap/metadata-concealment.yaml")
    })
  }

  # Used by the PD CSI driver (controller/node run with hostNetwork). Pods are
  # blocked from the metadata server, so they can't borrow this identity.
  service_account {
    email  = google_service_account.node.email
    scopes = ["cloud-platform"] # effective access is limited by IAM below
  }
  allow_stopping_for_update = true

  lifecycle {
    ignore_changes = [
      # don't recreate the node when the image family moves on
      boot_disk[0].initialize_params[0].image,
      # PVC disks are attached by the PD CSI driver; without this, any in-place
      # update of the instance makes Terraform detach them from running pods
      attached_disk,
    ]
  }
}

# --- Global external proxy Network Load Balancer -> MetalLB IPs on node-0 ---
# http/https -> Traefik, ssh -> GitLab's SSH Service (see local.lb_services)

resource "google_compute_firewall" "lb" {
  name    = "${var.prefix}-lb-to-traefik"
  network = google_compute_network.mk8s.name

  allow {
    protocol = "tcp"
    ports    = distinct([for s in values(local.lb_services) : tostring(s.port)])
  }

  # Google Front Ends: proxied traffic and health checks
  source_ranges      = ["35.191.0.0/16", "130.211.0.0/22"]
  destination_ranges = distinct([for s in values(local.lb_services) : s.ip])
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
  for_each              = local.lb_services
  name                  = "${var.prefix}-${each.value.backend}-${each.key}"
  zone                  = local.zone
  network               = google_compute_network.mk8s.id
  subnetwork            = google_compute_subnetwork.mk8s.id
  network_endpoint_type = "GCE_VM_IP_PORT"
  default_port          = each.value.port
}

# All LB backend addresses live in node-0's /24 only
resource "google_compute_network_endpoint" "lb" {
  for_each = local.lb_services

  network_endpoint_group = google_compute_network_endpoint_group.traefik[each.key].name
  zone                   = local.zone
  instance               = google_compute_instance.mk8s[0].name
  ip_address             = each.value.ip
  port                   = each.value.port
}

moved {
  from = google_compute_network_endpoint.traefik_http[0]
  to   = google_compute_network_endpoint.lb["http"]
}

moved {
  from = google_compute_network_endpoint.traefik_https[0]
  to   = google_compute_network_endpoint.lb["https"]
}

resource "google_compute_backend_service" "traefik" {
  for_each              = local.lb_services
  name                  = "${var.prefix}-${each.value.backend}-${each.key}"
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
  for_each        = local.lb_services
  name            = "${var.prefix}-${each.value.backend}-${each.key}"
  backend_service = google_compute_backend_service.traefik[each.key].id
}

resource "google_compute_global_forwarding_rule" "traefik" {
  for_each              = local.lb_services
  name                  = "${var.prefix}-${each.value.backend}-${each.key}"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  port_range            = tostring(each.value.port)
  target                = google_compute_target_tcp_proxy.traefik[each.key].id
}
