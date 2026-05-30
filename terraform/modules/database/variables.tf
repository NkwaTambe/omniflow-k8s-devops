# Database Module Variables

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "OmniFlow"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the database security group"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "Security group ID of the EKS cluster — used as ingress source"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.1"
}

variable "engine_version_major" {
  description = "Major version of PostgreSQL (for parameter group family)"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "omniflow"
}

variable "username" {
  description = "Master username for the database"
  type        = string
  default     = "omniflow_admin"
}

variable "password" {
  description = "Master password for the database (sensitive — use tfvars)"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Whether to enable Multi-AZ deployment"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on deletion"
  type        = bool
  default     = false
}
