# Documenter

A team of agents + skills that turns an existing fleet of **.NET / C# services** (HTTP +
Solace) into **RAG-ready Markdown documentation** for both humans and AI agents. It documents
each service from its implementation plus supplied business information, then stitches the
services into a system view: the C4 context, the cross-service data flow, the end-to-end
process/saga flows, the system-wide conventions, and the architecture decisions.

The output is two layers of Markdown, designed so each section stands alone when retrieved from
a RAG store:

- **Per-service docs** — one `<service_id>.md` per service.
- **Aggregate docs** — the `_`-prefixed system-level docs that tie the services together.

## The doc-set map

| file | answers | produced by |
|---|---|---|
| `<service_id>.md` | What is this service, how do I call it, how does it work, how does data flow through it? | service-doc-writer |
| `_system-context.md` | Who/what is outside the system and who uses it? (C4 L1) | flow-mapper |
| `_service-catalog.md` | What services exist and what does each own? | system-cataloger |
| `_message-registry.md` | If I publish/consume topic X, who produces/reacts? (AsyncAPI-aligned) | system-cataloger |
| `_http-call-matrix.md` | Who calls service Y over HTTP? | system-cataloger |
| `_process-flows.md` | How does business process Z run end-to-end across services, incl. failure? | flow-mapper |
| `_cross-cutting.md` | What conventions hold system-wide (auth, tracing, resilience, naming)? | system-cataloger |
| `_decisions.md` | Why is the architecture this way? (ADRs) | business-context-writer |
| `_glossary.md` | What does domain term T mean and who owns it? | business-context-writer / system-cataloger |
| `_system-dataflow.md` | Show me the whole graph (services, stores, brokers, edges). | system-cataloger |

## The team

| agent | role | reads / writes |
|---|---|---|
| `documentation-orchestrator` | Plans the run, delegates, verifies, integrates. Does not write docs. | read-only + Task |
| `service-analyzer` | Extracts one service's structure + internal architecture from C#. | read-only |
| `integration-mapper` | Builds one service's data-flow graph (HTTP + messaging, correlation, failure edges). | read-only |
| `business-context-writer` | Adds business context, boundaries, glossary, and ADRs from supplied input. | writes docs |
| `service-doc-writer` | Assembles the per-service `.md` from the above. | writes docs |
| `system-cataloger` | Builds the reconciliation aggregates (catalog, registry, matrix, cross-cutting, glossary, graph). | writes `_` docs |
| `flow-mapper` | Builds `_system-context.md` and `_process-flows.md`, stitching flows on the correlation key. | writes `_` docs |
| `doc-reviewer` | Final QA against schema, code, RAG rules, and aggregate integrity. | read-only |

Skills (procedural knowledge the agents apply): `dotnet-service-discovery`,
`http-flow-analysis`, `messaging-flow-analysis`, `architecture-diagrams`, `dataflow-diagrams`,
`system-context-and-flows`, `service-doc-template`, `system-catalog-template`,
`rag-doc-optimization`, `doc-maintenance`.

## Running a documentation campaign

Invoke `documentation-orchestrator` and give it four things:

1. **Scope** — which service(s): one project, a solution, or a named subset.
2. **Source** — the repo/solution path(s) to read.
3. **Business information** — capability descriptions, **process names** (for `_process-flows.md`),
   **human actors** (for `_system-context.md`), and **decision rationale** (for `_decisions.md`).
   None of this is invented; whatever is missing ships as an explicit `> Input needed: …` marker.
4. **Output location** — where the `.md` files go (e.g. `docs/services/`).

The orchestrator then runs, per service: analyze (service-analyzer ∥ integration-mapper) →
business context & decisions → assemble. After all services exist: catalog → system flows &
context → review. It verifies every stage against the code itself rather than trusting the
specialists' self-reports.

**Refreshing later (drift):** if the services were documented before, say so — the orchestrator
follows the `doc-maintenance` skill to re-document only the services whose code changed and only
the aggregates that reference a changed fact, instead of regenerating everything.

## Reading order

- **Human onboarding:** `_system-context.md` → `_service-catalog.md` → `_process-flows.md` →
  the per-service docs for the services you'll touch → `_cross-cutting.md` + `_decisions.md`.
- **AI agent planning a task:** retrieve the per-service doc's *Agent usage recipes* and
  *Public interface*; use `_message-registry.md` / `_http-call-matrix.md` to find producers/
  callees; use `_process-flows.md` to understand the end-to-end flow and its failure path.

## Conventions

These files follow the repo-wide conventions in [`../AGENTS.md`](../AGENTS.md) and
[`../README.md`](../README.md): portable frontmatter (PascalCase `tools`, model alias, `name`
== filename; skill folder == `name`), read-only agents limited to `Read, Grep, Glob`, and no
host-specific fields. The canonical files here are the source of truth; `scripts/sync-to-host.*`
mirrors them into `.claude/` for the host. Out of scope by design: `llms.txt`/JSON/AsyncAPI
*spec* exports (the docs stay Markdown), and protocols beyond HTTP/REST + Solace.
