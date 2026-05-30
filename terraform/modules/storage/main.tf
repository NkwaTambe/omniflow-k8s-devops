# Storage Module — Application-Level S3 Buckets
# This module manages ONLY application S3 buckets (static hosting + app assets).
# It does NOT create or manage the Terraform state bucket — that is owned
# exclusively by the bootstrap module.


# ------------------------------------------------------------------------------
# KMS Customer-Managed Keys
# ------------------------------------------------------------------------------

resource "aws_kms_key" "static_hosting" {
  description             = "CMK for ${var.project}-${var.environment} static hosting bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-static-hosting-key"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "static_hosting" {
  name          = "alias/${var.project}-${var.environment}-static-hosting"
  target_key_id = aws_kms_key.static_hosting.key_id
}

resource "aws_kms_key" "app_assets" {
  description             = "CMK for ${var.project}-${var.environment} app assets bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name        = "${var.project}-${var.environment}-app-assets-key"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "app_assets" {
  name          = "alias/${var.project}-${var.environment}-app-assets"
  target_key_id = aws_kms_key.app_assets.key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket — Static Website Hosting
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "static_hosting" {
  bucket = "${var.project}-${var.environment}-static-hosting"

  tags = {
    Name        = "${var.project}-${var.environment}-static-hosting"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "static-website"
  }
}

resource "aws_s3_bucket_versioning" "static_hosting" {
  bucket = aws_s3_bucket.static_hosting.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_hosting" {
  bucket = aws_s3_bucket.static_hosting.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_key_id    = aws_kms_key.static_hosting.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static_hosting" {
  bucket = aws_s3_bucket.static_hosting.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "static_hosting" {
  bucket = aws_s3_bucket.static_hosting.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_policy" "static_hosting" {
  bucket = aws_s3_bucket.static_hosting.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_hosting.arn}/*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# S3 Bucket — Application Assets
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "app_assets" {
  bucket = "${var.project}-${var.environment}-app-assets"

  tags = {
    Name        = "${var.project}-${var.environment}-app-assets"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "application-assets"
  }
}

resource "aws_s3_bucket_versioning" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_key_id    = aws_kms_key.app_assets.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
