#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.8"
# dependencies = [
#     "aiodns>=3.0.0",
#     "aiohttp>=3.8.0",
# ]
# ///
"""
CDN Health Monitoring Script for PowerDNS Geo-routing

IMPORTANT: This script is for TESTING and DEBUGGING purposes only.
It is NOT required for the geo-IP functionality to work.
The actual health checking and geo-routing is performed by PowerDNS
using the Lua script (geo_routing.lua) with the ifportup() function.

This script provides external monitoring to verify that the PowerDNS
geo-routing is functioning correctly and to observe failover behavior.

Usage with uv (recommended):
  uv run monitor_cdn_health.py               # Monitor localhost DNS
  uv run monitor_cdn_health.py --dns-server IP    # Monitor specific DNS server
  uv run monitor_cdn_health.py --json        # Single check with JSON output

Usage with regular Python (requires manual pip install):
  ./monitor_cdn_health.py                    # Monitor localhost DNS
  ./monitor_cdn_health.py --dns-server IP    # Monitor specific DNS server
  ./monitor_cdn_health.py --json             # Single check with JSON output
"""

import asyncio
import time
import json
import argparse
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
import aiodns  # type: ignore[import-not-found]
import aiohttp  # type: ignore[import-not-found]

# CDN Server Configuration
CDN_SERVERS = [
    {
        "name": "cdn-6.runonflux.io",
        "ip": "107.152.47.137",
        "location": "West Coast USA",
        "port": 443,
    },
    {
        "name": "cdn-10.runonflux.io",
        "ip": "51.159.52.154",
        "location": "Paris, EU",
        "port": 443,
    },
    {
        "name": "cdn-4.runonflux.io",
        "ip": "114.29.237.116",
        "location": "Hong Kong, East Asia",
        "port": 443,
    },
]


class AsyncCDNHealthMonitor:
    """
    Asynchronous CDN Health Monitor for testing PowerDNS geo-routing.

    NOTE: This is a testing utility only. The actual DNS health checking
    is performed by PowerDNS internally using Lua scripts.
    """

    def __init__(self, dns_server: str = "127.0.0.1", check_interval: int = 2):
        self.dns_server = dns_server
        self.check_interval = check_interval
        self.server_status: Dict[str, Dict[str, Any]] = {}
        self.recovery_tracking: Dict[str, datetime] = {}
        self.resolver: Optional[aiodns.DNSResolver] = None
        self.session: Optional[aiohttp.ClientSession] = None

    async def __aenter__(self) -> "AsyncCDNHealthMonitor":
        """Async context manager entry"""
        self.session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=2))
        self.resolver = aiodns.DNSResolver(nameservers=[self.dns_server], timeout=5.0)
        return self

    async def __aexit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """Async context manager exit"""
        if self.session:
            await self.session.close()

    async def check_port(self, ip: str, port: int, timeout: float = 2.0) -> bool:
        """
        Asynchronously check if a port is open on the given IP.

        This simulates what PowerDNS's ifportup() function does internally.
        """
        try:
            # Create connection with timeout
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(ip, port), timeout=timeout
            )
            writer.close()
            await writer.wait_closed()
            return True
        except (asyncio.TimeoutError, ConnectionRefusedError, OSError):
            return False

    async def check_dns_resolution(self, domain: str) -> List[str]:
        """
        Asynchronously resolve a domain name.

        This tests the actual DNS response from PowerDNS.
        """
        if not self.resolver:
            return []
        try:
            result = await self.resolver.query(domain, "A")
            return [r.host for r in result]
        except Exception as e:
            print(f"DNS resolution error for {domain}: {e}")
            return []

    async def check_https_endpoint(self, ip: str) -> bool:
        """
        Asynchronously check HTTPS endpoint availability.

        More thorough than port check - verifies HTTP/HTTPS response.
        """
        if not self.session:
            return False

        url = f"https://{ip}"
        try:
            async with self.session.get(
                url,
                ssl=False,  # Skip SSL verification for IP-based requests
                allow_redirects=False,
            ) as _response:
                # Any HTTP response means the server is up
                return True
        except Exception:
            return False

    async def update_server_status(self, server: Dict[str, Any]) -> Dict[str, Any]:
        """
        Update the status of a single server asynchronously.

        This mimics the health checking that PowerDNS performs internally.
        """
        ip = server["ip"]
        port = server["port"]

        # Check if port is reachable (what PowerDNS does)
        is_up = await self.check_port(ip, port)

        # Get previous status
        prev_status = self.server_status.get(ip, {})
        was_up = prev_status.get("is_up", False)

        # Track state changes
        now = datetime.now()
        status = {
            "name": server["name"],
            "ip": ip,
            "location": server["location"],
            "is_up": is_up,
            "last_check": now,
            "consecutive_failures": 0
            if is_up
            else prev_status.get("consecutive_failures", 0) + 1,
            "state_changed": is_up != was_up,
            "down_since": None if is_up else (prev_status.get("down_since") or now),
            "up_since": now if (is_up and not was_up) else prev_status.get("up_since"),
            "is_recovering": False,
            "recovery_complete_at": None,
        }

        # Handle recovery tracking (5-minute recovery period as configured in Lua)
        if ip in self.recovery_tracking:
            recovery_start = self.recovery_tracking[ip]
            recovery_duration = now - recovery_start

            if recovery_duration >= timedelta(minutes=5):
                # Recovery complete
                del self.recovery_tracking[ip]
                status["is_recovering"] = False
            else:
                # Still recovering
                status["is_recovering"] = True
                status["recovery_complete_at"] = recovery_start + timedelta(minutes=5)
        elif is_up and not was_up:
            # Server just came back online, start recovery tracking
            self.recovery_tracking[ip] = now
            status["is_recovering"] = True
            status["recovery_complete_at"] = now + timedelta(minutes=5)

        # Determine if server should be considered "healthy" for DNS
        # (matches the logic in geo_routing.lua)
        status["dns_healthy"] = is_up and not status["is_recovering"]

        return status

    async def check_all_servers(self) -> Dict[str, Dict[str, Any]]:
        """Check all servers concurrently"""
        tasks = [self.update_server_status(server) for server in CDN_SERVERS]
        results = await asyncio.gather(*tasks)

        for server, status in zip(CDN_SERVERS, results):
            ip_key = str(server["ip"])  # Ensure string type
            self.server_status[ip_key] = status

        return self.server_status

    async def monitor_loop(self, duration: Optional[int] = None) -> None:
        """
        Main asynchronous monitoring loop.

        This provides real-time visibility into what PowerDNS should be
        seeing internally when it performs health checks.
        """
        start_time = time.time()
        iteration = 0

        print("=" * 80)
        print("CDN Health Monitor - TESTING UTILITY")
        print(
            "This is for testing only - PowerDNS handles actual health checks internally"
        )
        print("=" * 80)
        print(f"DNS Server: {self.dns_server}")
        print(f"Check Interval: {self.check_interval} seconds")
        print(f"Monitoring {len(CDN_SERVERS)} servers")
        print("-" * 80)

        try:
            while True:
                iteration += 1

                # Check all servers concurrently
                await self.check_all_servers()

                # Display status
                self.display_status(iteration)

                # Check DNS resolution concurrently
                dns_task = self.check_dns_resolution("cdn-geo.runonflux.io")
                resolved_ips = await dns_task

                if resolved_ips:
                    print(
                        f"\nDNS Resolution: cdn-geo.runonflux.io -> {', '.join(resolved_ips)}"
                    )

                    # Verify the resolved IP matches a healthy server
                    for ip in resolved_ips:
                        if ip in self.server_status:
                            status = self.server_status[ip]
                            if status["dns_healthy"]:
                                print(
                                    f"  ✓ Resolved to healthy server: {status['name']} ({status['location']})"
                                )
                            elif status["is_recovering"]:
                                print(
                                    f"  ⚠ Resolved to recovering server: {status['name']} ({status['location']})"
                                )
                            else:
                                print(
                                    f"  ✗ WARNING: Resolved to unhealthy server: {status['name']}"
                                )

                # Check if we should exit
                if duration and (time.time() - start_time) >= duration:
                    break

                # Wait for next check
                await asyncio.sleep(self.check_interval)

        except KeyboardInterrupt:
            print("\n\nMonitoring stopped by user")
            self.print_summary()

    def display_status(self, iteration: int) -> None:
        """Display current status of all servers"""
        print(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Check #{iteration}")
        print("-" * 80)

        headers = [
            "Server",
            "Location",
            "Status",
            "Health",
            "Failures",
            "State",
        ]
        rows = []

        for ip, status in self.server_status.items():
            # Determine display status
            if status["is_up"]:
                if status["is_recovering"]:
                    minutes_left = 5 - int(
                        (datetime.now() - self.recovery_tracking[ip]).total_seconds()
                        / 60
                    )
                    state = f"RECOVERING ({minutes_left} min left)"
                    health = "⚠️"
                else:
                    state = "HEALTHY"
                    health = "✅"
                status_text = "UP"
            else:
                state = f"DOWN ({status['consecutive_failures']} failures)"
                health = "❌"
                status_text = "DOWN"

                if status["down_since"]:
                    downtime = datetime.now() - status["down_since"]
                    state += f" for {int(downtime.total_seconds())}s"

            # PowerDNS considers server down after 3 failures (6 seconds)
            if status["consecutive_failures"] >= 3:
                state += " [PDNS: DOWN]"

            rows.append(
                [
                    status["name"],
                    status["location"],
                    status_text,
                    health,
                    str(status["consecutive_failures"]),
                    state,
                ]
            )

        # Print table
        self.print_table(headers, rows)

    def print_table(self, headers: List[str], rows: List[List[str]]) -> None:
        """Print a formatted table"""
        # Calculate column widths
        widths = [len(h) for h in headers]
        for row in rows:
            for i, cell in enumerate(row):
                widths[i] = max(widths[i], len(str(cell)))

        # Print headers
        header_line = " | ".join(h.ljust(w) for h, w in zip(headers, widths))
        print(header_line)
        print("-" * len(header_line))

        # Print rows
        for row in rows:
            print(" | ".join(str(cell).ljust(w) for cell, w in zip(row, widths)))

    def print_summary(self) -> None:
        """Print monitoring summary"""
        print("\n" + "=" * 80)
        print("MONITORING SUMMARY (TEST RESULTS)")
        print("=" * 80)
        print("\nNOTE: This shows what PowerDNS should be seeing internally.")
        print("Actual DNS behavior is controlled by PowerDNS Lua scripts.\n")

        for ip, status in self.server_status.items():
            print(f"\n{status['name']} ({status['location']}):")
            print(f"  Current Status: {'UP' if status['is_up'] else 'DOWN'}")
            print(f"  DNS Healthy: {status['dns_healthy']}")
            print(f"  PowerDNS Should Use: {'YES' if status['dns_healthy'] else 'NO'}")

            if status["down_since"]:
                downtime = datetime.now() - status["down_since"]
                print(f"  Downtime: {int(downtime.total_seconds())} seconds")

            if status["is_recovering"]:
                remaining = status["recovery_complete_at"] - datetime.now()
                print(
                    f"  Recovery Time Remaining: {int(remaining.total_seconds())} seconds"
                )

    async def single_check(self) -> Dict[str, Any]:
        """Perform a single check of all servers (for JSON output)"""
        await self.check_all_servers()

        # Add DNS resolution check
        resolved_ips = await self.check_dns_resolution("cdn-geo.runonflux.io")

        # Convert datetime objects to strings for JSON serialization
        servers_output: Dict[str, Dict[str, Any]] = {}

        for ip, status in self.server_status.items():
            server_data = {
                k: v.isoformat() if isinstance(v, datetime) else v
                for k, v in status.items()
            }
            # Add PowerDNS interpretation
            server_data["pdns_should_use"] = status["dns_healthy"]
            server_data["pdns_marked_down"] = status["consecutive_failures"] >= 3
            servers_output[ip] = server_data

        output: Dict[str, Any] = {
            "timestamp": datetime.now().isoformat(),
            "dns_server": self.dns_server,
            "dns_resolution": {
                "domain": "cdn-geo.runonflux.io",
                "resolved_ips": resolved_ips,
            },
            "servers": servers_output,
        }

        output["test_note"] = (
            "This is test output only. Actual DNS behavior is controlled by PowerDNS."
        )

        return output


async def main() -> None:
    parser = argparse.ArgumentParser(
        description="Test monitor for PowerDNS geo-routing (NOT required for operation)",
        epilog="NOTE: This is a testing utility. PowerDNS handles actual health checks internally via Lua scripts.",
    )
    parser.add_argument(
        "--dns-server",
        default="127.0.0.1",
        help="DNS server to query for testing (default: 127.0.0.1)",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=2,
        help="Check interval in seconds (default: 2)",
    )
    parser.add_argument(
        "--duration",
        type=int,
        help="Test duration in seconds (runs forever if not specified)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output single test result in JSON format",
    )

    args = parser.parse_args()

    async with AsyncCDNHealthMonitor(
        dns_server=args.dns_server, check_interval=args.interval
    ) as monitor:
        if args.json:
            # Single check with JSON output
            result = await monitor.single_check()
            print(json.dumps(result, indent=2))
        else:
            # Interactive monitoring
            await monitor.monitor_loop(duration=args.duration)


if __name__ == "__main__":
    # With uv, dependencies are automatically installed, but provide fallback for regular Python
    try:
        import aiodns
        import aiohttp
    except ImportError as e:
        print(f"ERROR: Required library missing: {e}")
        print(
            "\nRecommended: Use 'uv run monitor_cdn_health.py' to automatically install dependencies"
        )
        print("Alternative: Install manually with 'pip install aiodns aiohttp'")
        print(
            "\nNOTE: These libraries are only needed for testing. PowerDNS does not require them."
        )
        exit(1)

    # Run the async main function
    asyncio.run(main())
