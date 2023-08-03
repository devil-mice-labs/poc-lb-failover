terraform {
  cloud {
    organization = "devil-mice-labs"

    workspaces {
      name = "poc-lb-failover"
    }
  }

  required_version = "1.4.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.1.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 4.68.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 4.68.0"
    }
  }
}
