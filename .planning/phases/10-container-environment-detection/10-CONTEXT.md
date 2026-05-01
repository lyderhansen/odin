# Phase 10: Container Environment Detection — Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Linux + Windows orchestrators enrich the existing `type=odin_host_info` event with 3 new fields when TA-ODIN is running INSIDE a container: `container_runtime`, `container_id`, `container_image_hint`. The 3 fields populate to `none` sentinels on baremetal hosts (per D-03 sentinel discipline). DATA-DICTIONARY.md `## type=odin_host_info` section extended with per-field 4-item structure (Description + Source (Linux) + Source (Windows) + Example) per HOST-04 D-10 convention.

**NOT in this phase:** Container enumeration (`type=container` events) — that's Phase 11. Container classification — that's Phase 12. Cloud asset metadata — that's v1.1.1.

</domain>

<decisions>
## Implementation Decisions

### container_runtime enum (D-11)

5-value enum + 2 sentinels = 7 total possible values:

| Value | When emitted |
|---|---|
| `docker` | Linux: `/proc/self/cgroup` contains `/docker/` token. Windows: detected via Docker Desktop env-vars or `vmcompute` parent process |
| `podman` | Linux: cgroup contains `/libpod-` or `/podman-` token |
| `containerd` | Linux: cgroup contains `/containerd/` (modern k8s direct, non-Docker) |
| `unknown` | Detected SOMETHING (cgroup ≠ `/`, or container env-vars present) but couldn't classify the runtime |
| `none` | Not in a container — D-03 sentinel for "not applicable" |

**Why 5 values, not more:** TA-ODIN targets Linux + Windows endpoints. Docker dominates dev/test (Linux + Windows); podman is RHEL-side standard; containerd is k8s 1.24+ default after dockershim removal. These 3 cover the 99% case. LXC, cri-o, rkt, garden, etc. → `unknown` (filterable in Splunk if needed). Per scope-focus feedback: don't bikeshed runtime taxonomies for cases TA-ODIN won't see.

**Why no `kubepods` (despite seed mentioning it):** Modern k8s pods detect as `containerd` or `cri-o` at the runtime level. The cgroup contains `/kubepods/` PATH but the runtime itself is containerd. Splitting on path-vs-runtime adds confusion — keeping runtime values pure helps Splunk classification.

### container_id parsing strategy (D-12)

**Linux source order** (first-match wins):
1. `/proc/self/cgroup` — extract container ID hash from cgroup-path (canonical Docker/podman pattern)
2. `/proc/1/cpuset` — fallback for older Docker / non-systemd cgroup configs
3. `$DOCKER_CONTAINER_ID` env-var — ultimate fallback if process-tree probing fails

**Format:** First 12-char hex prefix (matches `docker ps`'s short-id convention; shorter than full SHA but still unique within reasonable fleet size).

**Windows source order:**
1. `$env:CONTAINER_ID` — Docker Desktop / Mirantis sets this in container processes
2. `vmcompute` process parent → query Docker socket if accessible (best-effort per D-07 PSCL graceful degradation)
3. `unknown` if both fail

**Why 12-char not full 64-char SHA:** SOC dashboards aggregate by container_id; 12-char is the de-facto industry standard (`docker ps -q` short ID), saves event width, still uniquely identifies within a single host's container fleet. Full SHA adds 52 chars per event with marginal value.

### container_image_hint source (D-13)

**Single source: `/etc/os-release IMAGE_ID` field.**

Some container images (Red Hat UBI, recent Alpine, certain Bitnami images) populate this OS-release field with the image registry path or human-readable identifier. When present, it's a free signal at zero detection cost.

When NOT present (the majority of base images): emit `container_image_hint=none`. SOC analysts who need full image inventory can wait for Phase 11's `type=container` events which include `container_image` field via runtime-API queries.

**Explicitly NOT included as sources** (deferred to Phase 11 or out of scope):
- Docker labels via `/var/run/docker.sock` query → Phase 11 (requires socket access — different threat surface)
- k8s Downward API env-vars → Phase 11 (k8s-specific, doesn't make sense in Phase 10's "inside any container" scope)
- HOSTNAME env-var heuristics → too noisy (HOSTNAME often randomized)

Phase 10 scope is "free signal from filesystem you already have access to" — image_hint is an opportunistic enrichment, not a guarantee.

### Sentinel discipline (carries from D-03)

| State | All 3 fields |
|---|---|
| Not in container (baremetal Linux/Windows) | `container_runtime=none container_id=none container_image_hint=none` |
| In container, runtime classified | `container_runtime=<value> container_id=<12-hex> container_image_hint=<value-or-none>` |
| In container, runtime detection FAILED | `container_runtime=unknown container_id=unknown container_image_hint=none` (entire detection bailed) |

`unknown` MUST NOT mean "not in container" — that's `none`'s job. `unknown` means "we tried and it failed", giving SOC analysts a signal to investigate environmental issues.

### Carries forward from v1.0.2 (NO re-discussion needed)

These decisions from v1.0.2 phases apply directly to Phase 10 implementation. Do not re-litigate:

- **D-01** Helper placement — extend `TA-ODIN/bin/modules/_common.sh` and `TA-ODIN/bin/modules/_common.ps1` with new container-detection helpers (parallel to existing 8 v1.0.2 helpers like `detect_os_distro`, `detect_virt`, `probe_cloud_imds`). Add 1-2 helpers per platform: `detect_container()` returning runtime+id+image_hint as pipe-separated string.

- **D-03** Sentinel discipline — `unknown` for system failure, `none` for "not applicable". Applied above; non-negotiable.

- **D-04 pattern** Closed enum (5 values + 2 sentinels) — mirror of `virtualization` 7-value enum. Same convention: enum values are lowercase identifiers, no spaces, no dynamic values.

- **D-06** CIM only on Windows — for any WMI-style queries, use `Get-CimInstance` not `Get-WmiObject`.

- **D-07** PSCL graceful degradation — Windows container detection MUST work in Constrained Language Mode. If ConstrainedLanguage blocks something (e.g., complex socket-query patterns), fall back to env-var probing + `unknown` sentinel rather than crash.

- **D-10** Per-field DATA-DICTIONARY — each new field gets Description + Source (Linux) + Source (Windows) + Example. Mirror HOST-01..05 entries.

- **PS5.1 lessons learned (v1.0.2 baked-in conventions):**
  - ASCII-only output text (no em-dash, smart quotes, non-ASCII glyphs — PS5.1 reads UTF-8 without BOM as Windows-1252)
  - `[System.IO.Path]::Combine` for n-segment paths (PS5.1 `Join-Path` arity issue)
  - Single-quote literals for static `Write-Output`/`Write-Host` strings with literal brackets
  - `('...{0}' -f $var)` format for dynamic strings with literal brackets

### Claude's Discretion

- Exact regex pattern for cgroup-path container-id extraction (likely `[a-f0-9]{12,64}`)
- Whether to add `container_image_hint` value-trimming (some IMAGE_ID values are very long — cap at ~80 chars?)
- Exact helper-function naming (e.g., `detect_container_runtime` vs `detect_container_env`)
- Test fixture approach: real `docker run rocky:9` vs mock `/proc/1/cgroup` content for unit tests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope + acceptance
- `.planning/REQUIREMENTS.md` § Milestone v1.1.0 — CONT-01, CONT-02, CONT-03 with full acceptance criteria
- `.planning/ROADMAP.md` § Phase 10: Container Environment Detection — 5 success criteria (Linux + Windows + DATA-DICTIONARY + AppInspect)
- `.planning/seeds/v1.1.0-container-observability.md` § Phase 1 — original scope source with effort estimate (4-8h)

### Decision precedent (v1.0.2 carries forward)
- `.planning/phases/07-host-info-linux/07-CONTEXT.md` — D-01 (helper placement), D-03 (sentinel discipline), D-04 (closed-enum pattern); also reference 8-helper structure in `_common.sh`
- `.planning/phases/08-host-info-windows/08-CONTEXT.md` — D-06 (CIM only), D-07 (PSCL graceful degradation); reference 8-helper structure in `_common.ps1`
- `.planning/phases/09-validation-docs-dashboard/09-02-PLAN.md` — D-10 (per-field DATA-DICTIONARY structure with Description + Source (Linux) + Source (Windows) + Example)

### PS5.1 conventions (mandatory for Windows code in this phase)
- Inline header comment block in `tools/tests/check-host-info.ps1` (commit `571e6e7`) — documents the 3 PS5.1 quirks (string convention, Join-Path arity, ASCII-only) discovered during v1.0.2 UAT cycle. Phase 10 Windows module MUST follow these patterns from day 1.

### Implementation reference (existing helpers to extend)
- `TA-ODIN/bin/modules/_common.sh` — 343-line shared bash library; `detect_virt()` helper at end is closest analog (returns 7-value enum, parses /proc + dmidecode); add `detect_container()` following same pattern
- `TA-ODIN/bin/modules/_common.ps1` — 536-line shared PowerShell library; `Get-OdinVirtualization` is closest analog; add `Get-OdinContainer` following same pattern
- `TA-ODIN/bin/odin.sh` line ~99 — `emit_host_info` call site; integrates 13 fields today, will integrate 16 (13 + 3 new) after Phase 10
- `TA-ODIN/bin/odin.ps1` line ~95 — `Invoke-OdinEmitHostInfo` call site; same 13→16 expansion

### Documentation reference (existing structure to mirror)
- `DOCS/DATA-DICTIONARY.md` lines 80-178 — current `## type=odin_host_info` section with 13 fields in per-field 4-item structure. Phase 10 appends 3 more field entries (lines ~178+).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`detect_virt` (Linux _common.sh):** Returns 7-value enum, parses `/proc/1/cgroup` + dmidecode + systemd-detect-virt. The cgroup-parsing logic for the `container` virtualization value can be extracted/adapted for `detect_container()` (need to refine: virt's "container" return has zero granularity about runtime/id; Phase 10 fills that in).

- **`Get-OdinVirtualization` (Windows _common.ps1):** Mirror of detect_virt. Currently returns `vmware|hyperv|baremetal|...` based on Win32_ComputerSystem Manufacturer/Model. Returns `unknown` on PSCL block. New `Get-OdinContainer` follows same defensive structure.

- **`emit_host_info` aggregator (Linux):** Composes the type=odin_host_info event from 8 detection helpers. Phase 10 adds 1 new helper call (or extends existing detect_virt to also return container fields). Choice: add new helper vs extend existing — leaning toward NEW helper for separation of concerns (virt is hypervisor-detection, container is OCI-detection — different contexts).

### Established Patterns

- **Pipe-separated multi-value return:** Helpers like `detect_os_distro` return `distro|version|pretty` from a single function. `detect_container` should return `runtime|id|image_hint` similarly. Aggregator splits on `|`.

- **Idempotency guards:** All v1.0.2 helpers use `if ! declare -f X` pattern (bash) or `if (-not (Get-Command X))` (PS) to allow safe re-sourcing. Phase 10 helpers must follow.

- **`set -u` discipline (bash):** Every variable initialized with `local` declaration before use. Quoted parameter expansion. Phase 10 helpers continue.

- **`$ErrorActionPreference = 'Continue'` discipline (PowerShell):** Phase 10 helpers should swallow non-fatal errors and emit `unknown` sentinel rather than throwing.

### Integration Points

- **`emit_host_info` aggregator** — adds 3 new fields to event line. Field order: append after existing 13 fields (cloud_region) → place 3 new at end. This preserves backward-compat for any downstream parser that's positional (Splunk KV_MODE=auto handles positional changes fine, but tools that grep `field=value` are agnostic).

- **DATA-DICTIONARY.md** — appends 3 new field entries at end of `### Field reference` subsection (after existing `cloud_region`). Cloud-detection-timeout subsection unchanged.

- **No new orchestrator-level changes** — `odin.sh` and `odin.ps1` already invoke `emit_host_info` once. Phase 10 only changes WHAT that function emits, not WHEN/WHETHER it's called.

</code_context>

<deferred>
## Deferred Ideas

### Captured but explicitly Phase 11 scope (NOT this phase)
- Enumerate running containers via docker/podman/kubectl APIs → CONT-04..07
- Per-container detail fields (container_image, container_name, container_command, etc.) → Phase 11

### Captured but explicitly v1.1.1+ scope
- k8s Downward API env-var enrichment (DOWNWARD_API_NAMESPACE, POD_NAME, etc.)
- Container labels → host_role inheritance
- Image registry resolution (image manifest, digest, signed metadata)
- Container resource utilization (CPU/memory) — CNCF metrics-server territory

### Captured but out of scope
- Detection of "is this container PRIVILEGED" (security tooling territory)
- Detection of "is this container ROOTLESS" (could be useful but adds detection complexity)
- Container runtime version detection (e.g., docker engine 24.0 vs 25.0)
- Service mesh sidecar detection (Istio/Linkerd injection patterns)

These ideas surfaced during scope alignment. Recorded here so they're not lost; will be evaluated at v1.2+ planning if user demand emerges.

</deferred>

---

*Phase: 10-container-environment-detection*
*Context gathered: 2026-05-01*
