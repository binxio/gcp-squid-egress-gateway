# Postfix for naming
resource "random_id" "id" {
  byte_length = 1
}

# Networking
resource "google_compute_network" "example" {
  project = var.project_id
  name    = "example-${random_id.id.hex}"

  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "example_clients" {
  project       = var.project_id
  network       = google_compute_network.example.id
  name          = "${google_compute_network.example.name}-clients"
  region        = "europe-west1"
  ip_cidr_range = "10.0.0.0/24"

  private_ip_google_access = true
}

resource "google_compute_subnetwork" "example_gateway" {
  project       = var.project_id
  network       = google_compute_network.example.id
  name          = "${google_compute_network.example.name}-gateway"
  region        = "europe-west1"
  ip_cidr_range = "10.0.1.0/24"

  private_ip_google_access = true
}

# Allow IAP access to example VPC
resource "google_compute_firewall" "example_allow_iap_access" {
  project     = var.project_id
  network     = google_compute_network.example.id
  name        = "${google_compute_network.example.name}-iap-access"
  description = "Allow incoming access from Identity Aware Proxy subnet block 35.235.240.0/20 for SSH, RDP and WinRM"

  priority    = 4000
  direction   = "INGRESS"
  target_tags = ["allow-iap-access"]

  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22", "3389", "5986"]
  }
}

# Enable internet access for example VPC gateway subnet
resource "google_compute_router" "example_nat" {
  project = var.project_id
  region  = "europe-west1"
  name    = "${google_compute_network.example.name}-nat"
  network = google_compute_network.example.name
}

resource "google_compute_router_nat" "example_nat_config" {
  project                            = var.project_id
  region                             = "europe-west1"
  router                             = google_compute_router.example_nat.name
  name                               = "${google_compute_network.example.name}-nat-euw1"
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.example_gateway.self_link
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}
