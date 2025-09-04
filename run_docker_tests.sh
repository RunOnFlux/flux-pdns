#!/bin/bash

# Docker DNS Testing Runner
# Main script to run complete end-to-end validation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================"
echo -e "PowerDNS Migration Validation Suite"
echo -e "Pipe Backend → Bind Backend Migration"
echo -e "============================================${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running. Please start Docker and try again.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker is running${NC}"
    
    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1; then
        echo -e "${RED}❌ docker-compose is not installed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ docker-compose is available${NC}"
    
    # Check if required files exist
    local required_files=(
        "docker/docker-compose.test.yml"
        "zones/cdn-geo.runonflux.io.zone"
        "zones/app.runonflux.io.zone"
        "zones/app2.runonflux.io.zone"
        "scripts/geo_routing.lua"
        "scripts/app_routing.lua"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo -e "${RED}❌ Required file missing: $file${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓ All required files present${NC}"
    echo ""
}

# Function to clean up previous test runs
cleanup_previous() {
    echo -e "${BLUE}Cleaning up previous test runs...${NC}"
    
    # Stop and remove containers
    docker-compose -f docker/docker-compose.test.yml down --remove-orphans 2>/dev/null || true
    
    # Clean up results directory
    rm -rf docker/results/*
    mkdir -p docker/results
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
    echo ""
}

# Function to run Docker tests
run_docker_tests() {
    echo -e "${BLUE}Starting Docker test environment...${NC}"
    echo ""
    
    # Build and start containers
    echo "Building and starting test containers..."
    if docker-compose -f docker/docker-compose.test.yml up --build --abort-on-container-exit; then
        echo ""
        echo -e "${GREEN}✓ Docker tests completed successfully${NC}"
        return 0
    else
        echo ""
        echo -e "${RED}❌ Docker tests failed${NC}"
        return 1
    fi
}

# Function to display test results
display_results() {
    echo -e "${BLUE}Test Results Summary:${NC}"
    echo "======================"
    
    local results_dir="docker/results"
    
    # Check for validation results from production comparison
    if [[ -f "$results_dir/validation_summary.txt" ]]; then
        echo ""
        echo -e "${CYAN}📋 Production Validation Report:${NC}"
        cat "$results_dir/validation_summary.txt"
        
        # Check if all tests passed
        if grep -q "SUCCESS: All tests passed" "$results_dir/validation_summary.txt" 2>/dev/null; then
            echo ""
            echo -e "${GREEN}🎉 VALIDATION SUCCESSFUL!${NC}"
            echo -e "${GREEN}The bind backend produces identical results to production.${NC}"
            return 0
        elif grep -q "FAILURE:" "$results_dir/validation_summary.txt" 2>/dev/null; then
            echo ""
            echo -e "${RED}❌ VALIDATION FAILED!${NC}"
            echo -e "${RED}Some tests failed against production data.${NC}"
            
            # Show detailed results if available
            if [[ -f "$results_dir/validation_results.txt" ]]; then
                echo ""
                echo -e "${YELLOW}📋 Detailed Results:${NC}"
                tail -20 "$results_dir/validation_results.txt"
            fi
            return 1
        fi
    else
        echo -e "${YELLOW}⚠ No validation results found${NC}"
    fi
    
    echo -e "${YELLOW}⚠ Could not determine test results${NC}"
    return 1
}

# Function to show logs if tests failed
show_failure_logs() {
    echo ""
    echo -e "${YELLOW}Showing container logs for debugging:${NC}"
    echo "======================================"
    
    echo ""
    echo -e "${BLUE}PowerDNS Bind Server Logs:${NC}"
    docker-compose -f docker/docker-compose.test.yml logs pdns-server || true
    
    echo ""
    echo -e "${BLUE}Test Runner Logs:${NC}"
    docker-compose -f docker/docker-compose.test.yml logs test-runner || true
}

# Main function
main() {
    echo -e "${BLUE}This script will:${NC}"
    echo "1. Validate prerequisites"
    echo "2. Clean up previous test runs"
    echo "3. Start Docker test environment"
    echo "4. Validate bind backend against production data"
    echo "5. Generate validation report"
    echo ""
    
    # Run each step
    check_prerequisites
    cleanup_previous
    
    echo -e "${YELLOW}Starting DNS validation tests...${NC}"
    echo "This may take a few minutes as containers start up and run tests."
    echo ""
    
    if run_docker_tests; then
        echo ""
        display_results
        local result_code=$?
        
        # Cleanup containers
        echo ""
        echo -e "${BLUE}Cleaning up test containers...${NC}"
        docker-compose -f docker/docker-compose.test.yml down --remove-orphans 2>/dev/null || true
        
        if [[ $result_code -eq 0 ]]; then
            echo ""
            echo -e "${GREEN}✅ VALIDATION COMPLETE: Bind backend matches production!${NC}"
        else
            echo ""
            echo -e "${RED}❌ VALIDATION FAILED: Bind backend differs from production!${NC}"
        fi
        
        exit $result_code
    else
        show_failure_logs
        
        echo ""
        echo -e "${BLUE}Cleaning up test containers...${NC}"
        docker-compose -f docker/docker-compose.test.yml down --remove-orphans 2>/dev/null || true
        
        echo ""
        echo -e "${RED}❌ Docker tests failed. Check logs above for details.${NC}"
        exit 1
    fi
}

# Handle help
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo ""
    echo "Run end-to-end validation tests for PowerDNS migration"
    echo ""
    echo "This script:"
    echo "  • Starts PowerDNS server with bind backend"
    echo "  • Runs comprehensive DNS queries against production data"
    echo "  • Validates responses match expected production behavior"
    echo "  • Generates detailed validation report"
    echo ""
    echo "Prerequisites:"
    echo "  • Docker and docker-compose installed and running"
    echo "  • All zone files and Lua scripts present"
    echo "  • No conflicting services on ports 5300-5301"
    echo ""
    echo "Results will be saved in docker/results/ directory"
    exit 0
fi

# Execute main function
main "$@"