"""Tests for the template-owned zone record reconcile.

The fixtures below are copied from what the production API actually returns, not
invented, because the failure mode these guard against is a quoting or trailing
dot mismatch that makes a correct zone report a change on every run.

The important tests are the ones asserting what is *absent* from the change set:
out-of-band records must be untouchable regardless of what the diff decides.
"""

import copy

import pytest

from reconcile_zone_records import (
    ReconcileError,
    canonical,
    compute_changes,
    find_lua_drift,
    index_rrsets,
    txt_rdata,
)

GEO_ZONE = "cdn-geo.runonflux.io."
APP_ZONE = "app.runonflux.io."


def geo_zone_data():
    """cdn-geo as the API returns it, in the state vars.yaml describes."""
    return {
        "name": GEO_ZONE,
        "rrsets": [
            {
                "name": GEO_ZONE,
                "type": "SOA",
                "ttl": 300,
                "records": [
                    {
                        "content": (
                            "pdns.runonflux.io. hostmaster.runonflux.io. "
                            "2026062804 3600 600 86400 300"
                        ),
                        "disabled": False,
                    }
                ],
            },
            {
                "name": GEO_ZONE,
                "type": "NS",
                "ttl": 300,
                "records": [{"content": "pdns.runonflux.io.", "disabled": False}],
            },
            {
                "name": "_health.eu-central." + GEO_ZONE,
                "type": "TXT",
                "ttl": 300,
                "records": [
                    {
                        "content": '"Germany EU - cdn-1.runonflux.io - 159.195.85.44"',
                        "disabled": False,
                    }
                ],
            },
            {
                "name": "_health.as-east." + GEO_ZONE,
                "type": "TXT",
                "ttl": 300,
                "records": [
                    {
                        "content": '"Hong Kong Asia - cdn-3.runonflux.io - 180.188.197.165"',
                        "disabled": False,
                    }
                ],
            },
            {
                "name": "_config." + GEO_ZONE,
                "type": "LUA",
                "ttl": 300,
                "records": [
                    {
                        "content": "LUA \"dofile('/opt/pdns/scripts/geo_routing.lua')\"",
                        "disabled": False,
                    }
                ],
            },
            {
                "name": GEO_ZONE,
                "type": "LUA",
                "ttl": 300,
                "records": [
                    {
                        "content": "A \";include('_config'); return geoRoute()\"",
                        "disabled": False,
                    }
                ],
            },
        ],
    }


def geo_desired():
    return {
        "apex_ttl": 300,
        "health_ttl": 300,
        "nameservers": ["pdns.runonflux.io."],
        "soa_mname": "pdns.runonflux.io.",
        "soa_rname": "hostmaster.runonflux.io.",
        "health_records": [
            {"region": "eu-central", "content": "Germany EU - cdn-1.runonflux.io - 159.195.85.44"},
            {
                "region": "as-east",
                "content": "Hong Kong Asia - cdn-3.runonflux.io - 180.188.197.165",
            },
        ],
        "lua_records": [
            {
                "name": "_config." + GEO_ZONE,
                "content": "LUA \"dofile('/opt/pdns/scripts/geo_routing.lua')\"",
            },
            {"name": GEO_ZONE, "content": "A \";include('_config'); return geoRoute()\""},
        ],
    }


def changed_names(patch):
    return {(r["name"], r["type"]) for r in patch}


# --------------------------------------------------------------------------
# Idempotency. If this breaks, everything else is noise.
# --------------------------------------------------------------------------


def test_clean_zone_produces_no_changes():
    patch = compute_changes(GEO_ZONE, index_rrsets(geo_zone_data()), geo_desired())
    assert patch == []


def test_clean_zone_has_no_lua_drift():
    assert find_lua_drift(index_rrsets(geo_zone_data()), geo_desired()) == []


def test_txt_rdata_keeps_its_own_quotes():
    # Build the desired TXT without the embedded quotes and every run reports a
    # change. This is the single most likely implementation bug.
    assert txt_rdata("Germany EU") == '"Germany EU"'


def test_canonical_is_idempotent_and_adds_the_dot():
    assert canonical("pdns.runonflux.io") == "pdns.runonflux.io."
    assert canonical("pdns.runonflux.io.") == "pdns.runonflux.io."


# --------------------------------------------------------------------------
# Out-of-band records are untouchable. This is the property that makes the
# whole approach safe, and the reason it is not a load-zone.
# --------------------------------------------------------------------------


def test_acme_challenge_is_never_touched():
    zone = geo_zone_data()
    zone["rrsets"].append(
        {
            "name": "_acme-challenge." + GEO_ZONE,
            "type": "TXT",
            "ttl": 60,
            "records": [{"content": '"tokenvaluecertbotjustwrote"', "disabled": False}],
        }
    )
    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())
    assert patch == []


def test_acme_challenge_survives_alongside_real_drift():
    """The dangerous case: a write is happening anyway, and must stay scoped."""
    zone = geo_zone_data()
    zone["rrsets"].append(
        {
            "name": "_acme-challenge." + GEO_ZONE,
            "type": "TXT",
            "ttl": 60,
            "records": [{"content": '"tokenvaluecertbotjustwrote"', "disabled": False}],
        }
    )
    for rrset in zone["rrsets"]:
        if rrset["name"].startswith("_health.eu-central"):
            rrset["records"][0]["content"] = '"Germany EU - cdn-1.runonflux.io - 89.58.31.71"'

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    assert patch[0]["name"] == "_health.eu-central." + GEO_ZONE
    assert ("_acme-challenge." + GEO_ZONE, "TXT") not in changed_names(patch)


def test_app_a_records_are_never_touched():
    zone = {
        "name": APP_ZONE,
        "rrsets": [
            {
                "name": APP_ZONE,
                "type": "SOA",
                "ttl": 3600,
                "records": [
                    {
                        "content": (
                            "pdns.runonflux.io. hostmaster.runonflux.io. "
                            "2026073722 3600 600 86400 3600"
                        ),
                        "disabled": False,
                    }
                ],
            },
            {
                "name": APP_ZONE,
                "type": "NS",
                "ttl": 3600,
                "records": [{"content": "pdns.runonflux.io.", "disabled": False}],
            },
        ],
    }
    for index in range(171):
        zone["rrsets"].append(
            {
                "name": "app{}.{}".format(index, APP_ZONE),
                "type": "A",
                "ttl": 300,
                "records": [{"content": "10.0.0.{}".format(index % 255), "disabled": False}],
            }
        )

    desired = {
        "apex_ttl": 3600,
        "nameservers": ["pdns.runonflux.io."],
        "soa_mname": "pdns.runonflux.io.",
        "soa_rname": "hostmaster.runonflux.io.",
        "health_records": [],
        "lua_records": [],
    }
    assert compute_changes(APP_ZONE, index_rrsets(zone), desired) == []


def test_a_record_named_like_a_health_record_is_not_deleted():
    """The delete bound is prefix AND type AND zone - not prefix alone."""
    zone = geo_zone_data()
    zone["rrsets"].append(
        {
            "name": "_health.decoy." + GEO_ZONE,
            "type": "A",
            "ttl": 300,
            "records": [{"content": "10.1.2.3", "disabled": False}],
        }
    )
    assert compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired()) == []


def test_health_record_in_another_zone_is_not_deleted():
    zone = geo_zone_data()
    zone["rrsets"].append(
        {
            "name": "_health.eu-central.cdn-geodev.runonflux.io.",
            "type": "TXT",
            "ttl": 300,
            "records": [{"content": '"some other zone"', "disabled": False}],
        }
    )
    assert compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired()) == []


# --------------------------------------------------------------------------
# Convergence
# --------------------------------------------------------------------------


def test_stale_health_ip_converges():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["name"].startswith("_health.eu-central"):
            # The address cdn-1 left behind in December 2025.
            rrset["records"][0]["content"] = '"Germany EU - cdn-1.runonflux.io - 89.58.31.71"'

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    assert patch[0]["changetype"] == "REPLACE"
    assert patch[0]["records"][0]["content"] == (
        '"Germany EU - cdn-1.runonflux.io - 159.195.85.44"'
    )


def test_removed_region_is_deleted():
    """us-west, removed from vars.yaml, should clean itself up."""
    zone = geo_zone_data()
    zone["rrsets"].append(
        {
            "name": "_health.us-west." + GEO_ZONE,
            "type": "TXT",
            "ttl": 300,
            "records": [
                {
                    "content": '"US West - cdn-2.runonflux.io - 107.175.82.227"',
                    "disabled": False,
                }
            ],
        }
    )
    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    assert patch[0] == {
        "name": "_health.us-west." + GEO_ZONE,
        "type": "TXT",
        "changetype": "DELETE",
    }


def test_missing_health_record_is_created():
    zone = geo_zone_data()
    zone["rrsets"] = [r for r in zone["rrsets"] if not r["name"].startswith("_health.as-east")]
    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    assert patch[0]["name"] == "_health.as-east." + GEO_ZONE
    assert patch[0]["changetype"] == "REPLACE"


def test_wrong_nameserver_converges():
    """The pdns1 -> pdns fix that the 2026-07-28 deploy failed to apply."""
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "NS":
            rrset["records"] = [{"content": "pdns1.runonflux.io.", "disabled": False}]

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    assert patch[0]["type"] == "NS"
    assert patch[0]["records"] == [{"content": "pdns.runonflux.io.", "disabled": False}]


def test_soa_mname_converges_and_preserves_every_other_field():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "SOA":
            rrset["records"][0]["content"] = (
                "pdns1.runonflux.io. hostmaster.runonflux.io. 2026062804 3600 600 86400 300"
            )

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 1
    fields = patch[0]["records"][0]["content"].split()
    assert fields[0] == "pdns.runonflux.io."
    assert fields[1] == "hostmaster.runonflux.io."
    # The serial is carried through untouched; SOA-EDIT-API DEFAULT rewrites it.
    assert fields[2:] == ["2026062804", "3600", "600", "86400", "300"]


def test_soa_rname_converges():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "SOA":
            rrset["records"][0]["content"] = (
                "pdns.runonflux.io. old-contact.runonflux.io. 2026062804 3600 600 86400 300"
            )

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())
    assert patch[0]["records"][0]["content"].split()[1] == "hostmaster.runonflux.io."


def test_everything_wrong_at_once_batches_into_one_patch():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "NS":
            rrset["records"] = [{"content": "pdns1.runonflux.io.", "disabled": False}]
        if rrset["name"].startswith("_health.eu-central"):
            rrset["records"][0]["content"] = '"Germany EU - cdn-1.runonflux.io - 89.58.31.71"'
    zone["rrsets"].append(
        {
            "name": "_health.us-west." + GEO_ZONE,
            "type": "TXT",
            "ttl": 300,
            "records": [{"content": '"US West - dead"', "disabled": False}],
        }
    )

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())

    assert len(patch) == 3
    assert sum(1 for r in patch if r["changetype"] == "DELETE") == 1


def test_ttl_drift_is_corrected():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["name"].startswith("_health.as-east"):
            rrset["ttl"] = 3600
    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())
    assert len(patch) == 1
    assert patch[0]["ttl"] == 300


# --------------------------------------------------------------------------
# LUA records: detected, never written
# --------------------------------------------------------------------------


def test_lua_drift_is_detected():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "LUA" and rrset["name"] == GEO_ZONE:
            rrset["records"][0]["content"] = "A \";include('_config'); return oldGeoRoute()\""

    drift = find_lua_drift(index_rrsets(zone), geo_desired())

    assert len(drift) == 1
    assert drift[0]["name"] == GEO_ZONE


def test_missing_lua_record_is_drift():
    zone = geo_zone_data()
    zone["rrsets"] = [r for r in zone["rrsets"] if r["type"] != "LUA"]
    drift = find_lua_drift(index_rrsets(zone), geo_desired())
    assert len(drift) == 2
    assert all(d["actual"] is None for d in drift)


def test_lua_records_are_never_in_the_change_set():
    """Even when drifted, compute_changes must not propose writing them."""
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "LUA":
            rrset["records"][0]["content"] = "A \";include('_config'); return whatever()\""

    patch = compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())
    assert all(r["type"] != "LUA" for r in patch)
    assert patch == []


# --------------------------------------------------------------------------
# Refuse to guess
# --------------------------------------------------------------------------


def test_missing_soa_raises():
    zone = geo_zone_data()
    zone["rrsets"] = [r for r in zone["rrsets"] if r["type"] != "SOA"]
    with pytest.raises(ReconcileError, match="no SOA"):
        compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())


def test_malformed_soa_raises():
    zone = geo_zone_data()
    for rrset in zone["rrsets"]:
        if rrset["type"] == "SOA":
            rrset["records"][0]["content"] = "pdns.runonflux.io. hostmaster.runonflux.io."
    with pytest.raises(ReconcileError, match="malformed SOA"):
        compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())


def test_undotted_vars_still_compare_equal():
    """vars.yaml uses trailing dots today; a future edit dropping one must not
    silently rewrite the SOA on every run."""
    desired = geo_desired()
    desired["soa_mname"] = "pdns.runonflux.io"
    desired["nameservers"] = ["pdns.runonflux.io"]
    assert compute_changes(GEO_ZONE, index_rrsets(geo_zone_data()), desired) == []


def test_input_zone_data_is_not_mutated():
    zone = geo_zone_data()
    before = copy.deepcopy(zone)
    compute_changes(GEO_ZONE, index_rrsets(zone), geo_desired())
    assert zone == before
