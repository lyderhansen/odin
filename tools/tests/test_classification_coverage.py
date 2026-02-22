# tools/tests/test_classification_coverage.py
"""
Validate that generated ODIN data exercises the classification lookups.
Reads the actual CSV files and cross-references with host profile signals.
"""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

REPO_ROOT = Path(__file__).parent.parent.parent
LOOKUPS = REPO_ROOT / "ODIN_app_for_splunk" / "lookups"

from generate_odin_data import HOST_PROFILES


def load_csv_column(filename, column):
    """Load a set of values from a CSV column."""
    values = set()
    with open(LOOKUPS / filename) as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row.get(column):
                values.add(row[column].strip())
    return values


def test_service_signals_match_classify_services():
    """At least 20 generated service names should exist in odin_classify_services.csv."""
    lookup_services = load_csv_column("odin_classify_services.csv", "service_pattern")
    generated_services = set()
    for profile in HOST_PROFILES.values():
        for svc in profile["services"]:
            generated_services.add(svc["service_name"])
    matches = generated_services & lookup_services
    assert len(matches) >= 20, (
        f"Only {len(matches)} service matches: {sorted(matches)}"
    )


def test_port_signals_match_classify_ports():
    """At least 15 generated port/transport combos should exist in odin_classify_ports.csv."""
    lookup_ports = set()
    with open(LOOKUPS / "odin_classify_ports.csv") as f:
        reader = csv.DictReader(f)
        for row in reader:
            lookup_ports.add((row["port"].strip(), row["transport"].strip()))
    generated_ports = set()
    for profile in HOST_PROFILES.values():
        for pt in profile["ports"]:
            generated_ports.add((pt["listen_port"], pt["transport"]))
    matches = generated_ports & lookup_ports
    assert len(matches) >= 15, (
        f"Only {len(matches)} port matches: {sorted(matches)}"
    )


def test_package_signals_match_classify_packages():
    """At least 15 generated package names should exist in odin_classify_packages.csv."""
    lookup_packages = load_csv_column("odin_classify_packages.csv", "package_pattern")
    generated_packages = set()
    for profile in HOST_PROFILES.values():
        for pkg in profile["packages"]:
            generated_packages.add(pkg["package_name"])
    matches = generated_packages & lookup_packages
    assert len(matches) >= 15, (
        f"Only {len(matches)} package matches: {sorted(matches)}"
    )


def test_log_source_signals_match():
    """At least 25 generated (signal_type, signal_value) pairs should match odin_log_sources.csv."""
    lookup_signals = set()
    with open(LOOKUPS / "odin_log_sources.csv") as f:
        reader = csv.DictReader(f)
        for row in reader:
            lookup_signals.add((row["signal_type"].strip(), row["signal_value"].strip()))

    generated_signals = set()
    for profile in HOST_PROFILES.values():
        for svc in profile["services"]:
            generated_signals.add(("service", svc["service_name"]))
        for pt in profile["ports"]:
            generated_signals.add(("port", f"{pt['listen_port']}/{pt['transport']}"))
        for pkg in profile["packages"]:
            generated_signals.add(("package", pkg["package_name"]))

    matches = generated_signals & lookup_signals
    assert len(matches) >= 25, (
        f"Only {len(matches)} log source signal matches: {sorted(matches)}"
    )


def test_host_roles_covered():
    """Generated data should map to at least 10 distinct host_role values."""
    signal_to_role = {}
    with open(LOOKUPS / "odin_log_sources.csv") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["signal_type"].strip(), row["signal_value"].strip())
            signal_to_role[key] = row["host_role"].strip()

    roles_hit = set()
    for profile in HOST_PROFILES.values():
        for svc in profile["services"]:
            role = signal_to_role.get(("service", svc["service_name"]))
            if role:
                roles_hit.add(role)
        for pt in profile["ports"]:
            role = signal_to_role.get(("port", f"{pt['listen_port']}/{pt['transport']}"))
            if role:
                roles_hit.add(role)
        for pkg in profile["packages"]:
            role = signal_to_role.get(("package", pkg["package_name"]))
            if role:
                roles_hit.add(role)

    assert len(roles_hit) >= 10, (
        f"Only {len(roles_hit)} host roles covered: {sorted(roles_hit)}"
    )
