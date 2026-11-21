# ECR Reposirtorio para la API de Gestión de Bibliotecas
resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}/library-management-api"
  image_tag_mutability = "IMMUTABLE" # Esta configuración asegura que las imágenes no puedan ser sobrescritas una vez que se han subido al repositorio con otra imagen distinta. Esto es importante para mantener la integridad de las imágenes y evitar problemas de seguridad o inconsistencias en el despliegue.
  force_delete         = true # Esta configuración permite que el repositorio pueda ser eliminado incluso si contiene imágenes. Esto es útil en entornos de desarrollo o pruebas donde se desea limpiar recursos rápidamente, pero debe usarse con precaución en entornos de producción para evitar la pérdida accidental de datos.
  
  # Habilitar el escaneo de imágenes al subirlas al repositorio. Esto permite detectar vulnerabilidades en las imágenes y mejorar la seguridad de la aplicación.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-library-management-api"
  })
}