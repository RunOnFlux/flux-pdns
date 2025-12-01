# DNS-01 Certificate Architecture Plan

## Overview
This document outlines the complete architecture and implementation plan for setting up Let's Encrypt certificates using DNS-01 challenge validation with PowerDNS master/slave replication and automated certificate distribution to CDN nodes.

## Current Infrastructure

### PowerDNS Servers
**Development Environment:**
- 2 PowerDNS servers (geographically distributed)
- Load balanced behind `pdns2.runonflux.io`
- Currently no replication between servers

**Production Environment:**
- 3 PowerDNS servers (geographically distributed)
- Load balanced behind `pdns1.runonflux.io`
- Currently no replication between servers

### CDN Infrastructure
- **cdn-1.runonflux.io** (Germany, EU)
- **cdn-2.runonflux.io** (West Coast USA)
- **cdn-3.runonflux.io** (Hong Kong, Asia)
- All serve content via nginx with existing certbot certificates

### Target Domains
- **Development**: `cdn-geodev.runonflux.io`
- **Production**: `cdn-geo.runonflux.io`

## Proposed Architecture

### 1. PowerDNS Master/Slave Replication

#### Master Configuration (Europe Servers)
**Development:**
- Europe dev PowerDNS server becomes master
- Handles all DNS updates including ACME challenges

**Production:**
- Europe prod PowerDNS server becomes master
- Handles all DNS updates including ACME challenges

#### Slave Configuration (US/Asia Servers)
- US and Asia servers become slaves
- Automatically replicate zone changes from Europe masters
- Provide redundancy and geographic distribution

#### Replication Flow
```
Certificate Server -> Europe Master -> US/Asia Slaves
                                   -> Global DNS Resolution
```

### 2. Dedicated Certificate Server

#### Server Specifications
- Ubuntu server (can be small VPS)
- Location: Europe (for low latency to master DNS servers)
- Role: Centralized certificate management for both environments

#### Software Stack
- **certbot** with `certbot-dns-pdns` plugin
- **PowerDNS HTTP API** for DNS record management
- **SSH client** for certificate distribution
- **Discord webhook** integration for notifications

#### API Authentication
- PowerDNS HTTP API keys for each environment:
  - Development API key for staging environment
  - Production API key for production environment
- Secure key storage with proper file permissions (600)
- API endpoints on localhost:8081 (secure by default)

### 3. Certificate Management Workflow

#### DNS-01 Challenge Process
1. Certificate server requests certificate from Let's Encrypt
2. Let's Encrypt provides DNS-01 challenge token
3. Certificate server uses PowerDNS HTTP API to add TXT record to Europe master
4. Europe master notifies slaves to replicate change
5. Let's Encrypt validates TXT record from any geographic location
6. Certificate issued upon successful validation

#### Certificate Distribution
1. Validate certificate before distribution
2. Distribute to all CDN nodes via SSH:
   - cdn-1.runonflux.io (EU)
   - cdn-2.runonflux.io (US)
   - cdn-3.runonflux.io (Asia)
3. Update nginx configurations
4. Graceful nginx reload
5. Verify HTTPS functionality

## Implementation Phases

### Phase 1: PowerDNS Master/Slave Replication Setup
**Estimated Time: 2-4 hours**

#### Tasks:
1. Update PowerDNS configuration templates
2. Configure Europe servers as masters
3. Configure US/Asia servers as slaves
4. Generate and distribute TSIG keys for replication
5. Update ansible playbook for role-based configuration
6. Test replication between regions
7. Validate zone synchronization

#### Deliverables:
- Updated `pdns-geo.conf.j2` template
- Modified `powerdns_setup.yml` ansible playbook
- TSIG keys for zone transfer authentication
- Replication validation scripts

### Phase 2: Dedicated Certificate Server Setup
**Estimated Time: 3-5 hours**

#### Tasks:
1. Deploy certificate server (Ubuntu VPS)
2. Install and configure certbot with certbot-dns-pdns plugin
3. Extract PowerDNS API keys from master servers
4. Configure PowerDNS API settings for both environments
5. Create certificate management scripts
6. Set up certificate storage and backup
7. Test DNS-01 challenge process

#### Deliverables:
- Certificate server with certbot installed
- Environment-specific API keys
- PowerDNS API configuration files
- Certificate management scripts
- Automated renewal configuration

### Phase 3: Secure Certificate Distribution
**Estimated Time: 4-6 hours**

#### Tasks:
1. Generate SSH keypairs for certificate deployment
2. Distribute public keys to all CDN nodes
3. Create certificate deployment scripts
4. Update nginx configuration templates
5. Implement deployment validation
6. Set up rollback procedures
7. Test end-to-end certificate deployment

#### Deliverables:
- SSH key infrastructure
- Certificate deployment scripts
- Updated nginx configurations
- Deployment validation tools
- Rollback procedures

### Phase 4: Monitoring & Automation
**Estimated Time: 2-3 hours**

#### Tasks:
1. Set up certificate expiration monitoring
2. Configure automated renewal process
3. Implement Discord webhook integration
4. Create health check scripts
5. Set up audit logging
6. Configure backup procedures
7. Test full automation workflow

#### Deliverables:
- Certificate monitoring system
- Automated renewal scripts
- Discord notification integration
- Health check and validation tools
- Comprehensive logging and backup system

## Security Considerations

### API Key Security
- Separate keys for replication (TSIG) and ACME challenges (API)
- Restricted file permissions (600)
- Key rotation procedures
- Secure key distribution
- API endpoints only accessible from localhost (secure by default)

### Certificate Security
- Private keys never transmitted in plaintext
- Certificate validation before deployment
- Secure backup storage with encryption
- Audit logging for all operations

### SSH Security
- Dedicated keypairs for certificate deployment only
- Restricted SSH commands
- Key-based authentication only
- Regular key rotation

### Environment Isolation
- Separate API keys per environment
- Independent certificate management
- Isolated failure domains
- Clear audit trails

## Benefits

### Operational Benefits
- **Centralized Management**: Single point of certificate control
- **Automated Renewal**: No manual intervention required
- **Geographic Redundancy**: Multiple DNS servers serve zones
- **Fast Propagation**: NOTIFY ensures quick replication

### Security Benefits
- **DNS-01 Challenge**: Works behind firewalls, no port 80/443 required
- **HTTP API Authentication**: Secure API key-based DNS updates
- **Environment Separation**: Dev/prod isolation
- **Comprehensive Logging**: Full audit trail

### Reliability Benefits
- **Multi-Region DNS**: High availability even with server failures
- **Automated Recovery**: Self-healing certificate renewal
- **Validation Checks**: Prevent deployment of invalid certificates
- **Rollback Capability**: Quick recovery from issues

## Monitoring & Alerting

### Certificate Lifecycle Events
- Certificate issuance success/failure
- Renewal attempts and results
- Deployment status across all nodes
- Expiration warnings (30-day threshold)

### System Health Monitoring
- PowerDNS replication status
- Certificate server availability
- CDN node certificate validity
- HTTPS endpoint functionality

### Discord Integration
- Rich embed messages with certificate details
- Color-coded status indicators
- Actionable error information
- Success confirmations

## Maintenance Procedures

### Regular Tasks
- Weekly certificate expiration checks
- Monthly API key validation
- Quarterly security audits
- Annual key rotation

### Emergency Procedures
- Certificate revocation process
- Manual certificate deployment
- PowerDNS failover procedures
- Rollback to previous certificates

## Timeline Summary
- **Phase 1**: 2-4 hours (PowerDNS Replication)
- **Phase 2**: 3-5 hours (Certificate Server)
- **Phase 3**: 4-6 hours (Distribution System)
- **Phase 4**: 2-3 hours (Monitoring/Automation)
- **Total Estimated Time**: 11-18 hours

## Success Criteria
1. PowerDNS replication working between all regions
2. DNS-01 challenges completing successfully
3. Certificates automatically deploying to all CDN nodes
4. Nginx serving HTTPS with new certificates
5. Automated renewal process functioning
6. Discord notifications working for all events
7. Full documentation and runbooks complete