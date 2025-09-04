#!/bin/bash

# Production Baseline Capture Script
# Captures DNS responses from current production server for comparison
# Run this against your CURRENT production DNS server before migration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PRODUCTION_DNS_SERVER="${1:-$(dig +short myid.opendns.com @resolver1.opendns.com)}"
OUTPUT_FILE="${2:-production_baseline.json}"
VERBOSE="${3:-false}"

echo -e "${BLUE}Capturing Production DNS Baseline${NC}"
echo "=================================="
echo "DNS Server: $PRODUCTION_DNS_SERVER"
echo "Output File: $OUTPUT_FILE"
echo ""

# Test domains (same as Docker test)
TEST_DOMAINS=(
    # Production domains - character range testing
    "0test.app.runonflux.io"
    "1test.app.runonflux.io"
    "9test.app.runonflux.io"
    "atest.app.runonflux.io"
    "btest.app.runonflux.io"
    "gtest.app.runonflux.io"
    "htest.app.runonflux.io"
    "itest.app.runonflux.io"
    "ntest.app.runonflux.io"
    "otest.app.runonflux.io"
    "ptest.app.runonflux.io"
    "utest.app.runonflux.io"
    "vtest.app.runonflux.io"
    "wtest.app.runonflux.io"
    "ztest.app.runonflux.io"
    
    # Staging domains
    "0test.app2.runonflux.io"
    "atest.app2.runonflux.io"
    "mtest.app2.runonflux.io"
    "ntest.app2.runonflux.io"
    "ztest.app2.runonflux.io"
    
    # Real-world examples
    "myapp.app.runonflux.io"
    "testapp.app.runonflux.io"
    "hello.app.runonflux.io"
    "world.app.runonflux.io"
    "production.app.runonflux.io"
    "staging.app2.runonflux.io"
    
    # Edge cases
    "a.app.runonflux.io"
    "z.app.runonflux.io"
    "0.app.runonflux.io"
)

QUERY_TYPES=("A" "CNAME" "SOA" "ANY")

# Function to capture DNS response
capture_response() {
    local domain=$1
    local qtype=$2
    
    if [[ "$VERBOSE" == "true" ]]; then
        echo -n "Capturing $domain ($qtype)... "
    fi
    
    # Query with timeout and retries
    local result=$(timeout 5 dig @$PRODUCTION_DNS_SERVER $domain $qtype +short +time=2 +tries=2 2>/dev/null)
    local exit_code=$?
    
    # Create structured response
    local response="{\"server\":\"$PRODUCTION_DNS_SERVER\",\"domain\":\"$domain\",\"type\":\"$qtype\",\"result\":\"$result\",\"exit_code\":$exit_code,\"timestamp\":\"$(date -Iseconds)\",\"source\":\"production\"}"
    
    if [[ "$VERBOSE" == "true" ]]; then
        if [[ $exit_code -eq 0 ]]; then
            echo -e "${GREEN}✓ Success${NC}"
        else
            echo -e "${RED}✗ Failed${NC}"
        fi
    fi
    
    echo "$response"
}

# Main capture function
main() {
    local total=0
    local successful=0
    local failed=0
    
    # Initialize output file
    echo "{" > "$OUTPUT_FILE"
    echo "  \"metadata\": {" >> "$OUTPUT_FILE"
    echo "    \"capture_date\": \"$(date -Iseconds)\"," >> "$OUTPUT_FILE"
    echo "    \"production_server\": \"$PRODUCTION_DNS_SERVER\"," >> "$OUTPUT_FILE"
    echo "    \"total_tests\": $((${#TEST_DOMAINS[@]} * ${#QUERY_TYPES[@]}))," >> "$OUTPUT_FILE"
    echo "    \"purpose\": \"Production baseline for DNS migration validation\"" >> "$OUTPUT_FILE"
    echo "  }," >> "$OUTPUT_FILE"
    echo "  \"responses\": [" >> "$OUTPUT_FILE"
    
    local first_response=true
    
    for domain in "${TEST_DOMAINS[@]}"; do
        for qtype in "${QUERY_TYPES[@]}"; do
            ((total++))
            
            local response=$(capture_response "$domain" "$qtype")
            local exit_code=$(echo "$response" | jq -r '.exit_code')
            
            # Add comma separator except for first response
            if [[ "$first_response" == "false" ]]; then
                echo "," >> "$OUTPUT_FILE"
            fi
            first_response=false
            
            # Add response to file
            echo -n "    $response" >> "$OUTPUT_FILE"
            
            if [[ $exit_code -eq 0 ]]; then
                ((successful++))
            else
                ((failed++))
            fi
        done
    done
    
    # Close JSON structure
    echo "" >> "$OUTPUT_FILE"
    echo "  ]" >> "$OUTPUT_FILE"
    echo "}" >> "$OUTPUT_FILE"
    
    echo ""
    echo -e "${BLUE}Capture Summary:${NC}"
    echo "Total Queries: $total"
    echo -e "${GREEN}Successful: $successful${NC}"
    echo -e "${RED}Failed: $failed${NC}"
    echo ""
    echo -e "${GREEN}Production baseline captured to: $OUTPUT_FILE${NC}"
    echo ""
    echo "Use this file to compare against Docker test results:"
    echo "  docker-compose -f docker-compose.test.yml up --abort-on-container-exit"
}

# Help function
show_help() {
    echo "Usage: $0 [dns_server] [output_file] [verbose]"
    echo ""
    echo "Capture DNS responses from production server for migration validation"
    echo ""
    echo "Arguments:"
    echo "  dns_server   DNS server IP to query (default: auto-detect)"
    echo "  output_file  Output JSON file (default: production_baseline.json)"
    echo "  verbose      Set to 'true' for verbose output (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 8.8.8.8"
    echo "  $0 192.168.1.100 baseline.json true"
    echo ""
    echo "This script should be run BEFORE migration to capture current behavior."
}

# Parse arguments
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# Execute main function
main