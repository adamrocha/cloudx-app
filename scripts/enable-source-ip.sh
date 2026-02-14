#!/bin/bash

# Enable External IP Preservation
echo "=== Enabling External IP Preservation ==="
echo "This will modify your Kubernetes service to preserve source IPs"
echo

# Function to enable source IP preservation on service
enable_source_ip_preservation() {
    echo "🔧 Enabling externalTrafficPolicy: Local on SSP service..."
    
    kubectl patch service ssp -n ssp-namespace -p '{
        "spec": {
            "externalTrafficPolicy": "Local"
        }
    }'
    
    echo "✅ Source IP preservation enabled"
    echo
    
    echo "📋 Updated service configuration:"
    kubectl get service ssp -n ssp-namespace -o yaml | grep -A 5 -B 5 externalTrafficPolicy || echo "Policy may not be visible yet"
}

# Function to check load balancer configuration
check_lb_config() {
    echo "☁️  Checking Load Balancer Configuration..."
    
    # Get load balancer details
    LB_NAME=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[?DNSName==`ae3f7532b429540f09b361ef8faca898-279512477.us-east-1.elb.amazonaws.com`].LoadBalancerName' --output text)
    echo "Load Balancer: $LB_NAME"
    
    # Check current attributes
    echo "Current attributes:"
    aws elb describe-load-balancer-attributes --load-balancer-name "$LB_NAME" --query 'LoadBalancerAttributes'
}

# Function to create test with source IP
test_source_ip_capture() {
    echo "🧪 Testing Source IP Capture..."
    
    # Wait a moment for service changes to propagate
    echo "Waiting for service changes to propagate..."
    sleep 10
    
    echo "Your external IP: $(curl -s https://ipinfo.io/ip)"
    echo "Making test request..."
    
    LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    # Make request and immediately check connections
    curl -X POST "http://$LB_URL/auction" \
        -H "Content-Type: application/json" \
        -H "X-Real-IP: $(curl -s https://ipinfo.io/ip)" \
        -d '{"id": "external-ip-test", "app_id": "source-ip-test"}' \
        -s > /dev/null &
        
    # Quick check for new connections
    sleep 2
    echo "Checking for external IP in connections..."
    kubectl exec -n ssp-namespace deployment/ssp -- netstat -an | grep ":8091" | grep -v "LISTEN" | head -5
}

# Function to show the difference
compare_before_after() {
    echo "📊 Before vs After Comparison:"
    echo "Before: Only internal IPs (10.0.1.92) were visible"
    echo "After: External IPs should now be visible in connections"
    echo
    
    # Show current connections
    echo "Current connections:"
    kubectl exec -n ssp-namespace deployment/ssp -- netstat -an | grep ":8091" | grep -v "LISTEN" | head -5
}

# Main execution
case "${1:-enable}" in
    "enable")
        enable_source_ip_preservation
        ;;
    "check")
        check_lb_config
        ;;
    "test")
        test_source_ip_capture
        ;;
    "compare")
        compare_before_after
        ;;
    "all")
        enable_source_ip_preservation
        echo "---"
        check_lb_config
        echo "---"
        test_source_ip_capture
        ;;
    *)
        echo "Usage: $0 [enable|check|test|compare|all]"
        echo "  enable  - Enable source IP preservation on the service (default)"
        echo "  check   - Check current load balancer configuration"
        echo "  test    - Test source IP capture after changes"
        echo "  compare - Compare before/after connection IPs"
        echo "  all     - Run enable, check, and test"
        exit 1
        ;;
esac