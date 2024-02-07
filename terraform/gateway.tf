resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "gateway-${random_id.id.hex}"
  display_name = "Squid Proxy gateway service account"
}


resource "google_compute_instance_template" "gateway" {
  project     = var.project_id
  region      = "europe-west1"
  name_prefix = "gateway-${random_id.id.hex}-"

  # NOTE: IpForwarding is required to intercept traffic
  can_ip_forward = true

  # NOTE: Include tags to ensure internet route override
  tags = [
    "gateway-${random_id.id.hex}",
    "allow-iap-access",
  ]

  machine_type            = "e2-medium"
  metadata_startup_script = templatefile("${path.module}/resources/squid_proxy_startup_script.sh.tftpl", {
    load_balancer_ip = google_compute_address.gateway.address
  })

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    boot         = true
    disk_size_gb = 20
    disk_type    = "pd-ssd"

    auto_delete = true
  }

  network_interface {
    subnetwork_project = var.project_id
    subnetwork         = google_compute_subnetwork.example_gateway.self_link
  }

  service_account {
    email  = google_service_account.gateway.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_region_instance_group_manager" "gateway" {
  project = var.project_id
  region  = "europe-west1"
  name    = "gateway-${random_id.id.hex}-mig"

  base_instance_name = "gateway-${random_id.id.hex}"

  version {
    instance_template = google_compute_instance_template.gateway.id
  }

  named_port {
    name = "http"
    port = 80
  }

  named_port {
    name = "https"
    port = 443
  }

  named_port {
    name = "health"
    port = 3128
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.gateway.id
    initial_delay_sec = 60
  }

  update_policy {
    type           = "PROACTIVE"
    minimal_action = "REPLACE"
  }
}

resource "google_compute_region_autoscaler" "gateway" {
  project = var.project_id
  region  = "europe-west1"
  name    = "gateway-${random_id.id.hex}-autoscaler"

  target = google_compute_region_instance_group_manager.gateway.id

  autoscaling_policy {
    min_replicas    = 1
    max_replicas    = 3
    cooldown_period = 60

    metric {
      name   = "compute.googleapis.com/instance/network/sent_bytes_count"
      type   = "DELTA_PER_MINUTE"
      target = 500 * 1000 * 1000 # Egress above 500 MB for last minute
    }
  }
}


resource "google_compute_region_backend_service" "gateway" {
  project = var.project_id
  region  = "europe-west1"
  name    = "gateway-${random_id.id.hex}-service"

  load_balancing_scheme           = "INTERNAL"
  connection_draining_timeout_sec = 10

  health_checks = [google_compute_health_check.gateway.id]

  backend {
    group = google_compute_region_instance_group_manager.gateway.instance_group
  }
}

resource "google_compute_address" "gateway" {
  project      = var.project_id
  region       = "europe-west1"
  name         = "squid-proxy"
  subnetwork   = google_compute_subnetwork.example_gateway.id
  address_type = "INTERNAL"
}

resource "google_compute_forwarding_rule" "gateway" {
  project = var.project_id
  region  = "europe-west1"
  name    = "gateway-${random_id.id.hex}"

  ip_address            = google_compute_address.gateway.address
  ip_protocol           = "TCP"
  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true

  network    = google_compute_network.example.id
  subnetwork = google_compute_subnetwork.example_gateway.id

  backend_service = google_compute_region_backend_service.gateway.id
}


resource "google_compute_health_check" "gateway" {
  project             = var.project_id
  name                = "gateway-${random_id.id.hex}-health-check"
  check_interval_sec  = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port         = 3128
    proxy_header = "PROXY_V1"
  }
}


resource "google_compute_firewall" "gateway_health_check" {
  project = var.project_id
  name    = "${google_compute_network.example.name}-gateway-health-check"
  network = google_compute_network.example.id

  direction               = "INGRESS"
  source_ranges           = ["130.211.0.0/22", "35.191.0.0/16"]
  target_service_accounts = [google_service_account.gateway.email]

  allow {
    protocol = "tcp"
    ports    = ["3128"]
  }
}

resource "google_compute_firewall" "gateway_internal_access" {
  project = var.project_id
  name    = "${google_compute_network.example.name}-gateway-internal"
  network = google_compute_network.example.id

  direction = "INGRESS"
  source_ranges = [
    google_compute_subnetwork.example_clients.ip_cidr_range,
  ]

  target_service_accounts = [google_service_account.gateway.email]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_route" "example_gateway_internet" {
  project    = var.project_id
  name       = "${google_compute_network.example.name}-gateway-internet"
  dest_range = "0.0.0.0/0"

  network      = google_compute_network.example.id
  next_hop_ilb = google_compute_forwarding_rule.gateway.id
  priority     = 900
}

resource "google_compute_route" "example_default_internet" {
  project    = var.project_id
  name       = "${google_compute_network.example.name}-default-internet"
  dest_range = "0.0.0.0/0"

  network          = google_compute_network.example.id
  next_hop_gateway = "default-internet-gateway"
  priority         = 800

  tags = ["gateway-${random_id.id.hex}"]
}