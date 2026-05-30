# OmniFlow Infrastructure as Code — Terraform

This directory contains the complete Terraform configuration for provisioning the OmniFlow platform on AWS. It follows a modular architecture with environment-specific compositions.

## Architecture Overview

```
terraform/
├── bootstrap/              # State backend (S3 + DynamoDB) — apply FIRST
├── modules/
│   ├── networking/         # VPC, subnets, IGW, NAT, route tables
│   ├── kubernetes/         # EKS cluster, node groups, IAM roles
│   ├── database/           # RDS PostgreSQL, subnet group, security group
│   └── storage/            # Application S3 buckets (static hosting + assets)
└── environments/
    ├── dev/                # Dev workspace composition
    ├── staging/            # Staging workspace composition
    └── prod/               # Prod workspace composition
```

## Bootstrap-First Apply Sequence

The S3 backend and DynamoDB lock table **must exist** before any environment configs can use them as a remote backend. Follow this sequence:

### 1. Bootstrap the State Backend

```bash
cd terraform/bootstrap

# First apply uses local state (backend.tf is commented out)
terraform init
terraform apply -var="state_bucket_name=omniflow-terraform-state" -var="lock_table_name=omniflow-terraform-locks"

# After the S3 bucket and DynamoDB table exist, uncomment the backend block
# in backend.tf, then migrate state to S3:
terraform init -migrate-state
```

### 2. Create Terraform Workspaces

Each environment uses its own workspace to isolate state:

```bash
cd terraform/environments/dev
terraform init
terraform workspace new dev

cd ../staging
terraform init
terraform workspace new staging

cd ../prod
terraform init
terraform workspace new prod
```

### 3. Apply Environments

```bash
# Dev
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values (passwords, etc.)
terraform plan
terraform apply

# Staging
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform plan
terraform apply

# Prod
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform plan
terraform apply
```

## Module Scope Boundaries

| Module | Owns | Does NOT own |
|--------|------|--------------|
| **bootstrap** | S3 state bucket, DynamoDB lock table | Application buckets |
| **storage** | Static hosting bucket, app assets bucket | Terraform state bucket |
| **networking** | VPC, subnets, gateways, route tables | Compute or database resources |
| **kubernetes** | EKS cluster, node group, IAM roles, SG | Database or storage |
| **database** | RDS instance, subnet group, SG | Cluster or storage |

**Important**: The bootstrap and storage modules have a strict boundary. The bootstrap module exclusively owns the Terraform state S3 bucket and DynamoDB lock table. The storage module exclusively owns application-level S3 buckets. These boundaries must never overlap.

## Environment Scaling Differences

| Parameter | Dev | Staging | Prod |
|-----------|-----|---------|------|
| AZs | 1 | 2 | 3 |
| NAT Gateways | 1 (~$32/mo) | 2 (~$64/mo) | 3 (~$96/mo) |
| EKS Nodes | t3.small × 1 | t3.medium × 2 | t3.large × 3 |
| Max EKS Nodes | 2 | 4 | 10 |
| DB Instance | db.t3.small | db.t3.medium | db.r6g.large |
| DB Multi-AZ | No | Yes | Yes |
| DB Storage | 20 GB | 50 GB | 100 GB |
| Backup Retention | 1 day | 7 days | 30 days |

## Idempotency Verification

Terraform is idempotent by design — running `terraform apply` multiple times produces the same result. To verify:

```bash
# After an initial apply, run plan again — it should show "No changes"
terraform plan

# Run plan multiple times to confirm stability
terraform plan && terraform plan && terraform plan

# Expected output: "No changes. Your infrastructure matches the configuration."
```

## Security Notes

- `*.tfvars` is gitignored — never commit real secrets
- Use `terraform.tfvars.example` files as templates with placeholder values
- All S3 buckets have server-side encryption (SSE-KMS) enabled
- The state bucket has public access fully blocked
- The database security group allows ingress only from the EKS cluster SG on port 5432
- RDS storage encryption is enabled

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- AWS account with permissions for VPC, EKS, RDS, S3, DynamoDB, IAM
