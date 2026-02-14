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

variable "repo_name" {
  description = "ECR repository name"
  default     = "cloudx-app-repo"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag"
  default     = "latest"
  type        = string
}

variable "platforms" {
  description = "Platforms for Docker buildx"
  default     = ["linux/amd64", "linux/arm64"]
  type        = list(string)
}

variable "platform" {
  description = "Platform for Docker build"
  # default     = "linux/amd64"
  default = "linux/arm64"
  type    = string
}

variable "instance_type" {
  description = "EC2 instance type for the EKS node group"
  # default     = "t3.small"
  default = "t4g.small"
  type    = string
}

variable "ami_type" {
  description = "EC2 AMI type for the EKS node group"
  # default     = "AL2023_x86_64_STANDARD"
  default = "AL2023_ARM_64_STANDARD"
  type    = string
}