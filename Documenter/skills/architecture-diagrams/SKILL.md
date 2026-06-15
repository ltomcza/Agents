---
name: architecture-diagrams
description: "How to document a service's static architecture and explain how it works internally — C4-lite Container and Component diagrams in Mermaid, plus the 'how it works' narrative (processing pipeline, concurrency/state, transaction boundaries, error handling, design patterns). Apply when writing the Architecture & how it works section of a service doc. Complements dataflow-diagrams (dynamic behavior) with static structure, at architecture-overview depth."
---

The Architecture section answers "how is this service built and how does it work," where the
Data flow section answers "what happens when a request/message arrives." Architecture is
*static structure*; data flow is *dynamic behavior*. Both use Mermaid; keep them consistent.

Aim for **architecture-overview depth**: enough for an engineer to form a correct mental model
and for an agent to reason about where a change lands — without a class-by-class walkthrough.
Detailed internals rot fast; the structure and the pipeline are stable.

## Two diagrams: C4-lite Container and Component

C4 has four levels (Context, Container, Component, Code). Use the middle two — they carry the
most signal per unit of maintenance. Skip Context (the system catalog + `_system-dataflow.md`
already cover it) and Code (too volatile).

### Container diagram — the service in its surroundings

One box for *this* service, surrounded by the things it talks to: databases, the message
broker (topics/queues), and neighboring services. Built from `integration-mapper`'s edge
graph. Same edge convention as `dataflow-diagrams`: **solid = HTTP**, **dashed = message**.

```mermaid
flowchart LR
    subgraph this[Payments API]
      api[ASP.NET Core service]
    end
    orders[Orders API] -->|POST /v1/transfers| api
    broker(((orders.placed.v1))) -.-> api
    api -->|GET /v1/rates| fx[FX Service]
    api --> db[(Ledger DB)]
    api -.payments.completed.v1.-> notif[Notifications]
```

Shapes: `[Service]` rectangle, `[(Database)]`, `(((topic/queue)))` rounded for broker
destinations. Keep it to direct neighbors only.

### Component diagram — inside the service

The internal modules/layers and how a request or message traverses them. Built from
`service-analyzer`'s internal inventory (layering, handlers, key services, persistence). Show
the layering direction (outer → inner) and the one or two main paths through it.

```mermaid
flowchart TD
    subgraph api[API layer]
      ep[TransfersEndpoint]
    end
    subgraph app[Application layer]
      h[CreateTransferHandler]
      val[ValidationBehavior]
    end
    subgraph dom[Domain]
      svc[TransferService]
    end
    subgraph infra[Infrastructure]
      repo[LedgerRepository]
      pub[PaymentPublisher]
    end
    ep --> val --> h --> svc
    svc --> repo
    svc --> pub
    repo --> db[(Ledger DB)]
    pub -.payments.completed.v1.-> broker(((broker)))
```

Group by layer with `subgraph`. Arrows are call direction. If the service has multiple
distinct entry paths (an HTTP path and a message-consumer path), show both, or split into two
component diagrams if one diagram gets crowded — readability wins.

## The "how it works" narrative

Prose + short lists covering the mechanism. Cover these, skipping any that genuinely don't
apply (say so in one line):

- **Processing pipeline** — the ordered path a request/message takes: middleware → filters →
  endpoint/handler → pipeline behaviors (validation, logging, transactions) → domain →
  persistence/publish. Name the actual types where they matter.
- **Concurrency & state** — is the service stateless per request? Singleton state, caches,
  background loops, `Channel<T>` producer/consumer, `SemaphoreSlim`/locks, parallelism. What
  the caller can assume about ordering and races.
- **Transaction boundaries** — where a unit of work commits (`SaveChangesAsync`,
  `TransactionScope`, `BeginTransaction`), what's atomic, and the outbox/idempotency story if
  a DB write and a publish must agree.
- **Error & retry handling** — exception middleware / `ProblemDetails`, Polly policies,
  message nack/redelivery/DLQ, compensating actions. What a caller observes on failure.
- **Key design patterns** — CQRS/MediatR, repository, outbox, pipeline behaviors, hosted-service
  workers, strategy/factory where they shape the design. Name the pattern, point at the type.

Write it so an agent can answer "if I send X, what path does it take and when is it durable?"

## Consistency with the rest of the doc

- Reuse the **solid=HTTP / dashed=message** edge convention from `dataflow-diagrams`.
- Container-diagram neighbors must match the Dependencies section and the HTTP/messaging
  tables — same `service_id`s, same topic names.
- Component-diagram boxes must be real types/layers from `service-analyzer`'s inventory — no
  aspirational architecture. A reviewer spot-checks that each named component exists in code.
- Keep both diagrams ≤ ~12 nodes. Beyond that, split by concern; a diagram nobody can read
  documents nothing.

## Cautions
- Don't draw what you can't see in code. If the layering is unclear, document the layering you
  *can* verify and flag the rest as `uncertain` rather than inventing a clean architecture.
- Don't duplicate the dynamic flow here — a single representative path is enough to show
  structure; the Data flow section carries the full per-trigger sequences.
- Architecture-overview depth only. If you're naming private methods, you've gone too deep.
