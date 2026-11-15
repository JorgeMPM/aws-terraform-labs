resource "aws_s3_bucket" "practica" {
  bucket = "jorgempm-tf-practica-20261112"

  tags = {
    Project   = "terraform-practica"
    ManagedBy = "Terraform"
  }
}