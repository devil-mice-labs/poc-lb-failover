# This module provisions a regional external HTTPS load balancer on Google Cloud.
#
# External HTTP(S) load balancer overview
# https://cloud.google.com/load-balancing/docs/https
#
# Regional external HTTP load balancers require a proxy subnet
# https://cloud.google.com/load-balancing/docs/https#proxy-only-subnet
#
# FIXME regional HTTPS load balancer does not support Certificate Manager (?!) https://cloud.google.com/load-balancing/docs/ssl-certificates#certificate-summary
# FIXME regional HTTPS load balancer does not support Google-managed SSL certificates at all! https://cloud.google.com/load-balancing/docs/ssl-certificates#certificate-summary
#
# FIXME backend buckets are not supported by regional external HTTPS load balancers
# https://cloud.google.com/load-balancing/docs/url-map#configure_url_maps
#
# TODO the regional load balancer *could* also provide another endpoint for Let's Encrypt HTTP-01 challenge response, but I won't.

data "google_project" "default" {
  project_id = var.google_project
}

# TODO validate that services are enabled

locals {
  # Resolve the ambiguity of the potential presence of
  # the trailing dot by removing it, if it is present.
  domain          = trimsuffix(var.domain, ".")
  domain_parts    = split(".", local.domain)
  service_name    = local.domain_parts[0]
  zone_name_parts = slice(local.domain_parts, 1, length(local.domain_parts))
  zone_name       = join(".", local.zone_name_parts)
  root_cert_id    = var.root_cert_id
}

# The VPC and the proxy subnet for the load balancer.
resource "google_compute_network" "lb_net" {
  name                    = "lb-net"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "proxy_subnet" {
  project       = data.google_project.default.project_id
  region        = var.google_region
  network       = google_compute_network.lb_net.id
  name          = "proxy-only-subnet"
  description   = "This proxy subnet is shared between all of Envoy-based load balancers in its region."
  ip_cidr_range = "10.0.0.0/24"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Allocate a regional external IP address.
resource "google_compute_address" "default" {
  project = data.google_project.default.project_id
  region  = var.google_region

  address_type = "EXTERNAL"
  name         = "${local.service_name}-lb-https"
  network_tier = "STANDARD"
  # TODO would this work with the PREMIUM network tier address?
}

# Backend services overview
# https://cloud.google.com/load-balancing/docs/backend-service
#
# Backend services in Google Compute Engine can be either regionally or globally scoped.
# https://cloud.google.com/compute/docs/reference/rest/v1/regionBackendServices
#
# For regional external HTTPS load balancer, the scope of backend service is "regional" ?!
# https://cloud.google.com/load-balancing/docs/backend-service
#
resource "google_compute_region_backend_service" "default" {
  project = data.google_project.default.project_id
  region  = var.google_region

  name = local.service_name
  backend {
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    group           = var.neg_self_link
  }
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL_MANAGED"

  # TODO log config should probably come from input variables
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_region_url_map" "default" {
  project = data.google_project.default.project_id
  region  = var.google_region
  name    = "${local.service_name}-lb-https"

  # Accept only traffic that is addressed to the right domain name
  host_rule {
    hosts        = [local.domain]
    path_matcher = "default"
  }

  # Our service will handle all trafic that is addressed right
  path_matcher {
    name            = "default"
    default_service = google_compute_region_backend_service.default.id
  }

  # Drop the traffic not addressed to our service (wrong host)
  default_service = google_compute_region_backend_service.default.id
  default_route_action {
    fault_injection_policy {
      abort {
        http_status = 404
        percentage  = 100
      }
    }
  }
}

# TODO try reusing the existing (global) SSL policy resource
# FIXME as of Google provider version 4.68.0, the compute_region_ssl_policy resource is in "beta".
# https://registry.terraform.io/providers/hashicorp/google/4.68.0/docs/resources/compute_region_ssl_policy
resource "google_compute_region_ssl_policy" "modern" {
  provider = google-beta
  project  = data.google_project.default.project_id
  region   = var.google_region

  name            = "production-ssl-policy"
  description     = "Our SSL policy for all production services."
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# FIXME using regional SSL policy (a beta resource) requires using the beta provider for this as well
resource "google_compute_region_target_https_proxy" "default" {
  provider = google-beta
  project  = data.google_project.default.project_id
  region   = var.google_region

  ssl_certificates = [local.root_cert_id]
  name             = "${local.service_name}-https-proxy"
  ssl_policy       = google_compute_region_ssl_policy.modern.self_link
  url_map          = google_compute_region_url_map.default.id
}

resource "google_compute_forwarding_rule" "default" {
  project = data.google_project.default.project_id
  region  = var.google_region

  name                  = "${local.service_name}-lb-https"
  target                = google_compute_region_target_https_proxy.default.self_link
  ip_address            = google_compute_address.default.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  network_tier          = "STANDARD"

  # Reference the network via the subnet to make an implicit dependency explicit.
  network = google_compute_subnetwork.proxy_subnet.network
}

data "aws_route53_zone" "default" {
  name         = "${local.zone_name}."
  private_zone = false
}

resource "aws_route53_record" "lb_https_regional" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = local.domain
  type    = "A"
  ttl     = 300
  records = [
    google_compute_address.default.address,
  ]
  failover_routing_policy {
    type = "SECONDARY"
  }
  set_identifier = "regional"
}
