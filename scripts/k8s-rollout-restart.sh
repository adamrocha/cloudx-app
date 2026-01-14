#!/usr/bin/env bash

kubectl rollout restart deployment bidder -n bidder-app
kubectl rollout restart deployment ssp -n ssp-namespace

# Watch the rollout
kubectl rollout status deployment/bidder -n bidder-app
kubectl rollout status deployment/ssp -n ssp-namespace