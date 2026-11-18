variable "aws_region" {
  description = "AWS region where resources are created"
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource tags"
  type        = string
  default     = "aws-terraform-labs"
}