# PowerDNS API for Dynamic DNS Record Management

This document describes how to use the PowerDNS HTTP API to dynamically manage DNS A records for application subdomains.

## Overview

The PowerDNS API allows the cert server to add, update, and delete A records for specific application subdomains (e.g., `ipshow.app.runonflux.io`). These explicit A records override the wildcard CNAME Lua routing, enabling custom IP assignments for specific applications.

## Architecture

| Environment | DNS Master | Internal IP | API Port | Zone |
|-------------|------------|-------------|----------|------|
| Production | pdns-prod-fn1 | 10.100.0.153 | 8081 | app.runonflux.io |
| Staging | pdns-staging-fn1 | 10.100.0.154 | 8081 | app2.runonflux.io |

**Cert Server**: 10.100.0.172 (authorized to access both APIs)

## How It Works

### DNS Precedence

In DNS, explicit records always take precedence over wildcards. The zones have a wildcard LUA CNAME record:

```
*  IN  LUA  CNAME  ";include('_config'); return appRouteCname(qname)"
```

When you add an explicit A record for `ipshow.app.runonflux.io`, it takes precedence over the wildcard. Deleting the A record reverts to the wildcard CNAME behavior.

### Replication

Records added via API on the master are automatically replicated to slaves via AXFR/IXFR (configured with TSIG). The SOA serial auto-increments on changes.

## Authentication

All API requests require the `X-API-Key` header:

```bash
curl -H "X-API-Key: YOUR_API_KEY" ...
```

API keys are configured in the Ansible vars.yaml and deployed to the servers.

## API Endpoints

Base URL: `http://<master-ip>:8081/api/v1/servers/localhost`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/zones/{zone}.` | GET | List all records in zone |
| `/zones/{zone}.` | PATCH | Add/update/delete records |

**Note**: Zone names must end with a trailing dot (e.g., `app.runonflux.io.`)

## API Examples

### Add/Update an A Record

```bash
curl -X PATCH \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "ipshow.app.runonflux.io.",
      "type": "A",
      "ttl": 300,
      "changetype": "REPLACE",
      "records": [{"content": "1.2.3.4", "disabled": false}]
    }]
  }' \
  http://10.100.0.153:8081/api/v1/servers/localhost/zones/app.runonflux.io.
```

**Response**: `204 No Content` on success

### Delete an A Record

```bash
curl -X PATCH \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "ipshow.app.runonflux.io.",
      "type": "A",
      "changetype": "DELETE"
    }]
  }' \
  http://10.100.0.153:8081/api/v1/servers/localhost/zones/app.runonflux.io.
```

### List All A Records in Zone

```bash
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  http://10.100.0.153:8081/api/v1/servers/localhost/zones/app.runonflux.io. \
  | jq '.rrsets[] | select(.type == "A")'
```

### Get Zone Details

```bash
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  http://10.100.0.153:8081/api/v1/servers/localhost/zones/app.runonflux.io. \
  | jq '.'
```

### Add Multiple Records at Once

```bash
curl -X PATCH \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [
      {
        "name": "app1.app.runonflux.io.",
        "type": "A",
        "ttl": 300,
        "changetype": "REPLACE",
        "records": [{"content": "1.2.3.4", "disabled": false}]
      },
      {
        "name": "app2.app.runonflux.io.",
        "type": "A",
        "ttl": 300,
        "changetype": "REPLACE",
        "records": [{"content": "5.6.7.8", "disabled": false}]
      }
    ]
  }' \
  http://10.100.0.153:8081/api/v1/servers/localhost/zones/app.runonflux.io.
```

## Helper Script

A helper script is provided at `scripts/cert-server/dns-record-api.sh`:

```bash
# Set environment and API key
export PDNS_ENV=prod  # or staging
export PDNS_PROD_API_KEY=your-api-key

# Add/update A record
./scripts/cert-server/dns-record-api.sh add ipshow app.runonflux.io 1.2.3.4

# Add with custom TTL
./scripts/cert-server/dns-record-api.sh add ipshow app.runonflux.io 1.2.3.4 600

# Delete A record (reverts to wildcard CNAME)
./scripts/cert-server/dns-record-api.sh delete ipshow app.runonflux.io

# List all A records
./scripts/cert-server/dns-record-api.sh list app.runonflux.io

# Get specific record
./scripts/cert-server/dns-record-api.sh get ipshow app.runonflux.io

# Check if record exists
./scripts/cert-server/dns-record-api.sh exists ipshow app.runonflux.io

# Test API connectivity
./scripts/cert-server/dns-record-api.sh test
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PDNS_ENV` | Environment (prod/staging) | prod |
| `PDNS_PROD_API_KEY` | Production API key | (required) |
| `PDNS_STAGING_API_KEY` | Staging API key | (required) |
| `PDNS_PROD_API_URL` | Production API URL | http://10.100.0.153:8081 |
| `PDNS_STAGING_API_URL` | Staging API URL | http://10.100.0.154:8081 |
| `DEFAULT_TTL` | Default TTL for records | 300 |

### Sourcing as Library

The script can be sourced to use functions directly:

```bash
source ./scripts/cert-server/dns-record-api.sh

export PDNS_ENV=staging
export PDNS_STAGING_API_KEY=xxx

dns_add_a_record "myapp" "app2.runonflux.io" "1.2.3.4"
dns_delete_a_record "myapp" "app2.runonflux.io"

if dns_record_exists "myapp" "app2.runonflux.io"; then
    echo "Record exists"
fi
```

## Integration with Cert Server

The cert server can call this API to manage DNS records for applications. Example workflow:

1. Application requests a custom IP assignment
2. Cert server validates the request
3. Cert server calls PowerDNS API to add A record
4. DNS propagates to slaves within seconds
5. Application is accessible at custom IP

To revert to default load balancer routing, delete the A record.

## Troubleshooting

### Common Errors

**401 Unauthorized**
- Check API key is correct
- Verify `X-API-Key` header is included

**403 Forbidden**
- Request from unauthorized IP
- Only cert server (10.100.0.172) is allowed

**404 Not Found**
- Zone name incorrect (must end with `.`)
- Zone doesn't exist

**422 Unprocessable Entity**
- Invalid record format
- Check JSON syntax and record content

### Verify Record Propagation

```bash
# Check on master
dig @5.39.57.38 ipshow.app.runonflux.io A +short

# Check on slave
dig @5.161.203.77 ipshow.app.runonflux.io A +short

# Check wildcard fallback
dig @5.39.57.38 randomapp.app.runonflux.io CNAME +short
```

### Check Zone Serial

After adding records, verify the SOA serial incremented:

```bash
dig @5.39.57.38 app.runonflux.io SOA +short
```

### View API Logs

On the PowerDNS server:

```bash
journalctl -u pdns -f
```

## Security Notes

- API access is restricted to cert server IP via `webserver-allow-from`
- Additional firewall rules (ufw) restrict port 8081 access
- API keys should be stored securely and rotated periodically
- All changes are logged in PowerDNS logs
