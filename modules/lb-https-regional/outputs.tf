output "address_name" {
  value = google_compute_address.default.name
}

output "address_ipv4" {
  value = google_compute_address.default.address
}