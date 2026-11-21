# Declaración de la VPC 
output "vpc_id" {
  # La descripción del output
  description = "ID of the VPC"
  # El valor del output, que es el ID de la VPC creada
  value       = aws_vpc.main.id
}

# Declaración de los IDs de las subredes públicas 
output "public_subnet_ids" {
    # La descripción del output
  description = "IDs of the public subnets (ALB)"
  # El valor del output, que es un array con los IDs de las subredes públicas
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# Declaración de los IDs de las subredes privadas
output "private_subnet_ids" {
    # La descripción del output
  description = "IDs of the private subnets (RDS)"
  # El valor del output, que es un array con los IDs de las subredes privadas
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# Declaración del endpoint de la RDS, es la dirección que usará la aplicación para conectarse a la base de datos
output "db_endpoint" {
  description = "RDS endpoint (host:port) for the application"
  value       = aws_db_instance.main.endpoint
}

# Declaración del nombre de la base de datos, es el ARN del secreto que contiene la contraseña del usuario administrador de la base de datos
output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret with the master password"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}