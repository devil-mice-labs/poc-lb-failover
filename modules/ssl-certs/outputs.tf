output "root_cert_id" {
  description = <<-EOT
    A unique identifier for the managed SSL certificate resource that can be used to attach
    the certificate to a load balancer.
  EOT
  value       = google_certificate_manager_certificate.default.id
}
