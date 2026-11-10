# A random release string with one hard requirement: it has to be reproducible.
#
# The promotion workspace is ephemeral and this config keeps no remote state,
# so anything that depends on prior state regenerates on every apply --
# random_string's `keepers` included, since keepers only suppress regeneration
# when there is a state file to compare against. Seeding a shuffle instead
# makes the result a pure function of var.release:
#
#   - the same Freight always renders the same string
#   - the next release renders a different one
#   - staging and every prod shard agree, because they share the image tag
#
# Want a fresh value on every promotion instead? Replace this resource with
#
#   resource "random_string" "release" {
#     length  = 8
#     special = false
#     upper   = false
#   }
#
# and point the output at random_string.release.result. The trade is that
# `tf-apply` then never reports "No changes", and the same Freight looks
# different in each Stage.
resource "random_shuffle" "release" {
  input        = var.words
  result_count = 2
  seed         = var.release
}
