# Structure

**Analysis Date:** 2026-04-10

## Top-level layout

```
odin/
├── CLAUDE.md                       # Project source-of-truth: vision, two-app split, conventions
├── README.md                       # (none at repo root — see per-app READMEs)
├── TA-ODIN/                        # FORWARDER APP — deploys to Universal Forwarders via Deployment Server
├── ODIN_app_for_splunk/            # INDEXER + SEARCH HEAD APP — index, lookups, search-time config, dashboard
├── DOCS/                           # Project-level documentation
└── tools/                          # Out-of-band Python utilities (not deployed to Splunk)
```

The two top-level Splunk app directories are **the deployment unit** for this project — packaging is "tar each one and ship" with no build step.

## TA-ODIN/ — Forwarder App

```
TA-ODIN/
├── README.md                       # User-facing install/usage
├── bin/
│   ├── odin.sh                     # Linux orchestrator (autodiscovers modules/, exports ODIN_*, runs each)
│   ├── odin.ps1                    # Windows orchestrator placeholder (NOT IMPLEMENTED)
│   └── modules/                    # Auto-discovered discovery modules
│       ├── services.sh             # systemd / SysV / init.d service enumeration
│       ├── ports.sh                # Listening TCP/UDP ports (ss → netstat fallback)
│       ├── packages.sh             # dpkg / rpm / apk / pacman packages
│       ├── cron.sh                 # /etc/crontab, /etc/cron.d, user crontabs, systemd timers, anacron
│       ├── processes.sh            # Running processes (single ps -eo call)
│       └── mounts.sh               # df-based filesystem mount enumeration
├── default/                        # Splunk app default config (forwarder scope)
│   ├── app.conf                    # App metadata, version
│   ├── inputs.conf                 # [script://./bin/odin.sh] — 30-day interval, 120s timeout
│   └── props.conf                  # Line-breaking + timestamp ONLY (no KV_MODE here)
├── local/                          # Customer overrides (empty by default)
└── static/                         # Empty
```

**Hard rules for TA-ODIN/:**
- Never add `indexes.conf` here. Indexes belong in `ODIN_app_for_splunk/`.
- Never add `transforms.conf`, `savedsearches.conf`, or `lookups/` here.
- Never add KV_MODE / search-time props here. Forwarders only need line-breaking.
- New discovery modules go in `bin/modules/<name>.sh` — the orchestrator picks them up automatically. No registration step.

## ODIN_app_for_splunk/ — Indexer + Search Head App

```
ODIN_app_for_splunk/
├── README.md
├── default/
│   ├── app.conf                    # App metadata
│   ├── indexes.conf                # odin_discovery index definition (1y retention, 1GB cap)
│   ├── props.conf                  # Full search-time parsing: KV_MODE=auto, CIM aliases, LOOKUP-* bindings
│   ├── transforms.conf             # Lookup definitions (odin_classify_services / _ports / _packages)
│   ├── savedsearches.conf          # ODIN - Host Inventory / Log Source Details / TA Deployment Matrix
│   └── data/
│       └── ui/
│           ├── nav/
│           │   └── default.xml     # Navigation menu
│           └── views/
│               └── odin_overview.xml  # Dashboard Studio (v2 JSON-in-XML) overview view
├── lookups/                        # All classification + reference CSVs
│   ├── odin_classify_services.csv  # WILDCARD service_pattern → category/role/vendor
│   ├── odin_classify_ports.csv     # (port, transport) → expected_service/category
│   ├── odin_classify_packages.csv  # WILDCARD package_pattern → category/role/vendor
│   ├── odin_log_sources.csv        # (signal_type, signal_value) → host_role/log_source/recommended_ta
│   └── odin_recommended_tas.csv    # recommended_ta → Splunkbase metadata
└── metadata/
    └── default.meta                # Exports lookups/props/transforms/savedsearches/views to system scope
```

**Hard rules for ODIN_app_for_splunk/:**
- Never add `inputs.conf` here. Scripted inputs run on forwarders only.
- All new lookups go in `lookups/` and must be declared in `transforms.conf`.
- All new dashboards go in `default/data/ui/views/` and must be added to `default/data/ui/nav/default.xml`.
- All new saved searches go in `savedsearches.conf` with the `ODIN - Title Case` naming convention.
- Generated output lookups (e.g. `odin_host_inventory.csv`) are written by saved searches at runtime — do not commit them.

**Note on dashboard state:** `default/data/ui/views/odin_overview.xml` exists despite `CLAUDE.md`'s "Dashboards: Not started" claim. Treat the CLAUDE.md status note as outdated — there is a dashboard in flight.

## DOCS/ — Project documentation

```
DOCS/
├── CHANGEHISTORY.md                # ISO 8601 CET-stamped change log (project-wide rule)
├── ARCHITECTURE.md                 # ASCII architecture diagrams + file reference
├── COMMANDS.md                     # Per-command root requirements and risk notes
├── TA_COVERAGE_REPORT.md           # Splunkbase TA coverage analysis (Phase 2 output)
└── plans/                          # Date-prefixed historical plan documents
    ├── 2026-02-22-odin-synthetic-data.md
    ├── 2026-02-22-splunkbase-ta-coverage.md
    └── 2026-02-23-log-discovery-module.md
```

**Conventions:**
- Plans are immutable once written. New plans get a new dated file.
- `CHANGEHISTORY.md` is hand-maintained — there is no automation to update it.
- Architecture decisions and the two-app split rationale live in `CLAUDE.md`, not `DOCS/ARCHITECTURE.md`. The `DOCS/ARCHITECTURE.md` file is the diagram-and-file-reference companion to `CLAUDE.md`'s prose.

## tools/ — Out-of-band utilities

```
tools/
├── generate_odin_data.py           # Synthetic Splunk event generator (for demos / dashboard testing)
├── output/
│   └── odin_enumeration.log        # Last generator run output
└── tests/                          # Pytest suite — only covers the generator, NOT production bash
    ├── __init__.py
    ├── test_generate_odin_data.py
    └── test_classification_coverage.py
```

**Why this exists separately:**
- It is **not** part of either Splunk app and is never deployed.
- It generates fake `index=odin_discovery` events that look identical to what `bin/odin.sh` would emit on real hosts, so dashboards and saved searches can be developed without a real estate of endpoints to enumerate.
- The `test_classification_coverage.py` test is the only thing that touches `ODIN_app_for_splunk/lookups/*.csv` from CI (if CI existed). It is a coverage canary, not a lookup correctness test.

## Where to add things

| What you're adding | Where it goes |
|---|---|
| New discovery domain (e.g. firewall rules, kernel modules) | New file `TA-ODIN/bin/modules/<name>.sh` — auto-discovered |
| Windows enumeration | `TA-ODIN/bin/odin.ps1` (currently a placeholder) and Windows-specific modules |
| Service classification mapping | New row in `ODIN_app_for_splunk/lookups/odin_classify_services.csv` |
| Port classification mapping | New row in `ODIN_app_for_splunk/lookups/odin_classify_ports.csv` |
| Package classification mapping | New row in `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` |
| Host role / log source mapping (Phase 2) | New row in `ODIN_app_for_splunk/lookups/odin_log_sources.csv` |
| Recommended-TA reference data | New row in `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` |
| New dashboard | `ODIN_app_for_splunk/default/data/ui/views/<name>.xml` + nav entry in `default.xml` |
| New saved search | `ODIN_app_for_splunk/default/savedsearches.conf` (`ODIN - Title Case` stanza) |
| New scripted input | `TA-ODIN/default/inputs.conf` (forwarder side) |
| New index | `ODIN_app_for_splunk/default/indexes.conf` (indexer side, never forwarder) |
| New search-time field extraction or lookup binding | `ODIN_app_for_splunk/default/props.conf` + `transforms.conf` |
| Customer-specific override | `<app>/local/` — never edit `default/` |
| Project doc / plan | `DOCS/plans/YYYY-MM-DD-<slug>.md` |
| Change history entry | Append to top of `DOCS/CHANGEHISTORY.md` with CET timestamp |
| Sample / demo data | `tools/` (Python generator), output to `tools/output/` |

## Naming conventions (file-level)

- Modules: lowercase singular noun, `.sh` extension: `services.sh`, `ports.sh`.
- Lookups: `odin_<purpose>.csv` — `odin_classify_*` for classification, `odin_log_sources.csv` for the central Phase 2 mapping, `odin_recommended_tas.csv` for reference.
- Generated lookups: `odin_<topic>.csv` (e.g. `odin_host_inventory.csv`) — written by saved searches via `outputlookup`, not committed.
- Saved searches: `ODIN - <Title Case>` stanza names.
- Dashboards: `odin_<purpose>.xml`.
- Plans: `YYYY-MM-DD-<kebab-slug>.md`.

## default/ vs local/ override convention

- `default/` is the shipped configuration. Treat as read-only on customer installs.
- `local/` is the override layer. Customer-specific tuning (different scan interval, different index name, additional modules) goes here.
- Splunk merges `local/` over `default/` automatically.
- The repo ships `local/` empty in TA-ODIN; ODIN_app_for_splunk has no `local/` directory at all by default (Splunk creates it on first override).

## Two-app split — file placement (recap)

| Config / asset | TA-ODIN | ODIN_app_for_splunk |
|---|---|---|
| `bin/odin.sh` + modules | yes | no |
| `inputs.conf` (scripted input) | yes | **never** |
| `props.conf` (line-breaking + timestamp only) | yes | yes (full parsing version) |
| `indexes.conf` | **never** | yes |
| `transforms.conf` | no | yes |
| `savedsearches.conf` | no | yes |
| `lookups/*.csv` | no | yes |
| `data/ui/views/*.xml` (dashboards) | no | yes |
| `data/ui/nav/default.xml` | no | yes |
| `metadata/default.meta` | no | yes |

This split is the single most important architectural invariant. Files in the wrong app will either silently no-op (search-time props on a forwarder) or cause serious problems (`indexes.conf` on a forwarder will try to create indexes the UF can't host).
