# Terraform provisions and reports. It writes no repo files -- it emits the
# rendered manifests as a string, and Kargo's file-write step is what puts
# them on disk and commits them.

locals {
  header = <<-EOT
    # Generated from Terraform output by the `shards` promotion.
    # Do not edit by hand: change infra/shards.auto.tfvars and promote `shards`.
  EOT

  stage_manifests = [
    for name in sort(var.shards) : {
      apiVersion = "kargo.akuity.io/v1alpha1"
      kind       = "Stage"
      metadata = {
        name      = name
        namespace = "team-namho"
        annotations = {
          "argocd.argoproj.io/sync-wave" = "2"
          "kargo.akuity.io/color"        = "pink"
          "team-namho/shard-handle"      = terraform_data.shard[name].output.handle
          "team-namho/shard-endpoint"    = terraform_data.shard[name].output.endpoint
        }
        labels = { "team-namho/shard" = "true" }
      }
      # No promotionTemplate: these are control-flow Stages. They deploy
      # nothing and have no Argo CD Application, which is what keeps a
      # dynamically created shard from needing a kustomize overlay. Freight
      # flows into them automatically once staging verifies it.
      spec = {
        requestedFreight = [{
          origin  = { kind = "Warehouse", name = "smol" }
          sources = { stages = ["staging"] }
        }]
      }
    }
  ]
}

output "stages_yaml" {
  description = "Kargo Stage manifests for every shard, as one multi-document YAML string."
  value       = join("", concat([local.header], [for m in local.stage_manifests : "---\n${yamlencode(m)}"]))
}

output "shard_names" {
  description = "Sorted shard names, comma-separated, for commit messages."
  value       = join(", ", sort(var.shards))
}

output "shard_count" {
  description = "How many production shards exist."
  value       = length(var.shards)
}
