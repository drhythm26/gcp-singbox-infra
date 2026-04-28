resource "google_compute_address" "hk_ip" {
  name   = "singbox-hk-ip"
  region = var.hk_region
}

resource "google_compute_address" "sg_ip" {
  name   = "singbox-sg-ip"
  region = var.sg_region
}

resource "google_compute_instance" "hk_node" {
  name         = "singbox-hk"
  machine_type = "e2-micro"
  zone         = var.hk_zone
  tags         = ["singbox-node"]
  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      size  = 20
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.hk_subnetwork.id
    access_config {
      nat_ip = google_compute_address.hk_ip.address
    }
  }
  metadata = {
    ssh-key = "${var.ssh_user}:${var.ssh_public_key_path}"
  }
}

resource "google_compute_instance" "sg_node" {
  name         = "singbox-sg"
  machine_type = "e2-micro"
  zone         = var.sg_zone
  tags         = ["singbox-node"]
  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      size  = 20
      type  = "pd-balanced"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.sg_subnetwork.id
    access_config {
      nat_ip = google_compute_address.sg_ip.address
    }
  }
  metadata = {
    ssh-key = "${var.ssh_user}/${var.ssh_public_key_path}"
  }
}

