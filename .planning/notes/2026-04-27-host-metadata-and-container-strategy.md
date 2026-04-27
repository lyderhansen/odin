---
title: Host Metadata and Container Observability — Multi-Milestone Strategy
date: 2026-04-27
context: /gsd-explore session conducted while waiting for v1.0.1 PROD-02 pilot infrastructure
related_commits: [f3b1161, 78b259f, 718f76b, 9cb4894, 4b7ef88]
related_seeds: [v1.0.2-host-metadata-enrichment, v1.1.0-container-observability]
---

# Host Metadata and Container Observability — Multi-Milestone Strategy

## TL;DR

The path from v1.0.1 → v1.0.2 → v1.1.0 has been deliberately scoped into three
focused milestones rather than one large "container" milestone, because the
gap discovery during dev-cycle testing revealed that container support depends
on host-metadata foundations that don't exist yet. Each milestone is small,
focused, and additive — no v1.0.1 scope changes, no scope creep.

## How this strategy emerged

### Trigger event

While testing TA-ODIN end-to-end on real hosts on 2026-04-27 (Rocky Linux 9
Docker container + Windows 11 VM), the user observed two gaps:

1. **Containers are not enumerated.** Rocky test produced 175 packages but
   0 `host_role` matches because no application services were running in the
   minimal base image — the container itself was invisible to TA-ODIN.
2. **OS version is never emitted.** Every event has `os=linux` or `os=windows`,
   but never "Rocky 9.3" or "Windows 11 26100.4349". The user noted: "en ting
   jeg føler vi har glemt er å typ liste ut hva slags OS versjon vi kjører på
   i tillegg".

These are unrelated gaps but solving them together creates a coherent
foundation for richer host classification.

### Decision sequence (during /gsd-explore)

**Decision 1 — Scope of OS-version detection (a/b/c):**
- Variant (c) chosen: "Add OS version detection now (v1.0.x quick win) AND
  use it as a building block for v1.1.0 container work."
- Rationale: container images have OS-base identity that mirrors host OS
  identity; the same detection mechanism serves both.

**Decision 2 — Breadth of host info (Variant A/B/C):**
- Variant (B) chosen: "Full host metadata (13 fields) — not just OS version."
- Fields agreed: os_distro, os_version, os_pretty, os_kernel, os_arch,
  cpu_cores, mem_total_mb, uptime_seconds, fqdn, ip_primary, virtualization,
  cloud_provider, cloud_region.
- Rationale: same effort to detect 13 as 5; dashboards become dramatically
  richer; building block for cloud-aware future work.

**Decision 3 — Milestone structuring (Structure 1/2/3):**
- Structure (1) chosen: separate v1.0.2 milestone for host metadata,
  separate v1.1.0 milestone for containers.
- Rationale: matches user's stated principle "ikke ødelegg det vi har laget"
  — small focused milestones over one large milestone with high scope-creep
  risk. v1.0.1's "production readiness" focus stays uncontaminated.

## Resulting roadmap

| Milestone | Theme | Scope | Trigger |
|---|---|---|---|
| **v1.0.1** | Production Readiness | (existing — Phase 4 + Phase 5 done; Phase 6 PROD-02 pilot pending real infra) | Now |
| **v1.0.2** | Host Metadata Enrichment | 13-field `type=odin_host_info` event per scan; updated DATA-DICTIONARY; dashboard panels showing OS distribution | After v1.0.1 tagged (full or RC) |
| **v1.1.0** | Container Observability | Phase 1 (Nivå 2 env detection) + Phase 2 (Nivå 3 containers.{sh,ps1} module) + Phase 3 (container_images lookup + container_inventory saved search) + optional Phase 4 (cloud auto-discovery via IMDS) | After v1.0.2 shipped |

## Why NOT add to v1.0.1

Considered Structure 3 (add as PROD-08 to v1.0.1): rejected because:
- v1.0.1's narrative is "production readiness" (operational ergonomics, runbook,
  rollback, ops dashboard) — host metadata is a discovery/feature improvement,
  different category
- Mid-milestone scope changes invalidate the original UAT-acceptance criteria
- Would delay v1.0.1 release (which is already complete pending pilot infra)
- User has shown strong preference for "ship small, often" over "ship one
  big release"

## Why NOT make v1.1.0 a megamilestone

Considered Structure 2 (one large v1.1.0 with host metadata + containers +
cloud all together): rejected because:
- Three orthogonal feature sets share only "host enrichment" theme
- Long milestones risk scope-creep and never ship
- v1.0.2 (host metadata) provides immediate operational value before container
  work begins; users get value sooner with split structure

## Implementation prerequisites

Both v1.0.2 and v1.1.0 build on existing v1.0.1 architecture:
- Modular orchestrator pattern (`bin/modules/*.sh|.ps1` auto-discovery)
- Signal-based classification (`odin_log_sources.csv` lookup chain)
- Saved-search aggregation (`odin_host_inventory` pattern)
- Cross-platform parity discipline (Linux/Windows orchestrators in lockstep)

No architectural rework needed. v1.0.2 adds one new event type
(`type=odin_host_info`). v1.1.0 adds new modules + new lookup CSV +
new saved searches following the same patterns.

## Risk profile

Both milestones are LOW RISK because:
- All additive (no existing data is modified or removed)
- Schema is multi-row (additions can only enrich, not invalidate, existing
  classifications)
- Existing test infrastructure (HARD-01, PROD-01, PROD-05, windows-parity-harness)
  catches regressions
- AppInspect baseline is stable and easily verifiable

Higher-risk considerations deferred to later:
- Cloud IMDS endpoint probing (network-dependent, may have rate-limiting in
  certain providers — verify before implementing)
- Kubernetes API integration (requires RBAC negotiation in production
  deployments — needs operator coordination)
- Windows containers (separate runtime model from Linux containers — may
  need Phase 5 in v1.1.0 if scope grows)

## See also

- `.planning/seeds/v1.0.2-host-metadata-enrichment.md` — full v1.0.2 scope
- `.planning/seeds/v1.1.0-container-observability.md` — full v1.1.0 scope
- Commit `f3b1161` — Nivå 1 container signals added to existing v1.0.1 lookups
- `.planning/HANDOFF.md` — pre-compact handoff documenting v1.0.1 state
- `.planning/artifacts/manual-tests/` — test outputs from Linux Rocky + Windows 11 dev-cycle
