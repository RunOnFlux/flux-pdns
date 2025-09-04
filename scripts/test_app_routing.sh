#!/bin/bash

# Test script for App Routing Migration (Pipe Backend → Bind Backend)
# This script validates that the character-based routing behavior matches the original pipe backend

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DNS_SERVER="${1:-127.0.0.1}"
VERBOSE="${2:-false}"

# Expected routing mappings (from original pipe backend)
declare -A PRODUCTION_MAPPINGS=(
    # Characters 0-9, a-g -> fdm-lb-1-1.runonflux.io
    ["0"]="fdm-lb-1-1.runonflux.io"
    ["1"]="fdm-lb-1-1.runonflux.io"
    ["2"]="fdm-lb-1-1.runonflux.io"
    ["3"]="fdm-lb-1-1.runonflux.io"
    ["4"]="fdm-lb-1-1.runonflux.io"
    ["5"]="fdm-lb-1-1.runonflux.io"
    ["6"]="fdm-lb-1-1.runonflux.io"
    ["7"]="fdm-lb-1-1.runonflux.io"
    ["8"]="fdm-lb-1-1.runonflux.io"
    ["9"]="fdm-lb-1-1.runonflux.io"
    ["a"]="fdm-lb-1-1.runonflux.io"
    ["b"]="fdm-lb-1-1.runonflux.io"
    ["c"]="fdm-lb-1-1.runonflux.io"
    ["d"]="fdm-lb-1-1.runonflux.io"
    ["e"]="fdm-lb-1-1.runonflux.io"
    ["f"]="fdm-lb-1-1.runonflux.io"
    ["g"]="fdm-lb-1-1.runonflux.io"
    
    # Characters h-n -> fdm-lb-1-2.runonflux.io
    ["h"]="fdm-lb-1-2.runonflux.io"
    ["i"]="fdm-lb-1-2.runonflux.io"
    ["j"]="fdm-lb-1-2.runonflux.io"
    ["k"]="fdm-lb-1-2.runonflux.io"
    ["l"]="fdm-lb-1-2.runonflux.io"
    ["m"]="fdm-lb-1-2.runonflux.io"
    ["n"]="fdm-lb-1-2.runonflux.io"
    
    # Characters o-u -> fdm-lb-1-3.runonflux.io
    ["o"]="fdm-lb-1-3.runonflux.io"
    ["p"]="fdm-lb-1-3.runonflux.io"
    ["q"]="fdm-lb-1-3.runonflux.io"
    ["r"]="fdm-lb-1-3.runonflux.io"
    ["s"]="fdm-lb-1-3.runonflux.io"
    ["t"]="fdm-lb-1-3.runonflux.io"
    ["u"]="fdm-lb-1-3.runonflux.io"
    
    # Characters v-z -> fdm-lb-1-4.runonflux.io
    ["v"]="fdm-lb-1-4.runonflux.io"
    ["w"]="fdm-lb-1-4.runonflux.io"
    ["x"]="fdm-lb-1-4.runonflux.io"
    ["y"]="fdm-lb-1-4.runonflux.io"
    ["z"]="fdm-lb-1-4.runonflux.io"
)

declare -A STAGING_MAPPINGS=(
    # Characters 0-9, a-m -> fdm-lb-2-1.runonflux.io
    ["0"]="fdm-lb-2-1.runonflux.io"
    ["1"]="fdm-lb-2-1.runonflux.io"
    ["2"]="fdm-lb-2-1.runonflux.io"
    ["3"]="fdm-lb-2-1.runonflux.io"
    ["4"]="fdm-lb-2-1.runonflux.io"
    ["5"]="fdm-lb-2-1.runonflux.io"
    ["6"]="fdm-lb-2-1.runonflux.io"
    ["7"]="fdm-lb-2-1.runonflux.io"
    ["8"]="fdm-lb-2-1.runonflux.io"
    ["9"]="fdm-lb-2-1.runonflux.io"
    ["a"]="fdm-lb-2-1.runonflux.io"
    ["b"]="fdm-lb-2-1.runonflux.io"
    ["c"]="fdm-lb-2-1.runonflux.io"
    ["d"]="fdm-lb-2-1.runonflux.io"
    ["e"]="fdm-lb-2-1.runonflux.io"
    ["f"]="fdm-lb-2-1.runonflux.io"
    ["g"]="fdm-lb-2-1.runonflux.io"
    ["h"]="fdm-lb-2-1.runonflux.io"
    ["i"]="fdm-lb-2-1.runonflux.io"
    ["j"]="fdm-lb-2-1.runonflux.io"
    ["k"]="fdm-lb-2-1.runonflux.io"
    ["l"]="fdm-lb-2-1.runonflux.io"
    ["m"]="fdm-lb-2-1.runonflux.io"
    
    # Characters n-z -> fdm-lb-2-2.runonflux.io
    ["n"]="fdm-lb-2-2.runonflux.io"
    ["o"]="fdm-lb-2-2.runonflux.io"
    ["p"]="fdm-lb-2-2.runonflux.io"
    ["q"]="fdm-lb-2-2.runonflux.io"
    ["r"]="fdm-lb-2-2.runonflux.io"
    ["s"]="fdm-lb-2-2.runonflux.io"
    ["t"]="fdm-lb-2-2.runonflux.io"
    ["u"]="fdm-lb-2-2.runonflux.io"
    ["v"]="fdm-lb-2-2.runonflux.io"
    ["w"]="fdm-lb-2-2.runonflux.io"
    ["x"]="fdm-lb-2-2.runonflux.io"
    ["y"]="fdm-lb-2-2.runonflux.io"
    ["z"]="fdm-lb-2-2.runonflux.io"
)

echo "========================================"
echo "App Routing Test - Pipe → Bind Migration"
echo "========================================"
echo "DNS Server: $DNS_SERVER"
echo ""

# Function to test DNS resolution
test_dns_cname() {
    local domain=$1
    local expected=$2
    local environment=$3
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo -n "Testing $domain (expecting $expected)... "
    fi
    
    result=$(dig @$DNS_SERVER $domain CNAME +short 2>/dev/null | head -n1)
    
    if [ -z "$result" ]; then
        echo -e "${RED}✗ FAIL: No CNAME returned for $domain${NC}"
        return 1
    elif [ "$result" == "$expected." ] || [ "$result" == "$expected" ]; then
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ FAIL: $domain returned '$result', expected '$expected'${NC}"
        return 1
    fi
}

# Function to test all characters for an environment
test_environment() {
    local env_name=$1
    local domain_suffix=$2
    local -n mappings=$3
    
    echo -e "${BLUE}Testing $env_name Environment: *.$domain_suffix${NC}"
    echo "--------------------------------------"
    
    local total=0
    local passed=0
    local failed=0
    
    for char in "${!mappings[@]}"; do
        local test_domain="${char}test.$domain_suffix"
        local expected="${mappings[$char]}"
        
        ((total++))
        
        if test_dns_cname "$test_domain" "$expected" "$env_name"; then
            ((passed++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC} out of $total tests"
    echo ""
    
    return $failed
}

# Function to test debug endpoints
test_debug_endpoints() {
    echo -e "${BLUE}Testing Debug Endpoints${NC}"
    echo "-------------------------"
    
    # Test production debug
    echo -n "Production debug endpoint... "
    debug_result=$(dig @$DNS_SERVER _debug.app.runonflux.io TXT +short 2>/dev/null)
    if [ ! -z "$debug_result" ]; then
        echo -e "${GREEN}✓ Available${NC}"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Response: $debug_result"
        fi
    else
        echo -e "${YELLOW}⚠ Not responding${NC}"
    fi
    
    # Test staging debug
    echo -n "Staging debug endpoint... "
    debug_result=$(dig @$DNS_SERVER _debug.app2.runonflux.io TXT +short 2>/dev/null)
    if [ ! -z "$debug_result" ]; then
        echo -e "${GREEN}✓ Available${NC}"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Response: $debug_result"
        fi
    else
        echo -e "${YELLOW}⚠ Not responding${NC}"
    fi
    
    echo ""
}

# Function to test health endpoints
test_health_endpoints() {
    echo -e "${BLUE}Testing Health Endpoints${NC}"
    echo "-------------------------"
    
    # Test production health
    health_result=$(dig @$DNS_SERVER _health.app.runonflux.io TXT +short 2>/dev/null)
    if [ ! -z "$health_result" ]; then
        echo -e "${GREEN}✓ Production health endpoint responding${NC}"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Response: $health_result"
        fi
    else
        echo -e "${YELLOW}⚠ Production health endpoint not responding${NC}"
    fi
    
    # Test staging health
    health_result=$(dig @$DNS_SERVER _health.app2.runonflux.io TXT +short 2>/dev/null)
    if [ ! -z "$health_result" ]; then
        echo -e "${GREEN}✓ Staging health endpoint responding${NC}"
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Response: $health_result"
        fi
    else
        echo -e "${YELLOW}⚠ Staging health endpoint not responding${NC}"
    fi
    
    echo ""
}

# Function to test SOA queries
test_soa_queries() {
    echo -e "${BLUE}Testing SOA Queries${NC}"
    echo "-------------------"
    
    # Test production SOA
    echo -n "Production SOA query... "
    soa_result=$(dig @$DNS_SERVER app.runonflux.io SOA +short 2>/dev/null)
    if [ ! -z "$soa_result" ]; then
        echo -e "${GREEN}✓ Available${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    # Test staging SOA
    echo -n "Staging SOA query... "
    soa_result=$(dig @$DNS_SERVER app2.runonflux.io SOA +short 2>/dev/null)
    if [ ! -z "$soa_result" ]; then
        echo -e "${GREEN}✓ Available${NC}"
    else
        echo -e "${RED}✗ Failed${NC}"
    fi
    
    echo ""
}

# Main test execution
main() {
    # Test both environments
    production_failures=0
    staging_failures=0
    
    test_environment "Production" "app.runonflux.io" PRODUCTION_MAPPINGS
    production_failures=$?
    
    test_environment "Staging" "app2.runonflux.io" STAGING_MAPPINGS  
    staging_failures=$?
    
    # Test additional endpoints
    test_debug_endpoints
    test_health_endpoints
    test_soa_queries
    
    # Summary
    echo "========================================"
    total_failures=$((production_failures + staging_failures))
    
    if [ $total_failures -eq 0 ]; then
        echo -e "${GREEN}🎉 ALL TESTS PASSED!${NC}"
        echo -e "${GREEN}Migration from pipe backend to bind backend was successful!${NC}"
    else
        echo -e "${RED}❌ $total_failures tests failed${NC}"
        echo -e "${RED}Production failures: $production_failures${NC}"
        echo -e "${RED}Staging failures: $staging_failures${NC}"
        echo ""
        echo "Please check the Lua script and zone file configuration."
    fi
    
    echo "========================================"
    
    exit $total_failures
}

# Parse command line arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [dns_server_ip] [verbose]"
    echo ""
    echo "Test the app routing migration from pipe backend to bind backend"
    echo ""
    echo "Arguments:"
    echo "  dns_server_ip    IP address of the DNS server (default: 127.0.0.1)"
    echo "  verbose          Set to 'true' for verbose output (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Test using localhost"
    echo "  $0 10.0.0.1           # Test using specific DNS server"
    echo "  $0 127.0.0.1 true     # Test with verbose output"
    exit 0
fi

# Run the main test
main