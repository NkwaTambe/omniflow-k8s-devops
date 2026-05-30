# Storage Module Outputs

output "static_hosting_bucket_name" {
  description = "Name of the static website hosting S3 bucket"
  value       = aws_s3_bucket.static_hosting.id
}

output "static_hosting_bucket_arn" {
  description = "ARN of the static website hosting S3 bucket"
  value       = aws_s3_bucket.static_hosting.arn
}

output "static_hosting_website_endpoint" {
  description = "Website endpoint for the static hosting bucket"
  value       = aws_s3_bucket_website_configuration.static_hosting.website_endpoint
}

output "app_assets_bucket_name" {
  description = "Name of the application assets S3 bucket"
  value       = aws_s3_bucket.app_assets.id
}

output "app_assets_bucket_arn" {
  description = "ARN of the application assets S3 bucket"
  value       = aws_s3_bucket.app_assets.arn
}
