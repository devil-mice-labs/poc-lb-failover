# FIXME we'd like to procure a Domain Validated (DV) self-managed SSL certificate.
# FIXME can't do DNS-01 authorisation for Let's Encrypt. Have to do HTTP-01, then.
# Oh, crap, HTTP-01 is only supported on port 80. So we need to set up an extra LB for that now :(
# 
# TODO so this is what we need:
#   GCS bucket with public access
#   An object in the bucket containing authorisation string for HTTP-01
#   LB: a backend service for the bucket
#   LB: a URL map forwarding the request for the specific validation URL to the bucket
#   LB: a target HTTP proxy that the URL map plugs into
#   LB: a forwarding rule for port 80
#   LB: a redirect to https for every request apart from HTTP-01 authorisation
#   Create Compute Engine regional SSL certificate resource sourcing (two) input files with the certificate data
#
# FIXME the good thing is that the current LB components do not need updating! 
# TODO probably should use a new module for the extra LB

data "google_project" "default" {
  project_id = var.google_project
}

locals {
  domain_parts = split(".", var.domain)
  service_name = local.domain_parts[0]
}

# TODO document in readme that a manual step must be run before deploying this module
# FIXME the following resource configuration assumes that certbot root directory is located at "~/Certbot/
resource "google_compute_region_ssl_certificate" "default" {
  project     = data.google_project.default.project_id
  region      = var.google_region
  name_prefix = "${local.service_name}-lb-https-regional-0"
  description = "The certificate for regional HTTPS load balancer for ${local.service_name}."
  certificate = file(var.certificate)
  private_key = file(var.private_key)

  lifecycle {
    create_before_destroy = true
  }
}
