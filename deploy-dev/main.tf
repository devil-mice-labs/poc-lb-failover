# The root Terraform module for the "development" environment. 
# For deployment instructions, see the README file.
# For available deployment parameters, check out variables.tf file.

locals {
  aws_region     = var.aws_region
  google_project = var.google_project
  google_region  = var.google_region

  # Resolve the ambiguity of the potential presence of
  # the trailing dot by removing it, if it is present.
  # For those resources where we are going to need it,
  # we will add it there and then.
  service_fqdn = trimsuffix(var.service_fqdn, ".")
  domain_parts = split(".", local.service_fqdn)
  service_name = local.domain_parts[0]

  # Resolve the ambiguity of the potential presence of
  # the trailing slash in directory names by removing it,
  # if it is present. For those resources where we are going
  # to need it, we'll add it there and then.
  certificate_path = trimsuffix(var.certificate_path, "/")
}

# Most resources for this deployment are located on Google Cloud
provider "google" {
  project = local.google_project
  region  = "global"
}

# The only AWS service required for this deployment is Route 53 managed DNS.
provider "aws" {
  region = local.aws_region
}

# The backend for the public web service. This backend is not, by itself, publicly accessible.
module "backend" {
  source = "../modules/backend"

  google_project = local.google_project
  google_region  = local.google_region
  service_name   = local.service_name
}

# Google-managed TLS certificates for Global ALB.
module "ssl_certs_google_managed" {
  source = "../modules/ssl-certs"

  aws_region     = local.aws_region
  google_project = local.google_project
  google_region  = local.google_region
  domain         = local.service_fqdn
}

# This IPv4 address is shared between Global ALB for HTTPS (web service) 
# and HTTP (Let's Encrypt challenge response only).
resource "google_compute_global_address" "default" {
  name         = "${local.service_name}-lb-https"
  address_type = "EXTERNAL"
}

# Global ALB (HTTPS) - the main entry point for web service traffic. Secured by TLS.
module "lb_https_global" {
  source = "../modules/lb-https-global"

  aws_region       = local.aws_region
  google_project   = local.google_project
  google_region    = local.google_region
  domain           = local.service_fqdn
  neg_self_link    = module.backend.neg_self_link
  root_cert_id     = module.ssl_certs_google_managed.root_cert_id
  ipv4_global      = google_compute_global_address.default
  simulate_failure = var.simulate_failure
}

# Global ALB (HTTP) - the entry point for Let's Encrypt challenge response.
module "lb_http_global" {
  source = "../modules/lb-http-global"

  google_project = local.google_project
  google_region  = local.google_region
  domain         = local.service_fqdn
  ipv4_global    = google_compute_global_address.default
}

# The final few components -- a user-managed Compute Engine SSL certificate
# and a regional application load balancer will only be deployed after
# the certificate will have been provisioned from Let's Encrypted and
# saved in the specific location:

locals {
  certificate = pathexpand("${local.certificate_path}/${local.service_name}.crt")
  private_key = pathexpand("${local.certificate_path}/${local.service_name}.key")
}

# Regional ALB (HTTPS) does not support Google-managed TLS certificates, so we create
# user-managed ones.

module "ssl_certs_unmanaged" {
  source = "../modules/ssl-certs-unmanaged"

  count = (fileexists(local.certificate) && fileexists(local.private_key)) ? 1 : 0

  google_project = local.google_project
  google_region  = local.google_region
  domain         = local.service_fqdn

  certificate = local.certificate
  private_key = local.private_key
}

# Regional ALB (HTTPS). Secured by TLS certificates previously procured from Let's Encrypt.

module "lb_https_regional" {
  source = "../modules/lb-https-regional"

  count = (fileexists(local.certificate) && fileexists(local.private_key)) ? 1 : 0

  aws_region     = local.aws_region
  google_project = local.google_project
  google_region  = local.google_region
  domain         = local.service_fqdn
  root_cert_id   = module.ssl_certs_unmanaged[0].root_cert_id
  neg_self_link  = module.backend.neg_self_link
}
