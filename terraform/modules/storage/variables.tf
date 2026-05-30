# Storage Module Variables

variable "project" {
  description = "Project name for resource tagging"
  type        = string
  default     = "OmniFlow"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
