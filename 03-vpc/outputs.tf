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