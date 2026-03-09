resource "aws_s3_bucket" "example" {
  bucket = "${var.app_name}-${var.stage}-bucket"

  tags = {
    Name        = "SE Demo Bucket"
    Environment = "${var.stage}"
    owner       = "sedemo-team"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.example.bucket
}