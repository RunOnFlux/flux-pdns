# PDNS Primary-Secondary Verification Guide

This document describes commands used to verify that the primary-secondary PowerDNS configuration is working correctly.

## Dev Server Information

| Role      | Hostname     | Public IP   | Internal IP  |
| --------- | ------------ | ----------- | ------------ |
| Primary   | pdns-eu-2-01 | 5.39.57.39  | 10.100.0.154 |
| Secondary | pdns-us-2-01 | 5.161.41.40 | -            |

## Test Zone

The test zone used for verification is: `cdn-geodev.runonflux.io`

---

## Verification Steps

### 0. Set Environment Variables

Before running any API or AXFR commands, extract the keys from the PowerDNS config:

```bash
# API key for PowerDNS REST API
export PDNS_API_KEY=$(grep '^api-key=' /etc/powerdns/pdns.conf | cut -d'=' -f2)

# TSIG key for zone transfers (AXFR)
export TSIG_SECRET=$(grep 'secret' /etc/powerdns/tsig-keys/zone-transfer.conf | sed 's/.*"\(.*\)".*/\1/')
```

### 1. Create/Update a DNS Record on Primary

Use the PowerDNS API to create or update a TXT record on the primary server:

```bash
curl -v -X PATCH \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "debug.cdn-geodev.runonflux.io.",
      "type": "TXT",
      "changetype": "REPLACE",
      "records": [{
        "content": "\"debug-1234\"",
        "disabled": false
      }],
      "ttl": 300
    }]
  }' \
  'http://localhost:8081/api/v1/servers/localhost/zones/cdn-geodev.runonflux.io.'
```

### 1b. Delete a DNS Record on Primary

To remove the TXT record created above:

```bash
curl -v -X PATCH \
  -H "X-API-Key: $PDNS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "debug.cdn-geodev.runonflux.io.",
      "type": "TXT",
      "changetype": "DELETE"
    }]
  }' \
  'http://localhost:8081/api/v1/servers/localhost/zones/cdn-geodev.runonflux.io.'
```

### 2. Watch the Journal on Secondary

On the secondary server (pdns-us-2-01), watch the pdns journal to see zone transfers:

```bash
journalctl -f -u pdns
# or with a time filter:
journalctl -f -u pdns --since '15 minutes ago'
```

### 3. Compare SOA Records Between Primary and Secondary

The SOA serial should be the same on both servers after zone transfer:

```bash
# Query Primary
dig @5.39.57.39 cdn-geodev.runonflux.io SOA +short

# Query Secondary
dig @5.161.41.40 cdn-geodev.runonflux.io SOA +short

# Query localhost on secondary (run from pdns-us-2-01)
dig @127.0.0.1 cdn-geodev.runonflux.io SOA +short
```

### 4. Query A Records on Both Servers

Verify that A records resolve the same on both primary and secondary:

```bash
# Query Primary
dig @5.39.57.39 cdn-geodev.runonflux.io A +short

# Query Secondary
dig @5.161.41.40 cdn-geodev.runonflux.io A +short
```

---

### Zone Notifications

```bash
# Send NOTIFY to secondaries for a zone
pdns_control notify cdn-geodev.runonflux.io

# Show also-notify setting
pdns_control show also-notify

# Show secondary-do-renotify setting
pdns_control show secondary-do-renotify
```

### Force Zone Retrieval (on Secondary)

```bash
pdns_control retrieve cdn-geodev.runonflux.io
```

### Set Runtime Options

```bash
# Disable secondary re-notification
pdns_control set secondary-do-renotify no

# Set log level
pdns_control set loglevel=7
```

---

## PowerDNS Utilities (pdnsutil)

### Zone Information

```bash
# Show zone details (metadata, masters, serial, etc.)
pdnsutil show-zone cdn-geodev.runonflux.io

# List all records in a zone
pdnsutil list-zone cdn-geodev.runonflux.io

# List all zones
pdnsutil list-all-zones

# Check zone for errors
pdnsutil check-zone cdn-geodev.runonflux.io
```

### Zone Metadata

```bash
# Get all metadata for a zone
pdnsutil get-meta cdn-geodev.runonflux.io

# Get specific metadata
pdnsutil get-meta cdn-geodev.runonflux.io SOA-EDIT
pdnsutil get-meta cdn-geodev.runonflux.io SOA-EDIT-API
pdnsutil get-meta cdn-geodev.runonflux.io TSIG-ALLOW-AXFR
pdnsutil get-meta cdn-geodev.runonflux.io ALSO-NOTIFY
pdnsutil get-meta cdn-geodev.runonflux.io NOTIFY-DNSUPDATE
```

### Zone Kind (Master/Slave)

```bash
# Show zone kind
pdnsutil show-zone cdn-geodev.runonflux.io | grep -i kind
```

### SOA Serial Management

```bash
# Manually increase the SOA serial
pdnsutil increase-serial cdn-geodev.runonflux.io

# Send notify after serial increase
pdns_control notify cdn-geodev.runonflux.io
```

### Record Management

```bash
# Add a record via pdnsutil
pdnsutil add-record cdn-geodev.runonflux.io debug-pdnsutil TXT '"test-via-pdnsutil"'
```

### TSIG Key Management

```bash
# List all TSIG keys
pdnsutil list-tsig-keys
```

### Zone Transfer Operations (on Secondary)

```bash
# Retrieve zone from primary
pdnsutil retrieve cdn-geodev.runonflux.io

# Retrieve with explicit primary IP
pdnsutil retrieve-slave-zone cdn-geodev.runonflux.io 5.39.57.39

# Clear zone data (before re-sync)
pdnsutil clear-zone cdn-geodev.runonflux.io
```

---

## Manual Zone Transfer Testing (AXFR)

Test AXFR from the secondary to the primary using TSIG authentication:

```bash
# AXFR with TSIG key
dig @5.39.57.39 cdn-geodev.runonflux.io AXFR \
  -y "hmac-sha256:zone-transfer:$TSIG_SECRET"
```

---

## API Queries

### Query Zone Data via API

```bash
# On primary (internal IP)
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  'http://127.0.0.1:8081/api/v1/servers/localhost/zones/cdn-geodev.runonflux.io' | jq .

# On secondary
curl -s -H "X-API-Key: $PDNS_API_KEY" \
  'http://127.0.0.1:8081/api/v1/servers/localhost/zones/cdn-geodev.runonflux.io' | jq .
```

### Check Health Service

```bash
# On primary (internal IP)
curl -s 10.100.0.154:3000/health | jq .

# On secondary
curl -s http://localhost:3000/health | jq .
```

---

## API Access Restrictions

The PowerDNS API is protected at multiple levels:

| Server         | API Enabled | Allowed IPs (pdns.conf) | iptables                  |
| -------------- | ----------- | ----------------------- | ------------------------- |
| Primary (EU)   | Yes         | 127.0.0.1, 10.100.0.172 | Only 10.100.0.172 allowed |
| Secondary (US) | No          | N/A                     | N/A                       |

**Primary server config:**

```
webserver=yes
webserver-address=0.0.0.0
webserver-port=8081
webserver-allow-from=127.0.0.1,10.100.0.172
api=yes
```

**Secondary server config:**

```
webserver=no
api=no
```

The API on the primary is double-protected - both at the PowerDNS level (`webserver-allow-from`) and at the firewall level (iptables). Only the cert-server at `10.100.0.172` can access it remotely.

---

## Config Verification

```bash
# Check pdns config for errors
pdns_server --config=check

# More verbose config check
pdns_server --config=check --config-dir=/etc/powerdns

# Check SOA-EDIT setting in config
grep -i soa-edit /etc/powerdns/pdns.conf
```

---

## Deployment Commands

When changes need to be deployed to the servers:

```bash
# On the server (after ssh'ing in)
cd flux-pdns/
git pull
systemctl stop pdns
rm /etc/powerdns/pdns.conf
rm -rf /var/lib/powerdns/pdns.sqlite3*
ansible-playbook -i local_hosts.yaml powerdns_setup.yaml -e "DEPLOY_ENV=staging"
```

---

## Quick Verification Test Procedure

1. **Post a unique TXT record** to primary using the curl PATCH command
2. **Watch journal on secondary**: `journalctl -f -u pdns`
3. **Verify SOA serials match** on both servers using `dig @<ip> cdn-geodev.runonflux.io SOA +short`
4. **Query the new record** on both servers to confirm replication
5. **Use pdnsutil show-zone** on both servers to compare zone state

## Troubleshooting Commands

```bash
# If zone transfer isn't working, force retrieve on secondary:
pdns_control retrieve cdn-geodev.runonflux.io

# Check zone metadata on both servers:
pdnsutil get-meta cdn-geodev.runonflux.io

# Verify TSIG keys are configured:
pdnsutil list-tsig-keys

# Check zone kind is correct (MASTER on primary, SLAVE on secondary):
pdnsutil show-zone cdn-geodev.runonflux.io | grep -i kind

# Clear and re-sync zone on secondary:
pdnsutil clear-zone cdn-geodev.runonflux.io
pdns_control retrieve cdn-geodev.runonflux.io
```
