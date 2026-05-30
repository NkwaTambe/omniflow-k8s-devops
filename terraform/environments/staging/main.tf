# Staging Environment — Composes all infrastructure modules
# Apply with: terraform workspace select staging && terraform apply

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "omniflow-terraform-state"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "omniflow-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------

module "networking" {
  source = "../../modules/networking"

  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  environment          = var.environment
  project              = var.project
}

# ------------------------------------------------------------------------------
# Kubernetes
# ------------------------------------------------------------------------------

module "kubernetes" {
  source = "../../modules/kubernetes"

  environment        = var.environment
  project            = var.project
  region             = var.region
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.networking.vpc_id
  subnet_ids         = concat(module.networking.public_subnet_ids, module.networking.private_subnet_ids)
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_max_size      = var.node_max_size
  node_min_size      = var.node_min_size
  api_allowed_cidrs  = var.api_allowed_cidrs
}

# ------------------------------------------------------------------------------
# Database
# ------------------------------------------------------------------------------

module "database" {
  source = "../../modules/database"

  environment             = var.environment
  project                 = var.project
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  eks_security_group_id   = module.kubernetes.cluster_security_group_id
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  skip_final_snapshot     = var.db_skip_final_snapshot
}

# ------------------------------------------------------------------------------
# Storage
# ------------------------------------------------------------------------------

module "storage" {
  source = "../../modules/storage"

  environment = var.environment
  project     = var.project
}
