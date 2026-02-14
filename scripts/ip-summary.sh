#!/bin/bash

# IP Summary Tool - Shows captured source IPs
echo "=== CloudX Source IP Summary ==="
echo "Generated at: $(date)"
echo

echo "📊 Current Connection Status:"
kubectl exec -n ssp-namespace deployment/ssp -- netstat -an 2>/dev/null | grep ":8091" | awk '{print $5}' | grep -v ":::" | sort | uniq -c | sort -nr

echo
echo "🔍 Unique Source IPs (last 10 minutes):"

# Extract unique IPs from the monitoring log if it exists
if [[ -f /tmp/ssp-connections.log ]]; then
    echo "From monitoring log:"
    grep -v "^#" /tmp/ssp-connections.log | cut -d, -f2 | grep -v "^LOG$" | sort | uniq -c | sort -nr
    echo
fi

echo "📈 Live Connection Summary:"
echo "Service: SSP (port 8091)"
echo "Namespace: ssp-namespace"
echo "Load Balancer: $(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

echo
echo "🎯 Most Recent Connections:"
kubectl exec -n ssp-namespace deployment/ssp -- netstat -an 2>/dev/null | grep ":8091" | head -5

echo
echo "💡 To monitor live:"
echo "  ./scripts/monitor-connections.sh simple"
echo "  ./scripts/monitor-connections.sh monitor"

echo
echo "🔧 Available commands:"
echo "  make auction-request  # Generate test traffic"
echo "  kubectl logs -n ssp-namespace deployment/ssp --tail=10  # Check app logs"