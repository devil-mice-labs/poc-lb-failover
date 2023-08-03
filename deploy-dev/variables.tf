# The root module parameters (input variables).

variable "aws_region" {
  description = <<-EOT
    Region of the AWS service endpoint. 
    Appears to be required to be set by the AWS provider.
  EOT
  type        = string
  nullable    = false
  default     = "eu-west-2"
}

variable "google_project" {
  description = <<-EOT
    Existing Google Cloud project that is going to 
    contain all infrasturture for this deployment.
  EOT
  type        = string
  nullable    = false
  default     = "infernal-horse"
}

variable "google_region" {
  description = <<-EOT
    A Google Cloud region to host all regional resources
    for this deployment.
  EOT
  type        = string
  nullable    = false
  default     = "europe-west2"
}

variable "service_fqdn" {
  description = <<-EOT
    The FQDN on which the service is going to accept HTTPS connections.
    The leftmost part is going to be the name of the service.
  EOT

  type     = string
  nullable = false
  default  = "hello-service.dev.devilmicelabs.com"

  validation {
    condition     = length(var.service_fqdn) > 2 && length(split(".", var.service_fqdn)) > 1
    error_message = "The value must be a fully-qualified domain name."
  }
}

variable "certificate_path" {
  description = <<-EOT
    The location in the local file system where the TLS certificate
    and its private key files are stored.
  EOT

  type     = string
  nullable = false
  default  = "~/cert-prod-0/"
}

variable "simulate_failure" {
  description = <<-EOT
    Set to true to simulate global ALB failure via fault injection. 
    The ALB will respond with error 500 to all requests until reverted.
  EOT
  type        = bool
  nullable    = false
  default     = false
}
