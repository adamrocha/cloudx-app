# Build and push Docker image to ECR
# resource "terraform_data" "build_and_push_image" {
#   depends_on = [
#     terraform_data.wait_for_cluster,
#     aws_ecr_repository.repo
#   ]

#   provisioner "local-exec" {
#     command = "cd .. && chmod +x scripts/quick-build.sh && ./scripts/quick-build.sh"
#   }

#   # Rebuild image when source code changes
#   triggers = {
#     dockerfile_hash = filemd5("../app/Dockerfile")
#     main_go_hash    = filemd5("../app/main.go")
#     ssp_go_hash     = filemd5("../app/ssp.go")
#     bidder_go_hash  = filemd5("../app/bidder.go")
#     go_mod_hash     = filemd5("../app/go.mod")
#   }
# }

# Deploy Kubernetes manifests
resource "terraform_data" "deploy_app" {
  depends_on = [aws_eks_node_group.node_group]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks.name}
      
      # Use Kustomize to set the image dynamically
      cd ../k8s
      kustomize edit set image cloudx-app-repo=${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com/cloudx-app-repo:latest
      
      # Apply all manifests using Kustomize
      kubectl apply -k .
    EOT
  }
}

# Get LoadBalancer URL
# data "kubernetes_service" "ssp_service" {
#   depends_on = [terraform_data.deploy_app]

#   metadata {
#     name      = "ssp"
#     namespace = "ssp-namespace"
#     labels    = { app = "ssp" }
#   }
# }
