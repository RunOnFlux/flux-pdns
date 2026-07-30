"""Render templates/reconcile_desired.json.j2 against the real vars.yaml.

Two things are being protected here.

First, the LUA content strings. Those records are detect-only and drift fails
the play, so an expectation that does not match production byte for byte would
block every deploy on a zone that is perfectly correct. The expected values
below were read back from the production API, not written from the template.

Second, that this template and zone.template.j2 agree. zone.template.j2 writes a
zone at creation; this one holds it there afterwards. If they disagree, a
freshly created zone reports drift on its first reconcile. The round-trip test
at the bottom pins that down: render the desired state, feed it to the diff
against a zone captured from production, and require zero changes.

Skipped if jinja2/pyyaml are unavailable, so the suite still runs without them.
"""

import json
import pathlib

import pytest

jinja2 = pytest.importorskip("jinja2")
yaml = pytest.importorskip("yaml")

from reconcile_zone_records import compute_changes, index_rrsets  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parent.parent

# Read back from the production API on 2026-07-30. Do not regenerate these from
# the template - that would make the test tautological.
PRODUCTION_LUA = {
    "cdn-geo.runonflux.io.": {
        "_config.cdn-geo.runonflux.io.": "LUA \"dofile('/opt/pdns/scripts/geo_routing.lua')\"",
        "cdn-geo.runonflux.io.": "A \";include('_config'); return geoRoute()\"",
    },
    "app.runonflux.io.": {
        "_config.app.runonflux.io.": "LUA \"dofile('/opt/pdns/scripts/app_routing.lua')\"",
        "*.app.runonflux.io.": "CNAME \";include('_config'); return appRouteCname(qname)\"",
        "_debug.app.runonflux.io.": "TXT \";include('_config'); return appRouteDebug(qname)\"",
    },
}


def render(deploy_env):
    """Render the template the way Ansible would."""
    source = (REPO / "templates" / "reconcile_desired.json.j2").read_text()
    variables = yaml.safe_load((REPO / "vars.yaml").read_text())

    environment = jinja2.Environment(
        trim_blocks=True, lstrip_blocks=True, keep_trailing_newline=True
    )
    # Ansible provides this filter; plain Jinja does not. Mirror its behaviour
    # exactly, sort_keys included - the rendered file must be byte-stable across
    # runs or the template task reports changed on every deploy.
    environment.filters["to_nice_json"] = lambda value: json.dumps(
        value, indent=4, sort_keys=True
    )

    rendered = environment.from_string(source).render(
        DEPLOY_ENV=deploy_env, **variables
    )
    return json.loads(rendered)


def render_raw(deploy_env):
    """As render(), but returns the rendered text rather than parsed JSON."""
    source = (REPO / "templates" / "reconcile_desired.json.j2").read_text()
    variables = yaml.safe_load((REPO / "vars.yaml").read_text())
    environment = jinja2.Environment(
        trim_blocks=True, lstrip_blocks=True, keep_trailing_newline=True
    )
    environment.filters["to_nice_json"] = lambda value: json.dumps(
        value, indent=4, sort_keys=True
    )
    return environment.from_string(source).render(DEPLOY_ENV=deploy_env, **variables)


@pytest.mark.parametrize("environment", ["production", "staging"])
def test_render_is_byte_stable(environment):
    """The template task rewrites this file on every deploy. If rendering is not
    byte-stable the task reports changed forever."""
    assert render_raw(environment) == render_raw(environment)


def test_production_renders_both_zones():
    desired = render("production")
    assert set(desired) == {"cdn-geo.runonflux.io.", "app.runonflux.io."}


def test_staging_renders_both_zones():
    desired = render("staging")
    assert set(desired) == {"cdn-geodev.runonflux.io.", "app2.runonflux.io."}


@pytest.mark.parametrize("zone", sorted(PRODUCTION_LUA))
def test_lua_content_matches_production_exactly(zone):
    rendered = {r["name"]: r["content"] for r in render("production")[zone]["lua_records"]}
    assert rendered == PRODUCTION_LUA[zone]


def test_production_nameserver_is_the_one_that_resolves():
    # pdns1.runonflux.io has no records of any type. It was in the zone's NS set
    # and SOA MNAME until 2026-07-29.
    desired = render("production")["cdn-geo.runonflux.io."]
    assert desired["nameservers"] == ["pdns.runonflux.io."]
    assert desired["soa_mname"] == "pdns.runonflux.io."


def test_staging_nameserver_is_pdns2():
    desired = render("staging")["cdn-geodev.runonflux.io."]
    assert desired["nameservers"] == ["pdns2.runonflux.io."]


@pytest.mark.parametrize("environment", ["production", "staging"])
def test_no_region_references_the_relet_addresses(environment):
    """107.175.82.227 and 89.58.31.71 belong to other people now.

    The reconcile makes vars.yaml authoritative, so a region resurrected here
    would be written straight back into the zone on every run.
    """
    blob = json.dumps(render(environment))
    assert "107.175.82.227" not in blob
    assert "89.58.31.71" not in blob
    assert "us-west" not in blob


def test_health_content_matches_production_format():
    desired = render("production")["cdn-geo.runonflux.io."]
    contents = {r["region"]: r["content"] for r in desired["health_records"]}
    assert contents == {
        "eu-central": "Germany EU - cdn-1.runonflux.io - 159.195.85.44",
        "as-east": "Hong Kong Asia - cdn-3.runonflux.io - 180.188.197.165",
    }


def test_app_zone_has_no_health_records():
    assert render("production")["app.runonflux.io."]["health_records"] == []


def test_ttls_follow_the_zone_template():
    production = render("production")
    # _health is hardcoded to 300 in zone.template.j2 regardless of the default.
    assert production["cdn-geo.runonflux.io."]["health_ttl"] == 300
    assert production["cdn-geo.runonflux.io."]["apex_ttl"] == 300
    assert production["app.runonflux.io."]["apex_ttl"] == 3600


def test_round_trip_against_production_zone_is_a_no_op():
    """The end-to-end property: template and script agree on a live zone.

    This zone was captured from the production API. Reconciling it against the
    rendered desired state must propose nothing.
    """
    zone_name = "cdn-geo.runonflux.io."
    captured = {
        "rrsets": [
            {
                "name": zone_name,
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
                "name": zone_name,
                "type": "NS",
                "ttl": 300,
                "records": [{"content": "pdns.runonflux.io.", "disabled": False}],
            },
            {
                "name": "_health.eu-central." + zone_name,
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
                "name": "_health.as-east." + zone_name,
                "type": "TXT",
                "ttl": 300,
                "records": [
                    {
                        "content": '"Hong Kong Asia - cdn-3.runonflux.io - 180.188.197.165"',
                        "disabled": False,
                    }
                ],
            },
        ]
    }
    desired = render("production")[zone_name]
    assert compute_changes(zone_name, index_rrsets(captured), desired) == []
