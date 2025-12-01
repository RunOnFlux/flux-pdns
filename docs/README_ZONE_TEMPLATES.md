# Zone Template System

This directory contains a generic zone template system for creating consistent PowerDNS zone files.

## Files

- `templates/zone.template.j2` - Generic Jinja2 zone template
- `scripts/generate_zone.py` - Python script for generating zones from template
- `generate_zones.yaml` - Optional Ansible playbook for bulk zone generation
- `requirements.txt` - Python dependencies

## Setup

Install required Python packages:

```bash
# Using uv (recommended)
uv pip install -r requirements.txt

# Or using pip
pip install -r requirements.txt
```

## Usage

### Manual Zone Generation

Generate a single zone file:

```bash
# App routing zone (run from project root)
./scripts/generate_zone.py example.com staging app

# Geographic routing zone  
./scripts/generate_zone.py cdn-example.com production geo

# Simple zone (no Lua routing)
./scripts/generate_zone.py simple.com production simple

# Custom output directory
./scripts/generate_zone.py example.com staging app -o /path/to/zones/
```

### Preview Zone Content (Dry Run)

```bash
./scripts/generate_zone.py example.com staging app --dry-run
```

### Bulk Generation with Ansible

Generate all zones from the predefined list:

```bash
ansible-playbook generate_zones.yaml -e "generate_zones=true"
```

## Zone Types

### App Routing (`app`)
- Uses Lua-based character routing
- Loads `app_routing.lua` script
- Includes wildcard CNAME routing
- Debug endpoint at `_debug`
- TTL: 3600 seconds

### Geographic Routing (`geo`) 
- Uses Lua-based geographic routing
- Loads `geo_routing.lua` script
- Health check records for monitoring
- TTL: 300 seconds

### Simple (`simple`)
- Basic zone structure
- No Lua routing
- Manual A/CNAME records via template variables
- TTL: 3600 seconds

## Template Variables

The template accepts these variables:

### Required
- `zone_name` - Domain name
- `environment` - staging/production  
- `nameserver` - pdns1/pdns2

### Optional
- `default_ttl` - Default TTL (3600)
- `serial` - SOA serial (auto-generated YYYYMMDD00)
- `lua_routing` - Enable Lua routing (false)
- `geo_routing` - Enable geo routing (false)
- `routing_script` - Lua script filename
- `routing_function` - Lua function for CNAME
- `debug_function` - Lua debug function
- `custom_records` - List of custom records
- `a_records` - List of A records (simple zones)
- `cname_records` - List of CNAME records (simple zones)

## Customization

### Adding Custom Records

For simple zones, you can add custom records:

```python
template_vars['custom_records'] = [
    {'name': 'www', 'type': 'A', 'value': '192.0.2.1', 'ttl': '300'},
    {'name': 'mail', 'type': 'CNAME', 'value': 'mail.example.com.'},
]
```

### Environment-Specific Configurations

The script automatically uses environment-specific settings from `vars.yaml`:
- Nameserver selection (pdns1 vs pdns2)
- Zone configurations
- Environment detection

## Integration with Existing System

The template system is designed to coexist with existing zone files:
- Existing zones in `zones/` are preserved
- Template can recreate zones with identical content
- Generated zones use same SOA format (YYYYMMDD00)
- Same Lua routing configurations