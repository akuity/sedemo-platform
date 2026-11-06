# Terraform provisions and reports. It writes no repo files -- it emits the
# rendered manifests as strings, and Kargo's file-write steps are what put
# them on disk and commit them.

locals {
  repo_url = "https://github.com/akuity/sedemo-platform"

  stages_header = <<-EOT
    # Generated from Terraform output by the `shards` promotion.
    # Do not edit by hand: change infra/shards.auto.tfvars and promote `shards`.
  EOT

  apps_header = <<-EOT
    # Generated from Terraform output by the `shards` promotion.
    # One Argo CD Application per production shard. Do not edit by hand:
    # change infra/shards.auto.tfvars and promote `shards`.
  EOT

  # Each shard is a real deploy target: a Kargo Stage that renders manifests,
  # opens a PR for approval, and syncs its own Argo CD Application.
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
      spec = {
        requestedFreight = [{
          origin  = { kind = "Warehouse", name = "smol" }
          sources = { stages = ["staging"] }
        }]
        # render-pr builds the kustomize overlay in the promotion workspace,
        # so a shard needs no committed overlay directory of its own.
        promotionTemplate = {
          spec = {
            steps = [{ task = { name = "render-pr" } }]
          }
        }
      }
    }
  ]

  # The Argo CD side of the same list. These go to apps/team-namho/argocd/,
  # which the platform's argocd-apps ApplicationSet syncs with prune enabled,
  # so dropping a shard from the tfvars removes its Application too.
  app_manifests = [
    for name in sort(var.shards) : {
      apiVersion = "argoproj.io/v1alpha1"
      kind       = "Application"
      metadata = {
        name      = "team-namho-${name}"
        namespace = "argocd"
        annotations = {
          # Lets the Stage's argocd-update step drive this Application.
          "kargo.akuity.io/authorized-stage" = "team-namho:${name}"
        }
        labels = { "team-namho/shard" = "true" }
      }
      spec = {
        project = "team-namho"
        source = {
          repoURL = local.repo_url
          # Written by the shard's own promotion; missing until it first runs.
          targetRevision = "rendered/team-namho/${name}"
          path           = "."
        }
        destination = {
          name      = "sedemo-primary"
          namespace = "team-namho-${name}"
        }
        # No automated sync: Kargo's argocd-update step drives every sync.
        syncPolicy = {
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  ]
}

output "stages_yaml" {
  description = "Kargo Stage manifests for every shard, as one multi-document YAML string."
  value       = join("", concat([local.stages_header], [for m in local.stage_manifests : "---\n${yamlencode(m)}"]))
}

output "apps_yaml" {
  description = "Argo CD Application manifests for every shard, as one multi-document YAML string."
  value       = join("", concat([local.apps_header], [for m in local.app_manifests : "---\n${yamlencode(m)}"]))
}

output "shard_names" {
  description = "Sorted shard names, comma-separated, for commit messages."
  value       = join(", ", sort(var.shards))
}

output "shard_count" {
  description = "How many production shards exist."
  value       = length(var.shards)
}
