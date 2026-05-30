# Bootstrap Variables

variable "state_bucket_name" {
  description = "Globally unique name for the S3 bucket storing Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
  default     = "omniflow-terraform-locks"
}

variable "region" {
  description = "AWS region for the bootstrap resources"
  type        = string
  default     = "us-east-1"
}
