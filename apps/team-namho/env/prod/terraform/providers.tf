terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Same bucket and convention as governed-teams/apps-chart/terraform, keyed
  # clear of the unrelated kargo-steps/team-namho/shards state.
  backend "s3" {
    bucket       = "arad-tf-state-files"
    region       = "us-west-2"
    key          = "kargo-steps/team-namho-theme-prod/terraform.tfstate"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      owner   = "sedemo-team"
      purpose = "team-namho smol stage theme"
      stage   = var.stage
    }
  }
}
