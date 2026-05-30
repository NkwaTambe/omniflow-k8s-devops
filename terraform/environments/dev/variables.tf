# Dev Environment Variables

variable "region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "OmniFlow"
}

# Networking
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

# Kubernetes
variable "kubernetes_version" {
  description = "Kubernetes version for EKS"
  type        = string
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
}

variable "node_desired_size" {
  description = "Desired number of EKS nodes"
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of EKS nodes"
  type        = number
}

variable "node_min_size" {
  description = "Minimum number of EKS nodes"
  type        = number
}

variable "api_allowed_cidrs" {
  description = "CIDR blocks allowed to access EKS API"
  type        = list(string)
}

# Database
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database master username"
  type        = string
}

variable "db_password" {
  description = "Database master password (sensitive)"
  type        = string
  sensitive   = true
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for DB"
  type        = bool
}

variable "db_backup_retention_period" {
  description = "Backup retention in days"
  type        = number
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot on deletion"
  type        = bool
}
