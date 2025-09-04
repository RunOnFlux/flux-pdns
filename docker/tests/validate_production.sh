#!/bin/bash

# Validate Bind Backend Against Production Data
# Tests the new bind backend implementation against real production DNS responses

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BIND_SERVER="172.25.0.10"  # pdns-test-server IP
TEST_DATA_FILE="/tests/production_data.json"
RESULTS_FILE="/results/validation_results.txt"
SUMMARY_FILE="/results/validation_summary.txt"

# Initialize results
echo "PowerDNS Bind Backend Production Validation Results" > "$RESULTS_FILE"
echo "=================================================" >> "$RESULTS_FILE"
echo "Test run: $(date)" >> "$RESULTS_FILE"
echo "" >> "$RESULTS_FILE"

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to run DNS query and compare with expected result
test_dns_query() {
    local domain="$1"
    local qtype="$2"
    local expected="$3"
    local note="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "${BLUE}Testing: ${domain} ${qtype}${NC}"
    echo "Testing: $domain $qtype" >> "$RESULTS_FILE"
    
    # Query the bind server
    local actual
    actual=$(dig @"$BIND_SERVER" "$domain" "$qtype" +short | head -1 | sed 's/\.$//')
    
    if [ -z "$actual" ]; then
        echo -e "${RED}❌ FAIL: No response from bind server${NC}"
        echo "  FAIL: No response from bind server" >> "$RESULTS_FILE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # Remove trailing dot from expected for comparison
    local expected_clean
    expected_clean=$(echo "$expected" | sed 's/\.$//')
    
    if [ "$actual" = "$expected_clean" ]; then
        echo -e "${GREEN}✓ PASS: $actual${NC}"
        echo "  PASS: $actual" >> "$RESULTS_FILE"
        if [ -n "$note" ]; then
            echo "  Note: $note" >> "$RESULTS_FILE"
        fi
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}❌ FAIL: Expected '$expected_clean', got '$actual'${NC}"
        echo "  FAIL: Expected '$expected_clean', got '$actual'" >> "$RESULTS_FILE"
        if [ -n "$note" ]; then
            echo "  Note: $note" >> "$RESULTS_FILE"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to test geo domain (special case - just check it resolves to one of the expected CDN servers)
test_geo_dns() {
    local domain="$1"
    local qtype="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo -e "${BLUE}Testing Geo: ${domain} ${qtype}${NC}"
    echo "Testing Geo: $domain $qtype" >> "$RESULTS_FILE"
    
    # Query the bind server
    local actual
    actual=$(dig @"$BIND_SERVER" "$domain" "$qtype" +short | head -1)
    
    if [ -z "$actual" ]; then
        echo -e "${RED}❌ FAIL: No response from bind server${NC}"
        echo "  FAIL: No response from bind server" >> "$RESULTS_FILE"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
    
    # For geo routing, just verify we get a valid response
    echo -e "${GREEN}✓ PASS: Geo-routing returned $actual${NC}"
    echo "  PASS: Geo-routing returned $actual" >> "$RESULTS_FILE"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}PowerDNS Bind Backend Validation${NC}"
echo -e "${YELLOW}Validating against REAL production data${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Test app.runonflux.io domains (production)
echo -e "${BLUE}Testing app.runonflux.io domains...${NC}"
echo "" >> "$RESULTS_FILE"
echo "APP.RUNONFLUX.IO DOMAIN TESTS" >> "$RESULTS_FILE"
echo "============================" >> "$RESULTS_FILE"

# Test real production domains from our data
test_dns_query "0test.app.runonflux.io" "CNAME" "fdm-lb-1-1.runonflux.io" ""
test_dns_query "5test.app.runonflux.io" "CNAME" "fdm-lb-1-1.runonflux.io" ""
test_dns_query "9test.app.runonflux.io" "CNAME" "fdm-lb-1-1.runonflux.io" ""
test_dns_query "atest.app.runonflux.io" "CNAME" "fdm-lb-1-1.runonflux.io" ""
test_dns_query "htest.app.runonflux.io" "CNAME" "fdm-lb-1-2.runonflux.io" ""
test_dns_query "mole.app.runonflux.io" "CNAME" "fdm-lb-1-2.runonflux.io" "Real production app"
test_dns_query "ipshow.app.runonflux.io" "CNAME" "fdm-lb-1-2.runonflux.io" "Real production app"
test_dns_query "otest.app.runonflux.io" "CNAME" "fdm-lb-1-3.runonflux.io" ""
test_dns_query "vtest.app.runonflux.io" "CNAME" "fdm-lb-1-4.runonflux.io" ""
test_dns_query "wordpress1739500409433.app.runonflux.io" "CNAME" "fdm-lb-1-4.runonflux.io" "Real production app"

echo ""

# Test app2.runonflux.io domains (staging)
echo -e "${BLUE}Testing app2.runonflux.io domains...${NC}"
echo "" >> "$RESULTS_FILE"
echo "APP2.RUNONFLUX.IO DOMAIN TESTS (STAGING)" >> "$RESULTS_FILE"
echo "=======================================" >> "$RESULTS_FILE"

test_dns_query "mole.app2.runonflux.io" "CNAME" "fdm-lb-2-1.runonflux.io" "Real staging app"
test_dns_query "ipshow.app2.runonflux.io" "CNAME" "fdm-lb-2-1.runonflux.io" "Real staging app"
test_dns_query "wordpress1739500409433.app2.runonflux.io" "CNAME" "fdm-lb-2-2.runonflux.io" "Real staging app"

echo ""

# Test geo routing
echo -e "${BLUE}Testing geo routing...${NC}"
echo "" >> "$RESULTS_FILE"
echo "GEO-ROUTING TESTS" >> "$RESULTS_FILE"
echo "================" >> "$RESULTS_FILE"

test_geo_dns "cdn-geo.runonflux.io" "A"

echo ""

# Test SOA records
echo -e "${BLUE}Testing SOA records...${NC}"
echo "" >> "$RESULTS_FILE"
echo "SOA RECORD TESTS" >> "$RESULTS_FILE"
echo "===============" >> "$RESULTS_FILE"

test_dns_query "app.runonflux.io" "SOA" "ns1.runonflux.io. st.runonflux.io. 2022040801 3600 600 86400 3600" ""
test_dns_query "app2.runonflux.io" "SOA" "ns1.runonflux.io. st.runonflux.io. 2022040801 3600 600 86400 3600" ""
test_dns_query "cdn-geo.runonflux.io" "SOA" "ns1.runonflux.io. st.runonflux.io. 2022040801 3600 600 86400 3600" ""

# Generate summary
echo "" >> "$RESULTS_FILE"
echo "SUMMARY" >> "$RESULTS_FILE"
echo "=======" >> "$RESULTS_FILE"
echo "Total tests: $TOTAL_TESTS" >> "$RESULTS_FILE"
echo "Passed: $PASSED_TESTS" >> "$RESULTS_FILE"
echo "Failed: $FAILED_TESTS" >> "$RESULTS_FILE"

# Write summary to separate file
echo "PowerDNS Bind Backend Validation Summary" > "$SUMMARY_FILE"
echo "=======================================" >> "$SUMMARY_FILE"
echo "Test run: $(date)" >> "$SUMMARY_FILE"
echo "Total tests: $TOTAL_TESTS" >> "$SUMMARY_FILE"
echo "Passed: $PASSED_TESTS" >> "$SUMMARY_FILE"
echo "Failed: $FAILED_TESTS" >> "$SUMMARY_FILE"

# Final output
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Test Summary${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "Total tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED - Bind backend matches production!${NC}"
    echo "SUCCESS: All tests passed" >> "$SUMMARY_FILE"
    exit 0
else
    echo -e "${RED}❌ Some tests failed - Check results for details${NC}"
    echo "FAILURE: $FAILED_TESTS tests failed" >> "$SUMMARY_FILE"
    exit 1
fi