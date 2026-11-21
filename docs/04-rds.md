# Lab 04: grupos de seguridad y base de datos RDS MySQL

Añadir a la red del [lab 03](03-vpc.md) una base de datos **RDS MySQL** en las subredes **privadas**, accesible **solo** desde el grupo de seguridad de la aplicación, con la contraseña gestionada por **Secrets Manager**.

> Requisito: entorno preparado según [SETUP.md](SETUP.md) (`aws login` hecho y `aws sts get-caller-identity` con `user/<USUARIO>`).

> ⚠️ **Este lab crea recursos de pago** (RDS y un secreto de Secrets Manager). Hacer siempre `terraform destroy` al terminar.

---

## Índice

1. [Diseño](#1-diseño)
2. [Estructura de la carpeta](#2-estructura-de-la-carpeta)
3. [Grupos de seguridad](#3-grupos-de-seguridad)
4. [Grupo de subredes y RDS](#4-grupo-de-subredes-y-rds)
5. [Outputs](#5-outputs)
6. [Flujo de comandos](#6-flujo-de-comandos)
7. [Comprobaciones](#7-comprobaciones)
8. [Coste y tiempos](#8-coste-y-tiempos)
9. [Valores de laboratorio vs producción](#9-valores-de-laboratorio-vs-producción)
10. [Errores que evitar](#10-errores-que-evitar)
11. [Referencias oficiales](#11-referencias-oficiales)

---

## 1. Diseño

```text
VPC 10.0.0.0/16 (la del lab 03)
│
├── Subredes públicas (a, b)
│     └── [lab 06] ECS Fargate → SG "app"
│                                   │
│                                   │  solo TCP 3306 (MySQL)
│                                   ▼
└── Subredes privadas (a, b)
      └── RDS MySQL 8.4 → SG "db"
            └── contraseña en Secrets Manager (la gestiona RDS)
```

| Pieza | Qué es | Por qué |
|---|---|---|
| SG `app` | Grupo de seguridad vacío, para las tareas de ECS del lab 06 | La regla de la base de datos apunta a él |
| SG `db` | Entrada **solo** al 3306 **desde el SG `app`** | Mínimo privilegio: solo la API habla con la base de datos |
| DB subnet group | Las 2 subredes **privadas** | RDS exige subredes en al menos 2 AZ |
| RDS MySQL `db.t4g.micro` | Una instancia, sin Multi-AZ, sin acceso público | Opción más pequeña y nunca expuesta a internet |
| Contraseña | `manage_master_user_password = true` | RDS la genera y la guarda en Secrets Manager: no está en el código ni en el estado |

**Por qué la regla apunta a un SG y no a un rango de IP:**
- Las tareas de Fargate reciben **IP distintas** cada vez que arrancan. Una regla por SG sigue funcionando.
- Da igual en qué subred esté la app: entra quien lleve el SG `app`.
- Con `10.0.0.0/16`, **cualquier** recurso de la VPC podría conectarse a la base de datos.

---

## 2. Estructura de la carpeta

```text
04-rds/
├── versions.tf           # Copiado del lab 03
├── providers.tf          # Copiado del lab 03
├── .terraform.lock.hcl   # Copiado del lab 03 → SÍ a Git
├── variables.tf          # Copiado del lab 03
├── locals.tf             # Copiado del lab 03, con Lab = "04-rds"
├── network.tf            # = main.tf del lab 03 (la red)
├── main.tf               # NUEVO: grupos de seguridad y RDS
└── outputs.tf            # Outputs de red + endpoint y secreto
```

Se copia la red del lab 03 para que el lab sea **independiente**. Reutilizarla sin copiar exige módulos o estado remoto (labs posteriores).

Terraform lee **todos** los `.tf` de la carpeta: separar `network.tf` y `main.tf` solo sirve para ordenar.

Preparación (desde la raíz del repo):

```bash
mkdir 04-rds
cp 03-vpc/versions.tf 03-vpc/providers.tf 03-vpc/.terraform.lock.hcl 03-vpc/variables.tf 03-vpc/locals.tf 03-vpc/outputs.tf 04-rds/
cp 03-vpc/main.tf 04-rds/network.tf
```

---

## 3. Grupos de seguridad

### `main.tf` (primera parte)

```hcl
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
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  description                  = "MySQL from app tasks"
}
```

| Recurso / argumento | Qué hace |
|---|---|
| `aws_security_group` | Crea el grupo, vacío, en la VPC |
| `aws_vpc_security_group_ingress_rule` | Una regla de entrada por recurso (forma recomendada por el provider, en vez de reglas dentro del grupo) |
| `referenced_security_group_id` | El origen es **otro grupo de seguridad**, no un rango de IP |
| `from_port` / `to_port` | Rango de puertos: solo el 3306 |

### Reglas de salida: consola vs Terraform

| Creado desde… | Entrada | Salida |
|---|---|---|
| Consola de AWS | Todo bloqueado | **Todo permitido** (regla por defecto) |
| Terraform (`aws_security_group`) | Todo bloqueado | **Nada**: Terraform elimina la regla por defecto |

> El SG `app` necesitará reglas de salida en el lab 06 (hacia la base de datos y para descargar la imagen).

### Stateful: por qué la RDS puede responder sin reglas de salida

Los grupos de seguridad son **stateful** (con estado): si una conexión entra por una regla de entrada, **la respuesta sale automáticamente**.

| Tráfico | ¿Permitido? | Por qué |
|---|---|---|
| App → RDS, puerto 3306 | ✅ | Regla de entrada desde el SG `app` |
| RDS → app, respuesta | ✅ | Stateful: la respuesta sale sola |
| RDS → internet, conexión nueva | ❌ | Sin reglas de salida (y en subred privada) |

> Contraste: la **ACL de red** es **stateless**: hay que permitir la entrada y la salida de la respuesta por separado.

---

## 4. Grupo de subredes y RDS

### `main.tf` (segunda parte)

```hcl
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
```

| Argumento | Qué hace | Por qué este valor |
|---|---|---|
| `engine_version = "8.4"` | Versión mayor; RDS elige la menor más reciente | MySQL 8.0 está en **RDS Extended Support (de pago)** desde el 1 de agosto de 2026; 8.4 es LTS |
| `db.t4g.micro` | Instancia más pequeña (ARM, Graviton) | La más barata |
| `allocated_storage` / `gp3` | 20 GB de disco SSD | Mínimo razonable |
| `storage_encrypted = true` | Cifrado **en reposo** con KMS | En Terraform viene **desactivado** por defecto |
| `db_name` | Base de datos inicial | La que usa `library-management-api` |
| `manage_master_user_password` | RDS genera la contraseña y la guarda en **Secrets Manager** | No aparece en el código ni en el estado |
| `db_subnet_group_name` | Subredes donde puede vivir | Solo privadas |
| `vpc_security_group_ids` | SG aplicados a la instancia | Solo entra el SG `app` |
| `publicly_accessible = false` | Sin IP pública | Nunca accesible desde internet |
| `multi_az = false` | Una sola AZ | Coste mínimo (ver [sección 9](#9-valores-de-laboratorio-vs-producción)) |
| `skip_final_snapshot = true` | Al destruir, no guarda copia final | Lab: evita que `destroy` falle o deje snapshots de pago |
| `deletion_protection = false` | Permite borrarla | Lab: en producción, `true` |

### Multi-AZ vs réplicas de lectura

| | Multi-AZ (instancia) | Réplica de lectura |
|---|---|---|
| Objetivo | **Disponibilidad** | **Rendimiento** de lectura |
| Copia | *Standby* en otra AZ, **síncrona** | Asíncrona |
| ¿Atiende lecturas? | No | Sí |
| Si cae la principal | **Conmutación automática**, mismo endpoint | No conmuta sola |

Con `multi_az = false`, si cae la AZ de la instancia, la base de datos deja de estar disponible hasta que la AZ se recupere.

---

## 5. Outputs

Añadidos al final de `outputs.tf` (se mantienen los 3 de red):

```hcl
output "db_endpoint" {
  description = "RDS endpoint (host:port) for the application"
  value       = aws_db_instance.main.endpoint
}

output "db_master_secret_arn" {
  description = "ARN of the Secrets Manager secret with the master password"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
```

- `db_endpoint`: dirección a la que se conectará la API en el lab 06 (`<identificador>.<id>.eu-west-1.rds.amazonaws.com:3306`).
- `db_master_secret_arn`: el **ARN** del secreto, no la contraseña. `[0]` coge el primer (y único) elemento de la lista.

---

## 6. Flujo de comandos

| Paso | Comando | Resultado esperado |
|---|---|---|
| 1 | `terraform init` | Provider instalado según el lock file |
| 2 | `terraform validate` | `Success! The configuration is valid.` |
| 3 | `terraform plan` | `Plan: 18 to add` (13 de red + 2 SG + 1 regla + subnet group + RDS) |
| 4 | `terraform apply` → `yes` | RDS en ~5 min · `Apply complete! Resources: 18 added` + `Outputs:` |
| 5 | Comprobaciones | Ver [sección 7](#7-comprobaciones) |
| 6 | `terraform destroy` → `yes` | RDS en ~2 min · `Destroy complete! Resources: 18 destroyed.` |

> Al destruir, el SG `db` y el grupo de subredes **esperan** a que termine de borrarse la RDS, porque dependen de ella. La VPC se borra la última.

---

## 7. Comprobaciones

**En la consola** (Europa, Irlanda):
1. **RDS → Bases de datos → `aws-terraform-labs-db`**:
   - *Conectividad y seguridad*: **Accesible públicamente = No**; SG `aws-terraform-labs-db-sg`.
   - *Configuración*: **Cifrado = Habilitado**.
2. **Secrets Manager**: un secreto `rds!db-…` creado por RDS.
   > No recuperar ni compartir su valor.
3. Tras el `destroy`: el secreto desaparece o queda **programado para eliminación**.

**La contraseña no está en el estado:**

```bash
grep -n '"password"' terraform.tfstate
```

Resultado esperado:

```text
"password": null,
"value": "password"
```

- `"password": null` → la contraseña **no** está guardada.
- `"value": "password"` → forma parte de `sensitive_attributes`: es el **nombre** del atributo que Terraform trata como sensible, no un valor secreto.

**Nada del estado en Git** (desde la raíz):

```bash
git status -u
```

No debe aparecer `04-rds/terraform.tfstate` ni `04-rds/.terraform/`.

---

## 8. Coste y tiempos

| Concepto | Valor aproximado |
|---|---|
| `db.t4g.micro` MySQL en Irlanda, encendida todo el mes | ~12 USD/mes (fuente no oficial: Bytebase) → unos céntimos por hora |
| Secreto de Secrets Manager | Por mes, prorrateado |
| Red (VPC, subredes, IGW, tablas) y grupos de seguridad | Sin coste |
| Crear la RDS | ~5 min |
| Destruir la RDS | ~2 min |

**Regla:** `apply` al empezar la sesión y `destroy` al terminarla. Comprobar la factura en **Billing → Bills** de vez en cuando.

---

## 9. Valores de laboratorio vs producción

| Argumento | Lab | Producción |
|---|---|---|
| `multi_az` | `false` | `true` (alta disponibilidad) |
| `skip_final_snapshot` | `true` | `false` (copia final al borrar) |
| `deletion_protection` | `false` | `true` |
| `instance_class` | `db.t4g.micro` | Según la carga |
| `backup_retention_period` | Por defecto | Días según la política de copias |

---

## 10. Errores que evitar

| Error | Consecuencia | Cómo evitarlo |
|---|---|---|
| Usar MySQL 8.0 | Recargo de Extended Support | `engine_version = "8.4"` |
| Escribir la contraseña en el código (`password = "..."`) | Queda en el `.tfstate` en texto plano | `manage_master_user_password = true` |
| Olvidar `storage_encrypted = true` | Datos sin cifrar en reposo | Activarlo siempre |
| Regla del SG `db` desde `0.0.0.0/0` o toda la VPC | Cualquiera (o cualquier recurso) puede intentar conectarse | `referenced_security_group_id` = SG `app` |
| `publicly_accessible = true` | Endpoint con IP pública | `false` y subredes privadas |
| Sin `skip_final_snapshot` en el lab | `destroy` falla o deja snapshots de pago | `true` en el lab |
| Dejar la RDS encendida | Coste por hora | `terraform destroy` al terminar |
| `login session has expired` | `plan` falla sin credenciales | `aws login` (la sesión dura 12 h como máximo) |

---

## 11. Referencias oficiales

- Amazon RDS – Instancias en una VPC y grupos de subredes: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html>
- Amazon RDS – Contraseñas gestionadas con Secrets Manager: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html>
- Amazon RDS – Multi-AZ: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html>
- Amazon RDS – Cifrado: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html>
- Amazon RDS – Versiones de MySQL: <https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/MySQL.Concepts.VersionMgmt.html>
- AWS Database Blog – Upgrade de RDS for MySQL 8.0 a 8.4: <https://aws.amazon.com/blogs/database/upgrade-strategies-for-amazon-rds-for-mysql-8-0-to-8-4/>
- Amazon VPC – Grupos de seguridad: <https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html>
- Terraform – `aws_security_group`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group>
- Terraform – `aws_vpc_security_group_ingress_rule`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule>
- Terraform – `aws_db_subnet_group`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group>
- Terraform – `aws_db_instance`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance>
