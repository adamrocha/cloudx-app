data "aws_caller_identity" "current" {}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

resource "aws_eks_cluster" "eks" {
  # checkov:skip=CKV_AWS_39: Pubic access to the EKS cluster is required for this demo
  depends_on = [
    aws_vpc.eks,
    aws_internet_gateway.eks
  ]
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    endpoint_public_access  = true
    endpoint_private_access = true
  }
}

resource "aws_eks_node_group" "node_group" {
  depends_on = [
    aws_vpc.eks,
    aws_eks_cluster.eks,
    aws_internet_gateway.eks
  ]
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.public[*].id

  scaling_config {
    min_size     = 1
    desired_size = 1
    max_size     = 3
  }

  instance_types = [var.instance_type]
  capacity_type  = "ON_DEMAND"
  disk_size      = 20
  ami_type       = "AL2023_ARM_64_STANDARD"

  update_config {
    max_unavailable = 1
  }
}