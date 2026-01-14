#!/bin/bash
set -euo pipefail

export AWS_PAGER=""

# Configuration
readonly REGION="${AWS_REGION:-us-east-1}"
readonly VPC_NAME="${VPC_NAME:-eks-vpc}"

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

# Fetch all security groups in VPC
log_info "Fetching security groups in VPC..."
SG_DATA=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" \
  --output text)

if [[ -z "$SG_DATA" ]]; then
  log_success "No security groups to clean up"
  exit 0
fi

SG_COUNT=$(echo "$SG_DATA" | wc -l | tr -d ' ')
log_success "Found $SG_COUNT non-default security groups"
echo ""

# Process security groups
DELETED=0
SKIPPED=0
#FAILED=0

while IFS=$'\t' read -r sg_id sg_name; do
  [[ -z "$sg_id" ]] && continue
  
  echo -n "Checking $sg_id ($sg_name)... "
  
  # Check if SG is in use
  if aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=group-id,Values=$sg_id" \
    --query "NetworkInterfaces[0].NetworkInterfaceId" \
    --output text 2>/dev/null | grep -q "eni-"; then
    echo "in use, skipping"
    ((SKIPPED++))
    continue
  fi
  
  # Try to delete
  if aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" 2>/dev/null; then
    log_success "deleted"
    ((DELETED++))
  else
    log_warn "dependency violation or error, skipping"
    ((SKIPPED++))
  fi
done <<< "$SG_DATA"

echo ""
log_info "Cleanup summary: ${GREEN}$DELETED deleted${NC}, ${YELLOW}$SKIPPED skipped${NC}"
