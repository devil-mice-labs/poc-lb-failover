# This module provisions a managed SSL certificate used to secure HTTPS traffic
# between the service and its clients.
#
# Creates (via Google Certificate Manager):
#   * DNS authorisation
#   * SSL certificate
# The output of this module is meant to be fed into the module that manages DNS records,
# and into the modules that creates the load balancers.
#
# Inputs:
#  * Google Cloud project ID
#  * Google Cloud region
#  * domain name
# Outputs: 
#   * DNS resource record (name, type, data)
#   * SSL certificate ID
#
# References:
#   https://cloud.google.com/certificate-manager/docs/dns-authorizations
#   https://registry.terraform.io/providers/hashicorp/google/4.68.0/docs/resources/certificate_manager_dns_authorization
#   https://cloud.google.com/certificate-manager/docs/certificates
#   https://registry.terraform.io/providers/hashicorp/google/4.68.0/docs/resources/certificate_manager_certificate
#

data "google_project" "default" {
  project_id = var.google_project
}

locals {
  # Resolve the ambiguity of the potential presence of the trailing dot
  # by removing it, if it is present.
  domain          = trimsuffix(var.domain, ".")
  domain_parts    = split(".", local.domain)
  service_name    = local.domain_parts[0]
  zone_name_parts = slice(local.domain_parts, 1, length(local.domain_parts))
  zone_name       = join(".", local.zone_name_parts)
}

resource "google_certificate_manager_dns_authorization" "default" {
  project = data.google_project.default.project_id

  name   = "${local.domain_parts[0]}-dnsauth-0"
  domain = var.domain

  labels = {
    "terraform" : true
  }
}

resource "google_certificate_manager_certificate" "default" {
  project = data.google_project.default.project_id

  name     = "${local.domain_parts[0]}-rootcert-0"
  location = "global"
  managed {
    dns_authorizations = [
      google_certificate_manager_dns_authorization.default.id,
    ]
    domains = [
      var.domain,
    ]
  }

  labels = {
    "terraform" : true
  }
}

data "aws_route53_zone" "default" {
  name         = "${local.zone_name}."
  private_zone = false
}

# Create the authorisation record in DNS for Google-managed SSL certificate
#   https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/Welcome.html
#   https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record
resource "aws_route53_record" "dnsauth" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = google_certificate_manager_dns_authorization.default.dns_resource_record[0].name
  type    = google_certificate_manager_dns_authorization.default.dns_resource_record[0].type
  ttl     = 300
  records = [
    google_certificate_manager_dns_authorization.default.dns_resource_record[0].data,
  ]
}
