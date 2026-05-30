# Database Module — RDS PostgreSQL Instance
# Provisions a managed PostgreSQL database with security group restricting
# ingress to the EKS cluster security group only.

# ------------------------------------------------------------------------------
# DB Subnet Group (on private subnets)
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name        = "${var.project}-${var.environment}-db-subnet-group"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# Security Group — Allow ingress only from EKS SG on port 5432
# ------------------------------------------------------------------------------

resource "aws_security_group" "database" {
  name        = "${var.project}-${var.environment}-db-sg"
  description = "Security group for RDS PostgreSQL — ingress from EKS only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL access from EKS cluster"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-db-sg"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# RDS Parameter Group
# ------------------------------------------------------------------------------

resource "aws_db_parameter_group" "main" {
  family = "postgres${var.engine_version_major}"

  name = "${var.project}-${var.environment}-pg-params"

  tags = {
    Name        = "${var.project}-${var.environment}-pg-params"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# RDS PostgreSQL Instance
# ------------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier     = "${var.project}-${var.environment}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  password = var.password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az               = var.multi_az
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = var.skip_final_snapshot

  tags = {
    Name        = "${var.project}-${var.environment}-postgres"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
