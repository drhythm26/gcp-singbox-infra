resource "google_compute_network" "singbox_vpc" {
  name                    = "singbox-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "hk_subnetwork" {
  name          = "singbox-hk-subnet"
  network       = google_compute_network.singbox_vpc.id
  region        = var.hk_region
  ip_cidr_range = "10.10.0.0/24"
}

resource "google_compute_subnetwork" "sg_subnetwork" {
  name          = "singbox-sg-subnet"
  network       = google_compute_network.singbox_vpc.id
  region        = var.sg_region
  ip_cidr_range = "10.20.0.0/24"
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "singbox-allow-ssh"
  network = google_compute_network.singbox_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = var.admin_cidr
  target_tags   = ["singbox-node"]
}

resource "google_compute_firewall" "allow_singbox" {
  name    = "singbox-allow-service"
  network = google_compute_network.singbox_vpc.name
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  allow {
    protocol = "udp"
    ports    = ["8443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["singbox-node"]
}

