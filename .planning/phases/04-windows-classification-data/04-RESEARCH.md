---
phase: 04-windows-classification-data
status: complete
gathered: 2026-04-17
mode: inline (researcher subagent timed out at 502 after 51 tool uses; recovered via direct empirical scan + documented knowledge)
---

# Phase 4 Research — Windows Classification Data

## Critical Finding (changes scope of D3)

**`transforms.conf` wildcard support already exists.** Empirical scan of `ODIN_app_for_splunk/default/transforms.conf` shows:

```ini
[odin_classify_services]
filename = odin_classify_services.csv
case_sensitive_match = false
match_type = WILDCARD(service_pattern)

[odin_classify_packages]
filename = odin_classify_packages.csv
case_sensitive_match = false
match_type = WILDCARD(package_pattern)
```

**Implication for D3 (CONTEXT.md):** The `match_type = WILDCARD(package_pattern)` line was assumed missing — it is in fact **already present** along with case-insensitive matching. Phase 4 does **NOT** need a `transforms.conf` change. The plan should only modify the four CSV lookup files.

Service-pattern matching is already case-insensitive AND wildcard-enabled, so Windows service names like `MSSQLSERVER` (which Get-Service emits as `MSSQLSERVER`) will match patterns like `mssqlserver` or `MSSQL*`.

## 1. Verified Splunkbase TA names (canonical app IDs)

Source: `ODIN_app_for_splunk/lookups/odin_recommended_tas.csv` (project's own canonical registry, last refreshed during v1.0.0).

| Product | Canonical `recommended_ta` | Splunkbase ID | Status |
|---|---|---|---|
| Windows umbrella | `Splunk_TA_windows` | 742 | Official |
| IIS Web Server | `Splunk_TA_microsoft-iis` | 3185 | Official (CIM Web model; richer than Windows umbrella for IIS) |
| SQL Server | `Splunk_TA_microsoft_sqlserver` | 2648 | Official |
| Exchange Server | `Splunk_TA_microsoft_exchange` | 3225 | Official |
| Sysmon | `Splunk_TA_microsoft_sysmon` | 5709 | Official (replaces archived 1914) |
| Microsoft Defender | `Splunk_TA_microsoft_defender` | 6207 | Official (M365 Defender + Defender for Endpoint) |

**Corrections to CONTEXT.md D5 (typos in TA names):**
- ❌ `Splunk_TA_exchange` → ✅ `Splunk_TA_microsoft_exchange`
- ❌ `TA-microsoft-sysmon` → ✅ `Splunk_TA_microsoft_sysmon` (5709 replaces archived 1914)
- ✅ `Splunk_TA_microsoft-iis` is correct (note the hyphen — it's a Splunk inconsistency, the registry ID has hyphen even though most others use underscore)

**No dedicated TAs exist on Splunkbase for:** Active Directory (Splunk_TA_microsoft_ad referenced in CONTEXT.md does NOT appear in the registry — likely confused with the Identity model parts in Splunk_TA_windows; treat AD as baseline `Splunk_TA_windows`), Hyper-V, SCCM/MECM, ADFS, WSUS, ADCS, NPS, DFS, WDS, Failover Cluster, Print Server. All fall to `Splunk_TA_windows` baseline per D5 hybrid strategy.

**Action for planner:** If new entries reference TA IDs not in `odin_recommended_tas.csv`, the planner must EITHER add them to the recommended_tas registry first OR fall back to `Splunk_TA_windows` per D5. Easier: stick to the 6 confirmed TAs above + `Splunk_TA_windows` as fallback. Don't invent TA names.

## 2. Standard Splunk sourcetype values

Source: Splunk_TA_windows v8.x documentation patterns + Splunk Common Information Model (CIM) standards. These are the values that the named TAs canonically emit, so the lookup `sourcetype` column should match them.

| Log source | Standard sourcetype |
|---|---|
| Windows Security Event Log | `WinEventLog:Security` |
| Windows Application Event Log | `WinEventLog:Application` |
| Windows System Event Log | `WinEventLog:System` |
| Windows Setup Event Log | `WinEventLog:Setup` |
| Sysmon | `XmlWinEventLog:Microsoft-Windows-Sysmon/Operational` (Splunk_TA_microsoft_sysmon canonical) |
| PowerShell operational | `WinEventLog:Microsoft-Windows-PowerShell/Operational` |
| DNS Server analytical/audit | `WinEventLog:Microsoft-Windows-DNSServer/Analytical` and `/Audit` |
| DNS Debug log file | `MSAD:NT6:DNS` (legacy file-based debug log) |
| DHCP Server operational | `WinEventLog:Microsoft-Windows-Dhcp-Server/Operational` |
| DHCP audit text file | `DhcpSrvLog` (file-based) |
| IIS access log (W3C) | `iis` (canonical for Splunk_TA_microsoft-iis) |
| IIS HTTPERR log | `iis_httperr` |
| Exchange transport (msgtrk) | `MSExchange:2013:MessageTracking` (Splunk_TA_microsoft_exchange) |
| Exchange protocol logs | `MSExchange:2013:HttpProxy:*` family |
| ADFS audit | `WinEventLog:AD FS Tracing/Debug` and `WinEventLog:Security` |
| Active Directory Web Services | `WinEventLog:Active Directory Web Services` |
| Active Directory directory service | `WinEventLog:Directory Service` |
| Failover Cluster | `WinEventLog:Microsoft-Windows-FailoverClustering/Operational` |
| Hyper-V management | `WinEventLog:Microsoft-Windows-Hyper-V-VMMS/Admin` |
| Print Service | `WinEventLog:Microsoft-Windows-PrintService/Operational` and `/Admin` |
| TaskScheduler | `WinEventLog:Microsoft-Windows-TaskScheduler/Operational` |
| WindowsUpdate / WSUS Server | `WinEventLog:Application` (WSUS server uses Application channel + IIS access logs from WsusContent path) |
| RDS / Terminal Server | `WinEventLog:Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` |
| NPS / RADIUS | `WinEventLog:Security` (NPS logs to Security channel) + IAS file `C:\Windows\System32\LogFiles\IN*.LOG` typed as `IAS` |
| DFS Replication | `WinEventLog:DFS Replication` |

**Pitfall:** Sysmon TA expects `XmlWinEventLog:Microsoft-Windows-Sysmon/Operational`, NOT `WinEventLog:Microsoft-Windows-Sysmon/Operational`. The `Splunk_TA_windows` and `Splunk_TA_microsoft_sysmon` TAs handle different formats — use the XML form for Sysmon.

## 3. Realistic Get-Service names (case-sensitive correctness)

The TA-ODIN `services.ps1` module emits whatever `Get-Service | Select-Object Name` returns. Below are the canonical Windows service `Name` values per Microsoft documentation. Since `case_sensitive_match = false` in transforms.conf, exact case in the lookup `service_pattern` is not strictly required, but matching documentation case is the discoverable convention.

| Product | Service Name (Get-Service `Name`) |
|---|---|
| Active Directory NTDS | `NTDS` |
| AD Web Services | `ADWS` |
| Kerberos KDC | `Kdc` |
| Netlogon | `Netlogon` |
| DNS Server | `DNS` |
| DHCP Server | `DHCPServer` |
| IIS World Wide Web | `W3SVC` |
| IIS Windows Process Activation | `WAS` |
| IIS Admin Service | `IISADMIN` |
| SQL Server engine | `MSSQLSERVER` (default instance) or `MSSQL$INSTANCENAME` (named instance) |
| SQL Server Agent | `SQLSERVERAGENT` (default) or `SQLAgent$INSTANCENAME` |
| SQL Server Browser | `SQLBrowser` |
| SQL Server Analysis | `MSSQLServerOLAPService` |
| SQL Server Reporting | `SQLServerReportingServices` |
| Exchange IS | `MSExchangeIS` |
| Exchange Transport | `MSExchangeTransport` |
| Exchange ServiceHost | `MSExchangeServiceHost` |
| Exchange Frontend Transport | `MSExchangeFrontEndTransport` |
| Exchange Mailbox Replication | `MSExchangeMailboxReplication` |
| File server (SMB) | `LanmanServer` |
| File server workstation | `LanmanWorkstation` |
| Print Spooler | `Spooler` |
| Hyper-V VM Management | `vmms` |
| Hyper-V Compute | `vmcompute` |
| ADFS | `adfssrv` |
| Terminal Service | `TermService` |
| RDS Session Broker | `Tssdis` (Server 2008) / `SessionEnv` (newer) |
| RDS Connection Broker | `RDMS` |
| SCCM / MECM agent | `CcmExec` |
| SCCM / MECM site server | `SMS_SITE_COMPONENT_MANAGER`, `SMS_EXECUTIVE` |
| WSUS Service | `WsusService` |
| Certificate Services | `CertSvc` |
| NPS / Network Policy Server | `IAS` |
| DFS Namespace | `Dfs` |
| DFS Replication | `DFSR` |
| Windows Deployment Services | `WDSServer` |
| Failover Cluster | `ClusSvc` |
| Windows Remote Mgmt | `WinRM` |
| Remote Registry | `RemoteRegistry` |

## 4. Realistic registry display name patterns (wildcard-compatible per D3)

These are the typical `DisplayName` values shown in `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` for Windows server products. Confirmed via Microsoft installation guides and Splunkbase TA documentation (no live Windows host available — empirical refinement deferred to PROD-02 pilot).

| Product | Wildcard pattern recommendation |
|---|---|
| SQL Server engine | `Microsoft SQL Server *(64-bit)*` |
| SQL Server SSMS | `Microsoft SQL Server Management Studio*` |
| SQL Server Tools | `SQL Server *Common Files*` |
| Exchange Server | `Microsoft Exchange Server*` |
| Active Directory DS role | `Active Directory Domain Services*` (typically detected via service NTDS, not via uninstall key — but install-time roles sometimes register) |
| ADFS | `Active Directory Federation Services*` |
| ADCS / Cert Authority | `Active Directory Certificate Services*` |
| IIS | `Internet Information Services*` (rarely uninstall-key registered; usually detected via W3SVC service) |
| IIS Express (dev tooling) | `IIS *Express*` |
| Hyper-V | `Hyper-V*` |
| SCCM / MECM client | `Configuration Manager Client*` |
| SCCM / MECM site server | `System Center Configuration Manager*` |
| WSUS Server | `Windows Server Update Services*` |
| WDS | `Windows Deployment Services*` |
| .NET Framework | `Microsoft .NET Framework*` |
| Windows Server itself | `Windows Server *` (rare — installed not via package; usually OS detection via os field) |
| Windows 10 (workstation) | `Windows 10 *` |
| Windows 11 (workstation) | `Windows 11 *` |

**Pattern strategy:** Most server roles are detected reliably via SERVICE signal, not PACKAGE signal. Packages serve as supplementary evidence (e.g., `Microsoft SQL Server 2019 (64-bit)` confirms version when the SQL service is detected). Don't expect package-only detection to identify a role — pair signals.

**Excluded patterns (these are tools, NOT server roles — keep separate or omit):**
- `Microsoft SQL Server Management Studio*` is a workstation/admin tool, not a server signal
- `Visual Studio*` is a developer tool, not a server signal
- `Windows Admin Center*` is a management UI, not a server role

## 5. transforms.conf snippet for D3 — NOT NEEDED

Per the critical finding above: the `match_type = WILDCARD(package_pattern)` and `WILDCARD(service_pattern)` lines already exist in `transforms.conf`. Phase 4 must NOT modify transforms.conf.

**If the planner adds a transforms.conf change task, it is a deviation from research findings and the user should be alerted.**

## 6. AppInspect compatibility notes

Adding rows to `*.csv` lookup files is universally AppInspect-safe under any scope. Phase 3 already verified the lookups are accepted by `splunk-appinspect 4.1.3 --mode precert --excluded-tags cloud` — adding rows preserves that.

**Specific checks the planner should be aware of:**

- `check_for_lookups_with_invalid_csv` — CSV files must parse cleanly (no embedded unescaped quotes/newlines, comma-correct row counts). Addressed by valid CSV format.
- `check_for_lookups_referenced_in_transforms_conf` — every `*.csv` in `lookups/` must have a `[lookup_name]` stanza in `transforms.conf` with `filename = <csvname>.csv`. All 4 CSVs already have stanzas. No new lookups added — safe.
- `check_for_lookups_with_no_transforms_conf` — counterpart of above; no new lookup files created.
- `check_for_default_meta` — `metadata/default.meta` already permits `[lookups/odin_classify_services]`, etc. (Phase 3 PROD-05). Adding rows doesn't change permission scope.
- No "Cloud Victoria" rules apply because we use `--excluded-tags cloud`.

**Verification step the plan MUST include:** Re-run `splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud` and assert `summary.failure + summary.error == 0`. Save the JSON output to `.planning/artifacts/appinspect/odin-app-phase04.json` for traceability (mirror the Phase 3 pattern).

## 7. Validation Architecture (Nyquist)

Phase 4 is data-only. The Nyquist validation dimensions for a data phase reduce to:

| Dimension | Phase 4 application |
|---|---|
| **D1 — Field parity** | N/A (no new fields) |
| **D2 — Output format** | N/A (no new emit code) |
| **D3 — Idempotency** | New CSV rows must be unique (no duplicate `signal_type,signal_value` keys in `odin_log_sources.csv`) |
| **D4 — Bounds enforcement** | N/A (lookup files have no runtime bounds) |
| **D5 — Per-type behavior** | A simulated Windows host event (service=W3SVC + service=MSSQLSERVER + port=445/tcp) classifies to ≥2 distinct `host_role` values (e.g., web_server + database_server + file_server) |
| **D6 — Failure surfacing** | A simulated unknown Windows service does NOT crash the lookup pipeline; missing match returns null `host_role` (verified by SPL: `| eval signal_type="service" signal_value="UnknownService" | lookup odin_log_sources signal_type signal_value` returns row with null `host_role`) |
| **D7 — End-to-end pipeline** | Synthetic Windows fixture replay via existing `tools/tests/windows-fixtures/hostA` produces non-empty `host_roles` and non-empty `recommended_tas` columns when fed through the host-inventory saved search SPL |
| **D8 — Validation suite** | A `tools/tests/check-windows-classification.sh` script (or extension to existing harness) asserts: row counts grew per ROADMAP success criteria 1–4, no duplicate keys, simulated fixture classifies to ≥1 Windows-mapped role |

**Recommended VALIDATION.md content:** D5, D6, D7, D8 above with specific SPL snippets and shell commands. The planner should generate this file from the template.

## 8. Pitfalls and surprises discovered during research

1. **D3 already implemented** (transforms.conf change is a no-op) — see "Critical Finding" above.
2. **`Splunk_TA_microsoft_exchange` not `Splunk_TA_exchange`** — corrected naming.
3. **`Splunk_TA_microsoft_sysmon` (5709) not `TA-microsoft-sysmon` (1914)** — the older community-named TA was archived; use the current Splunk-official ID.
4. **Sysmon sourcetype is `XmlWinEventLog:` not `WinEventLog:`** — this trips many people up. Per Splunk_TA_microsoft_sysmon docs, the TA expects XML event format.
5. **No dedicated TA exists for AD/ADFS/Hyper-V/SCCM** — all map to `Splunk_TA_windows` baseline per D5. Don't invent TA names.
6. **Most server roles are detected via SERVICE signal, not PACKAGE signal** — package patterns serve as confirmation, not primary detection. The plan should weight services > ports > packages in `odin_log_sources.csv` row count.
7. **Named SQL instances** (`MSSQL$INSTANCENAME`) — wildcard pattern `MSSQL*` covers both default and named, but loses semantic info. Consider two patterns: exact `MSSQLSERVER` for default, `MSSQL$*` for named.
8. **NPS / RADIUS logs to Security channel** — there is no dedicated NPS log channel; everything appears in `WinEventLog:Security` with specific event IDs (6272–6280). The `log_path` should be `WinEventLog:Security` and `description` should mention "filter by EventCode 6272..6280 for NPS events".
9. **WSUS server is essentially an IIS web app** — its primary signal is the `WsusService` Windows service + IIS on port 8530/8531. The `Splunk_TA_windows` baseline covers it via Application channel; `Splunk_TA_microsoft-iis` may also apply for the WSUS HTTP layer.
10. **`odin_recommended_tas.csv` is a separate registry** that the planner should consult before inventing TA names. If a TA isn't in the registry, either add it (with verified Splunkbase ID) or fall back to `Splunk_TA_windows`.

---

## Summary for the planner

- **Scope reduced:** No transforms.conf changes (already in place from earlier work).
- **Files to modify:** 4 CSVs in `ODIN_app_for_splunk/lookups/` + `.planning/artifacts/appinspect/odin-app-phase04.json` (verification artifact).
- **Plan structure suggestion:** 1–2 plans. Single-plan option: one large data PR (~80–100 row additions across 4 files). Two-plan option: Plan 1 = `services` + `ports` (foundational signals); Plan 2 = `packages` + `log_sources` (registry patterns + TA mapping). Two-plan option is easier to review and allows AppInspect verification after Plan 1 lands.
- **Verification gates:** AppInspect Enterprise scope clean + synthetic Windows fixture produces non-empty classification + Phase 1+2+3 regression suite still green.
- **Use `odin_recommended_tas.csv` as the source of truth for TA names.** Don't invent.
- **CONTEXT.md D3 needs a planner-time correction note** — say explicitly that the transforms.conf change is unnecessary because it's already in place. Or update CONTEXT.md before planning. Recommend the latter for cleanliness.
