# Preparación del entorno de trabajo con AWS (Windows)

Guía de los pasos y comandos para dejar un equipo Windows listo para trabajar con AWS y Terraform **de forma segura**, sin claves de acceso de larga duración.

> Todos los pasos están contrastados con la documentación oficial de AWS y HashiCorp (enlaces al final).

---

## Índice

1. [Reglas de seguridad (antes de nada)](#1-reglas-de-seguridad-antes-de-nada)
2. [Alarmas de presupuesto en AWS Budgets](#2-alarmas-de-presupuesto-en-aws-budgets)
3. [Instalar Terraform](#3-instalar-terraform)
4. [Instalar la AWS CLI](#4-instalar-la-aws-cli)
5. [Iniciar sesión en la CLI con `aws login`](#5-iniciar-sesión-en-la-cli-con-aws-login)
6. [Comprobar la identidad](#6-comprobar-la-identidad)
7. [Editor de código](#7-editor-de-código)
8. [Terraform y `aws login`: versión mínima del provider](#8-terraform-y-aws-login-versión-mínima-del-provider)
9. [Uso diario](#9-uso-diario)
10. [Problemas frecuentes](#10-problemas-frecuentes)
11. [Referencias oficiales](#11-referencias-oficiales)

---

## 1. Reglas de seguridad (antes de nada)

| Regla | Por qué |
|---|---|
| **No usar el usuario raíz** para el trabajo diario. Solo para tareas que lo exigen (por ejemplo, recuperar permisos o activar el acceso de IAM a la facturación). | El raíz tiene poder total sobre la cuenta. |
| **Trabajar con un usuario de IAM con MFA.** | Con MFA, una contraseña robada no basta para entrar en la consola. |
| **No crear claves de acceso de larga duración** (`AKIA…`). Usar `aws login`. | No caducan: si se filtran, funcionan hasta que alguien las desactive. AWS las marca como "no recomendadas". |
| **Nunca guardar credenciales en texto plano** (CSV, `.txt`, código, repositorios). | Un programa malicioso o un `git push` las expone. |
| **Nunca escribir credenciales en los ficheros `.tf`.** | La documentación del provider AWS lo desaconseja: se filtran en cuanto el código llega a un repositorio. |
| **Cambiar la contraseña no anula una clave de acceso.** | Son credenciales independientes: la clave solo se anula desactivándola o borrándola. |

---

## 2. Alarmas de presupuesto en AWS Budgets

Se hace **una vez**, desde la consola web, **antes de crear ningún recurso**.

1. Abrir la consola de Billing and Cost Management: <https://console.aws.amazon.com/cost-management/>
2. En el menú, **Budgets** → **Create budget**.
3. **Use a template (simplified)**.
4. Crear dos presupuestos:
   - **Zero spend budget**: avisa en cuanto aparece cualquier cargo.
   - **Monthly cost budget** con un importe pequeño (por ejemplo, **5 USD**): avisa si el gasto del mes supera, o se prevé que supere, ese importe.
5. Indicar el email para los avisos → **Create budget**.

> Los presupuestos que solo envían alertas no tienen coste.

> **Nota:** para ver la facturación con un usuario de IAM, el raíz debe activar antes, una sola vez: menú de la cuenta → **Account** → **IAM user and role access to Billing information** → **Edit** → **Activate IAM Access**.

---

## 3. Instalar Terraform

Instalación manual del ejecutable oficial.

1. Descargar el zip para Windows (**AMD64**) desde <https://developer.hashicorp.com/terraform/install>.
2. Crear la carpeta `C:\terraform` y poner dentro `terraform.exe` (el resto de ficheros del zip se pueden borrar).
3. Añadir la carpeta al **PATH**:
   - Menú Inicio → **"Editar las variables de entorno de esta cuenta"**.
   - En **Variables de usuario**, seleccionar **`Path`** → **Editar** → **Nuevo** → `C:\terraform` → **Aceptar** en todas las ventanas.

   > ⚠️ Hay que **editar la variable `Path`**, no crear una variable nueva. Windows solo busca programas en las carpetas que están dentro de `Path`.

4. Abrir una terminal **nueva** y comprobar:

```powershell
terraform version
```

Salida esperada (la versión puede variar):

```text
Terraform v1.17.1
on windows_amd64
```

---

## 4. Instalar la AWS CLI

1. Descargar y ejecutar el instalador MSI oficial:
   - Para todos los usuarios (requiere administrador): <https://awscli.amazonaws.com/AWSCLIV2.msi>
   - Solo para el usuario actual: <https://awscli.amazonaws.com/AWSCLIV2-User.msi>
2. Seguir el asistente con las opciones por defecto.
3. Abrir una terminal **nueva** y comprobar:

```powershell
aws --version
```

Salida esperada (la versión puede variar):

```text
aws-cli/2.39.7 Python/3.14.8 Windows/11 exe/AMD64
```

---

## 5. Iniciar sesión en la CLI con `aws login`

`aws login` usa las credenciales de la **consola** para generar **credenciales temporales**. La CLI las renueva automáticamente durante un máximo de **12 horas**; después hay que volver a ejecutar `aws login`. No hay claves guardadas en ningún fichero.

**Requisitos:**
- Un usuario de IAM (no el raíz) con acceso a la consola y **MFA**.
- Permisos adecuados: la política administrada `SignInLocalDevelopmentAccess`, o permisos de administrador.

**Pasos:**

1. **Cerrar en el navegador cualquier sesión del usuario raíz**, para no elegirla por error.
2. En una terminal:

```powershell
aws login
```

3. La primera vez pide la **región por defecto**. Escribir, por ejemplo:

```text
eu-west-1
```

4. Se abre el navegador: iniciar sesión **como usuario de IAM** (ID de cuenta, usuario, contraseña y MFA).
5. La terminal confirma:

```text
Updated profile default to use arn:aws:iam::<ID_DE_CUENTA>:user/<USUARIO> credentials.
```

6. Si pregunta *"Configure AWS skills and the AWS MCP server for your AI coding agent(s)?"*, responder `n`, salvo que se vaya a usar.

Para cambiar la región más adelante:

```powershell
aws configure set region <NUEVA_REGION>
```

---

## 6. Comprobar la identidad

Antes de crear nada, comprobar **con quién** está trabajando la CLI:

```powershell
aws sts get-caller-identity
```

Salida esperada:

```json
{
    "UserId": "AIDA...",
    "Account": "<ID_DE_CUENTA>",
    "Arn": "arn:aws:iam::<ID_DE_CUENTA>:user/<USUARIO>"
}
```

✅ El `Arn` debe terminar en `user/<USUARIO>`.
❌ Si termina en `:root`, la sesión es del usuario raíz: ejecutar `aws logout` y repetir el paso 5.

> El `UserId` que empieza por `AIDA` es el identificador del usuario de IAM, **no** una clave de acceso.

---

## 7. Editor de código

- **VS Code** con la extensión oficial **HashiCorp Terraform** (editor: HashiCorp): resaltado, autocompletado y avisos de errores en los `.tf`.
- Los ficheros de Terraform son **texto plano en UTF-8** con extensión `.tf`.

> ⚠️ El Bloc de notas puede guardar `versions.tf.txt` y el Explorador oculta la extensión. Terraform **ignora** ese fichero. Comprobar siempre el nombre real con `Get-ChildItem`.

---

## 8. Terraform y `aws login`: versión mínima del provider

El provider AWS de Terraform resuelve las credenciales con su propio SDK, no con la CLI. Las primeras versiones no reconocían el `login_session` que escribe `aws login`.

- Con **backend local**, el provider lee `aws login` de forma nativa desde la **6.23.0**, sin necesidad de `credential_process`.
- Por eso, en todos los proyectos, el bloque `terraform` lleva:

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

✅ **Verificado el 12/11/2026:** `terraform plan` con el provider 6.73.0 y credenciales de `aws login`, sin ninguna configuración adicional.

> Si en el futuro se usa un **backend S3** para el estado, hace falta además **Terraform ≥ 1.15** (el backend usa el SDK del binario de Terraform, no el del provider).

---

## 9. Uso diario

| Situación | Comando |
|---|---|
| Empezar a trabajar (o las credenciales han caducado) | `aws login` |
| Comprobar con quién trabaja la CLI | `aws sts get-caller-identity` |
| Terminar la sesión y borrar las credenciales temporales | `aws logout` |
| Ver la versión de Terraform | `terraform version` |
| Ver la ayuda de Terraform | `terraform -help` |

---

## 10. Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `terraform` o `aws` "no se reconoce como comando" | La terminal se abrió antes de cambiar el `Path`, o la carpeta no está en `Path`. | Cerrar y abrir una terminal nueva. Revisar que la carpeta está **dentro** de la variable `Path`. |
| "La sesión ha expirado" / credenciales caducadas | Han pasado más de 12 horas desde el último `aws login`. | Ejecutar `aws login` y comprobar con `aws sts get-caller-identity`. |
| `aws sts get-caller-identity` funciona, pero `terraform plan` dice `no valid credential sources` | Provider AWS anterior a la 6.23.0, que no lee `aws login`. | Poner `version = "~> 6.23"` y ejecutar `terraform init -upgrade`. Ver [paso 8](#8-terraform-y-aws-login-versión-mínima-del-provider). |
| Terraform no "ve" un fichero `.tf` | El fichero se guardó como `.tf.txt`. | Comprobar con `Get-ChildItem` y renombrarlo. |
| La consola dice "no tienes permisos" en todo | El usuario de IAM no tiene políticas (por ejemplo, se ha sacado del grupo de administradores). | Entrar como raíz y volver a añadir el usuario a su grupo. |
| Billing dice "You need permissions" | Falta activar el acceso de IAM a la facturación. | Ver la nota del [paso 2](#2-alarmas-de-presupuesto-en-aws-budgets). |
| El usuario de IAM no puede cambiar su contraseña | La política de contraseñas no lo permite. | Hacerlo con el raíz (IAM → Users → usuario → Security credentials → Manage console access), o activar **Allow users to change their own password** en IAM → Account settings. |
| Alguna otra herramienta no reconoce las credenciales de `aws login` | Versiones antiguas de algunos SDK o herramientas todavía no admiten las credenciales de la consola. | Usar el método de *credential process* que describe la documentación de `aws login`. |

---

## 11. Referencias oficiales

- AWS CLI – Instalación en Windows: <https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html>
- AWS CLI – `aws login` (credenciales de la consola): <https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html>
- AWS CLI – Autenticación y credenciales: <https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html>
- AWS SDKs – Login credentials provider: <https://docs.aws.amazon.com/sdkref/latest/guide/feature-login-credentials.html>
- AWS Budgets – Plantillas: <https://docs.aws.amazon.com/cost-management/latest/userguide/budget-templates.html>
- IAM – Alias e ID de cuenta: <https://docs.aws.amazon.com/IAM/latest/UserGuide/console-account-alias.html>
- IAM – Cambio de contraseña de los usuarios: <https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_passwords_enable-user-change.html>
- Terraform – Instalación: <https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli>
- Terraform – Requisitos de providers: <https://developer.hashicorp.com/terraform/language/providers/requirements>
- Terraform – Provider AWS (autenticación): <https://registry.terraform.io/providers/hashicorp/aws/latest/docs>
- Soporte nativo de `aws login` en el provider (artículo técnico, no oficial): <https://dev.classmethod.jp/en/articles/aws-login-default-profile-credential-process-error/>
