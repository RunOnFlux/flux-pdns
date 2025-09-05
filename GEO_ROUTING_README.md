# PowerDNS Geo-Routing with Health Checks

This document describes the implementation of geographic DNS routing with automatic health checking and failover for the cdn-geo.runonflux.io domain.

## Overview

The geo-routing system provides:
- Geographic-based DNS resolution to direct clients to the nearest CDN server
- Automatic health checking of CDN servers every 2 seconds
- Failover to the next closest server when a server goes down
- 5-minute recovery period when servers come back online
- Support for three global CDN locations

## CDN Servers

| Server | IP Address | Location | Hostname |
|--------|------------|----------|----------|
| CDN-6 | 107.152.47.137 | West Coast USA | cdn-6.runonflux.io |
| CDN-1 | 5.39.57.50 | Dunkerque, EU | cdn-1.runonflux.io |
| CDN-4 | 114.29.237.116 | Hong Kong, East Asia | cdn-4.runonflux.io |

## Architecture

The implementation uses PowerDNS with the Bind backend and Lua Records to provide:

1. **Backend**: Bind backend replaces the previous pipe backend for better performance and reliability
2. **Health Checking**: The `ifportup()` function checks port 443 (HTTPS) on each CDN server
3. **Geographic Routing**: The `pickclosest()` function uses MaxMind GeoIP databases to select the geographically nearest healthy server
4. **Failover Logic**: Automatic failover after 3 failed health checks (6 seconds total)
5. **Recovery Tracking**: 5-minute delay before re-adding recovered servers to the pool

## Configuration Files

### 1. PowerDNS Main Configuration (`pdns-geo.conf.j2`)
- Enables Lua records and configures health check intervals
- Uses bind backend exclusively (pipe backend removed)
- Configures MaxMind GeoIP databases for location detection
- GeoIP database path: `/usr/share/GeoIP/GeoLite2-City.mmdb`

### 2. Lua Script (`scripts/geo_routing.lua`)
- Implements the `geoRoute()` function for A record queries
- Tracks server recovery times
- Provides fallback logic when all servers are down

### 3. Zone Files
- `zones/cdn-geo.runonflux.io.zone`: Geo-routing configuration with Lua records
- `zones/app.runonflux.io.zone`: Production app routing (character-based load balancing)
- `zones/app2.runonflux.io.zone`: Staging app routing (character-based load balancing)
- All zones use Lua records for dynamic routing logic

### 4. Ansible Playbook (`powerdns_setup.yml`)
- Automates deployment of all components
- Installs required packages including MaxMind geoipupdate
- Downloads and manages GeoIP databases from MaxMind
- Configures automatic weekly database updates via cron
- Validates PowerDNS configuration before restart

## Health Check Parameters

- **Check Interval**: 2 seconds
- **Timeout**: 2 seconds per check
- **Failure Threshold**: 3 consecutive failures
- **Detection Time**: ~6 seconds (3 checks × 2 seconds)
- **Recovery Period**: 5 minutes after server comes back online

## Deployment

### Prerequisites
- Ubuntu 24.04 or later (tested on Ubuntu 24.04)
- PowerDNS 4.9.5 or later
- Python 3.6+ (for monitoring scripts)
- Ansible for automated deployment
- MaxMind account for GeoIP databases (free registration required)

### Installation Steps

1. **Update hosts inventory**:
   ```bash
   vim hosts.ini
   # Add your target servers
   ```

2. **Configure MaxMind credentials**:
   - Register at https://www.maxmind.com/en/geolite2/signup
   - Get your Account ID and generate a License Key
   - Add as GitHub Secrets: `MAXMIND_ACCOUNT_ID` and `MAXMIND_LICENSE_KEY`
   - Or update directly in `powerdns_setup.yml`

3. **Deploy with Ansible**:
   ```bash
   # For production
   ansible-playbook -i hosts.ini powerdns_setup.yml -e "DEPLOY_ENV=production"
   
   # For staging  
   ansible-playbook -i hosts.ini powerdns_setup.yml -e "DEPLOY_ENV=staging"
   
   # With MaxMind credentials (if not using GitHub Actions)
   ansible-playbook -i hosts.ini powerdns_setup.yml \
     -e "DEPLOY_ENV=production" \
     -e "maxmind_account_id=YOUR_ID" \
     -e "maxmind_license_key=YOUR_KEY"
   ```

3. **Verify installation**:
   ```bash
   # Test DNS resolution
   dig @your-server-ip cdn-geo.runonflux.io A
   
   # Run test script
   ./test_geo_routing.sh your-server-ip
   ```

## Testing

### Test Script (`scripts/test_geo_routing.sh`)
Comprehensive testing script that verifies:
- Basic DNS resolution
- Health check functionality
- Geographic routing distribution
- Failover capabilities

Usage:
```bash
./scripts/test_geo_routing.sh [dns_server_ip]
```

### Monitoring Script (`scripts/monitor_cdn_health.py`)
Real-time monitoring of CDN server health:

```bash
# Interactive monitoring
./scripts/monitor_cdn_health.py --dns-server your-server-ip

# JSON output for automation
./scripts/monitor_cdn_health.py --json --dns-server your-server-ip

# Monitor for specific duration
./scripts/monitor_cdn_health.py --duration 60 --interval 5
```

## Failover Testing

To test failover behavior:

1. **Block a CDN server** (simulate failure):
   ```bash
   sudo iptables -A OUTPUT -d 107.152.47.137 -j DROP
   ```

2. **Wait 6 seconds** for detection (3 failed checks)

3. **Verify failover**:
   ```bash
   dig @your-server-ip cdn-geo.runonflux.io A
   # Should return a different CDN server IP
   ```

4. **Restore access**:
   ```bash
   sudo iptables -D OUTPUT -d 107.152.47.137 -j DROP
   ```

5. **Wait 5 minutes** for recovery period

6. **Verify recovery**:
   ```bash
   dig @your-server-ip cdn-geo.runonflux.io A
   # Server should be back in rotation
   ```

## DNS Queries

### Standard Query
```bash
dig cdn-geo.runonflux.io A
```
Returns the IP of the geographically closest healthy CDN server.

### Direct Server Queries (for testing)
```bash
dig cdn-6.runonflux.io A   # West Coast USA
dig cdn-1.runonflux.io A   # Dunkerque, EU
dig cdn-4.runonflux.io A   # Hong Kong, Asia
```

## Troubleshooting

### Check PowerDNS Status
```bash
sudo systemctl status pdns
sudo journalctl -u pdns -f
```

### Validate Configuration
```bash
sudo pdns_server --daemon=no --guardian=no --check-config
```

### Test Lua Script
```bash
# Check for syntax errors
lua -l /opt/pdns/scripts/geo_routing.lua
```

### Verify GeoIP Database
```bash
mmdblookup --file /usr/share/GeoIP/GeoLite2-City.mmdb --ip 8.8.8.8
```

## Monitoring and Logging

### PowerDNS Logs
- Location: `/var/log/pdns.log`
- Configured with logrotate for automatic rotation
- Includes DNS query logging and health check events

### Health Status Endpoint
Query the status TXT record for server health information:
```bash
dig @your-server-ip _status.cdn-geo.runonflux.io TXT
```

## Security Considerations

1. **Firewall Rules**: Ensure port 53 (DNS) is open
2. **MaxMind Credentials**: Store securely in GitHub Secrets or Ansible Vault
3. **GeoIP Database**: Automatically updated weekly via geoipupdate
4. **Health Checks**: Monitor for false positives/negatives
5. **Rate Limiting**: Consider implementing query rate limits
6. **Backend Security**: Bind backend is more secure than pipe backend (no arbitrary script execution)

## Performance Tuning

### PowerDNS Cache Settings
- `cache-ttl=60`: General cache TTL
- `query-cache-ttl=20`: Query-specific cache
- `max-cache-entries=1000000`: Maximum cache size

### Thread Configuration
- `distributor-threads=3`: Request distribution
- `receiver-threads=2`: Network reception

## Maintenance

### Update GeoIP Databases

#### Automatic Updates (Configured by default)
The system automatically updates GeoIP databases weekly via cron:
```bash
# View cron job
sudo crontab -l | grep geoipupdate
# Output: 0 3 * * 0 /usr/bin/geoipupdate
```

#### Manual Update
```bash
# Update databases manually
sudo geoipupdate

# Verify update
ls -la /usr/share/GeoIP/*.mmdb

# Restart PowerDNS to use new databases
sudo systemctl restart pdns
```

### Add/Remove CDN Servers
1. Edit `/opt/pdns/scripts/geo_routing.lua`
2. Update the `servers` table with new server information
3. Restart PowerDNS: `sudo systemctl restart pdns`

## CI/CD Integration

### GitHub Actions
The repository includes GitHub Actions workflow (`.github/workflows/master.yml`) that:
- Automatically deploys on push to master (staging) or release (production)
- Uses GitHub Secrets for MaxMind credentials
- Runs Ansible playbook with proper environment variables

### Required GitHub Secrets
- `SSH_PRIVATE_KEY`: SSH key for server access
- `MAXMIND_ACCOUNT_ID`: MaxMind account ID
- `MAXMIND_LICENSE_KEY`: MaxMind license key

## Support

For issues or questions:
1. Check PowerDNS logs: `sudo tail -f /var/log/pdns.log`
2. Run diagnostic script: `./scripts/test_geo_routing.sh`
3. Monitor health status: `./scripts/monitor_cdn_health.py`
4. Verify GeoIP updates: `sudo geoipupdate -v`