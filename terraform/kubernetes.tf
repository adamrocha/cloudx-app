# Wait for EKS cluster to be ready
resource "null_resource" "wait_for_cluster" {
  depends_on = [
    aws_eks_node_group.node_group,
    aws_route_table_association.public
  ]

  provisioner "local-exec" {
    command = "aws eks wait cluster-active --name ${aws_eks_cluster.eks.name} --region ${var.region}"
  }

  # Add a small delay to ensure cluster is fully ready
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Build and push Docker image to ECR
resource "null_resource" "build_and_push_image" {
  depends_on = [
    null_resource.wait_for_cluster,
    aws_ecr_repository.repo
  ]

  provisioner "local-exec" {
    command = "cd .. && chmod +x scripts/quick-build.sh && ./scripts/quick-build.sh"
  }

  # Rebuild image when source code changes
  triggers = {
    dockerfile_hash = filemd5("../app/Dockerfile")
    main_go_hash    = filemd5("../app/main.go")
    ssp_go_hash     = filemd5("../app/ssp.go")
    bidder_go_hash  = filemd5("../app/bidder.go")
    go_mod_hash     = filemd5("../app/go.mod")
  }
}

locals {
  aws_account_id     = data.aws_caller_identity.current.account_id
  ecr_repository_url = "${local.aws_account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.repo_name}"
}

# Update Kubernetes deployment files with correct image URI
resource "null_resource" "update_deployments" {
  depends_on = [null_resource.build_and_push_image]

  provisioner "local-exec" {
    command = <<-EOT
      cd ..
      # Update deployment files with correct image URI
      sed -i '' 's|image:.*cloudx-app.*|image: ${local.ecr_repository_url}:latest|g' k8s/ssp-deployment.yaml
      sed -i '' 's|image:.*cloudx-app.*|image: ${local.ecr_repository_url}:latest|g' k8s/bidder-deployment.yaml
      
      # Also handle placeholder format (escape the $ in sed command)
      sed -i '' 's|$${AWS_ACCOUNT_ID}\.dkr\.ecr\..*\.amazonaws\.com/.*:latest|${local.ecr_repository_url}:latest|g' k8s/ssp-deployment.yaml
      sed -i '' 's|$${AWS_ACCOUNT_ID}\.dkr\.ecr\..*\.amazonaws\.com/.*:latest|${local.ecr_repository_url}:latest|g' k8s/bidder-deployment.yaml
    EOT
  }

  triggers = {
    image_built = null_resource.build_and_push_image.id
  }
}

# Deploy Kubernetes manifests
resource "null_resource" "deploy_app" {
  depends_on = [
    null_resource.update_deployments,
    aws_eks_node_group.node_group
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks.name}
      kubectl apply -f ../k8s/namespaces.yaml
      kubectl apply -f ../k8s/ssp-deployment.yaml
      kubectl apply -f ../k8s/bidder-deployment.yaml
      kubectl apply -f ../k8s/ssp-service.yaml
      kubectl apply -f ../k8s/bidder-service.yaml
      kubectl apply -f ../k8s/ssp-network-policy.yaml
      kubectl apply -f ../k8s/bidder-network-policy.yaml
    EOT
  }

  # Add destroy-time cleanup
  # provisioner "local-exec" {
  #   when    = destroy
  #   command = <<-EOT
  #     kubectl delete networkpolicy --all --all-namespaces --ignore-not-found=true
  #     kubectl delete service --all --all-namespaces --ignore-not-found=true
  #     kubectl delete deployment --all --all-namespaces --ignore-not-found=true
  #     kubectl delete namespace ssp-namespace bidder-app --ignore-not-found=true
  #   EOT
  # }

  triggers = {
    deployments_updated = null_resource.update_deployments.id
  }
}

# Get LoadBalancer URL
data "kubernetes_service" "ssp_service" {
  depends_on = [null_resource.deploy_app]

  metadata {
    name      = "ssp"
    namespace = "ssp-namespace"
  }
}