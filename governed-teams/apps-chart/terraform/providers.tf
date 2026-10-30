terraform {
  backend "s3" {
    bucket       = "arad-tf-state-files"
    region       = "us-west-2"
    key          = "kargo-steps/${var.app_name}-${var.stage}/terraform.tfstate"
    use_lockfile = true
  }
}