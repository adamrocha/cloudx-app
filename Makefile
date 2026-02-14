.PHONY: help tf-init tf-plan tf-apply tf-destroy tf-validate tf-fmt tf-output clean build test deploy-env destroy-env

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Terraform commands
tf-init: ## Initialize Terraform
	terraform -chdir=terraform init 

tf-plan: ## Run Terraform plan
	terraform -chdir=terraform plan

tf-apply: ## Apply Terraform configuration
	terraform -chdir=terraform apply

tf-apply-auto: ## Apply Terraform configuration without confirmation
	terraform -chdir=terraform apply -auto-approve

tf-destroy: destroy-env ## Destroy Terraform infrastructure
	terraform -chdir=terraform destroy

tf-validate: ## Validate Terraform configuration
	terraform -chdir=terraform validate

tf-fmt: ## Format Terraform files
	terraform -chdir=terraform fmt -recursive

tf-output: ## Show Terraform outputs
	terraform -chdir=terraform output

tf-refresh: ## Refresh Terraform state
	terraform -chdir=terraform refresh

# Build commands
build: ## Build the Go application
	cd app && go build -o ../bin/server .

test: ## Run tests
	cd app && go test -v ./...

clean: ## Clean build artifacts
	rm -f bin/server

# Docker commands
# docker-build: ## Build Docker image
# 	docker build -t cloudx-app-repo -f app/Dockerfile .

shell: ## Drop into a shell in the Docker image
	docker run -it --rm cloudx-app /bin/sh

delete-images: ## Delete all images from ECR repository
	./scripts/delete-images.sh

# Testing & deployment
auction-request: ## Send test auction request to deployed SSP service
	./scripts/auction-request.sh

stats: ## Get auction statistics from deployed SSP service
	@LOAD_BALANCER_URL=$$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}') && \
	echo "SSP Stats:" && \
	curl -s http://$$LOAD_BALANCER_URL/stats | jq .

health: ## Check health of deployed SSP service
	@LOAD_BALANCER_URL=$$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}') && \
	echo "Health check: http://$$LOAD_BALANCER_URL/healthz" && \
	curl -s http://$$LOAD_BALANCER_URL/healthz && echo

pprof: ## Open pprof profiling interface in browser
	./scripts/open-pprof.sh

logs-ssp: ## View SSP service logs
	kubectl logs -n ssp-namespace deployment/ssp --tail=100 -f

logs-bidder: ## View Bidder service logs
	kubectl logs -n bidder-app deployment/bidder --tail=100 -f

logs-all: ## View logs from both services
	@echo "=== SSP Logs ===" && \
	kubectl logs -n ssp-namespace deployment/ssp --tail=50 && \
	echo -e "\n=== Bidder Logs ===" && \
	kubectl logs -n bidder-app deployment/bidder --tail=50

events-ssp: ## View events in SSP namespace
	kubectl get events -n ssp-namespace --sort-by='.lastTimestamp'

events-bidder: ## View events in Bidder namespace
	kubectl get events -n bidder-app --sort-by='.lastTimestamp'

events-all: ## View events in all namespaces
	kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Kubernetes deployment with environment variables
set-aws-account: ## Set AWS_ACCOUNT_ID environment variable from current AWS credentials
	@echo "export AWS_ACCOUNT_ID=\$$(aws sts get-caller-identity --query Account --output text)"
	@echo "Run the above command to set the AWS_ACCOUNT_ID environment variable"

deploy-env: ## Deploy using Kustomize (auto-detects AWS Account ID)
	@AWS_ACCOUNT_ID=$${AWS_ACCOUNT_ID:-$$(aws sts get-caller-identity --query Account --output text)} && \
	echo "Deploying with AWS_ACCOUNT_ID=$$AWS_ACCOUNT_ID" && \
	cd k8s && \
	kustomize edit set image cloudx-app-repo=$$AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/cloudx-app-repo:latest && \
	kubectl apply -k .

destroy-env: ## Delete all Kubernetes resources using Kustomize
	@echo "⚠️  WARNING: This will delete all Kubernetes resources!"
	@echo "This includes: Deployments, Services, Network Policies, and Namespaces."
	@echo "The LoadBalancer will also be deleted (may take a few minutes)."
	@echo ""
	@read -p "Are you sure you want to continue? [yes/N]: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		echo "Deleting Kubernetes resources..."; \
		kubectl delete -k k8s/ --ignore-not-found=true --timeout=5m || true; \
		echo "Waiting for LoadBalancer cleanup..."; \
		sleep 10; \
		echo "Kubernetes resources deleted"; \
	else \
		echo "Deletion cancelled."; \
		exit 1; \
	fi

# Local development
run-bidder: build ## Run bidder locally on port 8092
	./bin/server bidder 8092

run-ssp: build ## Run SSP locally on port 8091
	./bin/server ssp 8091 http://localhost:8092/bid
