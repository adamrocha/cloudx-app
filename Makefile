.PHONY: help tf-init tf-plan tf-apply tf-destroy tf-validate tf-fmt tf-output clean build test

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Terraform commands
tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Run Terraform plan
	cd terraform && terraform plan

tf-apply: ## Apply Terraform configuration
	cd terraform && terraform apply

tf-apply-auto: ## Apply Terraform configuration without confirmation
	cd terraform && terraform apply -auto-approve

tf-destroy: ## Destroy Terraform infrastructure
	cd terraform && terraform destroy

tf-destroy-auto: ## Destroy Terraform infrastructure without confirmation
	cd terraform && terraform destroy -auto-approve

tf-validate: ## Validate Terraform configuration
	cd terraform && terraform validate

tf-fmt: ## Format Terraform files
	cd terraform && terraform fmt -recursive

tf-output: ## Show Terraform outputs
	cd terraform && terraform output

tf-refresh: ## Refresh Terraform state
	cd terraform && terraform refresh

# Build commands
build: ## Build the Go application
	cd app && go build -o ../bin/server .

test: ## Run tests
	cd app && go test -v ./...

clean: ## Clean build artifacts
	rm -f bin/server

# Docker commands
docker-build: ## Build Docker image
	docker build -t cloudx-app-repo -f app/Dockerfile .

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

# Local development
run-bidder: build ## Run bidder locally on port 8092
	./bin/server bidder 8092

run-ssp: build ## Run SSP locally on port 8091
	./bin/server ssp 8091 http://localhost:8092/bid
