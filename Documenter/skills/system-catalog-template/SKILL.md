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

| topic / queue | message type | producers | consumers | delivery | notes |
|---|---|---|---|---|---|
| `orders.placed.v1` | `OrderPlaced` | orders-api | payments-api, fulfilment-worker | at-least-once | |
| `payments.completed.v1` | `PaymentCompleted` | payments-api | notifications, reporting | guaranteed | correlation: orderId |
| `payments.failed.v1` | `PaymentFailed` | payments-api | — | guaranteed | **orphan: no consumer** |

Rules:
- Normalize names exactly as they appear in code (including version suffix) so producer and
  consumer rows merge. If two services spell a topic differently, flag it — it's a bug or a
  naming-convention gap.
- Mark **orphans** explicitly (`— ` in producers/consumers + a `**orphan**` note). Orphans
  are the highest-signal finding the registry produces.
- Distinguish **topic** (pub/sub, fan-out) from **queue** (point-to-point) in the notes if
  the distinction matters for the messaging model in use.

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

## Consistency checks (run while building)
- Every `service_id` referenced in a matrix/registry row exists in `_service-catalog.md`.
- Every topic in a service doc's messaging table appears in `_message-registry.md`.
- Producer/consumer counts in the registry match the per-service messaging tables.
- No glossary term is defined twice with different definitions.
