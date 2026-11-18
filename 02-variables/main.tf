resource "aws_s3_bucket" "practica" {
  bucket = var.bucket_name
  tags   = local.common_tags
}
