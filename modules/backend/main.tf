data "google_project" "default" {
  project_id = var.google_project
}

# TODO validate that services are enabled

resource "google_service_account" "default" {
  project = data.google_project.default.project_id

  account_id  = var.service_name
  description = "Identity for HelloGruffalo Cloud Run service"
}

resource "google_cloud_run_v2_service" "default" {
  project = data.google_project.default.project_id

  name     = var.service_name
  location = var.google_region

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    containers {
      image = var.container_image
    }
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    service_account       = google_service_account.default.email
    scaling {
      min_instance_count = 0
      max_instance_count = 4
    }
  }

  # lifecycle {
  #   ignore_changes = all
  # }
}

resource "google_cloud_run_v2_service_iam_member" "default" {
  project = google_cloud_run_v2_service.default.project

  name     = google_cloud_run_v2_service.default.name
  location = google_cloud_run_v2_service.default.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# A (serverless) NEG is not a load balancing component!
# https://cloud.google.com/load-balancing/docs/negs/serverless-neg-concepts#load_balancing_components
resource "google_compute_region_network_endpoint_group" "default" {
  project = data.google_project.default.project_id

  name                  = var.service_name
  network_endpoint_type = "SERVERLESS"
  region                = var.google_region

  cloud_run {
    service = google_cloud_run_v2_service.default.name
  }

  # Recreating a regional NEG that's in use by another resource
  # will give a `resourceInUseByAnotherResource` error.
  # To avoid this type of error, create the replacement NEG first.
  lifecycle {
    create_before_destroy = true
  }
}
