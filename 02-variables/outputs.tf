output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.practica.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.practica.bucket_regional_domain_name
}