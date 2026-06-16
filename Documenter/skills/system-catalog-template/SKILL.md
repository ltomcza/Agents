---
name: system-catalog-template
description: "Schemas for the system-level aggregate documents that sit alongside per-service docs in the RAG store — the service catalog, Solace topic/queue registry, HTTP call matrix, glossary, and stitched system data-flow graph. Apply when building or refreshing the cross-service index after individual service docs are written, or when answering 'who produces/consumes topic X' and 'who calls service Y.'"
---

Per-service docs answer "what does this service do." The aggregate docs answer "how do the
services fit together" — the questions a human onboarding or an agent planning a multi-service
task actually asks. These files are regenerated from the set of per-service docs; never
hand-maintain a fact that already lives in a service doc, derive it.

All aggregate files are prefixed with `_` so they sort to the top and are easy to exclude
from per-service retrieval filters. Each still carries frontmatter for RAG.

## The aggregate set (what each `_` doc answers)

| file | answers | built by |
|---|---|---|
| `_system-context.md` | Who/what is outside the system? (users, external systems, boundary — C4 L1) | flow-mapper |
| `_service-catalog.md` | What services exist and what does each own? | system-cataloger |
| `_message-registry.md` | If I publish/consume topic X, who produces/reacts? | system-cataloger |
| `_http-call-matrix.md` | Who calls service Y over HTTP? | system-cataloger |
| `_process-flows.md` | How does business process Z run end-to-end across services (incl. failure)? | flow-mapper |
| `_cross-cutting.md` | What conventions hold system-wide (auth, tracing, resilience, naming)? | system-cataloger |
| `_decisions.md` | Why is the architecture this way? (ADRs) | business-context-writer |
| `_glossary.md` | What does domain term T mean and who owns it? | business-context-writer / system-cataloger |
| `_system-dataflow.md` | Show me the whole graph (services, stores, brokers, edges). | system-cataloger |

`_system-context.md` and `_process-flows.md` use the conventions in the
`system-context-and-flows` skill; the rest are defined below.

## `_service-catalog.md` — the map

```yaml
---
doc_id: service-catalog
type: catalog
last_updated: 2026-06-15
---
```

One row per service. The fast index a reader scans first.

| service_id | domain | type | core responsibility | doc |
|---|---|---|---|---|
| payments-api | payments | http-api | System of record for fund transfers | [doc](payments-api.md) |
| orders-api | orders | http-api | Owns order lifecycle | [doc](orders-api.md) |

## `_message-registry.md` — the Solace data-flow backbone

The most important aggregate doc. One row per **topic/queue**, reconciled across every
service's messaging interface so producers and consumers line up. This is what answers "if I
publish X, who reacts?" and reveals orphans (a topic with a producer but no consumer, or
vice versa).

```yaml
---
doc_id: message-registry
type: registry
last_updated: 2026-06-15
---
```

The columns follow the **AsyncAPI** vocabulary (the OpenAPI of event-driven systems) so the
registry reads like a contract: the topic/queue is the *channel*, publish/consume are
*operations*, the message type carries a *schema*, and `correlationId` is the saga join key.
This is a structuring convention only — keep it Markdown; do not emit a separate `.yaml` spec.

| channel (topic / queue) | kind | message type | producers | consumers | delivery | correlationId | DLQ / retry | notes |
|---|---|---|---|---|---|---|---|---|
| `orders.placed.v1` | topic | `OrderPlaced` | orders-api | payments-api, fulfilment-worker | at-least-once | `orderId` | `orders.placed.dlq` | |
| `payments.completed.v1` | topic | `PaymentCompleted` | payments-api | notifications, reporting | guaranteed | `orderId` | — | |
| `payments.failed.v1` | topic | `PaymentFailed` | payments-api | — | guaranteed | `orderId` | — | **orphan: no consumer** |

The **message schema** (fields + types) lives once in the producing service's doc (Public
interface → messaging); link to it rather than repeating it here.

Rules:
- Normalize channel names exactly as they appear in code (including version suffix) so producer
  and consumer rows merge. If two services spell a topic differently, flag it — it's a bug or a
  naming-convention gap.
- Mark **orphans** explicitly (`— ` in producers/consumers + a `**orphan**` note). Orphans
  are the highest-signal finding the registry produces.
- **`kind`** distinguishes **topic** (pub/sub, fan-out) from **queue** (point-to-point).
- **`correlationId`** is the message property that ties a publish to the saga it belongs to;
  it is the key `_process-flows.md` uses to stitch a flow across services. Record `unknown`
  if not statically discoverable.
- **`DLQ / retry`** records the dead-letter destination or retry policy when discoverable —
  the failure side of the flow. `—` if none; `unknown` if not visible statically.

## `_http-call-matrix.md` — synchronous dependencies

Directed caller → callee table for HTTP. Complements the message registry (async). Together
they are the complete data-flow picture.

```yaml
---
doc_id: http-call-matrix
type: matrix
last_updated: 2026-06-15
---
```

| caller | callee | endpoint(s) | purpose |
|---|---|---|---|
| orders-api | payments-api | POST `/v1/transfers` | record payment on checkout |
| payments-api | fx-service | GET `/v1/rates/{pair}` | convert currency before ledger write |

Resolve each outbound `HttpClient`/`BaseAddress`/config URL to a **callee `service_id`** when
possible. If a callee is external (third party, no service doc), name it and mark it
`external`.

## `_glossary.md` — domain terms

```yaml
---
doc_id: glossary
type: glossary
last_updated: 2026-06-15
---
```

Alphabetical. Each term: definition + the owning service. Service docs link terms here.

| term | definition | owned by |
|---|---|---|
| Idempotency Key | Client-supplied key that dedupes repeated transfer requests | payments-api |
| Ledger Entry | Immutable record of a balance change | payments-api |

## `_system-dataflow.md` — the stitched graph

A single system-wide Mermaid `flowchart` stitched from the per-service flows: nodes are
services + brokers/DBs, edges are HTTP calls (solid) and message flows (dashed, labelled with
the topic). Keep it readable — if the system has >~15 services, produce one graph per domain
instead of one mega-graph, and link them from here.

```mermaid
flowchart LR
  orders[Orders API] -->|POST /v1/transfers| payments[Payments API]
  orders -.orders.placed.v1.-> payments
  payments -.payments.completed.v1.-> notifications[Notifications]
  payments -->|GET /v1/rates| fx[FX Service]
```

Edge convention: **solid** = synchronous HTTP, **dashed** = async message (label = topic).

## `_system-context.md` — the C4 L1 boundary

The view the other aggregates skip: who is *outside* the system. Built by `flow-mapper`;
full conventions (the context diagram, actor table) live in the `system-context-and-flows`
skill. Frontmatter:

```yaml
---
doc_id: system-context
type: context
last_updated: 2026-06-15
---
```

Carries: a one-paragraph system purpose, an **actors/external-systems table** (who/what,
kind = person|external-system, interaction, entry service), and one C4-lite **Context
diagram** (the system as a single box, surrounded by actors and external systems). Where the
set of human actors needs business input, it carries a `> Input needed: …` marker.

## `_process-flows.md` — end-to-end business processes (the saga view)

The single most valuable doc for "how does the system actually work." Built by `flow-mapper`
by stitching per-service flow tables on the `correlationId`; full conventions (the system flow
table with its compensation/outcome column, the cross-service sequence diagram,
choreography-vs-orchestration) live in `system-context-and-flows`. Frontmatter:

```yaml
---
doc_id: process-flows
type: process-flows
last_updated: 2026-06-15
---
```

One section per business process (e.g. *Order-to-Cash*), each with the happy path **and** the
failure/compensation path. Process *names* come from supplied business input (gap-marked if
missing); process *steps* are derived from the per-service flow tables.

## `_cross-cutting.md` — system-wide conventions

The conventions every service shares, reconciled into one place so an agent learns them once
instead of re-deriving them per service (arc42 "crosscutting concepts"). Built by
`system-cataloger` from the per-service docs.

```yaml
---
doc_id: cross-cutting
type: cross-cutting
last_updated: 2026-06-15
---
```

One H2 per concern; each states the **convention** and links the services that follow (or
deviate from) it. Cover at least:

| concern | what to capture |
|---|---|
| Authentication / authorization | scheme(s) (Bearer/JWT, mTLS), where tokens come from, how scopes/policies map to endpoints |
| Correlation & tracing | the correlation/trace header (`traceparent`, `X-Correlation-Id`), how it propagates across HTTP and messages |
| Idempotency | the `Idempotency-Key` convention, which operations dedupe, how |
| Resilience | the standard retry/timeout/circuit-breaker policy (Polly), DLQ convention |
| Error contract | the shared HTTP error shape (`ProblemDetails`), the failure-event convention |
| Topic naming & versioning | the `<domain>.<object>.<action>.vN` convention, how breaking changes bump the suffix |
| Configuration & secrets | how config sections / connection strings / secrets are named and sourced |

Deviations are findings — list a service that breaks a convention rather than smoothing it over.

## `_decisions.md` — architecture decisions (ADRs)

The architectural **why** that code can't reveal — the counterpart to business context. Built
by `business-context-writer` from **supplied** decision input; it is never invented. When the
rationale for a visible choice isn't supplied, the entry carries a `> Input needed: …` marker.

```yaml
---
doc_id: decisions
type: decisions
last_updated: 2026-06-15
---
```

One lightweight ADR per decision, newest first:

```markdown
### ADR-003 — Transactional outbox for publish durability
- **Status:** accepted
- **Context:** A DB write and a Solace publish must not diverge if the process crashes between them.
- **Decision:** Write an outbox row in the same `SaveChangesAsync`; a worker drains and publishes.
- **Consequences:** At-least-once delivery (consumers must dedupe); one extra table + worker per producer.
- **Affects:** payments-api, orders-api · **Relates to:** `_cross-cutting.md#idempotency`
```

Keep the *what/why* of structural choices (broker choice, service boundaries, outbox, sync vs
async); skip routine library picks. Link each ADR to the services and cross-cutting concerns it
touches.

## Consistency checks (run while building)
- Every `service_id` referenced in a matrix/registry/context/flow row exists in `_service-catalog.md`.
- Every topic in a service doc's messaging table appears in `_message-registry.md`.
- Producer/consumer counts in the registry match the per-service messaging tables.
- No glossary term is defined twice with different definitions.
- Every step in a `_process-flows.md` flow resolves to a real per-service flow-table row (the
  process view never introduces a step the service docs don't have).
- Every `correlationId` a flow stitches on exists in the `_message-registry.md` rows it links.
- Every external system / actor in `_system-context.md` is the source or sink of at least one
  edge in `_http-call-matrix.md` or `_message-registry.md` (no floating actors).
- Each `_cross-cutting.md` convention names the services it covers; deviations are listed, not
  hidden. Each `_decisions.md` ADR links at least one affected service or is gap-marked.
