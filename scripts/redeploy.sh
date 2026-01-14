#!/usr/bin/env bash

# Delete all app resources
kubectl delete all --all -n bidder-app
kubectl delete all --all -n ssp-namespace

# Reapply everything
kubectl apply -f ./k8s/namespaces.yaml
kubectl apply -f ./k8s/bidder-deployment.yaml
kubectl apply -f ./k8s/ssp-deployment.yaml
kubectl apply -f ./k8s/bidder-service.yaml
kubectl apply -f ./k8s/ssp-service.yaml
kubectl apply -f ./k8s/bidder-network-policy.yaml
kubectl apply -f ./k8s/ssp-network-policy.yaml