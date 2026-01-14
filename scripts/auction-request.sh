#!/usr/bin/env bash

# Get the SSP service LoadBalancer URL
kubectl get service ssp -n ssp-namespace

# Get just the hostname
LOAD_BALANCER_URL=$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer URL: $LOAD_BALANCER_URL"

# Test with the correct URL
curl -X POST -H "Content-Type: application/json" \
  -d '{"id":"test-auc","app_id":"test-app"}' \
  http://$LOAD_BALANCER_URL/auction | jq .