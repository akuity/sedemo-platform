# The per-Stage palette: one bucket holding one public stylesheet, published by
# this Stage's promotion. smol links it, so the page's colours tell you which
# Stage you are looking at. dev has no terraform directory and so renders black
# on white with empty swatches.
#
# The key is fixed and the content is the only input, so an image-only release
# is a genuine no-op: Terraform acts when the palette actually changes -- a new
# flavor chosen at staging, or an edit to the CSS itself -- and not otherwise.

data "aws_caller_identity" "current" {}

locals {
  bucket = "smol-theme-${var.stage}-${data.aws_caller_identity.current.account_id}"
  theme  = "${path.module}/../../../themes/${var.flavor}.css"
}

resource "aws_s3_bucket" "theme" {
  bucket = local.bucket
}

# The stylesheet is fetched by the browser, so the object has to be publicly
# readable. There is no account-level Block Public Access on this account; this
# turns it off for this bucket so the policy below can take effect.
resource "aws_s3_bucket_public_access_block" "theme" {
  bucket                  = aws_s3_bucket.theme.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "theme" {
  bucket     = aws_s3_bucket.theme.id
  depends_on = [aws_s3_bucket_public_access_block.theme]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadThemes"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.theme.arn}/*"
    }]
  })
}

resource "aws_s3_object" "theme" {
  bucket       = aws_s3_bucket.theme.id
  key          = "theme.css"
  content      = file(local.theme)
  content_type = "text/css"
  # The key never changes, so the browser must revalidate rather than serve a
  # palette from the previous release.
  cache_control = "no-cache"
  etag          = filemd5(local.theme)
}

output "theme_url" {
  description = "Public URL of this Stage's stylesheet, fed into the chart as theme.url."
  value       = "https://${aws_s3_bucket.theme.bucket}.s3.${var.region}.amazonaws.com/${aws_s3_object.theme.key}"
}
