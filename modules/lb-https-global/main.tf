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

resource "google_compute_backend_service" "default" {
  project = data.google_project.default.project_id

  name = local.service_name
  backend {
    group = var.neg_self_link
  }
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL_MANAGED"

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "default" {
  project = data.google_project.default.project_id

  name = "${local.service_name}-lb-https"

  # Accept only traffic that is addressed to the right domain name
  host_rule {
    hosts        = [local.domain]
    path_matcher = "default"
  }

  # Our service will handle all trafic that is addressed right
  path_matcher {
    name            = "default"
    default_service = google_compute_backend_service.default.id
    default_route_action {
      fault_injection_policy {
        abort {
          http_status = 500
          percentage  = var.simulate_failure ? 100 : 0
        }
      }
    }
  }

  # Drop the traffic not addressed to our service (wrong host)
  default_service = google_compute_backend_service.default.id
  default_route_action {
    fault_injection_policy {
      abort {
        http_status = 404
        percentage  = 100
      }
    }
  }
}

resource "google_compute_ssl_policy" "modern" {
  project = data.google_project.default.project_id

  name            = "production-ssl-policy"
  description     = "Our SSL policy for all production services."
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

resource "google_certificate_manager_certificate_map" "default" {
  project = data.google_project.default.project_id

  name        = "${local.service_name}-certmap-0"
  description = "${local.domain} certificate map"

  labels = {
    "terraform" : true
  }
}

resource "google_certificate_manager_certificate_map_entry" "default" {
  project = data.google_project.default.project_id

  name     = "${local.service_name}-entry-0"
  map      = google_certificate_manager_certificate_map.default.name
  hostname = local.domain

  # FIXME no data resource exists for Certificate Manager certificates
  certificates = [
    local.root_cert_id,
  ]

  labels = {
    "terraform" : true
  }
}

resource "google_compute_target_https_proxy" "default" {
  project = data.google_project.default.project_id

  name            = "${local.service_name}-https-proxy"
  url_map         = google_compute_url_map.default.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.default.id}"
  ssl_policy      = google_compute_ssl_policy.modern.self_link

  # The Certificate Manager documentation says that the certificate map 
  # must only be attached to the target proxy after the certificate map
  # entries had been populated but there is no direct reference from
  # the certificate map entry to the target proxy so we create a dependency.
  # https://cloud.google.com/certificate-manager/docs/maps#attach-proxy
  depends_on = [
    google_certificate_manager_certificate_map_entry.default,
  ]
}

resource "google_compute_global_forwarding_rule" "default" {
  project = data.google_project.default.project_id

  name                  = "${local.service_name}-lb-https"
  target                = google_compute_target_https_proxy.default.self_link
  ip_address            = var.ipv4_global.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

data "aws_route53_zone" "default" {
  name         = "${local.zone_name}."
  private_zone = false
}

resource "aws_route53_health_check" "default" {
  fqdn             = local.domain
  ip_address       = var.ipv4_global.address
  port             = 443
  request_interval = 30
  tags = {
    "Name" : local.service_name
  }
  type = "HTTPS"
}

resource "aws_route53_record" "lb_https_global" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = local.domain
  type    = "A"
  ttl     = 300
  records = [
    var.ipv4_global.address,
  ]
  failover_routing_policy {
    type = "PRIMARY"
  }
  health_check_id = aws_route53_health_check.default.id
  set_identifier  = "global"
}
