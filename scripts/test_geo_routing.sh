#!/bin/bash

# Test script for PowerDNS geo-routing with health checks
# This script tests the cdn-geo.runonflux.io DNS resolution and health check functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DNS_SERVER="${1:-127.0.0.1}"
TEST_DOMAIN="cdn-geo.runonflux.io"
CDN_SERVERS=(
    "cdn-6.runonflux.io:107.152.47.137:West Coast USA"
    "cdn-1.runonflux.io:5.39.57.50:Dunkerque EU"
    "cdn-12.runonflux.io:114.29.237.116:Hong Kong Asia"
)

echo "================================================"
echo "PowerDNS Geo-Routing Test Script"
echo "================================================"
echo ""

# Function to test DNS resolution
test_dns_resolution() {
    local domain=$1
    local server=$2
    
    echo -e "${YELLOW}Testing DNS resolution for $domain${NC}"
    result=$(dig @$server $domain A +short 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo -e "${RED}✗ Failed to resolve $domain${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Resolved $domain to: $result${NC}"
        echo "$result"
        return 0
    fi
}

# Function to check if server is reachable
check_server_health() {
    local ip=$1
    local port=$2
    
    timeout 2 bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null
    return $?
}

# Function to test health checks
test_health_checks() {
    echo -e "\n${YELLOW}Testing CDN Server Health Checks${NC}"
    echo "--------------------------------"
    
    for server_info in "${CDN_SERVERS[@]}"; do
        IFS=':' read -r hostname ip location <<< "$server_info"
        
        echo -n "Checking $hostname ($location) at $ip:443... "
        
        if check_server_health "$ip" "443"; then
            echo -e "${GREEN}✓ Online${NC}"
        else
            echo -e "${RED}✗ Offline${NC}"
        fi
    done
}

# Function to test geographic routing
test_geo_routing() {
    echo -e "\n${YELLOW}Testing Geographic Routing${NC}"
    echo "--------------------------------"
    
    echo "Performing multiple DNS queries to check load distribution..."
    
    declare -A ip_count
    total_queries=10
    
    for i in $(seq 1 $total_queries); do
        result=$(dig @$DNS_SERVER $TEST_DOMAIN A +short 2>/dev/null | head -n1)
        if [ ! -z "$result" ]; then
            ((ip_count["$result"]++))
        fi
        sleep 0.1
    done
    
    echo -e "\nResults from $total_queries queries:"
    for ip in "${!ip_count[@]}"; do
        count=${ip_count[$ip]}
        percentage=$((count * 100 / total_queries))
        
        # Find location for this IP
        location="Unknown"
        for server_info in "${CDN_SERVERS[@]}"; do
            IFS=':' read -r hostname server_ip server_location <<< "$server_info"
            if [ "$server_ip" == "$ip" ]; then
                location="$server_location"
                break
            fi
        done
        
        echo "  $ip ($location): $count times ($percentage%)"
    done
}

# Function to simulate server failure
test_failover() {
    echo -e "\n${YELLOW}Testing Failover Capability${NC}"
    echo "--------------------------------"
    echo "NOTE: This is a simulation. Actual failover requires taking down a server."
    echo ""
    
    echo "Current resolution:"
    current_ip=$(dig @$DNS_SERVER $TEST_DOMAIN A +short 2>/dev/null | head -n1)
    echo "  Primary: $current_ip"
    
    echo -e "\n${YELLOW}To test actual failover:${NC}"
    echo "1. Block access to one of the CDN servers (e.g., using iptables)"
    echo "   sudo iptables -A OUTPUT -d 107.152.47.137 -j DROP"
    echo "2. Wait 6 seconds (3 failed checks × 2 seconds)"
    echo "3. Query DNS again to see if it returns a different server"
    echo "4. Restore access: sudo iptables -D OUTPUT -d 107.152.47.137 -j DROP"
    echo "5. Wait 5 minutes for the server to be marked as recovered"
}

# Function to test recovery timing
test_recovery_timing() {
    echo -e "\n${YELLOW}Recovery Timing Information${NC}"
    echo "--------------------------------"
    echo "According to configuration:"
    echo "  • Health check interval: 2 seconds"
    echo "  • Failures before marking down: 3"
    echo "  • Detection time: ~6 seconds"
    echo "  • Recovery wait time: 5 minutes"
}

# Function to query status record
test_status_record() {
    echo -e "\n${YELLOW}Querying Server Status (if configured)${NC}"
    echo "--------------------------------"
    
    status=$(dig @$DNS_SERVER _status.$TEST_DOMAIN TXT +short 2>/dev/null)
    
    if [ ! -z "$status" ]; then
        echo -e "${GREEN}Status information available:${NC}"
        echo "$status"
    else
        echo "Status record not configured or not accessible"
    fi
}

# Main test execution
main() {
    echo "DNS Server: $DNS_SERVER"
    echo ""
    
    # Test basic DNS resolution
    if ! test_dns_resolution "$TEST_DOMAIN" "$DNS_SERVER"; then
        echo -e "${RED}Basic DNS resolution failed. Exiting.${NC}"
        exit 1
    fi
    
    # Test health checks
    test_health_checks
    
    # Test geographic routing
    test_geo_routing
    
    # Test failover information
    test_failover
    
    # Test recovery timing
    test_recovery_timing
    
    # Test status record
    test_status_record
    
    echo -e "\n================================================"
    echo -e "${GREEN}Test completed successfully!${NC}"
    echo "================================================"
}

# Parse command line arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [dns_server_ip]"
    echo ""
    echo "Test the PowerDNS geo-routing configuration"
    echo ""
    echo "Arguments:"
    echo "  dns_server_ip    IP address of the DNS server (default: 127.0.0.1)"
    echo ""
    echo "Examples:"
    echo "  $0              # Test using localhost"
    echo "  $0 10.0.0.1     # Test using specific DNS server"
    exit 0
fi

# Run the main test
main