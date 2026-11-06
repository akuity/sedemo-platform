variable "shards" {
  description = <<-EOT
    Production shards to provision. Each entry becomes:
      - a simulated provisioned resource (terraform_data)
      - a Kargo Stage named after it
      - a kustomize overlay under ../stages/<name>/
    Edit shards.auto.tfvars, not this file.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.shards : can(regex("^prod-[a-z0-9]+$", s))])
    error_message = "Each shard must be named prod-<suffix>, lowercase alphanumeric (e.g. prod-a)."
  }
}

variable "domain" {
  description = "Base domain the generated Ingress hosts hang off."
  type        = string
  default     = "akpdemoapps.link"
}
