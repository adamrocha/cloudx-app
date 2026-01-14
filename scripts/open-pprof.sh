#!/bin/bash
set -euo pipefail

# Colors for output
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }

# Get the Load Balancer URL
log_info "Fetching SSP service load balancer URL..."
LOAD_BALANCER_URL=$(kubectl get service ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [[ -z "$LOAD_BALANCER_URL" ]]; then
  echo "Error: Could not retrieve load balancer URL. Is the service deployed?"
  exit 1
fi

PPROF_URL="http://${LOAD_BALANCER_URL}/debug/pprof/"

log_success "Load Balancer URL: $LOAD_BALANCER_URL"
log_info "Opening pprof at: $PPROF_URL"

# Open in default browser
if command -v open &> /dev/null; then
  # macOS
  open "$PPROF_URL"
elif command -v xdg-open &> /dev/null; then
  # Linux
  xdg-open "$PPROF_URL"
elif command -v start &> /dev/null; then
  # Windows
  start "$PPROF_URL"
else
  echo "Could not detect browser. Please open manually:"
  echo "$PPROF_URL"
fi

log_success "Browser opened successfully"
