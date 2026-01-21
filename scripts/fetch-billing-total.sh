#!/usr/bin/env bash
# This script fetches the total billing amount for the current month using AWS CLI.
# It uses the AWS Cost Explorer service to get the cost and usage data.
# Ensure you have the AWS CLI installed and configured with the necessary permissions.
# Usage: ./fetch-billing-total.sh

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null
then
    echo "AWS CLI could not be found. Please install it first."
    exit
fi

# Check if the user is authenticated
if ! aws sts get-caller-identity &> /dev/null
then
    echo "You are not authenticated. Please configure your AWS CLI."
    exit
fi

# Check if the user has permission to access Cost Explorer
if ! aws ce get-cost-and-usage --time-period "Start=$(date +%Y-%m-01),End=$(date -v+1d +%Y-%m-%d)" --granularity MONTHLY --metrics "UnblendedCost" &> /dev/null
then
    echo "You do not have permission to access Cost Explorer. Please check your IAM policies."
    exit
fi

# Fetch the total billing amount for the current month
aws ce get-cost-and-usage \
  --time-period "Start=$(date +%Y-%m-01),End=$(date -v+1d +%Y-%m-%d)" \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --query "ResultsByTime[].{Start:TimePeriod.Start,Amount:Total.UnblendedCost.Amount}" \
  --output table