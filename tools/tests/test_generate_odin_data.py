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
