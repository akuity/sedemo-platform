locals {
  # A short digest of the release keeps two draws of the same word pair apart,
  # and makes the string look provisioned rather than hand-written.
  suffix = substr(sha256(var.release), 0, 4)
}

output "release_message" {
  description = "The release string smol displays, e.g. copper-otter-9f3a."
  value       = "${join("-", random_shuffle.release.result)}-${local.suffix}"
}

output "release" {
  description = "The image tag this string was derived from, echoed back for the promotion log."
  value       = var.release
}
