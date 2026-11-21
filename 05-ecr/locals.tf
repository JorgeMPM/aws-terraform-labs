locals {
  common_tags = {
    Project   = var.project_name
    Lab       = "03-vpc"
    ManagedBy = "Terraform"
  }
}