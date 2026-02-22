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
