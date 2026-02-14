# CloudX EKS Infrastructure & Application Deployment

> Real-time bidding (RTB) auction system with SSP and Bidder services deployed on AWS EKS using Terraform, optimized for ARM64 architecture.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Testing & Verification](#testing--verification)
- [Architecture & Design](#architecture--design)
- [Trade-offs](#trade-offs)
- [Make Commands Reference](#make-commands-reference)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

**Deploy in 3 commands:**

```bash
make tf-init      # Initialize Terraform
make tf-plan      # Preview changes
make tf-apply     # Deploy everything (~20 mins)
```

**Test the service:**

```bash
make health           # Check health
make auction-request  # Send test auction
make stats            # View statistics
```

**Get the service URL:**

```bash
kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## Environment Variables & Security

For enhanced security, the deployment uses environment variable substitution instead of hardcoded AWS account IDs in the Kubernetes manifests.

### Setup Environment Variables

## Option 1: Using the helper script (Recommended)

```bash
source scripts/set-env.sh
```

## Option 2: Manual setup**

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Deploy with Environment Variables

```bash
make deploy-env    # Deploy with environment variable substitution
```

This approach:

- ✅ Keeps AWS account IDs out of version control
- ✅ Uses current AWS credentials dynamically
- ✅ Works in different AWS environments (dev/staging/prod)
- ✅ Follows security best practices

---

## Prerequisites

**Required Tools:**

- AWS CLI (v2.x+) with configured credentials
- Terraform (>= 1.13.0)
- kubectl (K8s 1.25+)
- Docker, jq (optional)

**AWS Permissions:** `eks:*`, `ec2:*`, `iam:*`, `ecr:*`, `elasticloadbalancing:*`

---

## Deployment

### Option 1: Make (Recommended)

```bash
make tf-init && make tf-plan && make tf-apply
```

### Option 2: Terraform Direct

```bash
cd terraform && terraform init && terraform plan && terraform apply
```

**What Gets Deployed:**

- **Infrastructure**: VPC (10.0.0.0/16), 2 AZs, EKS cluster, ARM64 nodes (2-4x t4g.small)
- **Container Registry**: ECR with auto-built ARM64 images
- **Kubernetes**: Namespaces, deployments, services (LoadBalancer + ClusterIP), NetworkPolicies
- **Auto-configuration**: kubectl, image URIs, deployment sync

**Deployment Time:** ~15-25 minutes (EKS cluster: 10-15m, nodes: 3-5m, app: 2-3m, LB: 2-3m)

---

## Testing & Verification

### Step 1: Get the SSP Service URL

The SSP service is exposed via an AWS LoadBalancer. Retrieve the URL:

**Using Make:**

```bash
make health
```

**Using kubectl:**

```bash
kubectl get service ssp -n ssp-namespace
```

**Get the LoadBalancer hostname:**

```bash
LOAD_BALANCER_URL=$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "SSP Service URL: http://$LOAD_BALANCER_URL"
```

Expected output format:

```text
SSP Service URL: http://a1234567890abcdef-1234567890.us-east-1.elb.amazonaws.com
```

### Step 2: Verify Health Endpoint

Test that the SSP service is running:

**Using Make:**

```bash
make health
```

**Using curl:**

```bash
curl http://$LOAD_BALANCER_URL/healthz
```

Expected response:

```text
OK
```

### Step 3: Send an Auction Request

Send a test auction request to the SSP service:

**Using Make:**

```bash
make auction-request
```

**Using curl:**

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"id":"test-auction-123","app_id":"test-app"}' \
  http://$LOAD_BALANCER_URL/auction
```

---

## Testing & Verification tools

### 1. Get Service URL

```bash
LOAD_BALANCER_URL=$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "SSP URL: http://$LOAD_BALANCER_URL"
```

### 2. Health Check

```bash
make health
# OR: curl http://$LOAD_BALANCER_URL/healthz
# Expected: OK
```

### 3. Send Auction Request

```bash
make auction-request
# OR: curl -X POST -H "Content-Type: application/json" \
#   -d '{"id":"test-auction-123","app_id":"test-app"}' \
#   http://$LOAD_BALANCER_URL/auction
```

**Expected Response:**

```json
{
  "auction_id": "test-auction-123",
  "winning_bid": {
    "bid_id": "bid_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "price": 1.50
  }
}
```

*Note: Bidder randomly decides whether to bid, so `winning_bid` may be null.*

### 4. View Statistics

```bash
make stats
# Expected: {"total_auctions": N}
```

### 5. Verify Services

```bash
# Check pods
kubectl get pods --all-namespaces

# Check services  
kubectl get svc -n ssp-namespace -n bidder-app

# View logs
kubectl logs -n ssp-namespace deployment/ssp --tail=50
kubectl logs -n bidder-app deployment/bidder --tail=50

# Test internal communication
kubectl exec -n ssp-namespace deployment/ssp -- \
  curl -s http://bidder.bidder-app.svc.cluster.local:8092/bid
```

### 6. Continuous Monitoring

```bash
# Watch pods
kubectl get pods --all-namespaces -w

# Monitor stats
watch -n 5 make stats
```

---

## Architecture & Design

### System Overview

```text
Internet → AWS LoadBalancer → [SSP] → [Bidder]
           (port 80)          (8091)   (8092)
                               │         │
                               └─────────┘
                              NetworkPolicy
                              (port 8092)
```

**Components:**

- **SSP**: Public auction endpoint (LoadBalancer service)
- **Bidder**: Internal bidding service (ClusterIP service)
- **Namespaces**: Separate isolation (`ssp-namespace`, `bidder-app`)

### Key Architecture Decisions

#### 1. ARM64 (Graviton) Architecture

**Why:** 20% cost savings, better price-performance, Go compiles natively to ARM64  
**How:** `GOARCH=arm64` builds, `t4g.small` instances, `AL2023_ARM_64_STANDARD` AMI

#### 2. Namespace Isolation

**Why:** Security isolation, independent resource quotas, network segmentation  
**Namespaces:** `ssp-namespace` (public), `bidder-app` (internal)

#### 3. Zero-Trust Network Security

**Why:** Implicit deny-all with explicit allows meets production security standards  
**Rules:**

- SSP → Bidder: port 8092
- Internet → SSP: port 80
- Both → DNS: port 53
- All other: denied

#### 4. LoadBalancer vs ClusterIP

**Why:** Only SSP needs public access; single LB reduces cost; bidder stays internal  
**Services:** SSP (LoadBalancer), Bidder (ClusterIP)

#### 5. Infrastructure as Code (Terraform)

**Why:** Repeatability, version control, automation, state management  
**Includes:** VPC, EKS, ECR, image building, K8s deployments

#### 6. Single Binary, Multiple Services

**Why:** Simplicity, image reuse, shared types  
**Trade-off:** Less modular; acceptable for this scale

#### 7. Security Hardening

**Implemented:**

- Non-root containers (UID 10000)
- Dropped Linux capabilities
- `allowPrivilegeEscalation: false`
- Resource limits (CPU: 250m-500m, Memory: 128Mi-256Mi)
- Docker HEALTHCHECK for SSP service (`/healthz` endpoint)

#### 8. Public Subnets for EKS Nodes

**Why:** Cost optimization (~$32/month NAT savings), faster deployment, simplified networking  
**Trade-off:** Less secure than private subnets; acceptable for demo  
**Production:** Use private subnets + NAT Gateway

---

## Trade-offs

### Conscious Compromises for Demo/Development

| Aspect | Current | Production | Rationale |
| ------ | ------- | ---------- | --------- |
| **Networking** | Public subnets | Private + NAT | Cost & simplicity |
| **Services** | Single binary | Separate images | Build simplicity |
| **Scaling** | Fixed replicas | HPA | Predictable costs |
| **Build** | Terraform-embedded | CI/CD pipeline | Single command deploy |
| **Regions** | Single (us-east-1) | Multi-region | Cost & complexity |
| **Storage** | In-memory | Database + cache | Stateless simplicity |
| **Monitoring** | Basic logs | Full observability | Time & cost |
| **Security** | HTTP | HTTPS + mTLS | Demo scope |
| **Reliability** | Basic | Retries + circuit breakers | Time constraint |
| **Deployments** | Rolling | Canary/blue-green | Simplicity |

**Key Principle:** Prioritize demonstration completeness over production readiness while maintaining security fundamentals.

### What's Missing for Production

❌ SSL/TLS termination (HTTPS)
❌ Horizontal Pod Autoscaling (HPA)
❌ Multi-region deployment
❌ Persistent storage (database)
❌ Centralized logging & monitoring
❌ Rate limiting & DDoS protection
❌ Canary/blue-green deployments
❌ Advanced error handling & retries
❌ Private subnets with NAT Gateway

---

## Make Commands Reference

```bash
# Terraform
make tf-init tf-plan tf-apply tf-destroy tf-validate tf-fmt tf-output

# Testing
make health stats auction-request

# Build & Dev
make build test clean docker-build shell delete-images

# Local
make run-bidder run-ssp

# Help
make help
```

---

## Troubleshooting

**LoadBalancer not ready:**

```bash
kubectl get service ssp -n ssp-namespace -w  # Wait 2-3 minutes
```

**Pods not running:**

```bash
kubectl get pods --all-namespaces
kubectl describe pod <pod-name> -n <namespace>
kubectl logs -n ssp-namespace deployment/ssp
```

**Connection refused:**

```bash
# Verify cluster access
aws eks update-kubeconfig --region us-east-1 --name cloudx-eks-app
kubectl cluster-info

# Check node status
kubectl get nodes
```

**Build failures:**

```bash
# Check Terraform state
make tf-plan

# Rebuild images manually
./scripts/quick-build.sh

# Validate Terraform
make tf-validate
```

---

## Development Notes

This project was developed using AI-assisted methodologies. For detailed information about the development process, metrics, and insights, see [docs/AI_METRICS.md](docs/AI_METRICS.md).

**Key Stats:**

- Development time: 3-4 hours (AI-assisted) vs estimated 12-16 hours without AI
- Efficiency gain: ~4x faster development cycle

---

## License

This project is for demonstration purposes.
