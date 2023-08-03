variable "google_project" {
  type     = string
  nullable = false
}

variable "google_region" {
  type     = string
  nullable = false
}

variable "domain" {
  description = "Fully-qualified domain name for Hello Service."

  type     = string
  nullable = false
  validation {
    condition     = length(var.domain) > 2 && length(split(".", var.domain)) > 1
    error_message = "The value must be a fully-qualified domain name."
  }
}

variable "ipv4_global" {
  description = "A resource representing a global IPv4 address to use for this application load balancer."
  type = object({
    id      = string
    name    = string
    address = string
  })
  nullable = false
}
