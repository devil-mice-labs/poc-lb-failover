data "google_project" "default" {
  project_id = var.google_project
}

# TODO validate that services are enabled

# Let's Encrypt HTTP-01 challenge
# https://letsencrypt.org/docs/challenge-types/

# The load balancer IP address is the same for HTTP and HTTPS parts.
# The IP address was provisioned in the `lb-https-global` module.

locals {
  domain       = var.domain
  domain_parts = split(".", local.domain)
  service_name = local.domain_parts[0]
}

resource "random_id" "bucket_prefix" {
  byte_length = 2
}

resource "google_storage_bucket" "acme" {
  name                        = "${random_id.bucket_prefix.hex}-${local.service_name}-acme-0"
  location                    = var.google_region
  uniform_bucket_level_access = true
  storage_class               = "STANDARD"
  force_destroy               = true
}

resource "google_storage_bucket_iam_member" "acme_all_users" {
  bucket = google_storage_bucket.acme.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "acme" {
  name        = "acme"
  description = "Stores token and thumbprint for Let's Encrypt HTTP-01 challenge."
  bucket_name = google_storage_bucket.acme.name
}

resource "google_compute_url_map" "default" {

  description = "Provide response to Let's Encrypt's HTTP-01 challenge and redirect all other queries to HTTPS."
  name        = "${local.service_name}-lb-http"
  project     = data.google_project.default.project_id

  host_rule {
    description  = "The only allowed host value is for ${local.service_name}. Other traffic will be discarded."
    hosts        = [local.domain]
    path_matcher = "default"
  }

  path_matcher {
    name        = "default"
    description = <<-EOT
      Direct Let's Encrypt's HTTP-01 challenge request to a GCS bucket. 
      Redirect all other requests to HTTPS.
    EOT

    route_rules {
      priority = 10
      match_rules {
        prefix_match = "/.well-known/acme-challenge/"
        ignore_case  = false
      }
      route_action {
        url_rewrite {
          path_prefix_rewrite = "/"
        }
      }
      service = google_compute_backend_bucket.acme.id
    }

    default_url_redirect {
      https_redirect = true
      strip_query    = false
    }
  }

  # Drop the traffic not addressed to our service (wrong host). The "default service" is never
  # reached in this case because the default route action returns error 404 in 100% of cases.
  default_service = google_compute_backend_bucket.acme.id
  default_route_action {
    fault_injection_policy {
      abort {
        http_status = 404
        percentage  = 100
      }
    }
  }

  test {
    description = "Test the response to Let's Encrypt HTTP-01 challenge."
    host        = local.domain
    path        = "/.well-known/acme-challenge/your-mom"
    service     = google_compute_backend_bucket.acme.id
  }
}

resource "google_compute_target_http_proxy" "default" {
  name    = "${local.service_name}-http-proxy"
  project = data.google_project.default.project_id
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  ip_address            = var.ipv4_global.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  name                  = "${local.service_name}-lb-http"
  port_range            = "80"
  project               = data.google_project.default.project_id
  target                = google_compute_target_http_proxy.default.self_link
}
