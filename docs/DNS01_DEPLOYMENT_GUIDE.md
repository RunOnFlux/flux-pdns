# DNS-01 Certificate Management Deployment Guide

## Overview
This guide provides step-by-step instructions for deploying the complete DNS-01 certificate management system with PowerDNS master/slave replication and automated certificate distribution.

## Prerequisites
- Access to PowerDNS servers (dev: 2 servers, prod: 3 servers)
- Access to CDN nodes (cdn-1, cdn-2, cdn-3)
- Ubuntu certificate server (can be small VPS)
- Discord webhook URL for notifications
- SSH access to all servers

## Deployment Steps

### Phase 1: Deploy PowerDNS Master/Slave Replication

#### 1.1 Update Development Environment
```bash
# Deploy to development servers
ansible-playbook -i hosts.yaml powerdns_setup.yaml -e "DEPLOY_ENV=staging"
```

#### 1.2 Update Production Environment
```bash
# Deploy to production servers
ansible-playbook -i hosts.yaml powerdns_setup.yaml -e "DEPLOY_ENV=production"
```

#### 1.3 Verify Replication
```bash
# Test zone transfers on slave servers
dig @<slave-server-ip> cdn-geodev.runonflux.io AXFR
dig @<slave-server-ip> cdn-geo.runonflux.io AXFR

# Verify TSIG keys exist on masters (for zone transfer only)
ssh root@10.100.0.154 "ls -la /etc/powerdns/tsig-keys/"  # Dev
ssh root@10.100.0.153 "ls -la /etc/powerdns/tsig-keys/"  # Prod

# Verify PowerDNS API is enabled
curl -H "X-API-Key: \$(grep api-key /etc/powerdns/pdns.conf | cut -d= -f2)" http://10.100.0.154:8081/api/v1/servers/localhost
curl -H "X-API-Key: \$(grep api-key /etc/powerdns/pdns.conf | cut -d= -f2)" http://10.100.0.153:8081/api/v1/servers/localhost
```

### Phase 2: Set Up Certificate Server

#### 2.1 Deploy Certificate Server
```bash
# On the certificate server (Ubuntu VPS)
scp scripts/cert-server/setup-cert-server.sh root@<cert-server>:/tmp/
ssh root@<cert-server> "bash /tmp/setup-cert-server.sh"
```

#### 2.2 Extract and Deploy API Keys
```bash
# On your local machine
./scripts/cert-server/extract-api-keys.sh both

# Deploy to certificate server
cd /tmp/api-keys
./deploy-to-cert-server.sh <cert-server-ip>
```

#### 2.3 Configure Discord Notifications
```bash
# On certificate server
echo "https://discord.com/api/webhooks/YOUR/WEBHOOK/URL" > /opt/certbot/discord-webhook.txt
chown certbot:certbot /opt/certbot/discord-webhook.txt
chmod 600 /opt/certbot/discord-webhook.txt
```

#### 2.4 Test Certificate Issuance
```bash
# Test development certificate
sudo -u certbot /opt/certbot/scripts/cert-dev.sh

# Test production certificate  
sudo -u certbot /opt/certbot/scripts/cert-prod.sh
```

### Phase 3: Set Up Certificate Distribution

#### 3.1 Configure SSH Keys
```bash
# On certificate server
scp scripts/cert-server/setup-ssh-keys.sh root@<cert-server>:/tmp/
ssh root@<cert-server> "bash /tmp/setup-ssh-keys.sh --distribute"
```

#### 3.2 Deploy Certificate Distribution Scripts
```bash
# Copy deployment scripts to certificate server
scp scripts/cert-server/deploy-cert-*.sh root@<cert-server>:/opt/certbot/scripts/
ssh root@<cert-server> "chown certbot:certbot /opt/certbot/scripts/deploy-cert-*.sh"
ssh root@<cert-server> "chmod +x /opt/certbot/scripts/deploy-cert-*.sh"
```

#### 3.3 Test Certificate Deployment
```bash
# Test development deployment
sudo -u certbot /opt/certbot/scripts/deploy-cert-dev.sh

# Test production deployment
sudo -u certbot /opt/certbot/scripts/deploy-cert-prod.sh
```

### Phase 4: Set Up Monitoring and Automation

#### 4.1 Deploy Monitoring System
```bash
# On certificate server
scp scripts/cert-server/setup-monitoring.sh root@<cert-server>:/tmp/
ssh root@<cert-server> "bash /tmp/setup-monitoring.sh"
```

#### 4.2 Configure Automated Monitoring
```bash
# Run initial health check
sudo -u certbot /opt/certbot/monitoring/scripts/health-check.sh

# Generate dashboard
sudo -u certbot /opt/certbot/monitoring/scripts/generate-dashboard.sh
```

#### 4.3 Verify Cron Jobs
```bash
# Check cron jobs are installed
sudo -u certbot crontab -l
```

## Configuration Files

### PowerDNS Configuration
- **Master servers**: Europe servers (10.100.0.x)
- **Slave servers**: US/Asia servers  
- **TSIG keys**: Generated automatically during deployment
- **Zone transfers**: Secured with TSIG authentication

### Certificate Server Structure
```
/opt/certbot/
├── configs/
│   ├── pdns-dev.ini         # Development PowerDNS API config
│   └── pdns-prod.ini        # Production PowerDNS API config
├── scripts/
│   ├── cert-dev.sh          # Development certificate management
│   ├── cert-prod.sh         # Production certificate management
│   ├── deploy-cert-dev.sh   # Development deployment
│   ├── deploy-cert-prod.sh  # Production deployment
│   └── discord-notify.sh    # Discord notifications
├── monitoring/
│   ├── scripts/
│   │   ├── health-check.sh  # Comprehensive health monitoring
│   │   └── generate-dashboard.sh # HTML dashboard
│   └── data/
│       └── health-status.json    # Current status data
└── logs/                    # All log files
```

## Operational Procedures

### Manual Certificate Renewal
```bash
# Development
sudo -u certbot /opt/certbot/scripts/cert-dev.sh

# Production
sudo -u certbot /opt/certbot/scripts/cert-prod.sh
```

### Check Certificate Status
```bash
# View dashboard
cat /opt/certbot/monitoring/dashboard.html

# Check expiration
sudo -u certbot openssl x509 -in /etc/letsencrypt/live/cdn-geo.runonflux.io/cert.pem -noout -dates
```

### Monitor Health
```bash
# Run health check
sudo -u certbot /opt/certbot/monitoring/scripts/health-check.sh

# View status
cat /opt/certbot/monitoring/data/health-status.json | jq .
```

### Troubleshooting DNS Updates
```bash
# Test DNS update manually via PowerDNS API
API_KEY=$(grep pdns_key /opt/certbot/configs/pdns-prod.ini | cut -d'=' -f2 | tr -d ' ')
curl -X PATCH "http://10.100.0.153:8081/api/v1/servers/localhost/zones/cdn-geo.runonflux.io" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [
      {
        "name": "_acme-challenge.cdn-geo.runonflux.io.",
        "type": "TXT",
        "records": [{"content": "\"test-token\"", "disabled": false}]
      }
    ]
  }'
```

### View Logs
```bash
# Certificate logs
tail -f /opt/certbot/logs/cert-*.log

# Deployment logs  
tail -f /opt/certbot/logs/deploy-*.log

# Health check logs
tail -f /opt/certbot/logs/health-check.log
```

## Security Considerations

### API Key Security
- Keys stored with 600 permissions
- Separate keys for replication (TSIG) and ACME challenges (API)
- PowerDNS API only accessible from localhost (secure by default)
- Regular key rotation (quarterly recommended)

### SSH Key Security
- Dedicated keypairs for certificate deployment
- Restricted SSH commands via sudoers
- Key rotation script available

### Certificate Security
- Private keys never transmitted in plaintext
- Certificate validation before deployment
- Automated backups with encryption

## Maintenance Tasks

### Weekly
- Review certificate expiration status
- Check health monitoring alerts
- Verify all CDN nodes are accessible

### Monthly
- Review logs for any errors
- Test manual certificate renewal
- Verify backup integrity

### Quarterly  
- Rotate API keys
- Rotate SSH keys
- Review and update documentation

## Emergency Procedures

### Certificate Expiry Emergency
1. Run manual renewal immediately
2. Check Discord notifications for errors
3. Verify certificate deployment to all CDN nodes
4. If DNS-01 fails, check PowerDNS master connectivity

### PowerDNS Master Failure
1. Verify slave servers are still serving zones
2. If needed, promote a slave to master temporarily
3. Update certificate server to point to new master
4. Restore original master when available

### CDN Node Certificate Deployment Failure
1. Check SSH connectivity to failed nodes
2. Verify nginx configuration on nodes
3. Deploy certificates manually if needed
4. Check for filesystem or permission issues

## Support Information

### Log Locations
- Certificate operations: `/opt/certbot/logs/`
- PowerDNS logs: `/var/log/pdns/`
- Nginx logs: `/var/log/nginx/`

### Key Commands
```bash
# Certificate server status
systemctl status cron
sudo -u certbot crontab -l

# PowerDNS status  
systemctl status pdns
pdns_control ping

# CDN node status
systemctl status nginx
nginx -t
```

### Discord Notifications
All certificate events are automatically sent to Discord:
- ✅ Successful certificate renewals and deployments
- ⚠️ Warnings for expiring certificates (30 days)
- ❌ Errors in certificate renewal or deployment
- 🚨 Critical issues requiring immediate attention

## Success Criteria

The deployment is successful when:
- [ ] PowerDNS master/slave replication is working
- [ ] Certificate server can issue certificates via DNS-01
- [ ] Certificates automatically deploy to all CDN nodes
- [ ] HTTPS works on all CDN nodes with new certificates
- [ ] Automated renewal process is functioning
- [ ] Health monitoring is active with Discord notifications
- [ ] All logs show no errors

## Next Steps

After successful deployment:
1. Monitor the system for 1 week to ensure stability
2. Document any environment-specific configurations
3. Train team members on operational procedures
4. Schedule regular maintenance windows
5. Consider implementing additional monitoring tools if needed