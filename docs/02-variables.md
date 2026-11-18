# Lab 02: variables, outputs y locals

Quitar del código los valores escritos a mano (*hardcoded*) del [lab 01](01-s3.md) y aprender las tres piezas que permiten reutilizar una configuración de Terraform: **variables** (entrada), **outputs** (salida) y **locals** (valores internos).

> Requisito: entorno preparado según [SETUP.md](SETUP.md) (`aws login` hecho y `aws sts get-caller-identity` con `user/<USUARIO>`).

---

## Índice

1. [Estructura de la carpeta](#1-estructura-de-la-carpeta)
2. [Variables de entrada](#2-variables-de-entrada)
3. [Cómo dar valor a una variable](#3-cómo-dar-valor-a-una-variable)
4. [Locals](#4-locals)
5. [Outputs](#5-outputs)
6. [Plantilla `terraform.tfvars.example`](#6-plantilla-terraformtfvarsexample)
7. [Flujo de comandos](#7-flujo-de-comandos)
8. [Errores que evitar](#8-errores-que-evitar)
9. [Referencias oficiales](#9-referencias-oficiales)

---

## 1. Estructura de la carpeta

```text
02-variables/
├── versions.tf                 # Igual que en el lab 01
├── providers.tf                # Región desde una variable
├── variables.tf                # Declaración de variables (entrada)
├── locals.tf                   # Valores internos reutilizables
├── main.tf                     # Recursos
├── outputs.tf                  # Valores de salida
├── terraform.tfvars.example    # Plantilla             → SÍ a Git
├── terraform.tfvars            # Valores reales        → NO a Git
└── .terraform.lock.hcl         # Copiado del lab 01    → SÍ a Git
```

> Se copió el lock file del lab 01 para usar la **misma versión del provider**. No se copian `.terraform/` ni el estado: cada lab tiene su propio estado.

---

## 2. Variables de entrada

Una variable es un **parámetro** de la configuración: se declara una vez y se usa donde haga falta con `var.<nombre>`.

### `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region where resources are created"
  type        = string
  default     = "eu-west-1"
}

variable "bucket_name" {
  description = "Globally unique name for the S3 bucket"
  type        = string
}

variable "project_name" {
  description = "Project name used in resource tags"
  type        = string
  default     = "aws-terraform-labs"
}
```

| Argumento | Para qué sirve |
|---|---|
| `description` | Documenta la variable. Terraform la muestra cuando pide un valor. |
| `type` | Terraform rechaza cualquier valor de otro tipo. |
| `default` | Valor si nadie da otro. **Sin `default`, la variable es obligatoria.** |

### Uso

```hcl
# providers.tf
provider "aws" {
  region = var.aws_region
}
```

```hcl
# main.tf
resource "aws_s3_bucket" "practica" {
  bucket = var.bucket_name
  tags   = local.common_tags
}
```

### Variable obligatoria sin valor

| Situación | Comportamiento |
|---|---|
| Terminal interactiva | Terraform **pregunta** el valor (`Enter a value:`) |
| CI/CD o `-input=false` | **Error:** `No value for required variable` |

> Las variables **no** se pueden usar dentro del bloque `terraform { }`: `required_version` y la versión del provider siguen siendo fijas.

### Declarar ≠ asignar

| Fichero | Papel |
|---|---|
| `variables.tf` | **Declara**: nombre, tipo y si es obligatoria. |
| `terraform.tfvars` | **Asigna**: el valor concreto. |

---

## 3. Cómo dar valor a una variable

| Forma | Ejemplo | Uso típico |
|---|---|---|
| `default` | En la declaración | Valor razonable para todos |
| Variable de entorno | `export TF_VAR_bucket_name=mi-bucket` | CI/CD (prefijo `TF_VAR_` obligatorio) |
| `terraform.tfvars` | `bucket_name = "mi-bucket"` | Valores habituales de un entorno |
| `*.auto.tfvars` | `prod.auto.tfvars` | Igual, varios ficheros |
| En el comando | `terraform plan -var="bucket_name=mi-bucket"` | Pruebas puntuales |
| Fichero en el comando | `terraform plan -var-file="dev.tfvars"` | Elegir entorno |

**Carga automática:** Terraform solo lee por sí mismo `terraform.tfvars`, `terraform.tfvars.json` y los `*.auto.tfvars`. Cualquier otro nombre hay que pasarlo con `-var-file`.

**Prioridad** (si la misma variable llega por varias vías, gana la de más abajo):

1. `default`
2. `TF_VAR_…`
3. `terraform.tfvars`
4. `*.auto.tfvars`
5. `-var` y `-var-file` en el comando

Ejemplo comprobado: con `default = "eu-west-1"`, `terraform.tfvars` con `eu-central-1` y `-var="aws_region=eu-south-2"`, gana **`eu-south-2`**.

---

## 4. Locals

Un *local value* da **un nombre a una expresión** para reutilizarla dentro del código. Evita repetir lo mismo en muchos recursos.

### `locals.tf`

```hcl
locals {
  common_tags = {
    Project   = var.project_name   # cambiable desde fuera
    Lab       = "02-variables"     # fijo
    ManagedBy = "Terraform"        # fijo
  }
}
```

> El bloque es `locals` (plural); la referencia es `local.` (singular): `local.common_tags`.

### Variable o local

| | Variable (`var.`) | Local (`local.`) |
|---|---|---|
| Quién da el valor | Desde fuera (tfvars, `-var`, entorno) | Dentro del código |
| ¿Cambiable sin tocar los `.tf`? | Sí | No |
| Para qué | Lo que cambia según quién o dónde se despliega | Evitar repetición y calcular valores internos |

**Patrón habitual:** un local que **combina** variables. `Project` se puede cambiar desde fuera (`-var="project_name=prueba"`), mientras `Lab` y `ManagedBy` son fijos, y todo se escribe una sola vez en `common_tags`.

---

## 5. Outputs

Los outputs son la **salida** de la configuración: valores que Terraform muestra al terminar el `apply`.

### `outputs.tf`

```hcl
output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.practica.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.practica.bucket_regional_domain_name
}
```

**Referencia a un atributo:** `tipo.nombre_local.atributo` → `aws_s3_bucket.practica.arn`.

| Momento | Valor del output |
|---|---|
| `terraform plan` | `(known after apply)`: lo asigna AWS al crear el recurso |
| Después de `apply` | Valor real, por ejemplo `arn:aws:s3:::<BUCKET>` |

Consultarlos después (sin llamar a AWS; los lee del estado):

```bash
terraform output
terraform output bucket_arn
```

---

## 6. Plantilla `terraform.tfvars.example`

`terraform.tfvars` está en el `.gitignore` porque en proyectos reales suele llevar valores sensibles. Sin él, quien clone el repo no sabe qué rellenar. Se sube una **plantilla**:

```hcl
# Copy this file to terraform.tfvars and set your own values.
# terraform.tfvars is excluded from Git (.gitignore).

# Required. S3 bucket names are globally unique.
bucket_name = "your-unique-bucket-name"

# Optional (these are the defaults).
# aws_region   = "eu-west-1"
# project_name = "aws-terraform-labs"
```

> La regla `*.tfvars` del `.gitignore` solo afecta a nombres que **terminan** en `.tfvars`. `terraform.tfvars.example` sí se sube.

Uso:

```bash
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars con un nombre de bucket propio
```

---

## 7. Flujo de comandos

| Paso | Comando | Resultado esperado |
|---|---|---|
| 1 | `cp terraform.tfvars.example terraform.tfvars` y editar | Valores propios |
| 2 | `terraform init` | Provider instalado según el lock file |
| 3 | `terraform validate` | `Success! The configuration is valid.` |
| 4 | `terraform plan` | `1 to add`; sección `Changes to Outputs` con `(known after apply)`; **sin preguntas** |
| 5 | `terraform plan -var="project_name=prueba"` | La etiqueta `Project` cambia a `prueba` |
| 6 | `terraform apply` → `yes` | Sección `Outputs:` con valores reales |
| 7 | `terraform output` | Los mismos valores, leídos del estado |
| 8 | `terraform destroy` → `yes` | `Destroy complete! Resources: 1 destroyed.` |
| 9 | `aws s3 ls` | Sin el bucket |

Antes del commit, desde la raíz del repo:

```bash
git status -u
```

Deben aparecer los `.tf`, el lock file y `terraform.tfvars.example`. **No** deben aparecer `terraform.tfvars`, `*.tfstate` ni `.terraform/`.

---

## 8. Errores que evitar

| Error | Consecuencia | Cómo evitarlo |
|---|---|---|
| Pegar un bloque `resource` dentro de otro | `Unexpected block: Blocks of type "resource" are not expected here` | Un bloque por recurso; sustituir, no anidar. |
| Escribir `locals.common_tags` | Referencia no válida | Se referencia en singular: `local.common_tags`. |
| Llamar al fichero de valores `valores.tfvars` | Terraform no lo carga y pregunta | Usar `terraform.tfvars` o pasar `-var-file`. |
| Subir `terraform.tfvars` | Exposición de valores sensibles | `.gitignore` + plantilla `.example`. |
| Usar un local para algo que otros deben cambiar | Obliga a editar el código | Variable (con `default` si hay un valor razonable). |
| Usar variables en el bloque `terraform { }` | Error de configuración | Versiones fijas en ese bloque. |

---

## 9. Referencias oficiales

- Terraform – Variables de entrada: <https://developer.hashicorp.com/terraform/language/values/variables>
- Terraform – Asignar valores a variables y prioridad: <https://developer.hashicorp.com/terraform/language/values/variables#assigning-values-to-root-module-variables>
- Terraform – Locals: <https://developer.hashicorp.com/terraform/language/values/locals>
- Terraform – Outputs: <https://developer.hashicorp.com/terraform/language/values/outputs>
- Terraform – `terraform output`: <https://developer.hashicorp.com/terraform/cli/commands/output>
- Terraform – Referencias a valores: <https://developer.hashicorp.com/terraform/language/expressions/references>
