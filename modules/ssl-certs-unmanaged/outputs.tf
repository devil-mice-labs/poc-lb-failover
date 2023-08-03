output "root_cert_id" {
  description = <<-EOT
    A unique identifier for the self-managed Compute Engine regional SSL certificate
    resource that can be used to attach the certificate to a load balancer.
  EOT
  value       = google_compute_region_ssl_certificate.default.id
}

output "domain" {
  description = "The domain for which a self-managed Compute Engine SSL certificate was created."
  value       = var.domain
}
