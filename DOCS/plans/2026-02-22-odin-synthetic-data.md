# ODIN Synthetic Data Generator — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Python script that generates realistic ODIN enumeration data for 15 Linux hosts with diverse server roles, enabling end-to-end validation of Phase 2 classification lookups and saved searches in Splunk.

**Architecture:** A standalone Python script (`tools/generate_odin_data.py`) in the ODIN repo that defines host profiles — each mapping a hostname to its services, ports, packages, cron jobs, processes, and mounts. One full ODIN scan is generated per host. Output is space-separated key=value lines matching the exact v2.2.0 format. The generated signals exercise entries across all four classification lookups.

**Tech Stack:** Python 3.9+, pytest

**TA-FAKE-TSHRT repo:** `/Users/joehanse/Library/CloudStorage/OneDrive-Cisco/Documents/03_Funny_Projects/GIT-TA-FAKE-TSHRT/The-Fake-T-Shirt-Company/TheFakeTshirtCompany/TA-FAKE-TSHRT/`
(If TA-FAKE-TSHRT integration is desired later, the generator can be adapted to follow that framework's patterns.)

---

## Task 1: Create `format_event` helper + tests

**Files:**
- Create: `tools/generate_odin_data.py`
- Create: `tools/tests/test_generate_odin_data.py`

**Step 1: Write the failing test**

```python
# tools/tests/test_generate_odin_data.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from generate_odin_data import format_event


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
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/joehanse/Library/CloudStorage/OneDrive-Cisco/Documents/03_Funny_Projects/Project_Odin/git/odin && python3 -m pytest tools/tests/test_generate_odin_data.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'generate_odin_data'`

**Step 3: Write minimal implementation**

```python
# tools/generate_odin_data.py
"""
ODIN Synthetic Data Generator

Generates realistic odin:enumeration events for multiple host profiles.
Output matches TA-ODIN v2.2.0 space-separated key=value format.

Usage:
    python3 tools/generate_odin_data.py [--output FILE] [--hosts HOST,...] [--date YYYY-MM-DD]
"""

ODIN_VERSION = "2.2.0"


def format_event(
    timestamp: str,
    hostname: str,
    os: str,
    run_id: str,
    version: str,
    type_: str,
    fields: dict,
) -> str:
    """Format a single ODIN event as space-separated key=value."""
    parts = [
        f"timestamp={timestamp}",
        f"hostname={hostname}",
        f"os={os}",
        f"run_id={run_id}",
        f"odin_version={version}",
        f"type={type_}",
    ]
    for key, val in fields.items():
        if val is None or val == "":
            continue
        val_str = str(val)
        if " " in val_str:
            parts.append(f'{key}="{val_str}"')
        else:
            parts.append(f"{key}={val_str}")
    return " ".join(parts)
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/joehanse/Library/CloudStorage/OneDrive-Cisco/Documents/03_Funny_Projects/Project_Odin/git/odin && python3 -m pytest tools/tests/test_generate_odin_data.py -v`
Expected: 3 passed

**Step 5: Commit**

```bash
git add tools/generate_odin_data.py tools/tests/test_generate_odin_data.py
git commit -m "feat(tools): add format_event helper for ODIN synthetic data generator"
```

---

## Task 2: Define host profiles

**Files:**
- Modify: `tools/generate_odin_data.py`
- Modify: `tools/tests/test_generate_odin_data.py`

### Host Fleet Design

15 hosts covering all major classification categories from the lookups:

| Hostname | Primary Role | Key Signals |
|----------|-------------|-------------|
| `web-prod-01` | web_server | nginx, 80/tcp, 443/tcp |
| `web-prod-02` | web_server | httpd/apache2, php-fpm, 80/tcp, 443/tcp |
| `db-prod-01` | database_server | postgresql, 5432/tcp |
| `db-prod-02` | database_server | mysqld, 3306/tcp |
| `app-prod-01` | container_host | docker, containerd, 8080/tcp |
| `cache-prod-01` | cache_server | redis, memcached, 6379/tcp, 11211/tcp |
| `log-prod-01` | splunk_server + syslog_receiver | splunkd, rsyslog, 514/tcp, 9997/tcp |
| `mon-prod-01` | monitoring_server | prometheus, grafana-server, 9090/tcp, 3000/tcp |
| `k8s-master-01` | kubernetes_master | kube-apiserver, etcd, 6443/tcp |
| `k8s-worker-01` | kubernetes_node + container_host | kubelet, containerd, 10250/tcp |
| `mail-prod-01` | mail_server | postfix, dovecot, 25/tcp, 993/tcp |
| `vpn-prod-01` | vpn_server | openvpn, 1194/udp |
| `ci-prod-01` | cicd_server | jenkins, docker, 8080/tcp, 50000/tcp |
| `dns-prod-01` | dns_server | named, 53/tcp, 53/udp |
| `mq-prod-01` | message_broker | rabbitmq-server, 5672/tcp, 15672/tcp |

Every host also gets common base signals: sshd, crond, rsyslog, auditd, node_exporter, port 22/tcp.

**Step 1: Write the failing test**

```python
# Add to tools/tests/test_generate_odin_data.py

from generate_odin_data import HOST_PROFILES, BASE_SERVICES, BASE_PACKAGES, BASE_MOUNTS


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
    """Generated signals should hit at least 10 distinct host_role values from lookups."""
    # We test this by collecting all service_names and checking against
    # known roles from odin_classify_services.csv
    all_services = set()
    for hostname, profile in HOST_PROFILES.items():
        for svc in profile["services"]:
            all_services.add(svc["service_name"])
    # These are roles our lookups map to — check we have signals for each
    expected_services = {
        "nginx", "postgresql", "docker", "redis", "rsyslog",
        "prometheus", "postfix", "openvpn", "jenkins", "named",
        "rabbitmq-server", "kubelet",
    }
    missing = expected_services - all_services
    assert not missing, f"Missing services for classification coverage: {missing}"
```

**Step 2: Run test to verify it fails**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py::test_host_profiles_exist -v`
Expected: FAIL — `ImportError: cannot import name 'HOST_PROFILES'`

**Step 3: Write implementation**

Add to `tools/generate_odin_data.py` — the full `HOST_PROFILES` dict, `BASE_SERVICES`, `BASE_PACKAGES`, and `BASE_MOUNTS` constants. Each profile entry is a dict with keys: `os`, `services` (list of dicts), `ports` (list of dicts), `packages` (list of dicts), `processes` (list of dicts), `mounts` (list of dicts), `cron` (list of dicts).

The base constants define common entries added to every host:

```python
BASE_SERVICES = [
    {"service_name": "sshd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "crond", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "rsyslog", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "auditd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "node_exporter", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "chronyd", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "systemd-journald", "service_status": "running", "service_enabled": "static"},
    {"service_name": "systemd-logind", "service_status": "running", "service_enabled": "static"},
    {"service_name": "NetworkManager", "service_status": "running", "service_enabled": "enabled"},
    {"service_name": "tuned", "service_status": "running", "service_enabled": "enabled"},
]

BASE_PORTS = [
    {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "22", "process_name": "sshd", "process_pid": ""},
    {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "9100", "process_name": "node_exporter", "process_pid": ""},
]

BASE_PACKAGES = [
    {"package_name": "bash", "package_version": "5.2.26-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "coreutils", "package_version": "8.32-36.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "openssl", "package_version": "3.0.7-27.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "curl", "package_version": "7.76.1-29.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "systemd", "package_version": "252-32.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "openssh-server", "package_version": "8.7p1-38.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "rsyslog", "package_version": "8.2208.0-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "audit", "package_version": "3.0.7-104.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "chrony", "package_version": "4.3-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "ca-certificates", "package_version": "2023.2.60-1.el9", "package_arch": "noarch", "package_manager": "rpm"},
    {"package_name": "node_exporter", "package_version": "1.7.0-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "glibc", "package_version": "2.34-100.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "python3", "package_version": "3.9.18-3.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "vim-minimal", "package_version": "8.2.2637-20.el9", "package_arch": "x86_64", "package_manager": "rpm"},
    {"package_name": "tar", "package_version": "1.34-6.el9", "package_arch": "x86_64", "package_manager": "rpm"},
]

BASE_MOUNTS = [
    {"mount_device": "/dev/sda2", "mount_point": "/", "mount_type": "xfs", "mount_size_kb": "52428800", "mount_used_kb": "8388608", "mount_avail_kb": "44040192", "mount_use_pct": "16"},
    {"mount_device": "/dev/sda1", "mount_point": "/boot", "mount_type": "xfs", "mount_size_kb": "1048576", "mount_used_kb": "262144", "mount_avail_kb": "786432", "mount_use_pct": "25"},
    {"mount_device": "tmpfs", "mount_point": "/dev/shm", "mount_type": "tmpfs", "mount_size_kb": "8177772", "mount_used_kb": "0", "mount_avail_kb": "8177772", "mount_use_pct": "0"},
    {"mount_device": "tmpfs", "mount_point": "/tmp", "mount_type": "tmpfs", "mount_size_kb": "8177772", "mount_used_kb": "4096", "mount_avail_kb": "8173676", "mount_use_pct": "1"},
]

BASE_PROCESSES = [
    {"process_pid": "1", "process_ppid": "0", "process_user": "root", "process_state": "Ss", "process_cpu": "0.0", "process_mem": "0.1", "process_elapsed": "30-00:00:00", "process_name": "systemd", "process_command": "/usr/lib/systemd/systemd --switched-root --system"},
    {"process_pid": "2", "process_ppid": "0", "process_user": "root", "process_state": "S", "process_cpu": "0.0", "process_mem": "0.0", "process_elapsed": "30-00:00:00", "process_name": "kthreadd", "process_command": ""},
]

BASE_CRON = [
    {"cron_source": "cron.daily", "cron_user": "root", "cron_schedule": "", "cron_command": "logrotate /etc/logrotate.conf", "cron_file": "/etc/cron.daily/logrotate"},
    {"cron_source": "cron.daily", "cron_user": "root", "cron_schedule": "", "cron_command": "man-db-cache-update", "cron_file": "/etc/cron.daily/man-db"},
]
```

Then `HOST_PROFILES` with 15 hosts. Example for web-prod-01:

```python
HOST_PROFILES = {
    "web-prod-01.odin.local": {
        "os": "linux",
        "services": [
            *BASE_SERVICES,
            {"service_name": "nginx", "service_status": "running", "service_enabled": "enabled"},
            {"service_name": "certbot.timer", "service_status": "running", "service_enabled": "enabled"},
        ],
        "ports": [
            *BASE_PORTS,
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "80", "process_name": "nginx", "process_pid": "2345"},
            {"transport": "tcp", "listen_address": "0.0.0.0", "listen_port": "443", "process_name": "nginx", "process_pid": "2345"},
        ],
        "packages": [
            *BASE_PACKAGES,
            {"package_name": "nginx", "package_version": "1.24.0-1.el9", "package_arch": "x86_64", "package_manager": "rpm"},
            {"package_name": "certbot", "package_version": "2.6.0-1.el9", "package_arch": "noarch", "package_manager": "rpm"},
        ],
        "processes": [
            *BASE_PROCESSES,
            {"process_pid": "2345", "process_ppid": "1", "process_user": "root", "process_state": "Ss", "process_cpu": "0.1", "process_mem": "0.3", "process_elapsed": "30-00:00:00", "process_name": "nginx", "process_command": "nginx: master process /usr/sbin/nginx"},
            {"process_pid": "2346", "process_ppid": "2345", "process_user": "nginx", "process_state": "S", "process_cpu": "0.5", "process_mem": "0.8", "process_elapsed": "30-00:00:00", "process_name": "nginx", "process_command": "nginx: worker process"},
        ],
        "mounts": [*BASE_MOUNTS],
        "cron": [
            *BASE_CRON,
            {"cron_source": "systemd_timer", "cron_user": "root", "cron_schedule": "*-*-01,15 03:00:00", "cron_command": "certbot renew --quiet", "cron_file": ""},
        ],
    },
    # ... 14 more hosts (defined similarly — see full list above)
}
```

Define all 15 host profiles following the table above. Each host gets `BASE_*` entries plus role-specific entries. Keep service/port/package values matching the classification lookups exactly.

**Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py -v`
Expected: All pass

**Step 5: Commit**

```bash
git add tools/generate_odin_data.py tools/tests/test_generate_odin_data.py
git commit -m "feat(tools): define 15 host profiles for synthetic ODIN data"
```

---

## Task 3: Implement scan generator

**Files:**
- Modify: `tools/generate_odin_data.py`
- Modify: `tools/tests/test_generate_odin_data.py`

**Step 1: Write the failing test**

```python
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
    """web-prod-01 should produce between 30 and 100 events (base + role-specific)."""
    events = generate_scan(
        hostname="web-prod-01.odin.local",
        profile=HOST_PROFILES["web-prod-01.odin.local"],
        scan_timestamp="2026-01-15T02:00:00Z",
        run_id="1736899200-1234",
    )
    # 2 control + ~12 services + ~4 ports + ~17 packages + ~4 processes + ~4 mounts + ~3 cron = ~46
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
```

**Step 2: Run test to verify it fails**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py::test_generate_scan_returns_events -v`
Expected: FAIL — `ImportError: cannot import name 'generate_scan'`

**Step 3: Write implementation**

```python
def generate_scan(
    hostname: str,
    profile: dict,
    scan_timestamp: str,
    run_id: str,
) -> list[str]:
    """Generate all events for one full ODIN scan of a host."""
    os_name = profile["os"]
    events = []

    # Parse base timestamp and increment seconds for each event
    # (simulates real scan where events are emitted within ~5 seconds)
    base_ts = scan_timestamp  # We'll increment from here
    sec_offset = 0

    def next_ts():
        nonlocal sec_offset
        # Replace seconds in timestamp
        # Parse: 2026-01-15T02:00:00Z -> increment seconds
        ts = scan_timestamp[:-4] + f"{sec_offset:02d}Z"
        sec_offset = min(sec_offset + 1, 59)
        return ts

    # 1. Start event
    events.append(format_event(
        timestamp=next_ts(), hostname=hostname, os=os_name,
        run_id=run_id, version=ODIN_VERSION, type_="odin_start",
        fields={"run_as": "root", "euid": "0", "message": "TA-ODIN enumeration started"},
    ))

    # 2. Service events
    for svc in profile["services"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="service",
            fields=svc,
        ))

    # 3. Port events
    for port in profile["ports"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="port",
            fields=port,
        ))

    # 4. Package events
    for pkg in profile["packages"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="package",
            fields=pkg,
        ))

    # 5. Cron events
    for cron in profile["cron"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="cron",
            fields=cron,
        ))

    # 6. Process events
    for proc in profile["processes"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="process",
            fields=proc,
        ))

    # 7. Mount events
    for mnt in profile["mounts"]:
        events.append(format_event(
            timestamp=next_ts(), hostname=hostname, os=os_name,
            run_id=run_id, version=ODIN_VERSION, type_="mount",
            fields=mnt,
        ))

    # 8. Complete event
    module_count = sum(1 for k in ["services", "ports", "packages", "cron", "processes", "mounts"] if profile[k])
    events.append(format_event(
        timestamp=next_ts(), hostname=hostname, os=os_name,
        run_id=run_id, version=ODIN_VERSION, type_="odin_complete",
        fields={
            "modules_total": "6",
            "modules_success": str(module_count),
            "modules_failed": str(6 - module_count),
            "message": "TA-ODIN enumeration completed",
        },
    ))

    return events
```

**Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py -v`
Expected: All pass

**Step 5: Commit**

```bash
git add tools/generate_odin_data.py tools/tests/test_generate_odin_data.py
git commit -m "feat(tools): implement generate_scan for full ODIN host enumeration"
```

---

## Task 4: Add CLI and file output

**Files:**
- Modify: `tools/generate_odin_data.py`
- Modify: `tools/tests/test_generate_odin_data.py`

**Step 1: Write the failing test**

```python
import tempfile
import os

from generate_odin_data import generate_all, HOST_PROFILES


def test_generate_all_produces_output():
    """generate_all() returns events for all hosts."""
    events = generate_all(scan_date="2026-01-15")
    assert len(events) > 0
    # Should have events for all 15 hosts
    hostnames_in_output = set()
    for event in events:
        for part in event.split():
            if part.startswith("hostname="):
                hostnames_in_output.add(part.split("=", 1)[1])
    assert len(hostnames_in_output) == len(HOST_PROFILES)


def test_generate_all_writes_file():
    """generate_all() writes events to output file."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
        tmpfile = f.name
    try:
        events = generate_all(scan_date="2026-01-15", output_file=tmpfile)
        with open(tmpfile) as f:
            lines = f.readlines()
        assert len(lines) == len(events)
        assert all(line.strip().startswith("timestamp=") for line in lines)
    finally:
        os.unlink(tmpfile)


def test_generate_all_host_filter():
    """generate_all() with hosts filter only generates for specified hosts."""
    events = generate_all(
        scan_date="2026-01-15",
        hosts=["web-prod-01.odin.local", "db-prod-01.odin.local"],
    )
    hostnames_in_output = set()
    for event in events:
        for part in event.split():
            if part.startswith("hostname="):
                hostnames_in_output.add(part.split("=", 1)[1])
    assert hostnames_in_output == {"web-prod-01.odin.local", "db-prod-01.odin.local"}
```

**Step 2: Run test to verify it fails**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py::test_generate_all_produces_output -v`
Expected: FAIL — `ImportError: cannot import name 'generate_all'`

**Step 3: Write implementation**

```python
import random
from datetime import datetime


def generate_all(
    scan_date: str = None,
    output_file: str = None,
    hosts: list[str] = None,
) -> list[str]:
    """Generate ODIN scans for all (or specified) host profiles.

    Args:
        scan_date: ISO date string (YYYY-MM-DD). Defaults to today.
        output_file: Path to write output. None = no file output.
        hosts: List of hostnames to generate. None = all profiles.

    Returns:
        List of all event strings.
    """
    if scan_date is None:
        scan_date = datetime.utcnow().strftime("%Y-%m-%d")

    profiles = HOST_PROFILES
    if hosts:
        profiles = {h: p for h, p in HOST_PROFILES.items() if h in hosts}

    all_events = []
    for hostname, profile in profiles.items():
        # Each host scans at a random hour (01:00-05:00 — typical maintenance window)
        hour = random.randint(1, 5)
        minute = random.randint(0, 59)
        scan_timestamp = f"{scan_date}T{hour:02d}:{minute:02d}:00Z"
        run_id = f"{int(datetime.fromisoformat(scan_timestamp.replace('Z', '+00:00')).timestamp())}-{random.randint(1000, 9999)}"

        events = generate_scan(hostname, profile, scan_timestamp, run_id)
        all_events.extend(events)

    # Sort by timestamp for realistic ordering
    all_events.sort(key=lambda e: e.split()[0])

    if output_file:
        from pathlib import Path
        Path(output_file).parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, "w") as f:
            for event in all_events:
                f.write(event + "\n")

    return all_events


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate synthetic ODIN enumeration data")
    parser.add_argument("--output", "-o", default="tools/output/odin_enumeration.log",
                        help="Output file path (default: tools/output/odin_enumeration.log)")
    parser.add_argument("--date", "-d", default=None,
                        help="Scan date in YYYY-MM-DD format (default: today)")
    parser.add_argument("--hosts", nargs="*", default=None,
                        help="Specific hostnames to generate (default: all)")
    parser.add_argument("--list-hosts", action="store_true",
                        help="List available host profiles and exit")
    args = parser.parse_args()

    if args.list_hosts:
        for h in sorted(HOST_PROFILES.keys()):
            print(h)
        raise SystemExit(0)

    events = generate_all(scan_date=args.date, output_file=args.output, hosts=args.hosts)
    print(f"Generated {len(events)} events for {len(set(e.split()[1].split('=')[1] for e in events))} hosts")
    if args.output:
        print(f"Written to: {args.output}")
```

**Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tools/tests/test_generate_odin_data.py -v`
Expected: All pass

**Step 5: Commit**

```bash
git add tools/generate_odin_data.py tools/tests/test_generate_odin_data.py
git commit -m "feat(tools): add CLI and file output for ODIN data generator"
```

---

## Task 5: Validate signals against classification lookups

**Files:**
- Create: `tools/tests/test_classification_coverage.py`

This is the key validation: do the generated signals actually match entries in our four classification CSVs?

**Step 1: Write the test**

```python
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
    lookup_services = load_csv_column("odin_classify_services.csv", "service_name")
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
    lookup_packages = load_csv_column("odin_classify_packages.csv", "package_name")
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
```

**Step 2: Run tests**

Run: `python3 -m pytest tools/tests/test_classification_coverage.py -v`
Expected: All pass. If any fail, adjust host profiles (Task 2) to add missing signal values until tests pass.

**Step 3: Commit**

```bash
git add tools/tests/test_classification_coverage.py
git commit -m "test(tools): add classification coverage validation for ODIN generator"
```

---

## Task 6: Generate data and ingest into Splunk

**Files:**
- No new files — operational task

**Step 1: Generate the data**

```bash
cd /Users/joehanse/Library/CloudStorage/OneDrive-Cisco/Documents/03_Funny_Projects/Project_Odin/git/odin
python3 tools/generate_odin_data.py --output tools/output/odin_enumeration.log --date 2026-01-15
```

Expected: `Generated ~700 events for 15 hosts` + file at `tools/output/odin_enumeration.log`

**Step 2: Verify output format**

```bash
head -5 tools/output/odin_enumeration.log
wc -l tools/output/odin_enumeration.log
grep -c "type=service" tools/output/odin_enumeration.log
grep -c "type=port" tools/output/odin_enumeration.log
grep -c "type=package" tools/output/odin_enumeration.log
```

**Step 3: Ingest into Splunk**

Option A — Upload via Splunk Web UI:
1. Settings → Add Data → Upload → select `odin_enumeration.log`
2. Set sourcetype = `odin:enumeration`, index = `odin_discovery`
3. If `odin_discovery` index doesn't exist, use `main` with sourcetype override

Option B — Use Splunk HEC (if available):
```bash
# Split into individual events and POST via HEC
while IFS= read -r line; do
  curl -s -k https://localhost:8088/services/collector/event \
    -H "Authorization: Splunk <HEC_TOKEN>" \
    -d "{\"sourcetype\": \"odin:enumeration\", \"index\": \"odin_discovery\", \"event\": \"$line\"}"
done < tools/output/odin_enumeration.log
```

Option C — Copy file to Splunk monitor path:
```bash
# If Splunk monitors a directory, copy the file there
cp tools/output/odin_enumeration.log /path/to/splunk/etc/apps/search/local/data/
```

**Step 4: Validate in Splunk**

Use the MCP Splunk tools or Splunk Web:

```spl
-- Count events by type
index=odin_discovery sourcetype=odin:enumeration | stats count by type

-- Test classification lookup
index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package)
| eval signal_type=type
| eval signal_value=case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)
| lookup odin_log_sources signal_type, signal_value
| where isnotnull(host_role)
| stats values(host_role) AS host_roles by hostname

-- Verify the Host Inventory saved search would work
index=odin_discovery sourcetype=odin:enumeration (type=service OR type=port OR type=package)
| eval signal_type=type
| eval signal_value=case(type="service", service_name, type="port", listen_port."/".transport, type="package", package_name)
| lookup odin_log_sources signal_type, signal_value
| where isnotnull(host_role)
| stats values(host_role) AS host_roles, values(log_source) AS log_sources, values(recommended_ta) AS recommended_tas by hostname
```

**Step 5: Commit generated data (optional)**

```bash
git add tools/output/odin_enumeration.log
git commit -m "data(tools): add sample ODIN synthetic data for 15 hosts"
```

---

## Task 7: Final commit and documentation

**Files:**
- Modify: `DOCS/CHANGEHISTORY.md` (add tools entry)

**Step 1: Add entry to CHANGEHISTORY.md**

Add under a new section at the top:

```markdown
## v2.2.1 — Synthetic Data Generator

**Date:** 2026-02-22

### New files

| File | Description |
|------|-------------|
| `tools/generate_odin_data.py` | Synthetic ODIN data generator (15 host profiles, ~700 events) |
| `tools/tests/test_generate_odin_data.py` | Unit tests for event format and scan generation |
| `tools/tests/test_classification_coverage.py` | Validation tests against classification lookups |
| `tools/output/odin_enumeration.log` | Sample generated data |

### Host profiles

15 Linux hosts covering: web_server, database_server, container_host, cache_server,
splunk_server, syslog_receiver, monitoring_server, kubernetes_master, kubernetes_node,
mail_server, vpn_server, cicd_server, dns_server, message_broker.
```

**Step 2: Commit**

```bash
git add DOCS/CHANGEHISTORY.md
git commit -m "docs: add v2.2.1 synthetic data generator to change history"
```

---

## Summary

| Task | Files | Tests | Description |
|------|-------|-------|-------------|
| 1 | `tools/generate_odin_data.py`, `tools/tests/test_*.py` | 3 | `format_event` helper |
| 2 | Same files | 6 | 15 host profiles with base + role signals |
| 3 | Same files | 5 | `generate_scan` for full host enumeration |
| 4 | Same files | 3 | `generate_all` + CLI with argparse |
| 5 | `tools/tests/test_classification_coverage.py` | 5 | Cross-reference signals vs lookup CSVs |
| 6 | (operational) | — | Generate, ingest, validate in Splunk |
| 7 | `DOCS/CHANGEHISTORY.md` | — | Documentation update |

**Total:** ~22 tests, ~1 Python file + 2 test files + 1 generated data file
