# Docker-Based End-to-End DNS Testing Suite

This comprehensive testing suite validates that the new bind backend implementation produces identical DNS responses to the current pipe backend implementation.

## Overview

The test suite creates isolated Docker containers running both implementations side-by-side and performs comprehensive validation:

```
┌──────────────────────────────────────────────────────┐
│                Docker Test Network                   │
│                                                      │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────┐   │
│  │   Bind      │    │    Pipe     │    │  Test   │   │
│  │   Backend   │    │   Backend   │    │ Runner  │   │
│  │(172.20.0.10)│    │(172.20.0.11)│    │         │   │
│  │   Port 53   │    │   Port 53   │    │         │   │
│  └─────────────┘    └─────────────┘    └─────────┘   │
│         │                    │              │        │
│         └──────────┬─────────┘              │        │
│                    │                        │        │
│                    └────────────────────────┘        │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │           Comprehensive DNS Query Tests         │ │
│  │     • Character-based routing validation        │ │
│  │     • Production vs Staging environment tests   │ │
│  │     • Query type validation (A,CNAME,SOA,ANY)   │ │
│  │     • Edge case and real-world scenario tests   │ │
│  │     • Response comparison and reporting         │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Files and Structure

```
docker/
├── docker-compose.test.yml          # Main Docker Compose configuration
├── pdns/                           # Bind backend configuration
│   ├── pdns.conf                   # PowerDNS bind backend config
│   └── named.conf                  # Zone configuration
├── pdns-pipe/                      # Pipe backend configuration
│   ├── pdns.conf                   # PowerDNS pipe backend config
│   └── pdns_pipe_backend.py        # Pipe backend script
├── geoip/                          # Mock GeoIP database
│   └── GeoLite2-City.mmdb          # Placeholder GeoIP file
├── tests/                          # Test scripts
│   └── run_e2e_tests.sh            # Main test execution script
└── results/                        # Test output directory
    ├── bind_results.json           # Bind backend responses
    ├── pipe_results.json           # Pipe backend responses
    ├── comparison.jsonl            # Detailed comparison data
    └── comparison_report.txt       # Human-readable report

scripts/
├── capture_production_baseline.sh  # Capture current production responses
└── run_docker_tests.sh             # Main test runner script
```

## Quick Start

### 1. Run Complete Validation

```bash
# Run full end-to-end validation
./run_docker_tests.sh
```

This will:

- ✅ Check prerequisites (Docker, docker-compose, required files)
- 🧹 Clean up any previous test runs
- 🐳 Build and start Docker containers
- 🧪 Run comprehensive DNS tests comparing both backends
- 📊 Generate detailed validation report
- ✅ Display pass/fail results

### 2. Capture Production Baseline (Optional)

Before migration, capture current production behavior:

```bash
# Capture from your production DNS server
./scripts/capture_production_baseline.sh YOUR_PROD_DNS_IP production_baseline.json true
```

### 3. View Results

Results are automatically displayed, but you can also review:

```bash
# View detailed comparison report
cat docker/results/comparison_report.txt

# View raw JSON results
jq . docker/results/bind_results.json
jq . docker/results/pipe_results.json
```

## Test Coverage

### Domain Testing

The suite tests **comprehensive character-based routing**:

**Production (`*.app.runonflux.io`)**:

- Characters `0-9, a-g` → `fdm-lb-1-1.runonflux.io`
- Characters `h-n` → `fdm-lb-1-2.runonflux.io`
- Characters `o-u` → `fdm-lb-1-3.runonflux.io`
- Characters `v-z` → `fdm-lb-1-4.runonflux.io`

**Staging (`*.app2.runonflux.io`)**:

- Characters `0-9, a-m` → `fdm-lb-2-1.runonflux.io`
- Characters `n-z` → `fdm-lb-2-2.runonflux.io`

### Query Types

- **A Records**: IPv4 address resolution
- **CNAME Records**: Canonical name resolution
- **SOA Records**: Start of Authority
- **ANY Records**: All available record types

### Test Scenarios

- 🔤 **Character Range Testing**: All 36 characters (0-9, a-z)
- 🌍 **Environment Testing**: Production vs Staging
- 🧪 **Edge Cases**: Single character domains, long domains
- 🌐 **Real-world Examples**: Common application names
- 🎯 **Geo-routing**: CDN geo-routing validation (bind-only)

## Expected Results

### ✅ Successful Validation

```
FINAL VALIDATION RESULTS
==================================================

Test Statistics:
  Total Tests: 144
  Matches: 144
  Mismatches: 0
  Success Rate: 100%

🎉 VALIDATION SUCCESSFUL!
The bind backend implementation produces identical results to the pipe backend.
Migration is safe to proceed.
```

### ❌ Failed Validation

```
FINAL VALIDATION RESULTS
==================================================

Test Statistics:
  Total Tests: 144
  Matches: 140
  Mismatches: 4
  Success Rate: 97%

❌ VALIDATION FAILED!
Found 4 mismatched responses.
Review the detailed report before proceeding with migration.
```

## Troubleshooting

### Common Issues

**Docker not running**:

```bash
# Start Docker Desktop or Docker daemon
sudo systemctl start docker  # Linux
# or start Docker Desktop app  # Mac/Windows
```

**Port conflicts**:

```bash
# Check what's using ports 5300-5301
lsof -i :5300
lsof -i :5301

# Stop conflicting services or change ports in docker-compose.test.yml
```

**Missing files**:

```bash
# Ensure all required files exist
ls zones/*.zone
ls scripts/*.lua
```

### Debug Container Issues

**View container logs**:

```bash
# View all container logs
docker-compose -f docker-compose.test.yml logs

# View specific container logs
docker-compose -f docker-compose.test.yml logs pdns-server
docker-compose -f docker-compose.test.yml logs pdns-pipe-server
docker-compose -f docker-compose.test.yml logs test-runner
```

**Manual container testing**:

```bash
# Start containers without auto-exit
docker-compose -f docker-compose.test.yml up -d

# Test bind server manually
dig @127.0.0.1 -p 5300 test.app.runonflux.io CNAME +short

# Test pipe server manually
dig @127.0.0.1 -p 5301 test.app.runonflux.io CNAME +short

# Clean up
docker-compose -f docker-compose.test.yml down
```

### Performance Considerations

**Resource Requirements**:

- **Memory**: ~512MB for all containers
- **CPU**: 1-2 cores recommended
- **Disk**: ~100MB for images and logs
- **Network**: Isolated Docker network (no external access needed)

**Test Duration**:

- **Container startup**: 30-60 seconds
- **Test execution**: 60-120 seconds
- **Total runtime**: 2-3 minutes

## Integration with CI/CD

The test suite is designed for automation:

```yaml
# Example GitHub Actions workflow
name: DNS Migration Validation
on: [push, pull_request]

jobs:
  validate-dns:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run DNS validation tests
        run: |
          chmod +x run_docker_tests.sh
          ./run_docker_tests.sh
      - name: Upload test results
        uses: actions/upload-artifact@v2
        with:
          name: dns-test-results
          path: docker/results/
```

## Validation Criteria

The test suite validates:

1. **✅ Functional Equivalence**: Both backends return identical responses
2. **✅ Character-based Routing**: All 36 characters route to correct load balancers
3. **✅ Environment Separation**: Production vs staging routing works correctly
4. **✅ Query Type Support**: A, CNAME, SOA, and ANY queries work identically
5. **✅ Error Handling**: Failed queries produce same error responses
6. **✅ Edge Cases**: Single characters, long names, special cases handle identically

## Next Steps After Successful Validation

1. **Review Results**: Ensure 100% match rate
2. **Deploy to Staging**: Test in staging environment
3. **Plan Migration**: Schedule production migration
4. **Monitor**: Set up monitoring for production deployment
5. **Rollback Plan**: Keep pipe backend configuration for emergency rollback

---

## Summary

This comprehensive Docker testing suite provides **bulletproof validation** that your DNS migration will not change any existing behavior. With 144+ test scenarios covering all character ranges, environments, and query types, you can be confident that the migration from pipe backend to bind backend is safe to proceed.

**🎯 Goal**: Zero behavior change during migration
**✅ Result**: Identical DNS responses with better performance and maintainability
