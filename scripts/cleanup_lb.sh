#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

# Configuration
readonly REGION="${AWS_REGION:-us-east-1}"
readonly VPC_NAME="${VPC_NAME:-eks-vpc}"
readonly NAMESPACE="${1:-ssp-namespace}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Clean up Kubernetes services
log_info "Cleaning up Kubernetes services in namespace: $NAMESPACE..."
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  kubectl patch svc ssp -n "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  log_success "Removed finalizers from services"
  
  log_info "Waiting 10 seconds for service cleanup..."
  sleep 10
else
  log_warn "Namespace $NAMESPACE not found, skipping Kubernetes cleanup"
fi

# Find VPC
log_info "Locating VPC with tag Name=$VPC_NAME in region $REGION..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[0].VpcId" \
  --output text 2>/dev/null)

if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
  log_warn "VPC named '$VPC_NAME' not found in region '$REGION'"
  exit 0
fi

log_success "Found VPC: $VPC_ID"

# Delete ALB/NLB
log_info "Checking for ALB/NLB load balancers in VPC..."
ALB_ARNS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text 2>/dev/null)

if [[ -n "$ALB_ARNS" ]]; then
  ALB_COUNT=$(echo "$ALB_ARNS" | wc -w | tr -d ' ')
  log_info "Deleting $ALB_COUNT ALB/NLB load balancer(s)..."
  echo "$ALB_ARNS" | xargs -n 1 aws elbv2 delete-load-balancer --region "$REGION" --load-balancer-arn
  log_success "Deleted $ALB_COUNT ALB/NLB load balancer(s)"
else
  log_info "No ALB/NLB load balancers found"
fi

# Delete Classic ELB
log_info "Checking for Classic ELB load balancers in VPC..."
CLB_NAMES=$(aws elb describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
  --output text 2>/dev/null)

if [[ -n "$CLB_NAMES" ]]; then
  CLB_COUNT=$(echo "$CLB_NAMES" | wc -w | tr -d ' ')
  log_info "Deleting $CLB_COUNT Classic ELB load balancer(s)..."
  echo "$CLB_NAMES" | xargs -n 1 aws elb delete-load-balancer --region "$REGION" --load-balancer-name
  log_success "Deleted $CLB_COUNT Classic ELB load balancer(s)"
else
  log_info "No Classic ELB load balancers found"
fi

echo ""
log_success "Load balancer cleanup completed for VPC '$VPC_NAME' ($VPC_ID)"
