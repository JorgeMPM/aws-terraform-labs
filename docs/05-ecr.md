# Lab 05: imagen Docker de la API y Amazon ECR

Construir la imagen Docker de [`library-management-api`](https://github.com/JorgeMPM/library-management-api), crear con Terraform un repositorio privado en **Amazon ECR**, subir la imagen y **revisar sus vulnerabilidades** con el escaneo de ECR.

> Requisitos: entorno según [SETUP.md](SETUP.md) (`aws login`), **Docker Desktop** arrancado y una copia local de `library-management-api`.

---

## Índice

1. [Qué se construye](#1-qué-se-construye)
2. [Docker: cliente y motor](#2-docker-cliente-y-motor)
3. [El Dockerfile multi-stage](#3-el-dockerfile-multi-stage)
4. [Construir la imagen](#4-construir-la-imagen)
5. [Repositorio ECR con Terraform](#5-repositorio-ecr-con-terraform)
6. [Subir la imagen](#6-subir-la-imagen)
7. [Qué hay en el repositorio: índice, imagen y atestación](#7-qué-hay-en-el-repositorio-índice-imagen-y-atestación)
8. [Caso real: vulnerabilidad CRITICAL en zlib](#8-caso-real-vulnerabilidad-critical-en-zlib)
9. [Destruir](#9-destruir)
10. [Coste](#10-coste)
11. [Errores que evitar](#11-errores-que-evitar)
12. [Referencias oficiales](#12-referencias-oficiales)

---

## 1. Qué se construye

```text
Tu PC                                         AWS (eu-west-1)
──────                                        ───────────────
library-management-api
   │ docker build
   ▼
imagen local  ── docker tag + docker push ──▶  Amazon ECR (privado)
library-management-api:1.0.1                   aws-terraform-labs/library-management-api
                                                  │  escaneo de vulnerabilidades al subir
                                                  ▼
                                               [lab 06] ECS Fargate descarga la imagen
```

| Pieza | Qué es |
|---|---|
| **Imagen** | Paquete con todo lo necesario para ejecutar la API: sistema base, Java y el `.jar` |
| **Amazon ECR** | Registro **privado** de imágenes en tu cuenta de AWS |
| **Repositorio** | Donde se guardan las versiones (*tags*) de una imagen |

- ECR es **regional** y **no vive en una VPC**: este lab no necesita red.
- Terraform crea el **repositorio**; la **imagen** se sube con Docker. Terraform gestiona infraestructura, no los artefactos de la aplicación.

---

## 2. Docker: cliente y motor

Docker usa una arquitectura **cliente-servidor**:

| Pieza | Qué es |
|---|---|
| **Cliente** (`docker`) | Donde se escriben los comandos. Solo envía órdenes |
| **Motor** (*daemon*) | Construye imágenes, ejecuta contenedores, sube y descarga imágenes |

En Windows, Docker Desktop ejecuta el motor dentro de una pequeña máquina virtual **Linux** (WSL 2), porque las imágenes son de Linux.

```bash
docker version
```

- Debe aparecer `Client:` **y** `Server: Docker Desktop`.
- Si solo sale `Client:` y un error `failed to connect to the docker API at npipe:...dockerDesktopLinuxEngine` → **el motor no está arrancado**: abrir Docker Desktop y esperar a *Engine running*.
- En `Server` → `OS/Arch: linux/amd64`: las imágenes construidas aquí son **`linux/amd64`**. En el lab 06, Fargate tendrá que usar esa misma arquitectura.

---

## 3. El Dockerfile multi-stage

`Dockerfile` de `library-management-api`:

```dockerfile
# Etapa 1: compilación con Maven y Java 21
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# Etapa 2: ejecución con solo el JRE de Java 21
FROM eclipse-temurin:21-jre-alpine
RUN apk upgrade --no-cache zlib
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-Dspring.profiles.active=docker", "-jar", "app.jar"]
```

> La línea `RUN apk upgrade --no-cache zlib` se añadió durante este lab (ver [sección 8](#8-caso-real-vulnerabilidad-critical-en-zlib)).

### Dos etapas (*multi-stage build*)

Cada `FROM` empieza una etapa. Solo la **última** forma la imagen final; de la primera se copia únicamente el `.jar`.

| | Etapa 1: `build` | Etapa 2: imagen final |
|---|---|---|
| Base | `maven:3.9-eclipse-temurin-21` (Maven + JDK) | `eclipse-temurin:21-jre-alpine` (solo JRE, Alpine Linux) |
| Para qué | Compilar y generar el `.jar` | Ejecutar el `.jar` |
| ¿Se sube a ECR? | No | **Sí** |

**Ventajas de no llevar Maven, el JDK ni el código fuente en la imagen final:**
1. **Tamaño:** subida a ECR y descarga en Fargate más rápidas; menos coste de almacenamiento.
2. **Seguridad:** menos software = menos vulnerabilidades posibles (**menor superficie de ataque**), y el código fuente no viaja en la imagen.

### Etapa 1, línea a línea

| Línea | Qué hace |
|---|---|
| `FROM maven:3.9-eclipse-temurin-21 AS build` | Base con Maven y JDK 21; `AS build` da nombre a la etapa |
| `WORKDIR /app` | Carpeta de trabajo dentro de la imagen (como un `cd`) |
| `COPY pom.xml .` | Copia solo el `pom.xml` |
| `RUN mvn dependency:go-offline -B` | Descarga todas las dependencias (`-B`: modo sin interacción) |
| `COPY src ./src` | Copia el código fuente |
| `RUN mvn package -DskipTests -B` | Compila y genera el `.jar` sin ejecutar los tests |

**Caché de capas:** cada instrucción crea una capa, y Docker reutiliza las que no han cambiado. Si una capa cambia, **todas las de debajo** se vuelven a ejecutar. Por eso se copia el `pom.xml` **antes** que el código:

| Si solo cambia una clase Java… | ¿Caché? |
|---|---|
| `FROM`, `WORKDIR`, `COPY pom.xml`, `RUN mvn dependency:go-offline` | ✅ Reutilizados (la descarga lenta no se repite) |
| `COPY src`, `RUN mvn package` | ❌ Se vuelven a ejecutar |

> `-DskipTests` acelera la construcción, pero entonces los tests deben ejecutarse en otro sitio: en el CI/CD (lab 08), antes de construir la imagen.

### Etapa 2, línea a línea

| Línea | Qué hace |
|---|---|
| `FROM eclipse-temurin:21-jre-alpine` | Empieza de cero con solo el JRE 21 sobre Alpine |
| `RUN apk upgrade --no-cache zlib` | Actualiza el paquete `zlib` (corrección de seguridad) |
| `WORKDIR /app` | Carpeta de trabajo |
| `COPY --from=build /app/target/*.jar app.jar` | Trae **solo** el `.jar` de la etapa `build` |
| `EXPOSE 8080` | **Documenta** el puerto de la aplicación. No lo abre |
| `ENTRYPOINT [...]` | Comando al arrancar el contenedor; activa el perfil de Spring `docker` |

### `EXPOSE` no publica el puerto

Cada contenedor tiene su propia red aislada. Para acceder desde fuera hay que **publicar** el puerto:

```bash
docker run -p 8080:8080 library-management-api:1.0.1
#             ▲    ▲
#             │    └── puerto dentro del contenedor
#             └─────── puerto en el PC
```

En ECS (lab 06) el equivalente es el `portMappings` de la definición de tarea.

> El perfil `docker` lee la conexión a MySQL de `application-docker.properties`. En AWS, la base de datos será la RDS del lab 04: los datos de conexión se pasarán **desde fuera** (variables de entorno y Secrets Manager) en el lab 06.

**Mejora pendiente:** el contenedor arranca como `root` (comportamiento por defecto). Conviene añadir un usuario sin privilegios con `USER`.

---

## 4. Construir la imagen

En la carpeta de `library-management-api`:

```bash
docker build --pull -t library-management-api:1.0.1 .
docker images library-management-api
```

| Parte | Significado |
|---|---|
| `-t nombre:versión` | Nombre y etiqueta de la imagen (sin versión → `latest`) |
| `.` | Contexto: carpeta de donde `COPY` toma los ficheros |
| `--pull` | Vuelve a descargar las imágenes base aunque estén en caché |

| Comando | ¿Importa la carpeta? |
|---|---|
| `docker build ... .` | **Sí**: la del proyecto (`Dockerfile`, `pom.xml`, `src/`) |
| `docker run`, `docker images`, `docker push` | No: usan imágenes guardadas en el motor |

### Comparación de tamaños

Con `--target build` se construye solo la etapa 1, como si el Dockerfile tuviera una sola etapa:

```bash
docker build --target build -t library-build-stage .
docker images library-build-stage
docker rmi library-build-stage
```

| Imagen | `CONTENT SIZE` (lo que se sube) | `DISK USAGE` (descomprimida) |
|---|---|---|
| Una sola etapa (Maven + JDK + dependencias + código) | 430 MB | 1,22 GB |
| **Multi-stage (imagen final)** | **137 MB** | 422 MB |

→ La imagen final es **unas 3 veces más pequeña**.

> `docker images maven` no muestra la imagen base de la etapa 1: BuildKit la guarda en su caché de construcción, no como imagen con nombre.

### Inspeccionar una imagen sin arrancar la aplicación

```bash
docker run --rm --entrypoint sh library-management-api:1.0.1 -c "apk list -I zlib"
```

| Parte | Qué hace |
|---|---|
| `--rm` | Borra el contenedor al terminar |
| `--entrypoint sh` | Sustituye el `ENTRYPOINT` (Java) por una terminal |
| `apk list -I zlib` | Versión **instalada** de `zlib` (gestor de paquetes de Alpine) |

---

## 5. Repositorio ECR con Terraform

### Estructura

```text
05-ecr/
├── versions.tf           # Copiado del lab 03
├── providers.tf          # Copiado del lab 03
├── .terraform.lock.hcl   # Copiado del lab 03 → SÍ a Git
├── variables.tf          # Del lab 03, sin vpc_cidr (aws_region, project_name)
├── locals.tf             # Del lab 03, con Lab = "05-ecr"
├── main.tf               # Repositorio ECR
└── outputs.tf            # URL del repositorio
```

### `main.tf`

```hcl
resource "aws_ecr_repository" "api" {
  name                 = "${var.project_name}/library-management-api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-library-management-api"
  })
}
```

| Argumento | Qué hace | Por qué |
|---|---|---|
| `name` | Nombre; la `/` agrupa repositorios | `aws-terraform-labs/library-management-api` |
| `image_tag_mutability = "IMMUTABLE"` | Una etiqueta (`1.0.0`) no se puede sobrescribir | Una versión siempre es la misma imagen; cada cambio = versión nueva |
| `force_delete = true` | Permite borrar el repositorio con imágenes dentro | Solo para el lab (si no, `destroy` falla) |
| `image_scanning_configuration` | Escanea cada imagen al subirla | Detectar vulnerabilidades sin coste extra (escaneo básico) |

> `image_scanning_configuration { ... }` va **sin `=`**: es un **bloque anidado**. `tags = { ... }` lleva `=` porque es un argumento (un mapa).

> **Examen:** el escaneo **básico** de ECR revisa los paquetes del **sistema operativo** de la imagen. El escaneo **mejorado** lo hace **Amazon Inspector** (también revisa librerías de la aplicación).

### `outputs.tf`

```hcl
output "repository_url" {
  description = "ECR repository URL to tag and push the image"
  value       = aws_ecr_repository.api.repository_url
}
```

```bash
terraform init
terraform plan     # 1 to add
terraform apply    # yes
```

Resultado:

```text
repository_url = "<ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/aws-terraform-labs/library-management-api"
```

```text
<ACCOUNT_ID> . dkr.ecr.eu-west-1.amazonaws.com / aws-terraform-labs/library-management-api
└─ cuenta ─┘   └────────── registro ──────────┘   └────────────── repositorio ─────────┘
```

---

## 6. Subir la imagen

### 6.1. Autenticar Docker ante ECR

```bash
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com
```

| Parte | Qué hace |
|---|---|
| `aws ecr get-login-password` | Token temporal (válido **12 horas**) a partir de la sesión de `aws login` |
| `\|` | Pasa la salida del primer comando como entrada del segundo |
| `--username AWS` | Siempre literalmente `AWS` |
| `--password-stdin` | Lee la contraseña de la entrada: no queda en el historial |
| URL | El **registro** (sin el repositorio) |

Resultado esperado: `Login Succeeded`.

### 6.2. Etiquetar y subir

```bash
docker tag library-management-api:1.0.1 <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/aws-terraform-labs/library-management-api:1.0.1
docker push <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/aws-terraform-labs/library-management-api:1.0.1
```

- `docker tag` crea un **alias** (mismo `ID`, no ocupa más). Docker decide adónde subir una imagen **por su nombre**.
- `docker push` sube capa a capa. Las capas que ya existen en ECR (`Layer already exists`) no se vuelven a subir.
- Al final muestra un `digest: sha256:...`: la huella única del contenido.

---

## 7. Qué hay en el repositorio: índice, imagen y atestación

```bash
docker buildx imagetools inspect <ACCOUNT_ID>.dkr.ecr.eu-west-1.amazonaws.com/aws-terraform-labs/library-management-api:1.0.1
```

| Elemento | Plataforma | Qué es |
|---|---|---|
| **Índice** (`image.index`) | — | Lleva la etiqueta `1.0.1` y apunta a los otros dos |
| **Imagen** | `linux/amd64` | La imagen real (~137 MB): esta es la que se ejecuta y se escanea |
| **Atestación** | `unknown/unknown` | Documento que describe **cómo** se construyó la imagen (procedencia). BuildKit lo añade por defecto |

> `aws ecr describe-images` muestra las tres entradas. Solo el índice lleva la etiqueta.

---

## 8. Caso real: vulnerabilidad CRITICAL en zlib

### 8.1. Detectar

El escaneo se hace sobre la **imagen** (`linux/amd64`), no sobre el índice. Consultar por etiqueta da `ScanNotFoundException`, porque la etiqueta apunta al índice:

```bash
# Recuento por gravedad (usar el digest de la imagen linux/amd64)
aws ecr describe-image-scan-findings \
  --repository-name aws-terraform-labs/library-management-api \
  --image-id imageDigest=sha256:<DIGEST_IMAGEN_AMD64> \
  --region eu-west-1 \
  --query "imageScanFindings.findingSeverityCounts"

# Detalle: CVE, gravedad, paquete y versión
aws ecr describe-image-scan-findings \
  --repository-name aws-terraform-labs/library-management-api \
  --image-id imageDigest=sha256:<DIGEST_IMAGEN_AMD64> \
  --region eu-west-1 \
  --query "imageScanFindings.findings[].{cve:name,gravedad:severity,paquete:attributes[?key=='package_name'].value|[0],version:attributes[?key=='package_version'].value|[0]}"
```

Resultado en la versión `1.0.0`:

| CVE | Gravedad | Paquete | Versión |
|---|---|---|---|
| CVE-2026-4738 | **CRITICAL** | zlib | 1.3.2-r1 |

### 8.2. Analizar

- Fallo de memoria en el módulo **opcional** `contrib/infback9` de zlib (`inftree9.c`). Afecta a zlib ≤ 1.3.2; **corregido en zlib 1.4** (publicada el 4–5 de noviembre de 2026).
- El mantenedor de zlib relativiza la gravedad práctica, y la probabilidad estimada de explotación es baja.
- Viene de la **imagen base** (`eclipse-temurin:21-jre-alpine`), no del código de la API. El escáner la detecta por la versión del paquete.
- Conclusión: riesgo real bajo, pero se corrige en lugar de ignorarse.

### 8.3. Corregir

1. **Intento 1:** `docker build --pull` → el resultado era **idéntico** (mismo digest): la imagen base aún no se había actualizado.
2. **Comprobar si Alpine ya tiene la corrección:**

   ```bash
   docker run --rm --entrypoint sh library-management-api:1.0.1 -c "apk update > /dev/null; apk list -u"
   # zlib-1.4-r0 x86_64 {zlib} (Zlib) [upgradable from: zlib-1.3.2-r1]
   ```

3. **Intento 2:** añadir al Dockerfile, en la etapa 2:

   ```dockerfile
   RUN apk upgrade --no-cache zlib
   ```

   Se actualiza **solo** el paquete vulnerable (cambio controlado y predecible). Cuando la imagen base incluya zlib 1.4, esta línea se puede quitar.

### 8.4. Verificar

```bash
docker run --rm --entrypoint sh library-management-api:1.0.1 -c "apk list -I zlib"
# zlib-1.4-r0 x86_64 {zlib} (Zlib) [installed]
```

Tras subir la `1.0.1`:

```bash
aws ecr describe-image-scan-findings \
  --repository-name aws-terraform-labs/library-management-api \
  --image-id imageDigest=sha256:<DIGEST_IMAGEN_AMD64> \
  --region eu-west-1 \
  --query "{estado:imageScanStatus.status,hallazgos:length(imageScanFindings.findings)}"
# { "estado": "COMPLETE", "hallazgos": 0 }
```

### 8.5. Versionar

- Como el repositorio es **`IMMUTABLE`**, la imagen corregida es la **`1.0.1`**: la `1.0.0` no se puede sobrescribir.
- El cambio del Dockerfile se integró en `library-management-api` con una rama `fix/zlib-cve-2026-4738` y un PR (*squash and merge*).

| Fase | Qué se hizo |
|---|---|
| Detectar | Escaneo de ECR al subir: 1 CRITICAL |
| Analizar | Paquete, origen (imagen base) y riesgo real |
| Corregir | `--pull` no bastaba → actualizar `zlib` en el Dockerfile |
| Verificar | `zlib-1.4-r0` en la imagen y 0 hallazgos en ECR |
| Versionar | Nueva etiqueta `1.0.1` + PR en el repo de la aplicación |

---

## 9. Destruir

```bash
terraform destroy    # 1 destroyed
```

Con `force_delete = true` se borra el repositorio con sus imágenes. En el lab 06 se vuelve a crear y se sube la `1.0.1`.

Limpieza local opcional:

```bash
docker image prune
```

---

## 10. Coste

| Concepto | Coste |
|---|---|
| Repositorio ECR vacío | Sin coste |
| Almacenamiento de imágenes | Por GB al mes: ~137 MB → céntimos |
| Escaneo básico | Sin coste extra |
| Transferencia de subida a ECR | Sin coste |

---

## 11. Errores que evitar

| Error | Consecuencia | Cómo evitarlo |
|---|---|---|
| Docker Desktop cerrado | `failed to connect to the docker API ... dockerDesktopLinuxEngine` | Abrir Docker Desktop y esperar a *Engine running* |
| `docker build` fuera de la carpeta del proyecto | No encuentra el `Dockerfile` | `cd` a la carpeta del proyecto |
| `docker run` de la API sin base de datos | La API falla al arrancar | Se prueba conectada a la RDS en el lab 06 |
| Esperar que `EXPOSE` abra el puerto | No se puede acceder | `-p` en local; `portMappings` en ECS |
| `docker push` sin `docker login` en ECR | Error de autenticación | `aws ecr get-login-password \| docker login ...` (el token dura 12 h) |
| Volver a subir una etiqueta existente | Rechazado (repositorio `IMMUTABLE`) | Nueva versión (`1.0.1`) |
| Consultar el escaneo por etiqueta | `ScanNotFoundException` (la etiqueta apunta al índice) | Usar el digest de la imagen `linux/amd64` |
| Fiarse solo de `--pull` para corregir una CVE | La base puede no estar actualizada todavía | Comprobar con `apk list -u` y actualizar el paquete |
| Error `Failed to initialize ... meta.json ... utilizado por otro proceso` | Bloqueo momentáneo de Windows | Repetir el comando; si persiste, reiniciar Docker Desktop |
| Publicar el ID de cuenta en la documentación | Información innecesaria expuesta | Usar `<ACCOUNT_ID>` |

---

## 12. Referencias oficiales

- Docker – Arquitectura (cliente y motor): <https://docs.docker.com/get-started/docker-overview/#docker-architecture>
- Docker – Multi-stage builds: <https://docs.docker.com/build/building/multi-stage/>
- Docker – Caché de construcción: <https://docs.docker.com/build/cache/>
- Docker – Referencia del Dockerfile (`EXPOSE`, `ENTRYPOINT`): <https://docs.docker.com/reference/dockerfile/>
- Docker – Atestaciones de procedencia: <https://docs.docker.com/build/metadata/attestations/slsa-provenance/>
- Amazon ECR – Autenticación del registro: <https://docs.aws.amazon.com/AmazonECR/latest/userguide/registry_auth.html>
- Amazon ECR – Subir una imagen: <https://docs.aws.amazon.com/AmazonECR/latest/userguide/docker-push-ecr-image.html>
- Amazon ECR – Inmutabilidad de etiquetas: <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html>
- Amazon ECR – Escaneo de imágenes: <https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html>
- Terraform – `aws_ecr_repository`: <https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository>
- zlib 1.4 (anuncio en oss-security): <https://www.openwall.com/lists/oss-security/2026/11/05/10>
