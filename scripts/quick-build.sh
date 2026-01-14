#!/usr/bin/env bash
set -euo pipefail

# Configuration
readonly REGION="${AWS_REGION:-us-east-1}"
readonly REPO_NAME="cloudx-app-repo"

# Colors for output
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Create ECR repository if it doesn't exist
log_info "Creating ECR repository..."
if aws ecr create-repository --repository-name "$REPO_NAME" --region "$REGION" 2>/dev/null; then
  log_success "Repository created"
else
  log_warn "Repository may already exist, continuing..."
fi

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_URL"

# Build Docker image
log_info "Building Docker image..."
docker build -t cloudx-app:latest ./app

# Tag image
log_info "Tagging image..."
docker tag cloudx-app:latest "${ECR_URL}/${REPO_NAME}:latest"

# Push to ECR
log_info "Pushing image to ECR..."
docker push "${ECR_URL}/${REPO_NAME}:latest"

echo ""
log_success "Build and push completed successfully!"
log_info "Image: ${ECR_URL}/${REPO_NAME}:latest"
