#!/bin/bash

# Monitor source IPs connecting to SSP service
# Usage: ./monitor-connections.sh

echo "=== CloudX SSP Connection Monitor ==="
echo "Started at: $(date)"
echo

# Function to monitor connections in real-time
monitor_connections() {
    echo "Monitoring active connections to SSP (port 8091)..."
    echo "Log file: /tmp/ssp-connections.log"
    echo "Format: [timestamp] [protocol] [local_address] [remote_address] [state]"
    echo "----------------------------------------"
    
    # Create log file
    LOG_FILE="/tmp/ssp-connections.log"
    echo "# SSP Connection Log - Started at $(date)" > "$LOG_FILE"
    echo "# Format: timestamp,source_ip,connection_state,full_netstat_line" >> "$LOG_FILE"
    
    while true; do
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Get raw netstat output for debugging
        echo "[$TIMESTAMP] Checking connections..."
        RAW_OUTPUT=$(kubectl exec -n ssp-namespace deployment/ssp -- netstat -an 2>/dev/null)
        
        # Debug: show all connections to port 8091
        echo "Raw netstat output for port 8091:"
        echo "$RAW_OUTPUT" | grep ":8091" || echo "No connections found on port 8091"
        
        # Process connections and log to file
        echo "$RAW_OUTPUT" | grep ":8091" | while read line; do
            if [[ -n "$line" ]]; then
                # Extract components based on netstat format
                # Typical format: tcp 0 0 0.0.0.0:8091 0.0.0.0:* LISTEN
                # or: tcp 0 0 10.0.1.1:8091 10.0.2.1:12345 ESTABLISHED
                PROTOCOL=$(echo "$line" | awk '{print $1}')
                LOCAL_ADDR=$(echo "$line" | awk '{print $4}')
                REMOTE_ADDR=$(echo "$line" | awk '{print $5}')
                STATE=$(echo "$line" | awk '{print $6}')
                
                # Extract just the IP from remote address (remove port)
                REMOTE_IP=$(echo "$REMOTE_ADDR" | sed 's/:[0-9]*$//')
                
                # Log all connections (not just ESTABLISHED)
                echo "$TIMESTAMP,$REMOTE_IP,$STATE,$line" >> "$LOG_FILE"
                
                if [[ "$STATE" == "ESTABLISHED" ]] || [[ "$STATE" == "TIME_WAIT" ]]; then
                    echo "[$TIMESTAMP] ✓ Active connection from: $REMOTE_IP (State: $STATE)"
                elif [[ "$STATE" == "LISTEN" ]]; then
                    echo "[$TIMESTAMP] 👂 Listening on: $LOCAL_ADDR"
                fi
            fi
        done
        
        # Also check for any HTTP requests in pod logs
        echo "[$TIMESTAMP] Checking recent HTTP requests..."
        kubectl logs -n ssp-namespace deployment/ssp --tail=5 --since=10s 2>/dev/null | \
        while read logline; do
            if [[ -n "$logline" ]]; then
                echo "[$TIMESTAMP] LOG: $logline"
                echo "$TIMESTAMP,LOG,$logline" >> "$LOG_FILE"
            fi
        done
        
        echo "--- Log entries written to $LOG_FILE ---"
        tail -5 "$LOG_FILE"
        echo
        
        sleep 5
    done
}

# Function to get load balancer access logs setup commands
show_elb_setup() {
    cat << 'EOF'

=== AWS Load Balancer Access Logs Setup ===

1. Create S3 bucket for access logs:
   aws s3 mb s3://cloudx-elb-logs-$(date +%s)

2. Enable access logs on your load balancer:
   aws elb modify-load-balancer-attributes \
     --load-balancer-name ae3f7532b429540f09b361ef8faca898 \
     --load-balancer-attributes '{
       "AccessLog": {
         "Enabled": true,
         "S3BucketName": "cloudx-elb-logs-$(date +%s)",
         "S3BucketPrefix": "elb-access-logs"
       }
     }'

3. Monitor logs:
   aws s3 sync s3://your-bucket-name/elb-access-logs/ ./logs/

EOF
}

# Function to test connectivity from external sources
test_external_access() {
    echo "=== Testing External Access ==="
    echo "Your SSP service is available at:"
    LB_URL=$(kubectl get svc ssp -n ssp-namespace -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    echo "http://$LB_URL"
    echo
    echo "Test commands you can run from external machines:"
    echo "curl -X POST http://$LB_URL/auction -H 'Content-Type: application/json' -d '{\"id\":\"test\",\"app_id\":\"test\"}'"
    echo "curl http://$LB_URL/stats"
    echo "curl http://$LB_URL/healthz"
}

# Function to show current pod logs
show_recent_activity() {
    echo "=== Recent SSP Activity ==="
    kubectl logs -n ssp-namespace deployment/ssp --tail=20
}

# Function to create a simple IP monitoring loop
simple_ip_monitor() {
    echo "=== Simple IP Monitor ==="
    echo "Watching for new connections every 2 seconds..."
    echo "Press Ctrl+C to stop"
    echo
    
    LAST_CONN_COUNT=0
    while true; do
        # Count current connections
        CONN_COUNT=$(kubectl exec -n ssp-namespace deployment/ssp -- netstat -an 2>/dev/null | grep ":8091" | wc -l)
        
        if [[ $CONN_COUNT -gt $LAST_CONN_COUNT ]]; then
            echo "[$(date '+%H:%M:%S')] 🔄 Connection count changed: $LAST_CONN_COUNT → $CONN_COUNT"
            
            # Show all current connections
            kubectl exec -n ssp-namespace deployment/ssp -- netstat -an 2>/dev/null | grep ":8091" | while read line; do
                REMOTE_ADDR=$(echo "$line" | awk '{print $5}')
                STATE=$(echo "$line" | awk '{print $6}')
                echo "  └─ $REMOTE_ADDR ($STATE)"
            done
        fi
        
        LAST_CONN_COUNT=$CONN_COUNT
        sleep 2
    done
}

# Main execution
case "${1:-monitor}" in
    "monitor")
        monitor_connections
        ;;
    "simple")
        simple_ip_monitor
        ;;
    "setup")
        show_elb_setup
        ;;
    "test")
        test_external_access
        ;;
    "logs")
        show_recent_activity
        ;;
    *)
        echo "Usage: $0 [monitor|simple|setup|test|logs]"
        echo "  monitor - Monitor real-time connections with detailed logging (default)"
        echo "  simple  - Simple connection count monitoring"
        echo "  setup   - Show ELB access logs setup commands"
        echo "  test    - Show external access test commands"
        echo "  logs    - Show recent pod logs"
        exit 1
        ;;
esac