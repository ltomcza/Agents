---
name: doc-maintenance
description: "How to keep an existing set of service docs alive as the code changes — detect which docs are stale by comparing each doc's source_commit against the current repo state, scope an incremental re-documentation run to only the affected services and aggregates, and restamp source_commit/last_updated. Apply when re-running the documentation team over a system that was documented before, instead of regenerating everything from scratch."
---

The first documentation run is the easy one. The hard problem for a large system is **drift**:
code moves, docs don't, and a confidently-wrong doc poisons retrieval worse than no doc. This
skill defines how to refresh an existing doc set cheaply — touch only what changed, and prove
the rest is still current rather than blindly regenerating.

The two frontmatter fields that exist for exactly this purpose: every per-service doc carries
`source_commit` (the SHA it was generated from) and `last_updated`. Maintenance is the loop
that keeps them meaningful.

## Step 1 — find the drifted services

For each per-service doc, compare its `source_commit` to the current `HEAD`, scoped to that
service's `repo_path` (also in frontmatter):

```
git diff --name-only <doc.source_commit>..HEAD -- <repo_path>
```

- **No files changed** → the doc is still current. Restamp nothing; optionally bump
  `last_updated` only if you re-verified it. Do **not** rewrite an unchanged doc.
- **Files changed** → the service is *drifted*; it needs a targeted re-analysis (below). Note
  *which* files changed — it tells you which sections are at risk.

A service whose `repo_path` no longer exists is a **removed service**: mark its doc
`> Stale: source path no longer exists` and flag it for deletion + removal from the aggregates;
don't silently drop it.

## Step 2 — classify the change (which sections are at risk)

Map changed files to the doc sections they threaten, so the re-run is surgical, not total:

| changed | at-risk sections | who re-runs |
|---|---|---|
| controllers / Minimal API / Refit ifaces | Public interface, Data flow, `_http-call-matrix.md` | service-analyzer + integration-mapper |
| publisher/consumer/handler code, topic constants/config | Messaging interface, Data flow, `_message-registry.md`, `_process-flows.md` | integration-mapper + flow-mapper |
| `Program.cs` / DI / `appsettings*` | Architecture, Configuration, Dependencies, `_cross-cutting.md` | service-analyzer |
| handlers / domain / EF mappings | Architecture (component diagram), Domain model | service-analyzer |
| only tests / comments / formatting | none — restamp `source_commit`, no content change | — |

A change that touches only test or generated files (`*.g.cs`, `obj/`) is not a documentation
change — restamp and move on.

## Step 3 — re-run only the affected stages

Drive the same pipeline as a fresh run, but scoped:
1. Re-run **only the analysis stages flagged in Step 2** for each drifted service (not the whole
   team, not the whole system).
2. Re-run **business-context-writer / decisions** only if business input or a structural choice
   actually changed — business context rarely drifts with code; don't churn it.
3. Re-assemble the affected per-service docs (`service-doc-writer`), preserving existing
   `> Input needed` / `unresolved` markers unless the change resolves them.
4. **Cascade to aggregates that reference a changed fact only.** If messaging changed, refresh
   `_message-registry.md`, `_process-flows.md`, `_system-dataflow.md`; if HTTP changed, refresh
   `_http-call-matrix.md`. If nothing cross-service changed, the aggregates stand.
5. Re-run **doc-reviewer** on the touched docs + any aggregate it cascaded into.

## Step 4 — restamp

On every doc you regenerated:
- set `source_commit` to the current `HEAD` SHA,
- set `last_updated` to today,
- bump `doc_version` only on a *material* content change (new endpoint, new topic, changed
  flow), not on a restamp.

Aggregates carry only `last_updated`; bump it when their content changed.

## What a maintenance run reports

```
drift scan: <N services checked, M drifted, K removed>
refreshed:
- <service_id>: sections <list> (commit <old>→<new>)
aggregates refreshed: <list> / unchanged: <list>
removed (flag for deletion): <service_id …>
still current (restamped only): <service_id …>
open: <markers still unresolved>
```

## Cautions
- **Don't regenerate the whole system to fix one service.** The cost and the diff noise hide
  the real change and risk re-introducing resolved gaps.
- **Don't restamp `source_commit` without re-verifying** — a fresh SHA on a stale body is a lie
  that defeats the entire staleness signal.
- **Preserve human-supplied content.** Business context, decisions, and gap markers are not
  re-derivable from code; carry them forward verbatim unless the input itself changed.
