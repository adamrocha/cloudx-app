#!/bin/bash

# Capture source IPs from HTTP requests in real-time
# This script uses tcpdump if available, or monitors HTTP headers

echo "=== CloudX IP Capture Tool ==="
echo "Started at: $(date)"

# Function to capture HTTP traffic using tcpdump
capture_with_tcpdump() {
    echo "Attempting to capture HTTP traffic on port 8091..."
    
    # Check if tcpdump is available, if not try to install it
    kubectl exec -n ssp-namespace deployment/ssp -- which tcpdump >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "tcpdump not found. Trying to install..."
        kubectl exec -n ssp-namespace deployment/ssp -- apk add --no-cache tcpdump >/dev/null 2>&1 || {
            echo "Failed to install tcpdump. Container might not have privileges or package manager access."
            echo "Falling back to /proc/net monitoring."
            capture_with_proc
            return
        }
    fi
    
    kubectl exec -n ssp-namespace deployment/ssp -- tcpdump -i any -n -A 'port 8091' 2>/dev/null | \
    while read line; do
        # Look for HTTP requests and extract source IP
        if [[ "$line" =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ ]]; then
            # Parse tcpdump timestamp and connection info
            echo "[$(date '+%H:%M:%S')] $line"
        elif [[ "$line" =~ POST|GET ]]; then
            echo "  📨 HTTP Request: $line"
        elif [[ "$line" =~ Host:|User-Agent:|X-Forwarded-For: ]]; then
            echo "  🏷️  Header: $line"
        fi
    done
}

# Function to monitor using netstat (alternative to ss)
capture_with_netstat() {
    echo "Using 'netstat' to monitor socket connections..."
    
    # First check if netstat is available, if not install it
    kubectl exec -n ssp-namespace deployment/ssp -- which netstat >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Installing netstat in container..."
        kubectl exec -n ssp-namespace deployment/ssp -- apk add --no-cache net-tools >/dev/null 2>&1 || {
            echo "Failed to install netstat. Falling back to /proc/net monitoring."
            capture_with_proc
            return
        }
    fi
    
    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Get established connections for port 8091
        ESTABLISHED=$(kubectl exec -n ssp-namespace deployment/ssp -- netstat -an | grep ":8091.*ESTABLISHED")
        if [[ -n "$ESTABLISHED" ]]; then
            echo "[$TIMESTAMP] Established connections:"
            echo "$ESTABLISHED" | while read conn; do
                # Extract peer address (source IP) - netstat format: tcp 0 0 local_ip:port foreign_ip:port ESTABLISHED
                PEER=$(echo "$conn" | awk '{print $5}' | cut -d: -f1)
                if [[ "$PEER" != "127.0.0.1" ]] && [[ "$PEER" != "::1" ]] && [[ -n "$PEER" ]] && [[ "$PEER" != "0.0.0.0" ]]; then
                    echo "  🔗 Source IP: $PEER"
                fi
            done
        fi
        
        sleep 3
    done
}

# Function to monitor HTTP requests by watching for new processes
capture_with_proc() {
    echo "Monitoring process activity for HTTP connections via /proc/net/tcp..."
    
    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Look for any network activity by checking /proc/net/tcp
        # Port 8091 in hex is 1F9B
        kubectl exec -n ssp-namespace deployment/ssp -- cat /proc/net/tcp 2>/dev/null | \
        awk 'NR>1 && $2 ~ /:1F9B/ && $4 == "01" {print $3}' | \
        while read remote; do
            if [[ -n "$remote" ]] && [[ "$remote" != "00000000:0000" ]]; then
                # Convert hex to IP - format is AABBCCDD:PORT in little-endian
                IP_HEX=$(echo "$remote" | cut -d: -f1)
                
                # Convert little-endian hex IP to dotted decimal
                if [[ ${#IP_HEX} -eq 8 ]]; then
                    # Extract bytes in reverse order (little-endian)
                    D=$((0x${IP_HEX:0:2}))
                    C=$((0x${IP_HEX:2:2}))
                    B=$((0x${IP_HEX:4:2}))
                    A=$((0x${IP_HEX:6:2}))
                    
                    IP="$A.$B.$C.$D"
                    
                    # Filter out local/invalid IPs
                    if [[ "$IP" != "0.0.0.0" ]] && [[ "$IP" != "127.0.0.1" ]]; then
                        echo "[$TIMESTAMP] 🔗 Active connection from: $IP"
                    fi
                fi
            fi
        done
        
        sleep 3
    done
}

# Function to test IP capture with a known request
test_ip_capture() {
    echo "=== Testing IP Capture ==="
    echo "Making a test request to generate traffic..."
    
    # Get the load balancer URL
    LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [[ -z "$LB_URL" ]]; then
        echo "No load balancer found. Trying service IP..."
        LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.spec.clusterIP}')
    fi
    
    echo "Service endpoint: $LB_URL"
    echo "Making test request..."
    
    # Make a request from outside (using wget from another pod)
    kubectl run test-client --rm -i --restart=Never --image=alpine/curl:latest -- \
        curl -X POST "http://$LB_URL:8091/auction" \
        -H "Content-Type: application/json" \
        -H "X-Test-Source: IP-Capture-Test" \
        -d '{"id": "test-ip-capture", "app_id": "test"}' || \
    echo "Test request completed (may have failed if endpoint doesn't exist)"
}

# Function to use kubectl logs to capture access patterns
capture_with_logs() {
    echo "Monitoring application logs for connection information..."
    echo "Note: This requires the application to log request details."
    
    kubectl logs -n ssp-namespace deployment/ssp -f | \
    while read line; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        # Look for log patterns that might contain IP addresses
        if echo "$line" | grep -qE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'; then
            echo "[$TIMESTAMP] 📄 Log entry with IP: $line"
        elif echo "$line" | grep -qiE 'request|connection|client'; then
            echo "[$TIMESTAMP] 📄 Request log: $line"
        fi
    done
}

# Main execution
case "${1:-proc}" in
    "tcpdump")
        capture_with_tcpdump
        ;;
    "ss")
        echo "Note: 'ss' command is not available in Alpine containers."
        echo "Falling back to netstat monitoring..."
        capture_with_netstat
        ;;
    "netstat")
        capture_with_netstat
        ;;
    "proc")
        capture_with_proc
        ;;
    "logs")
        capture_with_logs
        ;;
    "test")
        test_ip_capture
        ;;
    *)
        echo "Usage: $0 [tcpdump|ss|netstat|proc|logs|test]"
        echo "  tcpdump - Use tcpdump to capture HTTP traffic (if available)"
        echo "  ss      - Use ss (socket statistics) - falls back to netstat"
        echo "  netstat - Use netstat to monitor connections (installs if needed)"
        echo "  proc    - Monitor /proc/net/tcp for connections (default, no additional tools needed)"
        echo "  logs    - Monitor application logs for IP information"
        echo "  test    - Make a test request to generate traffic"
        echo ""
        echo "Recommended: Use 'proc' for most reliable monitoring without additional dependencies."
        exit 1
        ;;
esac