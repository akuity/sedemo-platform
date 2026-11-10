terraform {
  required_version = ">= 1.8"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # No backend, on purpose.
  #
  # Unlike ../infra (the shard generator), this config provisions nothing that
  # has to outlive the promotion. State is written into the ephemeral
  # promotion workspace and thrown away with it, so there is no bucket, no
  # lock table and nothing to clean up after a demo.
  #
  # That only works because the output is derived from the release rather than
  # from state -- see main.tf.
}
