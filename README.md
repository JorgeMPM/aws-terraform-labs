# AWS Terraform Labs

Hands-on labs to learn **Infrastructure as Code with Terraform on AWS**, step by step.

Each lab creates real AWS resources, inspects them, and destroys them. Every lab is documented with the commands used, the expected output and the concepts behind them.

---

## Labs

| # | Lab | What it covers | Status |
|---|---|---|---|
| 01 | [S3 bucket](01-s3/) | Provider and version constraints, lock file, resources, `plan` / `apply` / `destroy`, Terraform state, S3 secure defaults (encryption, Block Public Access) | ✅ Done |
| 02 | [Variables, outputs and locals](02-variables/) | Input variables, `terraform.tfvars` and precedence, outputs, locals for shared tags, `.tfvars.example` template | ✅ Done |
| 03 | [VPC networking](03-vpc/) | VPC across two AZs, public and private subnets, Internet Gateway, route tables and associations, implicit dependencies, network outputs | ✅ Done |
| 04 | [Security groups and RDS](04-rds/) | Security group referencing another security group, DB subnet group, encrypted RDS MySQL 8.4 in private subnets, master password managed in Secrets Manager (not in state) | ✅ Done |
| 05 | [Docker image and ECR](05-ecr/) | Multi-stage Dockerfile, layer caching, private ECR repository with immutable tags and scan on push, pushing the API image, fixing a CRITICAL CVE found by the scan | ✅ Done |

More labs will be added as the project grows toward deploying a Spring Boot API on AWS (VPC, ECS Fargate, RDS, load balancer, CI/CD).

---

## Tech stack

| Tool | Version |
|---|---|
| Terraform | >= 1.15 |
| AWS provider (`hashicorp/aws`) | ~> 6.23 |
| AWS CLI | v2 |
| AWS region | `eu-west-1` (Ireland) |

---

## Security practices

- **No long-term access keys.** Short-term credentials only, with `aws login` (IAM user with MFA, never the root user).
- **No credentials in code.** The AWS provider reads the credentials from the local AWS CLI session.
- **No state in Git.** `terraform.tfstate` and `.terraform/` are excluded by [`.gitignore`](.gitignore). The dependency lock file (`.terraform.lock.hcl`) is committed so everyone uses the same provider version.
- **Cost control.** AWS Budgets zero-spend alert, and every lab ends with `terraform destroy`.

---

## How to run a lab

Requirements: Terraform, AWS CLI v2 and an AWS account (see [docs/SETUP.md](docs/SETUP.md)).

```bash
aws login                      # short-term credentials
aws sts get-caller-identity    # check who you are working as

cd 01-s3
terraform init
terraform plan
terraform apply
terraform destroy              # always clean up
```

> S3 bucket names are globally unique: change the `bucket` value in `01-s3/main.tf` before running `apply`. From lab 02 on, copy `terraform.tfvars.example` to `terraform.tfvars` and set your own values instead.

---

## Documentation (in Spanish)

- [Environment setup](docs/SETUP.md): Terraform, AWS CLI, `aws login`, budgets and troubleshooting.
- [Lab 01: S3 bucket](docs/01-s3.md): code explained, commands, expected outputs and key concepts.
- [Lab 02: variables, outputs and locals](docs/02-variables.md): parameterising the configuration, value precedence and reusable tags.
- [Lab 03: VPC networking](docs/03-vpc.md): what makes a subnet public or private, route tables and network design for the API.
- [Lab 04: security groups and RDS](docs/04-rds.md): least-privilege database access, stateful security groups, Secrets Manager and lab vs production settings.
- [Lab 05: Docker image and ECR](docs/05-ecr.md): multi-stage builds, pushing to ECR and a real vulnerability workflow (detect, analyse, fix, verify, version).

---

## Author

**Jorge Martín Pérez Moreno**, Junior Software Developer

[LinkedIn](https://www.linkedin.com/in/jorge-martin-perez-moreno) · [Portfolio](https://jorge-martin-dev.netlify.app/)
