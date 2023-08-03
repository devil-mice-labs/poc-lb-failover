variable "google_project" {
  type     = string
  nullable = false
}

variable "google_region" {
  type     = string
  nullable = false
}

variable "domain" {
  description = "The domain for which a Google-managed SSL certificate should be issued."

  type     = string
  nullable = false
  validation {
    condition     = length(var.domain) > 2 && length(split(".", var.domain)) > 1
    error_message = "The domain value must be a fully-qualified domain name."
  }
}

variable "certificate" {
  description = "The path to a file containing the TLS certificate for Hello Service."
  type        = string
  nullable    = false
}

variable "private_key" {
  description = "The path to a file containing the TLS certificate private key for Hello Service."
  type        = string
  nullable    = false
}
