variable "region" {
  description = "AWS region"
  default     = "us-east-1"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  default     = "cloudx-eks-app"
  type        = string
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  default     = "cloudx-eks-node-group"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the EKS node group"
  default     = "t4g.small"
  type        = string
}

variable "repo_name" {
  description = "ECR repository name"
  default     = "cloudx-app-repo"
  type        = string
}