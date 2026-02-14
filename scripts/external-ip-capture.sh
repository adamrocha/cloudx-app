#!/bin/bash

# External IP Capture Tool
# Captures real external client IPs from various sources

echo "=== External IP Capture Tool ==="
echo "Started at: $(date)"
echo

# Function to make external requests and capture real IPs
test_external_requests() {
    echo "🌍 Testing External IP Capture..."
    
    LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "Load Balancer: $LB_URL"
    echo
    
    # Test from different external sources
    echo "Making test requests to capture external IPs..."
    
    # Test 1: From this machine's external IP
    echo "📍 Test 1: Your current external IP"
    curl -s https://ipinfo.io/ip && echo
    
    echo "📡 Making request to capture your IP..."
    curl -X POST "http://$LB_URL/auction" \
        -H "Content-Type: application/json" \
        -H "X-Test-Client: external-ip-test" \
        -d '{"id": "external-test", "app_id": "ip-capture"}' \
        -s > /dev/null
    
    echo "✅ Request sent from external IP"
    echo
}

# Function to check what headers the service receives
check_forwarded_headers() {
    echo "🔍 Checking for X-Forwarded-For headers in service..."
    
    # Get recent logs that might show forwarded headers
    kubectl logs -n ssp-namespace deployment/ssp --tail=5 --since=30s
}

# Function to monitor AWS ELB logs if available
monitor_elb_logs() {
    echo "☁️  Checking AWS ELB Access Logs..."
    
    # Check if access logs are enabled
    aws elb describe-load-balancer-attributes \
        --load-balancer-name ae3f7532b429540f09b361ef8faca898 \
        --query 'LoadBalancerAttributes.AccessLog.Enabled' 2>/dev/null || echo "Access logs not enabled"
}

# Function to get external IP information
get_current_external_ip() {
    echo "🌐 Current External IP Information:"
    echo "Your external IP: $(curl -s https://ipinfo.io/ip)"
    echo "IP details:"
    curl -s https://ipinfo.io/$(curl -s https://ipinfo.io/ip) | jq '.'
    echo
}

# Function to create a real external test
simulate_external_traffic() {
    echo "🚀 Simulating External Traffic..."
    
    LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    # Create multiple requests with different user agents
    for i in {1..3}; do
        echo "Request $i: $(date '+%H:%M:%S')"
        curl -X POST "http://$LB_URL/auction" \
            -H "Content-Type: application/json" \
            -H "User-Agent: ExternalClient-$i/1.0" \
            -H "X-Test-Session: external-session-$i" \
            -d "{\"id\": \"ext-$i\", \"app_id\": \"external-test\"}" \
            -w "Response: %{http_code} in %{time_total}s\n" \
            -s -o /dev/null
        sleep 2
    done
}

# Main execution
case "${1:-test}" in
    "test")
        test_external_requests
        ;;
    "headers")
        check_forwarded_headers
        ;;
    "elb")
        monitor_elb_logs
        ;;
    "ip")
        get_current_external_ip
        ;;
    "traffic")
        simulate_external_traffic
        ;;
    "all")
        get_current_external_ip
        echo "---"
        test_external_requests
        echo "---"
        simulate_external_traffic
        echo "---"
        check_forwarded_headers
        ;;
    *)
        echo "Usage: $0 [test|headers|elb|ip|traffic|all]"
        echo "  test    - Make external requests to test IP capture (default)"
        echo "  headers - Check for X-Forwarded-For headers in service logs"
        echo "  elb     - Check AWS ELB access log status"
        echo "  ip      - Show your current external IP"
        echo "  traffic - Simulate multiple external requests"
        echo "  all     - Run all tests"
        exit 1
        ;;
esac