#!/bin/bash
# Create a minimal mock GeoLite2 database for testing
# This creates a dummy file that satisfies PowerDNS GeoIP requirements

# Create a minimal mock database file
echo "Mock GeoLite2-City database for testing" > /usr/share/GeoIP/GeoLite2-City.mmdb
echo "This is not a real MaxMind database, just a placeholder for Docker testing" >> /usr/share/GeoIP/GeoLite2-City.mmdb

# Set proper permissions
chmod 644 /usr/share/GeoIP/GeoLite2-City.mmdb