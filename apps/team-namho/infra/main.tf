# Simulated provisioning: one resource per production shard.
#
# terraform_data is built into OpenTofu -- no provider, no credentials, no
# cloud resource, and the result is deterministic rather than random, so a
# re-apply with an unchanged shard list is a clean no-op.
#
# To make this provision something real, swap this one resource for an
# aws_ssm_parameter (or anything else) and keep the outputs the same shape.
# Nothing downstream reads anything but the outputs.
#
# This config deliberately writes NO repo files. Terraform provisions and
# reports; the `shards` promotion's file-write steps turn these outputs into
# Kargo Stage and Argo CD Application manifests, and Kargo commits them.
resource "terraform_data" "shard" {
  for_each = toset(var.shards)

  input = {
    name     = each.key
    endpoint = "smol-${each.key}.${var.domain}"
    # Stands in for whatever a real provisioner would hand back.
    handle = "shard/${each.key}"
  }
}
