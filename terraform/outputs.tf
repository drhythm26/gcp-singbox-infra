output "hk_public_ip" {
  value = google_compute_address.hk_ip.address
}
output "sg_public_ip" {
  value = google_compute_address.sg_ip.address
}