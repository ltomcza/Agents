---
name: service-doc-template
description: "Canonical schema for a single-service Markdown document destined for a RAG store. Apply when writing or reviewing documentation for one .NET/C# service — defines the required YAML frontmatter, the ordered body sections (summary, business context, role in system, interface, data flow, dependencies, config, agent usage recipes), and a completed mini-example. The single source of truth for 'what a service doc must contain.'"
---

A service document serves two readers at once: a human who needs to understand the
service, and a programming agent that needs to *call* it and know its place in the system.
Every section must pay rent for both. The document is uploaded to a RAG store, so each H2
section must stand alone when retrieved out of context — no "as mentioned above."

One service = one file. Filename is the `service_id` (kebab-case) + `.md`.

## Required frontmatter

```yaml
---
service_id: payments-api          # stable kebab-case id; equals the filename
display_name: Payments API
type: http-api                    # http-api | worker | library | hybrid
domain: payments                  # bounded context / business domain
owner: payments-team
tags: [payments, ledger, solace, http-api]   # capability + tech tags for retrieval filtering
runtime: net8.0
repo_path: src/Payments.Api
doc_version: 1
source_commit: a1b2c3d            # git SHA the doc was generated from
last_updated: 2026-06-15
---
```

Rules:
- `service_id` is stable and deterministic — never rename casually; cross-links depend on it.
- `tags` drive retrieval filtering. Include the domain, the integration tech (`solace`,
  `http-api`, `ef-core`), and the core capability. 3-8 tags.
- `source_commit` + `last_updated` let a reader judge staleness. Always stamp them.

## Body sections (in this order)

Skip a section only if it is genuinely N/A, and say so in one line rather than deleting the
heading — a consistent skeleton makes RAG chunks predictable.

### 1. Summary
2-3 sentences. What the service is and its **single core responsibility**. Lead with the
noun ("Payments API is the system of record for..."), not "This service...". A retrieval
hit on this chunk alone should tell the reader whether they have the right service.

### 2. Business context
The business capabilities it provides, the domain concepts it owns, and where it sits in the
larger business process. Sourced from provided business information — **do not invent**. If
business input is missing, write `> Business input needed: <what>` and move on.

### 3. Role in the system
- **Upstream** (who calls or triggers this service).
- **Downstream** (what this service depends on).
- **Blast radius** — one line: "If this service is down, X stops working."
This section is what lets an agent reason about the service's place before using it.

### 4. Responsibilities & boundaries
Two short lists:
- **Owns / does** — the authoritative responsibilities.
- **Does NOT do** — explicit non-responsibilities and common misconceptions. This prevents
  an agent from calling the wrong service.

### 5. Public interface
How to call it. Be precise enough that an agent can construct a valid request.

**HTTP endpoints** — table, then per-endpoint detail for the important ones:

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/transfers` | Bearer (JWT) | Create a fund transfer |

For each important endpoint: request schema, response schema, status codes, error body
shape, idempotency key behavior, and one concrete example request + response.

**Messaging interface** — what it consumes and publishes. Columns follow the AsyncAPI
vocabulary (channel = topic/queue, operation = consume/publish, `correlationId` = the saga join
key) so the table reconciles cleanly into `_message-registry.md`:

| Direction | Channel (topic / queue) | Message type | Delivery | correlationId | DLQ / retry |
|---|---|---|---|---|---|
| consumes | `orders.placed.v1` | `OrderPlaced` | at-least-once | `orderId` | `orders.placed.dlq` |
| publishes | `payments.completed.v1` | `PaymentCompleted` | guaranteed | `orderId` | — |
| publishes | `payments.failed.v1` | `PaymentFailed` | guaranteed | `orderId` | — |

Include the **message schema** (fields + types) for each *published* message — this is the
single home for that schema; `_message-registry.md` links here rather than repeating it.
Record `correlationId` for every message (the property `_process-flows.md` stitches sagas on)
and the `DLQ / retry` destination where discoverable — they are the failure side of the flow.
A service that publishes a `*.failed.*`/compensation event must list it here.

### 6. Architecture & how it works
The technical "how" — static structure plus internal behavior, at architecture-overview
depth. See the `architecture-diagrams` skill for the exact diagram conventions. Provide:

- **Container diagram** (C4-lite Mermaid) — this service as one box surrounded by its
  databases, the broker, and neighboring services. Edge convention: solid = HTTP, dashed =
  message. Built from the integration graph.
- **Component diagram** (C4-lite Mermaid) — the internal layers/modules (API → application →
  domain → infrastructure) and the main path a request/message takes through them. Boxes must
  be real types/layers from the code.
- **How it works** narrative — the **processing pipeline** (middleware → filters →
  handler/endpoint → pipeline behaviors → domain → persistence/publish), the
  **concurrency/state model**, **transaction boundaries** (where the unit of work commits and
  what's atomic, incl. outbox/idempotency), **error & retry handling** (exception middleware,
  Polly, nack/DLQ), and the **key design patterns** in play. Enough to answer "if I send X,
  what path does it take and when is it durable?" — without a class-by-class walkthrough.

### 7. Data flow
The dynamic view: how inbound triggers become outbound effects. Provide **both** a Mermaid
diagram (for humans) **and** a flow table (for agents). See the `dataflow-diagrams` skill for
the exact format. Minimum: one flow table covering each inbound trigger. (Architecture, above,
is the static structure; this is the per-trigger behavior.)

Cover the **failure path**, not just the happy path: where an inbound trigger can fail (downstream
error, validation reject, payment declined), add the failure/compensation rows (`2f, 3f…`) and
the terminal outcome — what state the service is left in, whether it nacks/DLQs, and which
compensation event it emits. These rows are what `_process-flows.md` stitches into the
system-level saga. If a trigger genuinely has no failure branch, say so in one line.

### 8. Domain model
Key entities / DTOs and where they persist (tables / collections). A compact list, not a
full ERD. Name the entity, its purpose, and its store.

### 9. Dependencies
Every downstream service, database, broker, third-party API, each with a one-line *why*.
Distinguish hard dependencies (service fails without them) from soft ones.

### 10. Configuration
Significant settings / env vars / connection-string **names** (never secret values), feature
flags, with defaults and whether required. Table: key, default, required, purpose.

### 11. Operational notes
Health-check endpoint, key metrics/traces, retry/timeout/back-off, DLQ behavior, and any
**compensation** the service performs or triggers on failure. Note the correlation/trace
header it propagates (link the system-wide convention in `_cross-cutting.md` rather than
restating it). Keep it to what affects a caller's expectations (idempotency, eventual
consistency windows, what they observe when a downstream step fails).

### 12. Agent usage recipes
Task-oriented recipes that make the doc directly actionable:
> **To record a payment for an order:** POST `/v1/transfers` with `{orderId, amount,
> currency}` and an `Idempotency-Key` header. On success the service publishes
> `payments.completed.v1`. Do **not** also publish `OrderPlaced` — that is the Orders
> service's job.

Cover the 2-5 most common things another service/agent would want to do.

### 13. Cross-references
Links to related service docs (by `service_id`) and the system aggregates: the catalog, the
glossary, the `_process-flows.md` processes this service participates in, the
`_cross-cutting.md` conventions it follows, and any `_decisions.md` ADR that explains its
shape. Use the consistent link format from `rag-doc-optimization`.

## Completed mini-example

```markdown
---
service_id: payments-api
display_name: Payments API
type: http-api
domain: payments
owner: payments-team
tags: [payments, ledger, solace, http-api]
runtime: net8.0
repo_path: src/Payments.Api
doc_version: 1
source_commit: a1b2c3d
last_updated: 2026-06-15
---

# Payments API

## Summary
Payments API is the system of record for fund transfers between customer accounts. It
exposes a synchronous HTTP API for initiating transfers and publishes completion events for
downstream reconciliation.

## Business context
Provides the **Record Payment** capability in the Order-to-Cash process. Owns the concepts
*Transfer*, *Ledger Entry*, and *Idempotency Key*. Sits immediately after order placement
and before settlement reporting.

## Role in the system
- **Upstream:** Orders API (HTTP), `orders.placed.v1` consumers.
- **Downstream:** Ledger DB, Notifications service (`payments.completed.v1`).
- **Blast radius:** If down, no new transfers are recorded; order fulfilment stalls at the
  payment step.

## Responsibilities & boundaries
**Owns / does:** validate and record transfers; enforce idempotency; emit completion events.
**Does NOT do:** currency conversion (see `fx-service`), refunds (see `refunds-api`),
customer notifications.

## Public interface
| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | `/v1/transfers` | Bearer (JWT) | Create a fund transfer |

... (request/response schemas, messaging table, etc.)

## Architecture & how it works

Container:
```mermaid
flowchart LR
    orders[Orders API] -->|POST /v1/transfers| payments[Payments API]
    broker(((orders.placed.v1))) -.-> payments
    payments -->|GET /v1/rates| fx[FX Service]
    payments --> ledger[(Ledger DB)]
    payments -.payments.completed.v1.-> notif[Notifications]
```

Component:
```mermaid
flowchart TD
    ep[TransfersEndpoint] --> val[ValidationBehavior] --> h[CreateTransferHandler]
    h --> svc[TransferService]
    svc --> repo[LedgerRepository] --> db[(Ledger DB)]
    svc --> pub[PaymentPublisher] -.payments.completed.v1.-> broker(((broker)))
```

**How it works:** Minimal API endpoint → `ValidationBehavior` (FluentValidation) →
`CreateTransferHandler` (MediatR) → `TransferService` (domain) writes a `LedgerEntry` via
`LedgerRepository` and enqueues an outbox row in **one** `SaveChangesAsync` (atomic). A
`BackgroundService` drains the outbox and publishes `payments.completed.v1`, so the DB write
and the publish never diverge. Idempotency is enforced on the `Idempotency-Key` header
(unique index). Stateless per request; downstream `fx-service` calls use a Polly retry +
circuit breaker. Patterns: CQRS/MediatR, repository, transactional outbox.

## Data flow
... (Mermaid sequence diagram + flow table)

## Agent usage recipes
**To record a payment for an order:** POST `/v1/transfers` with an `Idempotency-Key`. On
success, `payments.completed.v1` is published with `orderId` as the correlation key.

## Cross-references
- [Orders API](orders-api.md) · [Service catalog](_service-catalog.md) · [Glossary](_glossary.md)
- Processes: [Order-to-Cash](_process-flows.md#order-to-cash) · Conventions: [Cross-cutting](_cross-cutting.md) · Decisions: [ADR-003](_decisions.md)
```

## What makes a doc fail review
- Restates code without explaining the business role.
- Architecture section missing, or its component diagram boxes don't exist in the code
  (aspirational architecture instead of the real one).
- Data-flow section with a diagram but no flow table (agents can't parse the diagram reliably).
- Data-flow that documents only the happy path — no failure/compensation rows for a trigger
  that can clearly fail.
- Invents business context not supplied by the user.
- Secret values pasted into configuration.
- Cross-links to `service_id`s that don't exist.
- Sections that say "see above" — breaks when the chunk is retrieved alone.
