variable "google_project" {
  type     = string
  nullable = false
}

variable "google_region" {
  type     = string
  nullable = false
}

variable "service_name" {
  type     = string
  nullable = false
}

variable "container_image" {
  type     = string
  nullable = false
  default  = "gcr.io/cloudrun/hello"
}
