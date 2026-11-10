variable "release" {
  description = <<-EOT
    The image tag being promoted, and the only input to the generated string.
    The `render` and `render-pr` promotion tasks write it into
    release.auto.tfvars with hcl-update before applying, so a given Freight
    renders the same value in staging and in every production shard.
  EOT
  type        = string
  default     = "unknown"
}

variable "words" {
  description = <<-EOT
    The pool the release string is drawn from. Short, unambiguous words that
    read well at the back of a room -- this ends up as the largest text on the
    page.
  EOT
  type        = list(string)
  default = [
    "amber", "basalt", "cobalt", "copper", "cedar", "delta",
    "ember", "flint", "garnet", "harbor", "indigo", "juniper",
    "kestrel", "lagoon", "marble", "nimbus", "onyx", "pewter",
    "quartz", "rowan", "saffron", "tundra", "umber", "verdant",
    "willow", "zephyr",
  ]

  validation {
    condition     = length(var.words) >= 4
    error_message = "words needs at least 4 entries for the shuffle to be worth anything."
  }
}
