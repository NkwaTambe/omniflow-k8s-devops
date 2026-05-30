# Backend Configuration
#
# On the FIRST apply, this file should remain commented out (local state).
# After the S3 bucket and DynamoDB table exist, uncomment and run:
#   terraform init -migrate-state
#
# terraform {
#   backend "s3" {
#     bucket         = "omniflow-terraform-state"
#     key            = "bootstrap/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "omniflow-terraform-locks"
#     encrypt        = true
#   }
# }
