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

# FIXME if only Route 53 resources are used, why can I not use a "global endpoint"? wouldn't STS be part of IAM which is global?
# https://docs.aws.amazon.com/STS/latest/APIReference/welcome.html
# https://docs.aws.amazon.com/general/latest/gr/rande.html
variable "aws_region" {
  description = "Region of the AWS service endpoint."
  type        = string
  nullable    = false
}
