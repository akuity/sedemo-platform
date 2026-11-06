terraform {
  required_version = ">= 1.8"

  # Same bucket and credentials the beyond-k8s Kargo steps use. State has to
  # persist between promotions: the promotion workspace is ephemeral, so
  # without this every run would think no shard had ever been created.
  backend "s3" {
    bucket       = "arad-tf-state-files"
    region       = "us-west-2"
    key          = "kargo-steps/team-namho/shards/terraform.tfstate"
    use_lockfile = true
  }
}
