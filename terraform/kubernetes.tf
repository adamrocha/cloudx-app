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

# Deploy Kubernetes manifests
resource "null_resource" "deploy_app" {
  depends_on = [
    null_resource.build_and_push_image,
    aws_eks_node_group.node_group
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.eks.name}
      
      # Set environment variables for envsubst
      export AWS_ACCOUNT_ID=${data.aws_caller_identity.current.account_id}
      export AWS_REGION=${var.region}
      export REPO_NAME=${var.repo_name}
      
      # Apply manifests without environment substitution first
      kubectl apply -f ../k8s/namespaces.yaml
      kubectl apply -f ../k8s/ssp-service.yaml
      kubectl apply -f ../k8s/bidder-service.yaml
      kubectl apply -f ../k8s/ssp-network-policy.yaml
      kubectl apply -f ../k8s/bidder-network-policy.yaml
      
      # Apply deployments with environment variable substitution
      envsubst < ../k8s/ssp-deployment.yaml | kubectl apply -f -
      envsubst < ../k8s/bidder-deployment.yaml | kubectl apply -f -
    EOT
  }

  # Add destroy-time cleanup
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      # Set kubeconfig first (using hardcoded region and cluster name from environment)
      REGION=$(aws configure get region)
      CLUSTER_NAME=$(aws eks list-clusters --region $REGION --query 'clusters[0]' --output text 2>/dev/null || echo "")
      
      if [ ! -z "$CLUSTER_NAME" ]; then
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME || true
        
        # Delete resources in proper order
        kubectl delete networkpolicy --all --all-namespaces --ignore-not-found=true || true
        kubectl delete service --all -n ssp-namespace --ignore-not-found=true || true
        kubectl delete service --all -n bidder-app --ignore-not-found=true || true
        kubectl delete deployment --all -n ssp-namespace --ignore-not-found=true || true
        kubectl delete deployment --all -n bidder-app --ignore-not-found=true || true
        kubectl delete namespace ssp-namespace bidder-app --ignore-not-found=true || true
        
        # Wait longer for AWS Load Balancer resources to be cleaned up
        echo "Waiting for AWS Load Balancers and Security Groups to be cleaned up..."
        sleep 60
        
        # Clean up any remaining ELB security groups
        VPC_ID=$(aws ec2 describe-vpcs --region $REGION --filters "Name=tag:Name,Values=eks-vpc" --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
        if [ ! -z "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
          aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=k8s-elb-*" --query "SecurityGroups[].GroupId" --output text 2>/dev/null | tr '\t' '\n' | while read sg_id; do
            [ ! -z "$sg_id" ] && aws ec2 delete-security-group --region $REGION --group-id "$sg_id" 2>/dev/null || true
          done
        fi
      fi
    EOT
  }

  triggers = {
    # deployments_updated = null_resource.update_deployments.id
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