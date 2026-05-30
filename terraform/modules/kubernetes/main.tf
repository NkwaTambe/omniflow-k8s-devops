# Kubernetes Module — EKS Cluster, Node Group, IAM Roles, Security Group
# Provisions a managed EKS cluster with configurable k8s version and node scaling.

# ------------------------------------------------------------------------------
# IAM Role for EKS Cluster
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project}-${var.environment}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_amazon_eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

# ------------------------------------------------------------------------------
# IAM Role for EKS Node Group
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-${var.environment}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "node_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_amazon_ec2_container_registry_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# ------------------------------------------------------------------------------
# Security Group for EKS Cluster
# ------------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.project}-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster API and inter-node communication"
  vpc_id      = var.vpc_id

  # Allow API server access from anywhere (restrict in production)
  ingress {
    description = "API server access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.api_allowed_cidrs
  }

  # Allow inter-node communication
  ingress {
    description     = "Inter-node communication"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    self            = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-${var.environment}-eks-cluster-sg"
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# EKS Cluster
# ------------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = "${var.project}-${var.environment}-cluster"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.cluster.id]
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_amazon_eks_cluster_policy,
    aws_iam_role_policy_attachment.cluster_amazon_eks_vpc_resource_controller,
  ]
}

# ------------------------------------------------------------------------------
# EKS Node Group
# ------------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  instance_types = [var.node_instance_type]

  depends_on = [
    aws_iam_role_policy_attachment.node_amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.node_amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.node_amazon_ec2_container_registry_readonly,
  ]

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
