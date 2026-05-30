# Bootstrap — Terraform State Backend Infrastructure
# This is the ONLY config that manages the TF state bucket and lock table.
# Apply this FIRST with local state, then migrate to the S3 backend.
# Do NOT overlap with the storage module (application-level buckets).

# ------------------------------------------------------------------------------
# KMS Customer-Managed Key for State Bucket Encryption
# ------------------------------------------------------------------------------

resource "aws_kms_key" "terraform_state" {
  description             = "CMK for Terraform state bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Project     = "OmniFlow"
    Environment = "management"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/omniflow-terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket for Terraform State
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = {
    Project     = "OmniFlow"
    Environment = "management"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_key_id    = aws_kms_key.terraform_state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# DynamoDB Table for State Locking
# ------------------------------------------------------------------------------

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project     = "OmniFlow"
    Environment = "management"
    ManagedBy   = "terraform"
  }
}
