#!/usr/bin/env python3
"""
Zone Generation Script for PowerDNS
Generates DNS zone files from templates with environment-specific configurations
"""

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path
import yaml
from jinja2 import Environment, FileSystemLoader, Template


def load_config(config_file):
    """Load configuration from vars.yaml"""
    try:
        with open(config_file, "r") as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"Error: Configuration file {config_file} not found")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"Error parsing YAML file: {e}")
        sys.exit(1)


def get_serial():
    """Generate today's serial in YYYYMMDD00 format"""
    return datetime.now().strftime("%Y%m%d00")


def generate_zone(zone_name, environment, zone_type, output_dir, config):
    """Generate a zone file from template"""

    # Setup Jinja2 environment
    template_dir = Path(__file__).parent.parent / "templates"
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template("zone.template.j2")

    # Get environment-specific config
    env_config = config["powerdns"][environment]

    # Base template variables
    nameserver_host = "pdns2" if environment == "staging" else "pdns1"
    template_vars = {
        "zone_name": zone_name,
        "environment": environment,
        "serial": get_serial(),
        "soa_nameserver": f"{nameserver_host}.runonflux.io.",
        "nameservers": [f"{nameserver_host}.runonflux.io."],
        "ansible_date_time": {"iso8601": datetime.now().isoformat()},
    }

    # Zone type specific configurations
    if zone_type == "app":
        template_vars.update(
            {
                "default_ttl": "3600",
                "lua_routing": True,
                "routing_script": "app_routing.lua",
                "routing_function": "appRouteCname",
                "debug_function": "appRouteDebug",
            }
        )

    elif zone_type == "geo":
        template_vars.update(
            {
                "default_ttl": "300",
                "geo_routing": True,
                "geo_regions": [
                    {
                        "name": "us-west",
                        "description": "West Coast USA",
                        "server": "cdn-6.runonflux.io",
                        "ip": "107.152.47.137",
                    },
                    {
                        "name": "eu-west",
                        "description": "France EU",
                        "server": "cdn-1.runonflux.io",
                        "ip": "5.39.57.50",
                    },
                    {
                        "name": "asia-east",
                        "description": "Hong Kong Asia",
                        "server": "cdn-4.runonflux.io",
                        "ip": "114.29.237.116",
                    },
                ],
            }
        )

    elif zone_type == "simple":
        template_vars.update(
            {
                "default_ttl": "3600",
                "lua_routing": False,
                "geo_routing": False,
            }
        )

    # Render template
    try:
        zone_content = template.render(**template_vars)
    except Exception as e:
        print(f"Error rendering template: {e}")
        sys.exit(1)

    # Write zone file
    output_file = Path(output_dir) / f"{zone_name}.zone"
    try:
        with open(output_file, "w") as f:
            f.write(zone_content)
        print(f"Zone file generated: {output_file}")
        return output_file
    except IOError as e:
        print(f"Error writing zone file: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Generate PowerDNS zone files from templates"
    )
    parser.add_argument(
        "zone_name", help="Domain name for the zone (e.g., example.com)"
    )
    parser.add_argument(
        "environment", choices=["staging", "production"], help="Environment"
    )
    parser.add_argument(
        "zone_type",
        choices=["app", "geo", "simple"],
        help="Zone type: app=application routing, geo=geographic routing, simple=basic zone",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        help="Output directory for zone files (default: ../zones from script location)",
    )
    parser.add_argument(
        "-c",
        "--config",
        help="Configuration file path (default: ../vars.yaml from script location)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show template output without writing file",
    )

    args = parser.parse_args()

    # Set default paths relative to script location
    script_dir = Path(__file__).parent
    project_root = script_dir.parent

    config_path = args.config if args.config else project_root / "vars.yaml"
    output_dir = args.output_dir if args.output_dir else project_root / "zones"

    # Load configuration
    config = load_config(config_path)

    # Generate zone
    if args.dry_run:
        print("=== DRY RUN - Zone file content ===")
        # For dry run, just print the content
        template_dir = Path(__file__).parent.parent / "templates"
        env = Environment(loader=FileSystemLoader(template_dir))
        template = env.get_template("zone.template.j2")

        nameserver_host = "pdns2" if args.environment == "staging" else "pdns1"
        template_vars = {
            "zone_name": args.zone_name,
            "environment": args.environment,
            "serial": get_serial(),
            "soa_nameserver": f"{nameserver_host}.runonflux.io.",
            "nameservers": [f"{nameserver_host}.runonflux.io."],
            "ansible_date_time": {"iso8601": datetime.now().isoformat()},
        }

        if args.zone_type == "app":
            template_vars.update(
                {
                    "default_ttl": "3600",
                    "lua_routing": True,
                    "routing_script": "app_routing.lua",
                    "routing_function": "appRouteCname",
                    "debug_function": "appRouteDebug",
                }
            )

        print(template.render(**template_vars))
    else:
        generate_zone(
            args.zone_name, args.environment, args.zone_type, output_dir, config
        )


if __name__ == "__main__":
    main()
