# Phase 4 — Deferred Items (Out-of-Scope Discoveries)

Items found during plan 04-01 execution that are out of scope per the plan's
SCOPE BOUNDARY rule (only auto-fix issues directly caused by the current task's
changes; pre-existing failures in unrelated content are tracked here, not fixed).

---

## D-04-01 — Pre-existing duplicate (port, transport) keys in odin_classify_ports.csv

**Discovered during:** Plan 04-01 Task 2 verification
**File:** `ODIN_app_for_splunk/lookups/odin_classify_ports.csv`
**Origin commit:** `da1f66e` ("Expand all classification lookups with Windows and additional Linux technologies") — predates v1.0.1 milestone

**Pre-existing duplicate keys** (4 pairs, 8 rows total):

| Port/Transport | Line A | Line B | Difference |
|----------------|--------|--------|------------|
| `1883,tcp` | line 48 — `mqtt,messaging,MQTT messaging` | line 139 — `mqtt,messaging,MQTT messaging` | byte-identical |
| `5000,tcp` | line 67 — `docker-registry,container,Docker registry` | line 148 — `docker-registry,container,Docker registry / Flask dev` | description differs |
| `6660,tcp` | line 82 — `irc,messaging,IRC chat` | line 155 — `irc,messaging,IRC (alt)` | description differs |
| `8000,tcp` | line 86 — `http-alt,web_server,HTTP alternate (common app port)` | line 159 — `http-alt,web_server,HTTP alternate (common)` | description differs |

**Why deferred:** All 4 affected rows are Linux/cross-platform context (MQTT, Docker, IRC, HTTP-alt). The user's plan-execution prompt explicitly forbids modifying or deleting any existing rows: *"DO NOT modify or delete any existing Linux rows in either CSV — only append new Windows rows after the last existing row."* The duplicates predate Phase 4 by many commits and are unrelated to the Windows classification work.

**Impact:** Splunk lookup behavior with duplicate keys is "first match wins" — but for these 4 pairs the first 4 fields are identical, so the search-time enrichment outcome is identical regardless of which row matches. Only the `description` column differs (rows 67/148, 82/155, 86/159), and `description` isn't used by the saved searches that drive the host inventory or TA deployment matrix. Operational impact: nil. Cosmetic impact: lookup audits report duplicate keys.

**Suggested fix (future plan or v1.0.2 cleanup):**
1. Pick the more-descriptive of each pair (lines 148, 155, 86 — though 86 vs 159 is a coin flip).
2. Delete the redundant row.
3. Re-run AppInspect (no impact expected — `check_for_lookups_with_invalid_csv` does not flag duplicate keys, only malformed CSV structure).

**Why this blocks the literal T2 acceptance gate but not the substantive intent:**
The plan's `automated_verify` for Task 2 includes:
```
test $(awk -F, 'NR>1 {print $1","$2}' ... | sort | uniq -d | wc -l) -eq 0
```
This check returns 4 (the pre-existing dupes) regardless of what Plan 04-01 appends. The 18 rows appended by Plan 04-01 introduce ZERO new duplicates — verified explicitly via:
```
git diff -- ... | grep '^+[^+]' | sed 's/^+//' | awk -F, '{print $1","$2}' | sort | uniq -d
```
returns empty.

The plan author drafted the AC against an assumed-clean baseline; the baseline was not in fact clean. The substantive intent ("no new duplicates introduced by Plan 04-01") IS satisfied.

---

## D-04-02 — Pre-existing Windows service rows use legacy roles (D1 violations)

**Discovered during:** Plan 04-01 Task 1 baseline scan
**File:** `ODIN_app_for_splunk/lookups/odin_classify_services.csv`
**Origin commit:** `da1f66e`

**Issue:** ~23 Windows service rows already exist in the CSV from commit `da1f66e`, but they use a legacy role taxonomy that conflicts with CONTEXT.md D1 (the LOCKED cross-platform host_role decision):

| Service | Existing role | D1-mandated role |
|---------|---------------|------------------|
| `W3SVC`, `WAS`, `IISADMIN` | `web` | `web_server` |
| `NTDS`, `Netlogon`, `CertSvc` | `directory` | `domain_controller`, `domain_controller`, `certificate_server` |
| `MSSQLSERVER`, `MSSQL$*`, `SQLSERVERAGENT` | `database` | `database_server` |
| `MSExchangeIS`, `MSExchangeTransport`, `MSExchangeServiceHost` | `mail` | `mail_server` |
| `DNS` | `dns` | `dns_server` |
| `DHCPServer` | `dhcp` | `dhcp_server` |
| `vmms`, `vmcompute` | `virtualization` | `virtualization_host` |
| `TermService`, `SessionEnv` | `infrastructure` | `rdp_server` |
| `WinRM` | `infrastructure` | `windows_management` |
| `Spooler` | `print` | `print_server` |

**Why deferred:** User prompt forbids modifying existing rows. Re-aligning these legacy roles to D1 requires modifications, which the gating rule prohibits. Following the rule literally, the new rows added in Plan 04-01 use the D1-correct taxonomy, while the legacy rows remain with their pre-existing role values.

**Impact:** Search-time `lookup` calls will return `role=web` for `W3SVC` events (from the legacy row that will match first since transforms.conf has `case_sensitive_match = false` and the legacy row appears earlier in the file). Saved searches that aggregate by `host_role` will see two distinct values for IIS hosts depending on which signal matched first: `web` from the service lookup vs. `web_server` from the package lookup or log_sources lookup.

**Suggested fix (future plan):**
A focused cleanup plan in v1.0.1 or v1.0.2 should rewrite the ~23 legacy rows to match D1 and document the change as a Rule 1 fix. AppInspect impact: none (CSV row content changes don't trigger any AppInspect rules). Saved-search regression risk: low (the legacy roles aren't referenced by any current saved search per a `grep -r` of the savedsearches.conf).

**Why this doesn't block Plan 04-01:**
Plan 04-01 acceptance criteria check that NEW rows don't introduce `windows_iis`/`windows_dc`/etc roles (verified: 0 such roles introduced). They do NOT require pre-existing legacy roles to be cleaned up. Plan 04-01's added rows ARE D1-compliant.

---

*Document maintained by the gsd-executor for Phase 4. Append new deferred items below as they are discovered.*
