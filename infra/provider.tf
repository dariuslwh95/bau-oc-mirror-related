terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # If you want to use GitLab Managed State later, you add this:
  # backend "http" {}
}

provider "aws" {
  region = "ap-southeast-1" 
  # Terraform will automatically look for credentials in ~/.aws/credentials
}