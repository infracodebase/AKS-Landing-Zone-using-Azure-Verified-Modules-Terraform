terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.75.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.1.0, != 4.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.0"
    }
  }

  # Remote state configuration examples (uncomment as needed)
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "eks-landing-zone/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }

  # backend "remote" {
  #   hostname     = "app.terraform.io"
  #   organization = "your-organization"
  #
  #   workspaces {
  #     name = "eks-landing-zone"
  #   }
  # }
}