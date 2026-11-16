variable "region" {
  type    = string
  default = "us-west-2"
}

variable "stage" {
  type        = string
  description = "The Kargo Stage this theme belongs to."
  default     = "prod-mocha"
}

variable "flavor" {
  type        = string
  description = <<-EOT
    Which Catppuccin palette this Stage publishes, named after a file in
    apps/team-namho/themes/. Written by the promotion's hcl-update step from
    the Stage's `flavor` task var: the production regions pass a fixed one,
    staging passes whatever the promoter picked, and prod reads staging's
    choice back off the Freight.
  EOT
  default     = "mocha"

  validation {
    condition     = contains(["latte", "frappe", "macchiato", "mocha"], var.flavor)
    error_message = "flavor must be one of latte, frappe, macchiato, mocha."
  }
}
