#!/usr/bin/env python3
"""Reconcile template-owned zone records against vars.yaml, through the PowerDNS API.

Zone records are written once, when powerdns_setup.yaml first creates the zone,
and never again - the generate/import tasks are gated on the zone being absent
from SQLite. Editing vars.yaml afterwards changes nothing while the deploy still
reports success. That is how _health.eu-central pointed at a decommissioned
address for seven months, and how the pdns1 -> pdns nameserver fix deployed on
2026-07-28 did nothing at all.

The gate cannot simply be removed, because the import is `pdnsutil load-zone`,
which replaces the whole zone. Doing that on every run would destroy every
record written out of band: the ~170 app A records, and any _acme-challenge TXT
that certbot's DNS-01 flow has in flight. The second is the more dangerous of
the two, since those records exist only during an issuance - a whole-zone
rewrite tests clean and breaks renewal on an unlucky run.

So this reconciles individual records instead, and owns an enumerated set:

  written    apex NS
             apex SOA MNAME and RNAME  (never the serial)
             _health.<region> TXT

  detected   LUA records - compared and reported, never written

  ignored    everything else, which is neither read nor written

LUA records are deliberately read-only. Their content is a pointer to a script
file, and that file is templated to disk on every run, so the part that actually
changes is already reconciled. What is left is the apex A that serves all geo
traffic and the wildcard CNAME that serves every Flux app: the highest
consequence records in the zones, the rarest to change, and the fiddliest to
quote. Drift there should stop a deploy and get a human, not be silently
rewritten.

Exit codes:
  0   completed; see "changed" in the JSON report on stdout
  1   error
  2   LUA record drift; nothing was written
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# Deletion candidates are bounded by this prefix, by record type, and by zone -
# in code, not by trusting the diff to be correct. _acme-challenge cannot be
# selected by construction rather than by intent.
HEALTH_PREFIX = "_health."

SOA_FIELDS = 7

# A TXT string longer than this is split into several quoted chunks in the
# rdata, so what we sent and what comes back would never compare equal and the
# reconcile would report a change on every single run. Refuse instead.
MAX_TXT_STRING = 255


class ReconcileError(RuntimeError):
    """Anything that should fail the play rather than be worked around."""


def canonical(name: str) -> str:
    """PowerDNS canonicalises names and name-valued rdata to a trailing dot.

    vars.yaml already writes nameservers and soa_nameserver that way, so the two
    compare directly. (`pdnsutil list-zone` renders the SOA MNAME *without* the
    dot, so a reconcile built on its output would report a change forever.)
    """
    return name if name.endswith(".") else name + "."


def txt_rdata(value: str) -> str:
    """TXT rdata carries its own quotes, inside the JSON string.

    The API returns '"Germany EU - cdn-1..."' including the quote characters.
    Building the desired value without them makes every run report a change.
    """
    return '"{}"'.format(value)


def index_rrsets(zone_data: dict) -> dict:
    """Key the zone's rrsets by (name, type) for lookup."""
    return {(r["name"], r["type"]): r for r in zone_data.get("rrsets", [])}


def _replace(name: str, rtype: str, ttl: int, contents: list) -> dict:
    return {
        "name": name,
        "type": rtype,
        "ttl": ttl,
        "changetype": "REPLACE",
        "records": [{"content": c, "disabled": False} for c in contents],
    }


def find_lua_drift(existing: dict, desired: dict) -> list:
    """Compare LUA records without proposing any write.

    Content only - a TTL difference on a LUA record is harmless and is not worth
    failing a deploy over.
    """
    drift = []
    for want in desired.get("lua_records", []):
        name = canonical(want["name"])
        rrset = existing.get((name, "LUA"))
        if rrset is None:
            drift.append({"name": name, "expected": want["content"], "actual": None})
            continue
        actual = [r["content"] for r in rrset.get("records", [])]
        if actual != [want["content"]]:
            drift.append({"name": name, "expected": want["content"], "actual": actual})
    return drift


def compute_changes(zone: str, existing: dict, desired: dict) -> list:
    """Pure function: current state + desired state -> list of PATCH rrsets.

    No I/O, so the properties that make this safe are unit-testable without a
    running PowerDNS.
    """
    zone = canonical(zone)
    apex_ttl = int(desired["apex_ttl"])
    patch = []

    # --- apex SOA: MNAME and RNAME only -------------------------------------
    # The serial is never sent. Every zone carries SOA-EDIT-API DEFAULT, so
    # PowerDNS rewrites it on write; supplying one would only fight that.
    soa = existing.get((zone, "SOA"))
    if soa is None:
        raise ReconcileError("zone {} has no SOA record".format(zone))
    fields = soa["records"][0]["content"].split()
    if len(fields) != SOA_FIELDS:
        raise ReconcileError(
            "zone {} has a malformed SOA ({} fields, expected {}): {!r}".format(
                zone, len(fields), SOA_FIELDS, soa["records"][0]["content"]
            )
        )
    want_mname = canonical(desired["soa_mname"])
    want_rname = canonical(desired["soa_rname"])
    if fields[0] != want_mname or fields[1] != want_rname or soa["ttl"] != apex_ttl:
        rebuilt = " ".join([want_mname, want_rname] + fields[2:])
        patch.append(_replace(zone, "SOA", apex_ttl, [rebuilt]))

    # --- apex NS ------------------------------------------------------------
    ns = existing.get((zone, "NS"))
    want_ns = sorted(canonical(n) for n in desired["nameservers"])
    have_ns = sorted(r["content"] for r in ns["records"]) if ns else []
    if have_ns != want_ns or (ns is not None and ns["ttl"] != apex_ttl):
        patch.append(_replace(zone, "NS", apex_ttl, want_ns))

    # --- _health.<region> TXT ------------------------------------------------
    # TTL is 300 in zone.template.j2 independently of the zone default, so it is
    # carried separately rather than derived from apex_ttl.
    health_ttl = int(desired.get("health_ttl", 300))
    want_health = {}
    for region in desired.get("health_records", []):
        if len(region["content"]) > MAX_TXT_STRING:
            raise ReconcileError(
                "_health.{} content is {} bytes, over the {}-byte TXT string limit; "
                "PowerDNS would split it into chunks and this would never converge".format(
                    region["region"], len(region["content"]), MAX_TXT_STRING
                )
            )
        name = canonical("_health.{}.{}".format(region["region"], zone))
        want_health[name] = txt_rdata(region["content"])

    for name in sorted(want_health):
        rrset = existing.get((name, "TXT"))
        have = [r["content"] for r in rrset["records"]] if rrset else None
        if have != [want_health[name]] or (rrset is not None and rrset["ttl"] != health_ttl):
            patch.append(_replace(name, "TXT", health_ttl, [want_health[name]]))

    # A region dropped from vars.yaml takes its record with it - that is how
    # us-west would have cleaned itself up instead of being deleted by hand.
    # Three independent bounds, all checked here rather than inferred:
    for name, rtype in sorted(existing):
        if rtype != "TXT":
            continue
        if not name.startswith(HEALTH_PREFIX):
            continue
        if not name.endswith("." + zone):
            continue
        if name in want_health:
            continue
        patch.append({"name": name, "type": "TXT", "changetype": "DELETE"})

    return patch


def describe(patch: list) -> list:
    """Render the patch as readable lines for the deploy log."""
    lines = []
    for rrset in patch:
        if rrset["changetype"] == "DELETE":
            lines.append("delete {} {}".format(rrset["type"], rrset["name"]))
        else:
            contents = ", ".join(r["content"] for r in rrset["records"])
            lines.append(
                "set {} {} ttl={} -> {}".format(
                    rrset["type"], rrset["name"], rrset["ttl"], contents
                )
            )
    return lines


def api_request(base: str, key: str, path: str, method: str = "GET", body=None):
    url = "{}/api/v1/servers/localhost{}".format(base.rstrip("/"), path)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("X-API-Key", key)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:500]
        raise ReconcileError(
            "{} {} -> HTTP {}: {}".format(method, url, exc.code, detail)
        ) from exc
    except urllib.error.URLError as exc:
        raise ReconcileError("{} {} -> {}".format(method, url, exc.reason)) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zone", required=True)
    parser.add_argument("--api-url", required=True, help="e.g. http://10.100.0.153:8081")
    parser.add_argument(
        "--desired", required=True, help="JSON file keyed by canonical zone name"
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # Read from the environment, never argv - argv is world-readable in /proc.
    key = os.environ.get("PDNS_API_KEY", "")
    if not key:
        raise ReconcileError("PDNS_API_KEY is empty; refusing to run")

    zone = canonical(args.zone)
    with open(args.desired) as handle:
        all_desired = json.load(handle)
    if zone not in all_desired:
        raise ReconcileError(
            "no desired state for {} in {}".format(zone, args.desired)
        )
    desired = all_desired[zone]

    zone_data = api_request(args.api_url, key, "/zones/{}".format(zone))
    existing = index_rrsets(zone_data)

    drift = find_lua_drift(existing, desired)
    if drift:
        # Stop before writing anything. LUA drift means the zone is not in the
        # state we think it is, and a human should look before we mutate it.
        print(
            json.dumps(
                {
                    "zone": zone,
                    "changed": False,
                    "lua_drift": drift,
                    "message": "LUA record drift detected; no records were written",
                },
                indent=2,
            )
        )
        return 2

    patch = compute_changes(zone, existing, desired)
    report = {
        "zone": zone,
        "changed": bool(patch) and not args.dry_run,
        "dry_run": args.dry_run,
        "changes": describe(patch),
    }

    if patch and not args.dry_run:
        # One PATCH for the whole zone: one serial bump, one notify, however
        # many records moved.
        api_request(args.api_url, key, "/zones/{}".format(zone), "PATCH", {"rrsets": patch})
        api_request(args.api_url, key, "/zones/{}/notify".format(zone), "PUT")

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ReconcileError as error:
        print(json.dumps({"error": str(error)}, indent=2), file=sys.stderr)
        sys.exit(1)
