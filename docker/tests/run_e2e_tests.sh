#!/bin/bash

# End-to-End DNS Testing Script
# Compares bind backend (new) vs pipe backend (current) implementations
# Validates that both produce identical DNS responses

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# DNS server IPs (from docker-compose)
BIND_SERVER="172.25.0.10"    # New bind backend implementation
PIPE_SERVER="172.25.0.11"    # Current pipe backend implementation

# Results directory
RESULTS_DIR="/results"
BIND_RESULTS="$RESULTS_DIR/bind_results.json"
PIPE_RESULTS="$RESULTS_DIR/pipe_results.json"
COMPARISON_REPORT="$RESULTS_DIR/comparison_report.txt"

# Ensure results directory exists
mkdir -p "$RESULTS_DIR"

echo -e "${CYAN}=================================================="
echo -e "END-TO-END DNS VALIDATION TEST"
echo -e "Bind Backend (New) vs Pipe Backend (Current)"
echo -e "==================================================${NC}"
echo ""

# Test domains - covers all character ranges
TEST_DOMAINS=(
    # Production domains (app.runonflux.io)
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
    
    # Staging domains (app2.runonflux.io)
    "0test.app2.runonflux.io"
    "1test.app2.runonflux.io"
    "9test.app2.runonflux.io"
    "atest.app2.runonflux.io" 
    "btest.app2.runonflux.io"
    "mtest.app2.runonflux.io"
    "ntest.app2.runonflux.io"
    "otest.app2.runonflux.io"
    "ztest.app2.runonflux.io"
    
    # Real-world examples
    "myapp.app.runonflux.io"
    "testapp.app.runonflux.io"
    "hello.app.runonflux.io"
    "world.app.runonflux.io"
    "production.app.runonflux.io"
    "staging.app2.runonflux.io"
    "example.app2.runonflux.io"
    
    # Edge cases
    "0.app.runonflux.io"          # Single character
    "a.app.runonflux.io"
    "z.app.runonflux.io" 
    "zzzzzzz.app.runonflux.io"    # Long name starting with z
    "000000.app.runonflux.io"     # Long name starting with 0
    
    # Geo-routing domain (should work on bind server only)
    "cdn-geo.runonflux.io"
)

# Query types to test
QUERY_TYPES=("A" "CNAME" "SOA" "ANY")

# Function to query DNS server and return structured result
query_dns() {
    local server=$1
    local domain=$2
    local qtype=$3
    local timeout=5
    
    # Use dig to query the DNS server
    local result=$(timeout $timeout dig @$server $domain $qtype +short +time=2 +tries=2 2>/dev/null)
    local exit_code=$?
    
    # Structure the response
    local response="{\"server\":\"$server\",\"domain\":\"$domain\",\"type\":\"$qtype\",\"result\":\"$result\",\"exit_code\":$exit_code,\"timestamp\":\"$(date -Iseconds)\"}"
    echo "$response"
}

# Function to test both servers for a domain/type combination
test_domain_type() {
    local domain=$1
    local qtype=$2
    
    echo -n "Testing $domain ($qtype)... "
    
    # Query both servers
    local bind_response=$(query_dns "$BIND_SERVER" "$domain" "$qtype")
    local pipe_response=$(query_dns "$PIPE_SERVER" "$domain" "$qtype")
    
    # Extract results for comparison
    local bind_result=$(echo "$bind_response" | jq -r '.result')
    local pipe_result=$(echo "$pipe_response" | jq -r '.result')
    local bind_exit=$(echo "$bind_response" | jq -r '.exit_code')
    local pipe_exit=$(echo "$pipe_response" | jq -r '.exit_code')
    
    # Store detailed results
    echo "$bind_response" >> "$BIND_RESULTS"
    echo "$pipe_response" >> "$PIPE_RESULTS"
    
    # Compare results
    local match="false"
    local status="UNKNOWN"
    
    # Special handling for cdn-geo domain (only works on bind server)
    if [[ "$domain" == "cdn-geo.runonflux.io" ]]; then
        if [[ "$bind_exit" == "0" && "$pipe_exit" != "0" ]]; then
            match="true"
            status="BIND_ONLY"
            echo -e "${GREEN}✓ BIND ONLY${NC}"
        else
            status="UNEXPECTED"
            echo -e "${RED}✗ UNEXPECTED${NC}"
        fi
    else
        # Regular app domains should work on both servers
        if [[ "$bind_exit" == "0" && "$pipe_exit" == "0" ]]; then
            if [[ "$bind_result" == "$pipe_result" ]]; then
                match="true"  
                status="MATCH"
                echo -e "${GREEN}✓ MATCH${NC}"
            else
                status="MISMATCH"
                echo -e "${RED}✗ MISMATCH: '$bind_result' != '$pipe_result'${NC}"
            fi
        elif [[ "$bind_exit" != "0" && "$pipe_exit" != "0" ]]; then
            match="true"
            status="BOTH_FAILED"
            echo -e "${YELLOW}⚠ BOTH FAILED${NC}"
        else
            status="ONE_FAILED"
            echo -e "${RED}✗ ONE FAILED: bind_exit=$bind_exit, pipe_exit=$pipe_exit${NC}"
        fi
    fi
    
    # Log comparison result
    local comparison="{\"domain\":\"$domain\",\"type\":\"$qtype\",\"match\":$match,\"status\":\"$status\",\"bind_result\":\"$bind_result\",\"pipe_result\":\"$pipe_result\",\"bind_exit\":$bind_exit,\"pipe_exit\":$pipe_exit}"
    echo "$comparison" >> "$RESULTS_DIR/comparison.jsonl"
    
    return $([ "$match" == "true" ] && echo 0 || echo 1)
}

# Function to run all tests
run_all_tests() {
    echo -e "${BLUE}Running comprehensive DNS tests...${NC}"
    echo ""
    
    # Initialize results files
    echo "[]" > "$BIND_RESULTS"
    echo "[]" > "$PIPE_RESULTS"
    echo "" > "$RESULTS_DIR/comparison.jsonl"
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # Test each domain with each query type
    for domain in "${TEST_DOMAINS[@]}"; do
        for qtype in "${QUERY_TYPES[@]}"; do
            ((total_tests++))
            
            if test_domain_type "$domain" "$qtype"; then
                ((passed_tests++))
            else
                ((failed_tests++))
            fi
        done
    done
    
    echo ""
    echo -e "${BLUE}Test Summary:${NC}"
    echo "Total Tests: $total_tests"
    echo -e "${GREEN}Passed: $passed_tests${NC}"
    echo -e "${RED}Failed: $failed_tests${NC}"
    
    return $failed_tests
}

# Function to generate detailed comparison report
generate_report() {
    echo -e "${BLUE}Generating detailed comparison report...${NC}"
    
    cat > "$COMPARISON_REPORT" << EOF
DNS VALIDATION REPORT
$(date)

OVERVIEW
========
This report compares the DNS responses between:
- Bind Backend (New Implementation): $BIND_SERVER
- Pipe Backend (Current Implementation): $PIPE_SERVER

The goal is to validate that the new bind backend implementation
produces identical results to the current pipe backend.

TEST RESULTS
============
EOF
    
    # Analyze results
    local total_tests=$(wc -l < "$RESULTS_DIR/comparison.jsonl")
    local matches=$(grep -c '"match":true' "$RESULTS_DIR/comparison.jsonl" || echo 0)
    local mismatches=$(grep -c '"match":false' "$RESULTS_DIR/comparison.jsonl" || echo 0)
    
    cat >> "$COMPARISON_REPORT" << EOF
Total Tests: $total_tests
Matching Responses: $matches
Mismatched Responses: $mismatches

SUCCESS RATE: $(( matches * 100 / total_tests ))%

DETAILED RESULTS
================
EOF
    
    # Add detailed results for mismatches
    if [[ $mismatches -gt 0 ]]; then
        echo "MISMATCHES FOUND:" >> "$COMPARISON_REPORT"
        echo "=================" >> "$COMPARISON_REPORT"
        
        while read -r line; do
            local match=$(echo "$line" | jq -r '.match')
            if [[ "$match" == "false" ]]; then
                local domain=$(echo "$line" | jq -r '.domain')
                local qtype=$(echo "$line" | jq -r '.type')
                local status=$(echo "$line" | jq -r '.status')
                local bind_result=$(echo "$line" | jq -r '.bind_result')
                local pipe_result=$(echo "$line" | jq -r '.pipe_result')
                
                cat >> "$COMPARISON_REPORT" << EOF

Domain: $domain
Query Type: $qtype
Status: $status
Bind Result: '$bind_result'
Pipe Result: '$pipe_result'
EOF
            fi
        done < "$RESULTS_DIR/comparison.jsonl"
    else
        echo "🎉 ALL TESTS PASSED! The bind backend implementation produces identical results to the pipe backend." >> "$COMPARISON_REPORT"
    fi
    
    echo "" >> "$COMPARISON_REPORT"
    echo "END OF REPORT" >> "$COMPARISON_REPORT"
}

# Function to display final results
display_final_results() {
    echo ""
    echo -e "${CYAN}=================================================="
    echo -e "FINAL VALIDATION RESULTS"
    echo -e "==================================================${NC}"
    
    local total_tests=$(wc -l < "$RESULTS_DIR/comparison.jsonl")
    local matches=$(grep -c '"match":true' "$RESULTS_DIR/comparison.jsonl" || echo 0)
    local mismatches=$(grep -c '"match":false' "$RESULTS_DIR/comparison.jsonl" || echo 0)
    local success_rate=$(( matches * 100 / total_tests ))
    
    echo ""
    echo -e "${BLUE}Test Statistics:${NC}"
    echo "  Total Tests: $total_tests"
    echo -e "  Matches: ${GREEN}$matches${NC}"
    echo -e "  Mismatches: ${RED}$mismatches${NC}"
    echo -e "  Success Rate: ${GREEN}$success_rate%${NC}"
    echo ""
    
    if [[ $mismatches -eq 0 ]]; then
        echo -e "${GREEN}🎉 VALIDATION SUCCESSFUL!${NC}"
        echo -e "${GREEN}The bind backend implementation produces identical results to the pipe backend.${NC}"
        echo -e "${GREEN}Migration is safe to proceed.${NC}"
    else
        echo -e "${RED}❌ VALIDATION FAILED!${NC}"
        echo -e "${RED}Found $mismatches mismatched responses.${NC}"
        echo -e "${RED}Review the detailed report before proceeding with migration.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Report Location: ${CYAN}$COMPARISON_REPORT${NC}"
    echo -e "${BLUE}Bind Results: ${CYAN}$BIND_RESULTS${NC}"
    echo -e "${BLUE}Pipe Results: ${CYAN}$PIPE_RESULTS${NC}"
    echo ""
    
    return $mismatches
}

# Main execution
main() {
    # Wait for DNS servers to be fully ready
    echo -e "${YELLOW}Waiting for DNS servers to be ready...${NC}"
    sleep 5
    
    # Test connectivity to both servers
    echo -n "Testing bind server ($BIND_SERVER)... "
    if timeout 5 dig @$BIND_SERVER version.bind txt +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Ready${NC}"
    else
        echo -e "${YELLOW}⚠ Not responding to version query, but may still work${NC}"
    fi
    
    echo -n "Testing pipe server ($PIPE_SERVER)... "
    if timeout 5 dig @$PIPE_SERVER test.app.runonflux.io cname +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Ready${NC}"
    else
        echo -e "${YELLOW}⚠ Not responding to test query, but may still work${NC}"
    fi
    
    echo ""
    
    # Run all tests
    run_all_tests
    
    # Generate detailed report
    generate_report
    
    # Display final results
    display_final_results
    
    local exit_code=$?
    
    echo -e "${CYAN}End-to-end testing complete.${NC}"
    
    exit $exit_code
}

# Execute main function
main "$@"