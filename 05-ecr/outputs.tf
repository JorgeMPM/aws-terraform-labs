# ECR Reposirtorio para la API de Gestión de Bibliotecas
output "repository_url" {
  description = "ECR repository URL to tag and push the image"
  value       = aws_ecr_repository.api.repository_url
}