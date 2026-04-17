# Phase 4: Windows Classification Data — Context

**Gathered:** 2026-04-17
**Status:** Ready for planning
**Source:** /gsd-discuss-phase 4 (5 gray areas, all decided)

<domain>
## Phase Boundary

Populate Windows-specific rows in the four classification lookups under `ODIN_app_for_splunk/lookups/`:

- `odin_classify_services.csv` — Windows service patterns → category/subcategory/vendor/role/description
- `odin_classify_ports.csv` — Windows-relevant TCP/UDP listening ports → expected_service/category/description
- `odin_classify_packages.csv` — Windows registry display names → category/vendor/role/description (wildcard-enabled)
- `odin_log_sources.csv` — `(signal_type, signal_value) → host_role + log_source + sourcetype + recommended_ta + log_path + description + daily_volume_low_mb + daily_volume_high_mb`

Plus a `transforms.conf` update to enable wildcard matching on `odin_classify_packages` (D3).

Goal: every piloted Windows host (PROD-02) classifies to at least one `host_role` in the host inventory and produces at least one `recommended_tas` row in the deployment matrix. No code changes, no schema changes, no Linux row modifications.

</domain>

<decisions>
## Implementation Decisions

### D1 — Role naming: cross-platform reuse (no `windows_` prefix)

Windows signals map to **existing** `host_role` values where the role is semantically the same as Linux. No `windows_iis`, no `windows_dc`, no `windows_dns`. Cross-platform OS filtering is done via `os=windows` in SPL, not by splitting roles.

**Examples of mappings:**
- IIS (W3SVC) → `web_server`
- DNS (DNS service / 53/tcp+udp) → `dns_server`
- DHCP (DHCPServer) → `dhcp_server`
- File server (LanmanServer + 445/tcp) → `file_server`
- SQL Server (MSSQLSERVER) → `database_server`
- Exchange (MSExchangeIS, MSExchangeTransport) → `mail_server`
- Print Server (Spooler + 9100/tcp) → `print_server`
- Generic member server → `windows_host` (already exists in lookup)
- Generic workstation → `windows_host` (same; differentiated by absence of server signals)

**Exception (Windows-only roles where no Linux analog exists):**
- Domain Controller → `domain_controller` (already exists; Windows AD-specific)
- ADFS → use `identity_server` (existing)
- ADCS → use `certificate_server` (existing)
- Hyper-V → use `virtualization_host` (existing)
- RDS / Terminal Server → use `rdp_server` (existing)
- WSUS → use `management_server` (existing)
- SCCM/MECM → use `management_server` (existing)
- DFS → use `file_server` (re-uses existing role; Sysmon/file-share angle)
- WDS → use `management_server` (deployment infrastructure)
- Failover Cluster → use `ha_cluster` (existing)
- NPS / RADIUS → use `identity_server` (existing)

**Rationale:** TA deployment matrix already groups by `host_role`. SREs see "10 web_servers — 7 need Splunk_TA_nginx, 3 need Splunk_TA_microsoft-iis" in one row, which is more useful than two separate `web_server` and `windows_iis` rows. SPL filtering on `os=windows` is cheap when needed.

### D2 — Coverage depth: extended Windows role set (20 roles)

**Minimum 10 Windows roles** (must-have for any enterprise pilot):
1. Domain Controller — services: NTDS, ADWS, KDC, Netlogon; ports: 88/tcp+udp, 389/tcp, 636/tcp, 3268/tcp, 3269/tcp; packages: `Active Directory Domain Services*`
2. IIS Web Server — services: W3SVC, WAS; ports: 80/tcp, 443/tcp; packages: `Internet Information Services*`, `IIS *`
3. SQL Server — services: MSSQLSERVER, SQLSERVERAGENT, SQLBrowser; ports: 1433/tcp, 1434/udp; packages: `Microsoft SQL Server *(64-bit)*`
4. Exchange Server — services: MSExchangeIS, MSExchangeTransport, MSExchangeServiceHost; ports: 25/tcp, 587/tcp, 993/tcp, 995/tcp; packages: `Microsoft Exchange Server*`
5. DNS Server — services: DNS; ports: 53/tcp+udp
6. DHCP Server — services: DHCPServer; ports: 67/udp, 68/udp
7. File Server — services: LanmanServer; ports: 445/tcp, 139/tcp; baseline `Splunk_TA_windows` (SMB share access via Security log)
8. Print Server — services: Spooler; ports: 9100/tcp, 515/tcp
9. Generic member server — services: WinRM, RemoteRegistry; ports: 5985/tcp, 5986/tcp, 3389/tcp; packages: `Windows Server*`
10. Generic workstation — packages: `Windows 10*`, `Windows 11*`; absence of server services

**Extended +10 Windows roles** (also in scope this phase):
11. Hyper-V — services: vmms, vmcompute; packages: `Hyper-V*`
12. ADFS — services: adfssrv; packages: `Active Directory Federation Services*`
13. RDS / Terminal Server — services: TermService, SessionBroker; ports: 3389/tcp
14. SCCM / MECM — services: CcmExec, SMS_EXECUTIVE; packages: `Configuration Manager*`, `System Center*`
15. WSUS — services: WsusService; packages: `Windows Server Update Services*`
16. ADCS / Certificate Authority — services: CertSvc; packages: `Active Directory Certificate Services*`
17. NPS / RADIUS — services: IAS; ports: 1812/udp, 1813/udp
18. DFS / DFS-R — services: Dfs, DFSR
19. WDS — services: WDSServer; ports: 4011/udp, 67/udp
20. Failover Cluster — services: ClusSvc

**Rationale:** PROD-02 pilot will land on real enterprise hosts; minimum-set leaves obvious gaps (e.g., a piloted Hyper-V host or ADFS server would classify as `windows_host` only). Extended set ensures ~95% coverage of typical Windows server roles in a Splunk-onboarded fleet.

### D3 — Package pattern format: wildcard-matching with precise prefix patterns

**Patterns use glob wildcards** rather than exact strings or regex:
- `Microsoft SQL Server *(64-bit)*` — matches the SQL Server engine across versions, excludes Management Studio
- `Microsoft SQL Server Management Studio*` — separate row, different role
- `Microsoft Exchange Server*` — matches all editions/years
- `Microsoft .NET Framework*` — single row covers 4.x patches
- `Active Directory Domain Services*` — DC role
- `Internet Information Services*` and `IIS *` — both patterns to handle Windows version differences

**Mandatory transforms.conf change:** Add `match_type = WILDCARD(package_pattern)` to the `odin_classify_packages` lookup-stanza in `ODIN_app_for_splunk/default/transforms.conf`. Without this, Splunk does exact-match on the pattern column and the wildcards are taken literally.

**Acceptance:** A simulated Windows event with `package_name="Microsoft SQL Server 2019 (64-bit)"` matches the row pattern `Microsoft SQL Server *(64-bit)*` after the transforms.conf change. Existing Linux exact-match patterns (`nginx`, `mysql-server`) continue to work because Splunk WILDCARD match still treats a pattern with no wildcard chars as an exact match.

### D4 — Windows Event Log channel representation in `log_path`: hybrid

**`log_path` column convention** (mirrors Linux convention of "directly copyable into inputs.conf"):

- **File-based Windows logs** → real file path with wildcards
  - IIS access logs: `C:\inetpub\logs\LogFiles\W3SVC*\u_ex*.log`
  - IIS HTTPERR logs: `C:\Windows\System32\LogFiles\HTTPERR\httperr*.log`
  - Sysmon archive logs (where shipped to file): file path
- **Event Log channels** → Splunk inputs.conf stanza syntax
  - Security: `WinEventLog://Security`
  - Application: `WinEventLog://Application`
  - System: `WinEventLog://System`
  - Sysmon: `WinEventLog://Microsoft-Windows-Sysmon/Operational`
  - PowerShell: `WinEventLog://Microsoft-Windows-PowerShell/Operational`
  - DNS Debug: `WinEventLog://Microsoft-Windows-DNSServer/Audit` and `/Analytical`
  - DHCP: `WinEventLog://Microsoft-Windows-Dhcp-Server/Operational`
  - DFS-R: `WinEventLog://DFS Replication`
- **DNS Debug log file** (legacy DNS debugging): `C:\Windows\System32\dns\dns.log`

**Rationale:** A Splunk admin reading the deployment matrix can copy the `log_path` value directly into a `Splunk_TA_windows` `inputs.conf` stanza without translation. Mental model is identical to the Linux side ("here's the path the input goes against").

### D5 — Recommended TA: hybrid (canonical TAs + baseline fallback with description marker)

**Three-tier `recommended_ta` strategy:**

1. **Canonical Splunkbase TA exists** — use it directly:
   - IIS → `Splunk_TA_microsoft-iis`
   - SQL Server → `Splunk_TA_microsoft-sqlserver`
   - Exchange → `Splunk_TA_exchange` (or `Splunk_TA_microsoft_exchange` depending on Splunkbase canonical id; planner verifies)
   - Sysmon → `TA-microsoft-sysmon`
   - Active Directory → `Splunk_TA_microsoft_ad` + `Splunk_TA_windows`
2. **No dedicated TA, but Windows baseline TA covers the channel** — use `Splunk_TA_windows` and mark in description:
   - ADFS, WSUS, Print Server, WDS, NPS, DFS, ADCS, Failover Cluster
   - description prefix: `"[baseline only — no dedicated Splunkbase TA]"` followed by what the baseline captures
3. **Generic Windows host with no role-specific signals** — `Splunk_TA_windows` with description `"baseline Windows host monitoring"`

**Rationale:** PROD-02 pilot needs every piloted host to surface in the deployment matrix. Empty `recommended_tas` cells make a host look like "we don't know what to do here" instead of "baseline coverage is enough". Description marker keeps honesty about what's canonical vs baseline-only.

### Daily volume estimates (`daily_volume_low_mb`, `daily_volume_high_mb`)

Apply existing pattern from Linux rows. For Windows roles use realistic enterprise estimates:

- Security log (DC): 500–5000 MB/day depending on audit policy
- Security log (member server): 50–500 MB/day
- Sysmon: 200–2000 MB/day (depends on event filter aggressiveness)
- IIS access log: 50–2000 MB/day depending on traffic
- Exchange transport log: 100–1000 MB/day
- DHCP log: 5–100 MB/day
- DNS audit/analytical: 50–500 MB/day
- Generic Application/System: 5–50 MB/day baseline
- PowerShell: 10–200 MB/day (depends on script-block logging policy)

These are not load-bearing for the planner — they're informational fields that help SREs size indexer capacity. Planner can use these defaults or refine per row.

### Claude's Discretion

- Exact wording of `description` columns (within the conventions set by D5)
- Order of rows within each CSV (alphabetic vs grouped by role — planner picks)
- Whether to add separate rows for x86 / Wow6432Node variants of the same package (planner decides; Wow6432 detection is incidental — same display name typically)
- Whether to combine signals (e.g., one row per host_role) or split by signal_type/value (one row per service/port/package). Existing Linux rows split by signal — planner should follow that convention.
- Internal sourcetype values: use Splunk standard sourcetypes where they exist (`MSAD:NT6:DNS`, `WinEventLog:Security`), planner verifies via Splunkbase TA documentation

## Locked downstream contract

Researcher and planner will produce content that satisfies:

1. **CSV diffs only** — no `.sh`, `.ps1`, or `.conf` changes EXCEPT one transforms.conf edit for D3 (`match_type = WILDCARD(package_pattern)` on `odin_classify_packages`).
2. **Linux rows untouched** — every existing row in all 4 CSVs is preserved byte-for-byte (the planner can reorder rows but cannot delete or modify Linux rows).
3. **Cross-platform `host_role` values** per D1 — no Windows-prefixed roles introduced in this phase.
4. **WILDCARD-compatible package patterns** per D3 — but Linux exact patterns remain valid because no-wildcard strings still exact-match under WILDCARD mode.
5. **Hybrid log_path + recommended_ta** per D4 and D5 — no empty `recommended_tas` cells; baseline marker present where applicable.
6. **AppInspect compliance preserved** — adding rows to lookup CSVs and adding `match_type` to a transforms-stanza are AppInspect-safe under Enterprise scope (`--excluded-tags cloud`); planner must include a verification task that re-runs `splunk-appinspect inspect ODIN_app_for_splunk --mode precert --excluded-tags cloud` and asserts `failure + error == 0`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing lookup state and conventions
- `ODIN_app_for_splunk/lookups/odin_classify_services.csv` — 332 Linux rows; column schema `service_pattern,category,subcategory,vendor,role,description`
- `ODIN_app_for_splunk/lookups/odin_classify_ports.csv` — 206 Linux rows; column schema `port,transport,expected_service,category,description`
- `ODIN_app_for_splunk/lookups/odin_classify_packages.csv` — 274 Linux rows; column schema `package_pattern,category,vendor,role,description`
- `ODIN_app_for_splunk/lookups/odin_log_sources.csv` — 274 Linux rows; column schema `signal_type,signal_value,host_role,log_source,sourcetype,recommended_ta,log_path,description,daily_volume_low_mb,daily_volume_high_mb`

### Existing host_role taxonomy (55 unique values, reuse where applicable per D1)
- Full list extracted at scout time: `awk -F, 'NR>1 {print $3}' ODIN_app_for_splunk/lookups/odin_log_sources.csv | sort -u`
- Re-uses for Windows: `web_server`, `dns_server`, `dhcp_server`, `file_server`, `database_server`, `mail_server`, `print_server`, `domain_controller`, `identity_server`, `certificate_server`, `virtualization_host`, `rdp_server`, `management_server`, `ha_cluster`, `windows_host`, `windows_management`

### Splunk transforms.conf — wildcard lookup syntax
- `ODIN_app_for_splunk/default/transforms.conf` — current lookup-stanza for `odin_classify_packages` needs `match_type = WILDCARD(package_pattern)` added per D3
- Splunk docs: lookup `match_type` semantics — wildcards in the column value are treated as glob; rows with no wildcard remain exact-match

### AppInspect baseline (must not regress)
- `.planning/artifacts/appinspect/odin-app-final.json` — current state: failure=0, error=0, warning=0, success=14, na=7 under Enterprise scope
- Phase 4 acceptance includes re-running AppInspect after CSV/transforms changes and asserting same clean state

### Project conventions
- `CLAUDE.md` — two-app split (lookups belong in `ODIN_app_for_splunk`, never in `TA-ODIN`), AppInspect Enterprise scope (`--excluded-tags cloud`), output format frozen
- `.planning/REQUIREMENTS.md` PROD-01 section — acceptance criterion is "a simulated Windows host classifies to a non-empty set of roles and produces a non-empty TA deployment matrix row"

</canonical_refs>

<specifics>
## Specific Ideas

### Test fixture for verification
- Create or reuse `tools/tests/windows-fixtures/hostA` to feed a synthetic Windows host through the classification lookups and assert non-empty `host_roles` + non-empty `recommended_tas` (PROD-01 acceptance criterion 5 in ROADMAP §Phase 4).
- The fixture should include realistic signals across at least 3 of the 20 Windows roles (e.g., DC + IIS + SQL on a single host that masquerades as multiple roles, OR three separate fixtures).

### Wildcard transforms.conf snippet
Expected addition to `ODIN_app_for_splunk/default/transforms.conf`:
```
[odin_classify_packages]
filename = odin_classify_packages.csv
match_type = WILDCARD(package_pattern)
```
(Existing stanza already has `filename = ...` — only the `match_type` line is new.)

### Row-count growth targets (from ROADMAP §Phase 4 success criteria)
- `odin_classify_services.csv`: ≥ +20 Windows service rows
- `odin_classify_ports.csv`: ≥ +15 Windows port rows including the canonical Windows port set
- `odin_classify_packages.csv`: ≥ +30 Windows registry display name rows
- `odin_log_sources.csv`: ≥ +15 new rows with Windows host_roles + filled log_source/sourcetype/recommended_ta

</specifics>

<deferred>
## Deferred Ideas

- **Live Windows-host empirical sampling** — pulling actual registry display names from a real Windows Server lab to refine wildcard patterns. Out of scope for Phase 4 (no Windows host available); left to PROD-02 pilot to surface any real-world patterns we missed.
- **CIS-benchmark-derived audit policy → Security event volume mapping** — could refine `daily_volume_*_mb` estimates per audit policy level. Out of scope for v1.0.1; current estimates are ranges and operationally adequate.
- **Group Policy / Intune-deployed package detection** — apps deployed via GPO sometimes have inconsistent Uninstall-key entries. Out of scope; baseline registry scan is enough for v1.0.1.
- **Windows kernel driver classification** — driver enumeration would be a new module, not a classification lookup row. Out of scope; tracked in v1.1+ backlog if needed.
- **Sysmon config-aware event volume** — if a fleet uses Olaf Hartong's modular config vs. SwiftOnSecurity vs. default, volumes differ by 10x. Out of scope; one range estimate is fine for v1.0.1.

</deferred>

---

*Phase: 04-windows-classification-data*
*Context gathered: 2026-04-17 via /gsd-discuss-phase 4*
