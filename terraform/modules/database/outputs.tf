# Database Module Outputs

output "db_instance_endpoint" {
  description = "Endpoint of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_arn" {
  description = "ARN of the RDS PostgreSQL instance"
  value       = aws_db_instance.main.arn
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.main.db_name
}

output "db_security_group_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}
