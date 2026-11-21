resource "aws_vpc" "main" {
  # El rango de direcciones de la VPC. AWS permite entre /16 (65.536 direcciones) y /28 (16)
  cidr_block           = var.vpc_cidr
  # Activa la resolución DNS de AWS dentro de la VPC (ya viene activada por defecto)
  enable_dns_support   = true
  # Da nombres DNS a los recursos. En una VPC nueva viene desactivado; lo necesitaremos para los VPC endpoints y para resolver el nombre de la RDS
  enable_dns_hostnames = true

  # Etiquetas para identificar la VPC
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-vpc" # Etiqueta Name para identificar la VPC en la consola de AWS
  })
}

# Subred pública en la zona de disponibilidad A
resource "aws_subnet" "public_a" {
  # La VPC a la que pertenece la subred
  vpc_id            = aws_vpc.main.id
  # El rango de direcciones de la subred. Debe estar dentro del rango de la VPC
  cidr_block        = "10.0.1.0/24"
  # La zona de disponibilidad donde se creará la subred. Se construye a partir de la región y la letra de la zona
  availability_zone = "${var.aws_region}a"

  # Etiquetas para identificar la subred
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-public-a" # Etiqueta Name para identificar la subred en la consola de AWS
  })
}

# Subred pública en la zona de disponibilidad B
resource "aws_subnet" "public_b" {
  # La VPC a la que pertenece la subred
  vpc_id            = aws_vpc.main.id
  # El rango de direcciones de la subred. Debe estar dentro del rango de la VPC
  cidr_block        = "10.0.2.0/24"
  # La zona de disponibilidad donde se creará la subred. Se construye a partir de la región y la letra de la zona
  availability_zone = "${var.aws_region}b"

  # Etiquetas para identificar la subred
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-public-b" # Etiqueta Name para identificar la subred en la consola de AWS
  })
}

# Creamos un Internet Gateway para permitir la salida a Internet desde la VPC
resource "aws_internet_gateway" "main" {
  # La VPC a la que pertenece el Internet Gateway
  vpc_id = aws_vpc.main.id

  # Etiquetas para identificar el Internet Gateway
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-igw" # Etiqueta Name para identificar el Internet Gateway en la consola de AWS
  })
}

# 1. Tabla de rutas propia para las subredes públicas
resource "aws_route_table" "public" {
  # La VPC a la que pertenece la tabla de rutas
  vpc_id = aws_vpc.main.id

  # Etiquetas para identificar la tabla de rutas
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-public-rt" # Etiqueta Name para identificar la tabla de rutas en la consola de AWS
  })
}

# 2. La ruta: todo lo que vaya a internet → Internet Gateway
resource "aws_route" "public_internet" {
  # La tabla de rutas a la que pertenece la ruta
  route_table_id         = aws_route_table.public.id
  # La ruta: todo lo que vaya a internet → Internet Gateway
  destination_cidr_block = "0.0.0.0/0"
  # El ID del Internet Gateway que se creó antes
  gateway_id             = aws_internet_gateway.main.id
}

# 3. Asociar la tabla a cada subred pública
resource "aws_route_table_association" "public_a" {
  # La subred a la que se asocia la tabla de rutas
  subnet_id      = aws_subnet.public_a.id
  # La tabla de rutas que se asocia a la subred
  route_table_id = aws_route_table.public.id
}

# Asociar la tabla a la subred pública B
resource "aws_route_table_association" "public_b" {
  # La subred a la que se asocia la tabla de rutas
  subnet_id      = aws_subnet.public_b.id
  # La tabla de rutas que se asocia a la subred
  route_table_id = aws_route_table.public.id
}

# Subredes privadas
resource "aws_subnet" "private_a" {
  # La VPC a la que pertenece la subred
  vpc_id            = aws_vpc.main.id
  # El rango de direcciones de la subred. Debe estar dentro del rango de la VPC
  cidr_block        = "10.0.11.0/24"
  # La zona de disponibilidad donde se creará la subred. Se construye a partir de la región y la letra de la zona
  availability_zone = "${var.aws_region}a"

  # Etiquetas para identificar la subred
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-private-a" # Etiqueta Name para identificar la subred en la consola de AWS
  })
}

# Subred privada en la zona de disponibilidad B
resource "aws_subnet" "private_b" {
  # La VPC a la que pertenece la subred
  vpc_id            = aws_vpc.main.id
  # El rango de direcciones de la subred. Debe estar dentro del rango de la VPC
  cidr_block        = "10.0.12.0/24"
  # La zona de disponibilidad donde se creará la subred. Se construye a partir de la región y la letra de la zona
  availability_zone = "${var.aws_region}b"

  # Etiquetas para identificar la subred
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-private-b" # Etiqueta Name para identificar la subred en la consola de AWS
  })
}

# Creamos una tabla de rutas para las subredes privadas
resource "aws_route_table" "private" {
  # La VPC a la que pertenece la tabla de rutas
  vpc_id = aws_vpc.main.id

  # Etiquetas para identificar la tabla de rutas
  tags = merge(local.common_tags, { # merge() funcion de Terraform que combina dos mapas en uno solo
    Name = "${var.project_name}-private-rt" # Etiqueta Name para identificar la tabla de rutas en la consola de AWS
  })
}

# Asociar la tabla a cada subred privada
resource "aws_route_table_association" "private_a" {
  # La subred a la que se asocia la tabla de rutas
  subnet_id      = aws_subnet.private_a.id
  # La tabla de rutas que se asocia a la subred
  route_table_id = aws_route_table.private.id
}

# Asociar la tabla a la subred privada B
resource "aws_route_table_association" "private_b" {
  # La subred a la que se asocia la tabla de rutas
  subnet_id      = aws_subnet.private_b.id
  # La tabla de rutas que se asocia a la subred
  route_table_id = aws_route_table.private.id
}