# Lab 03: red (VPC, subredes, Internet Gateway y tablas de rutas)

Construir con Terraform la red donde vivirá la API: una VPC con **subredes públicas** (para el balanceador) y **privadas** (para la base de datos) en **dos zonas de disponibilidad**.

> Requisito: entorno preparado según [SETUP.md](SETUP.md) (`aws login` hecho y `aws sts get-caller-identity` con `user/<USUARIO>`). Conviene haber hecho el [lab 02](02-variables.md) (variables, locals y outputs).

---

## Índice

1. [Diseño de la red](#1-diseño-de-la-red)
2. [Estructura de la carpeta](#2-estructura-de-la-carpeta)
3. [Código](#3-código)
4. [Qué hace pública o privada a una subred](#4-qué-hace-pública-o-privada-a-una-subred)
5. [Dependencias entre recursos](#5-dependencias-entre-recursos)
6. [Flujo de comandos](#6-flujo-de-comandos)
7. [Comprobar en la consola](#7-comprobar-en-la-consola)
8. [Coste](#8-coste)
9. [Errores que evitar](#9-errores-que-evitar)
10. [Referencias oficiales](#10-referencias-oficiales)

---

## 1. Diseño de la red

```text
VPC 10.0.0.0/16  (eu-west-1)
│
├── Internet Gateway  ←→  internet
│
├── eu-west-1a
│   ├── public-a   10.0.1.0/24   → public-rt  (0.0.0.0/0 → Internet Gateway)
│   └── private-a  10.0.11.0/24  → private-rt (solo local)
│
└── eu-west-1b
    ├── public-b   10.0.2.0/24   → public-rt  (0.0.0.0/0 → Internet Gateway)
    └── private-b  10.0.12.0/24  → private-rt (solo local)
```

| Pieza | Qué es | Uso en el proyecto |
|---|---|---|
| VPC `/16` | Red privada en la región (65.536 direcciones) | Todo |
| Subredes públicas | Su tabla de rutas tiene salida a internet | Balanceador (ALB) |
| Subredes privadas | Su tabla de rutas no tiene salida a internet | Base de datos (RDS) |
| Internet Gateway | Puerta entre la VPC e internet (uno por VPC, gestionado por AWS) | — |
| Tablas de rutas | Deciden adónde va el tráfico de cada subred | — |

**Por qué dos zonas de disponibilidad:** el **Application Load Balancer** y el **grupo de subredes de RDS** exigen subredes en **al menos dos AZ**.

**Direcciones por subred:** un `/24` tiene 256 direcciones, pero AWS **reserva 5 en cada subred** (las 4 primeras y la última). Quedan **251** utilizables.

---

## 2. Estructura de la carpeta

```text
03-vpc/
├── versions.tf           # Copiado del lab 02
├── providers.tf          # Copiado del lab 02 (usa var.aws_region)
├── .terraform.lock.hcl   # Copiado del lab 02 → SÍ a Git
├── variables.tf          # aws_region, project_name, vpc_cidr
├── locals.tf             # common_tags con Lab = "03-vpc"
├── main.tf               # 13 recursos de red
└── outputs.tf            # vpc_id, public_subnet_ids, private_subnet_ids
```

Todas las variables tienen `default`, así que este lab **no necesita `terraform.tfvars`**.

---

## 3. Código

### `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region where resources are created"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used in resource names and tags"
  type        = string
  default     = "aws-terraform-labs"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
```

### `locals.tf`

```hcl
locals {
  common_tags = {
    Project   = var.project_name
    Lab       = "03-vpc"
    ManagedBy = "Terraform"
  }
}
```

### `main.tf`

#### VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}
```

| Elemento | Qué hace |
|---|---|
| `cidr_block` | Rango de direcciones de la VPC (entre `/16` y `/28`) |
| `enable_dns_support` | Resolución DNS de AWS dentro de la VPC (activada por defecto) |
| `enable_dns_hostnames` | Nombres DNS para los recursos. **Desactivado por defecto** en VPC nuevas; necesario para VPC endpoints y para resolver el nombre de la RDS |
| `merge(a, b)` | Función: une dos mapas. Aquí, etiquetas comunes + `Name` |
| `"${var.project_name}-vpc"` | Interpolación: mete el valor de una variable en un texto |

> La etiqueta `Name` es la que muestra la consola en la columna *Name*.

Al crear la VPC, **AWS crea automáticamente** una tabla de rutas principal, una ACL de red y un grupo de seguridad por defecto (en el plan: `main_route_table_id`, `default_network_acl_id`, `default_security_group_id`).

#### Subredes

```hcl
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-a"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-b"
  })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}a"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-a"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "${var.aws_region}b"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-b"
  })
}
```

> `"${var.aws_region}a"` → `eu-west-1a`. Si cambia la región, cambian las AZ.

#### Internet Gateway

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}
```

#### Tabla de rutas pública

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
```

#### Tabla de rutas privada

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
```

| Recurso | Qué hace |
|---|---|
| `aws_route_table` | Tabla nueva. AWS le añade sola la ruta `local` |
| `aws_route` | Ruta `0.0.0.0/0` (cualquier destino fuera de la VPC) → Internet Gateway |
| `aws_route_table_association` | Indica a una subred qué tabla usar en lugar de la principal |

**Por qué una tabla privada propia, si la principal ya no tiene salida:**
1. Queda explícito en el código qué tabla usa cada subred.
2. Si más adelante se añade un NAT gateway, la ruta `0.0.0.0/0 → NAT` irá en esta tabla y solo afectará a las privadas.

### `outputs.tf`

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB)"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (RDS)"
  value       = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
```

> Los corchetes `[ ]` crean una **lista**. El ALB y el grupo de subredes de RDS piden una lista de subredes.

---

## 4. Qué hace pública o privada a una subred

**Regla:** una subred es pública **solo** si su tabla de rutas tiene `0.0.0.0/0 → Internet Gateway`.

| Situación | ¿Pública? | Por qué |
|---|---|---|
| Subred recién creada, con la tabla principal | No | La principal solo tiene `10.0.0.0/16 → local` |
| Internet Gateway creado y conectado a la VPC, sin ruta | **No** | La puerta existe, pero ninguna ruta lleva a ella |
| Subred asociada a `public-rt` | **Sí** | Su tabla tiene `0.0.0.0/0 → igw-…` |
| Subred asociada a `private-rt` | No | Solo `local` |
| Subred nueva **sin asociación explícita** | No | Usa la tabla principal (solo `local`) |

Rutas de cada tabla:

| Ruta | `public-rt` | `private-rt` | Principal |
|---|---|---|---|
| `10.0.0.0/16 → local` | ✅ | ✅ | ✅ |
| `0.0.0.0/0 → igw-…` | ✅ | ❌ | ❌ |

> **Decisión de diseño:** la ruta a internet **no** se añade a la tabla principal. Así, cualquier subred que se cree sin asociación queda **privada por defecto** (seguro por defecto).

> El nombre `public-a` es solo una etiqueta: no cambia el comportamiento.

---

## 5. Dependencias entre recursos

Cuando un recurso referencia a otro (`vpc_id = aws_vpc.main.id`), Terraform deduce el orden: **dependencia implícita**.

- **Al crear:** primero la VPC; después, a la vez, las subredes, el Internet Gateway y las tablas de rutas; por último la ruta y las asociaciones.
- **Al destruir:** en orden **inverso**. La VPC se borra la última.
- En el plan, `vpc_id` de las subredes aparece como `(known after apply)`: el ID de la VPC lo asigna AWS al crearla.

---

## 6. Flujo de comandos

| Paso | Comando | Resultado esperado |
|---|---|---|
| 1 | `terraform init` | Provider instalado según el lock file |
| 2 | `terraform validate` | `Success! The configuration is valid.` |
| 3 | `terraform plan` | `Plan: 13 to add, 0 to change, 0 to destroy.` |
| 4 | `terraform apply` → `yes` | `Apply complete! Resources: 13 added` + sección `Outputs:` |
| 5 | `terraform output` | `vpc_id` y las dos listas de subredes |
| 6 | Revisar en la consola | Ver [sección 7](#7-comprobar-en-la-consola) |
| 7 | `terraform destroy` → `yes` | `Destroy complete! Resources: 13 destroyed.` |

Recursos (13): 1 VPC, 4 subredes, 1 Internet Gateway, 2 tablas de rutas, 1 ruta y 4 asociaciones.

---

## 7. Comprobar en la consola

Región **Europa (Irlanda)**.

1. **VPC → Sus VPC** → `aws-terraform-labs-vpc` → pestaña **Resource map**: subredes, tablas de rutas y Internet Gateway conectados.
2. **Tablas de enrutamiento** → **Filtrar por VPC** → `aws-terraform-labs-vpc`.
   - Aparecen 3 tablas: la principal, `public-rt` y `private-rt`.
   - Pestaña **Rutas**: comprobar las rutas de la [sección 4](#4-qué-hace-pública-o-privada-a-una-subred).
   - Pestaña **Asociaciones de subredes**: cada subred en su tabla.
3. **Puertas de enlace de Internet** → `aws-terraform-labs-igw` en estado **Attached**.

> La cuenta tiene también la **VPC por defecto** de la región, con su propia tabla principal. No se toca.

---

## 8. Coste

| Recurso | Coste |
|---|---|
| VPC, subredes, tablas de rutas, Internet Gateway | **Sin coste** |
| NAT gateway | **Se cobra por hora y por GB** → no se crea en este lab |

Aun así, cada sesión termina con `terraform destroy` para no dejar recursos olvidados.

---

## 9. Errores que evitar

| Error | Consecuencia | Cómo evitarlo |
|---|---|---|
| Pensar que una subred es pública por su nombre | Recursos sin salida a internet | Revisar las **rutas** de su tabla |
| Crear el Internet Gateway sin ruta | Ninguna subred sale a internet | `aws_route` con `0.0.0.0/0 → igw` |
| Añadir la ruta a internet en la tabla principal | Toda subred nueva sería pública por accidente | Tabla pública propia + asociaciones |
| Olvidar la asociación de una subred | Usa la tabla principal (privada) | Una `aws_route_table_association` por subred |
| Subredes en una sola AZ | El ALB y RDS no se pueden crear | Una subred pública y una privada por AZ, en dos AZ |
| `ls -a 03-vpc` estando ya dentro de `03-vpc` | `No such file or directory` | Las rutas son relativas: `ls -a` |

---

## 10. Referencias oficiales

- Amazon VPC – Cómo funciona: <https://docs.aws.amazon.com/vpc/latest/userguide/how-it-works.html>
- Amazon VPC – Subredes y tamaño (5 IP reservadas): <https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html>
- Amazon VPC – Tablas de rutas: <https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html>
- Amazon VPC – Internet Gateway: <https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html>
- Amazon VPC – Atributos DNS: <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-dns.html>
- Elastic Load Balancing – Subredes del ALB: <https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html#subnets-load-balancer>
- Amazon RDS – Grupos de subredes: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html>
- Terraform – `aws_vpc`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc>
- Terraform – `aws_subnet`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet>
- Terraform – `aws_route_table`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table>
- Terraform – Función `merge`: <https://developer.hashicorp.com/terraform/language/functions/merge>
