output "service_uri" {
  description = "The Cloud Run URI of Hello Service."
  value       = module.backend.service_uri
}

output "global_lb_ipv4" {
  description = "Public endpoint for Hello Service - Global ALB."
  value       = google_compute_global_address.default.address
}

output "acme_bucket" {
  description = "Cloud Storage bucket to use for domain verification with Let's Encrypt."
  value       = module.lb_http_global.acme_bucket
}

output "regional_lb_ipv4" {
  description = "Public endpoint for Hello Service - Regional ALB."
  value       = try(module.lb_https_regional[0].address_ipv4, null)
}
