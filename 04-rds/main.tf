# Grupo de seguridad de la aplicación (se usará en el lab 06 con ECS)
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Application tasks (ECS, lab 06)"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-sg"
  })
}

# Grupo de seguridad de la base de datos
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "RDS MySQL: only reachable from the app security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-sg"
  })
}

# Regla: MySQL (3306) solo desde el SG de la aplicación
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id # Referencia al SG de la aplicación
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL from app tasks"
}

# Grupo de subredes: dónde puede vivir la RDS (solo privadas, 2 AZ)
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnets"
  })
}

# Instancia RDS MySQL
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = "8.4"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "library"
  username                    = "library_admin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db"
  })
}