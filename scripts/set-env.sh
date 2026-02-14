#!/bin/bash
# Script to set up environment variables for Kubernetes deployment

# Get AWS Account ID from current credentials
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Error: Unable to get AWS Account ID. Please ensure you have AWS credentials configured."
    echo "Run: aws configure"
    exit 1
fi

echo "Environment variables set:"
echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo ""
echo "You can now run:"
echo "  make deploy-env    # Deploy with environment variable substitution"
echo "  make health        # Check health of deployed services"
echo "  make stats         # Get service statistics"