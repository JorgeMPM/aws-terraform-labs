locals {
  common_tags = {
    Project   = var.project_name   # cambiable desde fuera
    Lab       = "02-variables"     # fijo
    ManagedBy = "Terraform"       # fijo
  }
}

