# ==============================================================================
# Terraform & AWS Provider Specifications
# Projeto: ferry-telemetry-tde | Módulo: Core Networking (SCRUM-7)
# ==============================================================================

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ferry-telemetry-tde"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "https://github.com/rafafigolif/ferry-telemetry-tde"
    }
  }
}

