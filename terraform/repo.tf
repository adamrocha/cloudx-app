resource "terraform_data" "update_kubeconfig" {
  depends_on = [aws_eks_cluster.eks]

  triggers_replace = { cluster_name = aws_eks_cluster.eks.id }

  provisioner "local-exec" {
    command     = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.region}"
    interpreter = ["bash", "-c"]
  }
}

# Ensure the ECR repository exists
data "aws_ecr_authorization_token" "token" {}

resource "aws_ecr_repository" "repo" {
  name                 = var.repo_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "KMS"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "terraform_data" "docker_buildx" {
  depends_on = [aws_ecr_repository.repo]

  triggers_replace = {
    image_tag = var.image_tag
    platforms = join(",", var.platforms)
    # Rebuild image when source code changes
    dockerfile_hash = filemd5("../app/Dockerfile")
    main_go_hash    = filemd5("../app/main.go")
    ssp_go_hash     = filemd5("../app/ssp.go")
    bidder_go_hash  = filemd5("../app/bidder.go")
    go_mod_hash     = filemd5("../app/go.mod")
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -e
      echo "🔨 Building multi-architecture image..."
      
      # Login to ECR
      aws ecr get-login-password --region ${var.region} | \
        docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com
      
      # Create buildx builder if not exists
      docker buildx create --use --name multiarch-builder 2>/dev/null || docker buildx use multiarch-builder
      
      # Build and push multi-arch image
      docker buildx build \
        --platform ${join(",", var.platforms)} \
        --tag ${aws_ecr_repository.repo.repository_url}:${var.image_tag} \
        --push \
        ../app/
      
      echo "✅ Multi-arch image pushed successfully"
    EOT
    interpreter = ["bash", "-c"]
  }
}

# Lookup the image safely
data "aws_ecr_image" "image" {
  depends_on = [
    aws_eks_cluster.eks,
    aws_ecr_repository.repo,
    terraform_data.docker_buildx
  ]
  region          = var.region
  repository_name = aws_ecr_repository.repo.name
  image_tag       = var.image_tag
}