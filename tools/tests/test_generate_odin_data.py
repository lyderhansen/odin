# tools/tests/test_generate_odin_data.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from generate_odin_data import format_event, HOST_PROFILES, BASE_SERVICES, BASE_PACKAGES, BASE_MOUNTS, ODIN_VERSION


def test_format_event_basic():
    """Basic event with simple string values."""
    result = format_event(
        timestamp="2026-01-15T02:00:00Z",
        hostname="web-prod-01.company.local",
        os="linux",
        run_id="1736899200-1234",
        version="2.2.0",
        type_="service",
        fields={
            "service_name": "nginx",
            "service_status": "running",
            "service_enabled": "enabled",
        },
    )
    assert result == (
        "timestamp=2026-01-15T02:00:00Z hostname=web-prod-01.company.local "
        "os=linux run_id=1736899200-1234 odin_version=2.2.0 type=service "
        "service_name=nginx service_status=running service_enabled=enabled"
    )


def test_format_event_quotes_spaces():
    """Values with spaces get double-quoted."""
    result = format_event(
        timestamp="2026-01-15T02:00:00Z",
        hostname="app-prod-01.company.local",
        os="linux",
        run_id="1736899200-5678",
        version="2.2.0",
        type_="process",
        fields={
            "process_pid": "1234",
            "process_name": "java",
            "process_command": "/usr/bin/java -Xmx4g -jar app.jar",
        },
    )
    assert 'process_command="/usr/bin/java -Xmx4g -jar app.jar"' in result


def test_format_event_omits_empty():
    """Empty or None values are omitted."""
    result = format_event(
        timestamp="2026-01-15T02:00:00Z",
        hostname="web-prod-01.company.local",
        os="linux",
        run_id="1736899200-1234",
        version="2.2.0",
        type_="port",
        fields={
            "transport": "tcp",
            "listen_address": "0.0.0.0",
            "listen_port": "80",
            "process_name": "nginx",
            "process_pid": "",
        },
    )
    assert "process_pid" not in result
    assert "listen_port=80" in result


def test_host_profiles_exist():
    """At least 15 host profiles are defined."""
    assert len(HOST_PROFILES) >= 15


def test_all_profiles_have_required_keys():
    """Every profile has services, ports, packages, processes, mounts, cron."""
    required = {"os", "services", "ports", "packages", "processes", "mounts", "cron"}
    for hostname, profile in HOST_PROFILES.items():
        missing = required - set(profile.keys())
        assert not missing, f"{hostname} missing keys: {missing}"


def test_base_services_on_every_host():
    """Common services (sshd, crond, auditd) appear on every profile."""
    for hostname, profile in HOST_PROFILES.items():
        svc_names = {s["service_name"] for s in profile["services"]}
        for base in BASE_SERVICES:
            assert base["service_name"] in svc_names, (
                f"{hostname} missing base service: {base['service_name']}"
            )


def test_web_server_has_web_signals():
    """web-prod-01 must have nginx service + port 80 + port 443."""
    p = HOST_PROFILES["web-prod-01.odin.local"]
    svc_names = {s["service_name"] for s in p["services"]}
    ports = {(pt["listen_port"], pt["transport"]) for pt in p["ports"]}
    assert "nginx" in svc_names
    assert ("80", "tcp") in ports
    assert ("443", "tcp") in ports


def test_db_server_has_db_signals():
    """db-prod-01 must have postgresql service + port 5432."""
    p = HOST_PROFILES["db-prod-01.odin.local"]
    svc_names = {s["service_name"] for s in p["services"]}
    ports = {(pt["listen_port"], pt["transport"]) for pt in p["ports"]}
    assert "postgresql" in svc_names
    assert ("5432", "tcp") in ports


def test_classification_coverage():
    """Generated signals should hit key services from lookups."""
    all_services = set()
    for hostname, profile in HOST_PROFILES.items():
        for svc in profile["services"]:
            all_services.add(svc["service_name"])
    expected_services = {
        "nginx", "postgresql", "docker", "redis", "rsyslog",
        "prometheus", "postfix", "openvpn", "jenkins", "named",
        "rabbitmq-server", "kubelet",
    }
    missing = expected_services - all_services
    assert not missing, f"Missing services for classification coverage: {missing}"


from generate_odin_data import generate_scan


def test_generate_scan_returns_events():
    """A scan for one host returns a list of event strings."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    assert isinstance(events, list)
    assert len(events) > 0
    assert all(isinstance(e, str) for e in events)


def test_scan_starts_and_ends_with_control_events():
    """First event is odin_start, last is odin_complete."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    assert "type=odin_start" in events[0]
    assert "type=odin_complete" in events[-1]


def test_scan_has_all_event_types():
    """A scan should produce service, port, package, process, mount, cron events."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    combined = "\n".join(events)
    for t in ["type=service", "type=port", "type=package", "type=process", "type=mount", "type=cron"]:
        assert t in combined, f"Missing event type: {t}"


def test_scan_event_count_reasonable():
    """web-prod-01 should produce between 30 and 100 events."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    assert 30 <= len(events) <= 100, f"Unexpected event count: {len(events)}"


def test_all_events_have_common_header():
    """Every event must have timestamp, hostname, os, run_id, odin_version, type."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    for event in events:
        assert "timestamp=2026-01-15T02:00:" in event
        assert "hostname=web-prod-01.odin.local" in event
        assert "os=linux" in event
        assert "run_id=1736899200-1234" in event
        assert "odin_version=2.2.0" in event
