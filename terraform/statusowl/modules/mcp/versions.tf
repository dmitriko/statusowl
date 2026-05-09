terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 7.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3"
    }
  }
}
