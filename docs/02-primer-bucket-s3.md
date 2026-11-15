# Fase 2: primer recurso con Terraform (bucket S3)

Crear, inspeccionar y destruir un bucket S3 con Terraform para aprender el ciclo completo: `init` → `plan` → `apply` → `destroy`.

> Requisito: entorno preparado según [SETUP.md](SETUP.md) (`aws login` hecho y `aws sts get-caller-identity` con `user/<USUARIO>`).

---

## Índice

1. [Estructura de la carpeta](#1-estructura-de-la-carpeta)
2. [Código](#2-código)
3. [Flujo de comandos](#3-flujo-de-comandos)
4. [Conceptos clave](#4-conceptos-clave)
5. [Qué va a Git y qué no](#5-qué-va-a-git-y-qué-no)
6. [Errores que evitar](#6-errores-que-evitar)
7. [Referencias oficiales](#7-referencias-oficiales)

---

## 1. Estructura de la carpeta

```text
01-s3/
├── versions.tf            # Versión de Terraform y del provider
├── providers.tf           # Configuración del provider (región)
├── main.tf                # Recursos
├── .gitignore
├── .terraform.lock.hcl    # Creado por init  → SÍ a Git
├── .terraform/            # Creado por init  → NO a Git
├── terraform.tfstate      # Creado por apply → NO a Git
└── terraform.tfstate.backup  # Copia del estado anterior → NO a Git
```

> Terraform lee **todos** los `.tf` de la carpeta como una sola configuración. Los nombres de fichero son una convención.

---

## 2. Código

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.23"
    }
  }
}
```

| Línea | Significado |
|---|---|
| `required_version` | Versión mínima del binario de Terraform. |
| `aws` | **Nombre local** del provider. Se usa en `provider "aws"` y en los recursos `aws_*`. |
| `source` | Origen en el registro: `registry.terraform.io/hashicorp/aws`. |
| `version = "~> 6.23"` | ≥ 6.23.0 y < 7.0.0. La 6.23 es la mínima que lee las credenciales de `aws login` (ver SETUP.md, paso 8). |

### `providers.tf`

```hcl
provider "aws" {
  region = "eu-west-1"
}
```

- La región va **escrita en el código** para que el resultado sea el mismo en cualquier máquina y en CI/CD, que no tiene `~/.aws/config`.
- **No hay credenciales.** El provider las busca solo (variables de entorno, después los ficheros de `~/.aws/`). Nunca se escriben en un `.tf`.

### `main.tf`

```hcl
resource "aws_s3_bucket" "practica" {
  bucket = "jorgempm-tf-practica-20261112"

  tags = {
    Project   = "terraform-practica"
    ManagedBy = "Terraform"
  }
}
```

| Parte | Significado |
|---|---|
| `aws_s3_bucket` | **Tipo** de recurso, definido por el provider. |
| `practica` | **Nombre local**: solo existe dentro de Terraform. |
| `aws_s3_bucket.practica` | **Dirección** del recurso en el plan y en el estado. |
| `bucket` | Nombre **real** en AWS: único en todo el mundo, 3–63 caracteres, minúsculas, números, puntos y guiones. |
| `tags` | `ManagedBy = "Terraform"` avisa de que no se debe modificar a mano en la consola. |

---

## 3. Flujo de comandos

| Paso | Comando | ¿Llama a AWS? | Resultado esperado |
|---|---|---|---|
| 1 | `terraform init` | No (solo al registro) | `Installing hashicorp/aws v6.x.x` · crea `.terraform/` y `.terraform.lock.hcl` |
| 2 | `terraform fmt` | No | Formatea los `.tf` |
| 3 | `terraform validate` | No | `Success! The configuration is valid.` |
| 4 | `terraform plan` | Sí (lee) | `Plan: 1 to add, 0 to change, 0 to destroy.` |
| 5 | `terraform apply` → `yes` | Sí (crea) | `Apply complete! Resources: 1 added` · crea `terraform.tfstate` |
| 6 | `terraform state list` | No | `aws_s3_bucket.practica` |
| 7 | `terraform state show aws_s3_bucket.practica` | No | Todos los atributos (`arn`, `id`…) |
| 8 | `aws s3 ls` | Sí | El bucket aparece |
| 9 | `aws s3api get-public-access-block --bucket <BUCKET>` | Sí | Los cuatro ajustes a `true` |
| 10 | `terraform destroy` → `yes` | Sí (borra) | `Destroy complete! Resources: 1 destroyed.` |
| 11 | `aws s3 ls` | Sí | El bucket ya no aparece |

> Solo `yes` confirma `apply` y `destroy`. Cualquier otra respuesta cancela sin tocar nada.

**Antes de cada `apply` o `destroy`, leer el resumen.** Si aparece `to destroy` o `-/+` (reemplazo) y no se esperaba, **parar**.

### Símbolos del plan

| Símbolo | Acción |
|---|---|
| `+` | Crear |
| `~` | Modificar sin recrear |
| `-` | Destruir |
| `-/+` | Destruir y volver a crear (reemplazo) |

### `apply` con y sin `-out`

| Forma | Comportamiento |
|---|---|
| `terraform apply` | Calcula un plan nuevo, lo muestra y pide `yes`. Uso en local. |
| `terraform plan -out=tfplan` + `terraform apply tfplan` | Aplica **exactamente** el plan guardado, sin pedir confirmación. Uso en CI/CD. |

---

## 4. Conceptos clave

### Rango de versiones y fichero de bloqueo

- `~> 6.23` es un **rango**. `init` elige la versión más alta disponible dentro de él (en esta práctica, la 6.73.0).
- `.terraform.lock.hcl` **fija** esa versión exacta para todos los que usen el repositorio.
- Para subir de versión: `terraform init -upgrade`.

### `(known after apply)`

Hay atributos que decide el usuario (`bucket`, `tags`, `region`) y otros que **asigna AWS al crear el recurso** (`arn`, `id`, `bucket_regional_domain_name`…). Estos segundos aparecen en el plan como `(known after apply)` y se guardan en el estado cuando AWS responde.

### El estado (`terraform.tfstate`)

Es la memoria de Terraform: relaciona `aws_s3_bucket.practica` con el bucket real y guarda todos sus atributos.

`plan` compara **código** y **estado**:

| Momento | Código | Estado | Plan |
|---|---|---|---|
| Antes de `apply` | 1 bucket | vacío | `1 to add` |
| Después de `apply` | 1 bucket | 1 bucket | `No changes` |
| Después de `destroy` | 1 bucket | vacío | `1 to add` |

Reglas:
1. **No editarlo a mano.** Usar `terraform state list` y `terraform state show`.
2. **Nunca a Git.** Puede contener secretos en texto plano (por ejemplo, la contraseña de una RDS).
3. **No borrarlo.** Si se pierde, Terraform deja de gestionar los recursos, que siguen existiendo (y costando) en AWS.

### Nombre local ≠ nombre real

Cambiar `"practica"` por otro nombre **después del `apply`** hace que Terraform proponga **destruir** el recurso y crear otro. Para renombrar sin destruir se usa un bloque `moved`:

```hcl
moved {
  from = aws_s3_bucket.practica
  to   = aws_s3_bucket.pruebas
}
```

### `force_destroy = false`

Valor por defecto. Si el bucket tiene objetos, `destroy` **falla** en lugar de borrarlos. Es una red de seguridad que conviene mantener.

### Seguridad por defecto de S3 (comprobada en el estado y con la CLI)

| Ajuste | Valor | Significado |
|---|---|---|
| Cifrado | `AES256` (SSE-S3) | Los objetos se cifran en reposo sin configurar nada. |
| Block Public Access | Los cuatro ajustes a `true` | Nadie de internet puede leer el bucket, y AWS rechaza cualquier intento de hacerlo público. |
| Control de versiones | Desactivado | Sin copia de objetos borrados o sobrescritos. |

---

## 5. Qué va a Git y qué no

| Elemento | ¿A Git? | Motivo |
|---|---|---|
| `*.tf` | Sí | Es el código. |
| `.terraform.lock.hcl` | **Sí** | Fija la versión exacta del provider para todos. |
| `.terraform/` | No | Binarios descargados; se regeneran con `init`. |
| `terraform.tfstate`, `terraform.tfstate.backup` | **No** | Pueden contener secretos. |
| `tfplan` (planes guardados) | No | Pueden contener secretos. |
| `*.tfvars` | No | Suelen contener valores sensibles. |

El fichero [`.gitignore`](../.gitignore) del repositorio aplica estas reglas. **Debe existir antes del primer `git add`.**

Comprobación antes de cada commit:

```powershell
git status
```

No debe aparecer ningún `.tfstate` ni la carpeta `.terraform/`.

---

## 6. Errores que evitar

| Error | Consecuencia | Cómo evitarlo |
|---|---|---|
| Fijar una versión del provider anterior a la 6.23 | `plan` no encuentra credenciales aunque la CLI funcione. | `version = "~> 6.23"`. |
| Omitir `region` en el provider | Cada máquina despliega en su región por defecto, o falla. | Región explícita en el código. |
| Responder `y` en lugar de `yes` | Se cancela la operación. | Escribir `yes` completo. |
| Renombrar el nombre local tras `apply` | Destrucción y recreación del recurso. | Bloque `moved`. |
| Subir `terraform.tfstate` a Git | Exposición de datos y secretos. | `.gitignore` antes del primer commit. |
| Modificar en la consola un recurso gestionado por Terraform | El estado deja de coincidir con la realidad. | Cambiar siempre el código y aplicar. |

---

## 7. Referencias oficiales

- Terraform – Requisitos de providers: <https://developer.hashicorp.com/terraform/language/providers/requirements>
- Terraform – Fichero de bloqueo de dependencias: <https://developer.hashicorp.com/terraform/language/files/dependency-lock>
- Terraform – Bloque `resource`: <https://developer.hashicorp.com/terraform/language/resources/syntax>
- Terraform – Refactorización con `moved`: <https://developer.hashicorp.com/terraform/language/modules/develop/refactoring>
- Terraform – Estado: <https://developer.hashicorp.com/terraform/language/state>
- Terraform – `terraform apply`: <https://developer.hashicorp.com/terraform/cli/commands/apply>
- Terraform – `terraform destroy`: <https://developer.hashicorp.com/terraform/cli/commands/destroy>
- Provider AWS – `aws_s3_bucket`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket>
- Amazon S3 – Reglas de nombres de buckets: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html>
- Amazon S3 – Block Public Access: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html>
- Amazon S3 – Cifrado por defecto: <https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html>
- Plantilla oficial de `.gitignore` para Terraform: <https://github.com/github/gitignore/blob/main/Terraform.gitignore>
