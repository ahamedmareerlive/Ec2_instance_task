terraform {

  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "mareer-tf-state-prod-001"
    key          = "ec2/dev/terraform.tfstate"
    region       = "us-east-1"

    encrypt      = true
    use_lockfile = true
  }

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
