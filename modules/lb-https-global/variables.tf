# FIXME if only Route 53 resources are used, why can I not use a "global endpoint"? wouldn't STS be part of IAM which is global?
# https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html
# https://docs.aws.amazon.com/general/latest/gr/rande.html
variable "aws_region" {
  description = "Region of the AWS service endpoint."
  type        = string
  nullable    = false
}

variable "google_project" {
  type     = string
  nullable = false
}

variable "google_region" {
  type     = string
  nullable = false
}

variable "domain" {
  description = "The FQDN on which Hello Service is accepting connections."

  type     = string
  nullable = false
  validation {
    condition     = length(var.domain) > 2 && length(split(".", var.domain)) > 1
    error_message = "The domain value must be a fully-qualified domain name."
  }
}

variable "ipv4_global" {
  description = "A resource representing a global IPv4 address to use for this application load balancer."
  nullable    = false
  type = object({
    id      = string
    name    = string
    address = string
  })
}

variable "neg_self_link" {
  description = "The URI of NEG to add to the load balancer's backend service."
  nullable    = false
  type        = string
}

variable "root_cert_id" {
  description = <<-EOT
    A unique identifier for the managed SSL certificate resource that can be used to attach
    the certificate to a load balancer.
  EOT
  nullable    = false
  type        = string
}

variable "simulate_failure" {
  default     = false
  description = "Simulate global load balancer failure with fault injection returning error 500 to all requests. Defaults to false."
  nullable    = false
  type        = bool
}
