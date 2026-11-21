locals {
  common_tags = {
    Project   = var.project_name
    Lab       = "04-rds"
    ManagedBy = "Terraform"
  }
}