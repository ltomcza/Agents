---
name: messaging-flow-analysis
description: "Library-agnostic discovery of asynchronous data flow in a .NET service — find where it publishes and consumes Solace topics/queues, the message types, and delivery semantics, without hard-coding a specific client API. Apply when mapping the messaging side of a service's data flow. Detects the project's own publisher/consumer abstractions and topic naming conventions; includes a checklist to adapt to a custom Solace wrapper supplied later."
---

The goal is the async half of the data-flow graph: for each service, the list of topics/queues
it **publishes** to and **consumes** from, with the message type and delivery semantics. This
feeds the per-service messaging table and the system `_message-registry.md`.

Do **not** assume a specific Solace client API. Codebases wrap the broker behind their own
abstractions, and a custom wrapper may be supplied later. Detect the project's *own* seams
first; fall back to known client signatures only if there is no wrapper.

## Step 1 — find the messaging abstraction

Look for the project's publish/consume seam by shape, not by a fixed library name:
```
interface I\w*(Publisher|Producer|Consumer|Subscriber|Handler|MessageBus|EventBus)
class \w*(Publisher|Producer|Consumer|Subscriber|MessageHandler)
Publish|PublishAsync|Send|SendAsync|Subscribe|Consume|HandleAsync|OnMessage
```
Also scan `Program.cs`/DI extensions for registrations like `AddMessaging`, `AddSolace`,
`AddPublisher`, `AddConsumer`, `AddSubscription`, or the custom wrapper's `Add*` method. The
registration usually names the broker connection config section too.

Once you find the seam (e.g. `IMessagePublisher.PublishAsync<T>(string topic, T message)`),
every call site of that method is a flow edge. This is more reliable than chasing the raw
client.

## Step 2 — find publish sites (outbound async)

Search for calls to the publish method(s) identified in step 1:
```
\.Publish|\.PublishAsync|\.Send|\.SendAsync|\.Emit|\.Produce
```
For each call site capture:
- **Topic/queue name** — see Step 4 for how names are expressed.
- **Message type** — the generic argument or the argument's type (`PublishAsync<PaymentCompleted>`).
- **Trigger** — what code path leads here (an HTTP handler? a consumer? a timer?). This links
  the publish to its cause in the flow table.

## Step 3 — find consume/subscribe sites (inbound async)

Search for subscription registration and message handlers:
```
\.Subscribe|\.Consume|AddSubscription|ISubscriber|IMessageHandler|IConsumer<|IHandleMessages<
HandleAsync\(|OnMessageAsync\(|Consume\(.*Context|\[Subscribe|\[Topic|\[Queue
```
A handler class typically declares the message type it handles (`IMessageHandler<OrderPlaced>`
or a `Consume(ConsumeContext<OrderPlaced>)`). Capture:
- **Topic/queue** it subscribes to.
- **Message type** handled.
- **Effect** — what the handler does (writes DB? publishes another message? calls HTTP?).
  This is the inbound trigger for a worker/hybrid service's data flow.

## Step 4 — resolve the topic/queue name

Names hide in several places. Check all:
- **String literals** at the call site: `PublishAsync("payments.completed.v1", msg)`.
- **Constants** / `static class Topics { public const string PaymentCompleted = "..."; }` —
  resolve the constant to its value.
- **Config keys**: `_config["Topics:PaymentCompleted"]` → read `appsettings.json` for the value.
- **Attributes**: `[Topic("orders.placed.v1")]`, `[Queue("...")]` on the handler/message.
- **Conventions**: some wrappers derive the topic from the message type name or a namespace.
  If so, document the convention and compute the effective name.

**Normalize** the resolved name exactly (including version suffix like `.v1`) so the same
topic from a producer and a consumer merges into one registry row.

## Step 5 — delivery semantics

Note what the code/config implies, when discoverable:
- **Topic vs queue** — pub/sub fan-out vs point-to-point.
- **Guaranteed/persistent vs direct/best-effort** — look for `Persistent`, `Guaranteed`,
  `DeliveryMode`, ack/settle calls, or wrapper options.
- **Ordering** / partition / correlation key — often a header or a property on the message.
- **DLQ / retry** — dead-letter queue config, retry policies, `MoveToDeadLetter`, nack/redeliver.

If a property isn't discoverable from static analysis, write `unknown` rather than guessing.

## Adapting to the custom Solace wrapper (when supplied)

When the project's Solace wrapper library lands, do this once and the analysis sharpens:
1. Identify the wrapper's **publish** method signature(s) and add them to Step 2's search set.
2. Identify the **subscribe/handler** registration shape and add to Step 3's set.
3. Identify how the wrapper names topics/queues (param, attribute, convention) for Step 4.
4. Identify how it expresses delivery mode / DLQ for Step 5.
5. Append those concrete signatures under the placeholder below so future runs match directly.

> ### Custom wrapper API (fill in when available)
> - Publish: `<signature>` — topic from `<where>`, message type from `<where>`.
> - Subscribe/handle: `<signature>` — topic from `<where>`, message type from `<where>`.
> - Delivery semantics expressed via: `<config / option / attribute>`.
> - DLQ / retry expressed via: `<...>`.

## Output of this analysis

```
publishes: [ {topic, messageType, trigger, delivery} ]
consumes:  [ {topic, messageType, effect, delivery} ]
unresolved: [ {site, reason} ]   # names that couldn't be resolved statically — flag, don't guess
```

## Cautions
- A topic referenced only as a config key with no value in any `appsettings.*` is unresolved —
  report it; the value may come from a deployment secret.
- Distinguish a real publish from a *re-publish in a test/fake*. Skip test projects unless
  documenting test harnesses.
- One handler can publish downstream — that's a chain; record both edges so the flow table is
  complete.
