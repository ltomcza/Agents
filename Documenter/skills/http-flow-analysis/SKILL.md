---
name: http-flow-analysis
description: "Map the synchronous HTTP data flow of a .NET service — catalog its inbound endpoints and resolve its outbound HTTP dependencies (typed HttpClient, Refit, BaseAddress/config URLs) to concrete callee services. Apply when documenting the HTTP side of a service's data flow and building the system HTTP call matrix. Covers auth, error contracts, and service-name resolution."
---

The HTTP half of the data-flow graph: what calls **in** (this service's endpoints) and what
this service calls **out** (its downstream HTTP dependencies). Inbound feeds the service's
public interface; outbound feeds `_http-call-matrix.md`.

## Inbound — the service's own endpoints

Reuse the endpoint inventory from `dotnet-service-discovery` (controllers + Minimal API). For
the data-flow purpose, what matters per endpoint:
- **Trigger identity**: method + path (the thing a caller invokes).
- **Auth**: `[Authorize]`, `.RequireAuthorization()`, policy/scheme names, `[AllowAnonymous]`.
- **Request → response shape**: the DTO types.
- **Error contract**: `ProblemDetails`, exception filters, `[ProducesResponseType(4xx/5xx)]`,
  status codes a caller must handle.
- **Idempotency**: does it read an `Idempotency-Key` header / dedupe?

These become the per-service "Public interface → HTTP endpoints" section and the *callee* side
of matrix rows.

## Outbound — downstream HTTP dependencies

Find every way the service calls another service over HTTP.

**Typed `HttpClient` via factory** (the idiomatic case):
```
AddHttpClient<|IHttpClientFactory|HttpClient .*BaseAddress|new HttpClient\(
```
`services.AddHttpClient<IPaymentsClient, PaymentsClient>(c => c.BaseAddress = ...)` registers a
typed client. The class methods (`GetAsync`/`PostAsync` with a path) are the individual calls.

**Refit interfaces:**
```
AddRefitClient|: IRefit|\[Get\(|\[Post\(|\[Put\(|\[Delete\(
```
A Refit interface declares each downstream endpoint directly as a method with an attribute —
the cleanest possible source for caller→callee edges. `[Post("/v1/transfers")]` = one edge.

**Raw / ad-hoc:** `new HttpClient()`, `RestClient`, `FlurlClient`, `GraphQLHttpClient`. Note
these — `new HttpClient()` per call is also a code smell worth flagging back.

For each outbound call capture: HTTP method, path, the **base address source**, purpose, auth
(how the token is attached — `DelegatingHandler`, header, `AddHeaderPropagation`), and resilience
(Polly policies: retry/circuit-breaker/timeout) since that affects the caller's contract.

## Resolving the callee to a service

A matrix row needs the **callee `service_id`**, not a URL. Resolve in this order:
1. **Config key → value**: `BaseAddress` usually comes from `appsettings`/`IOptions`
   (`"Services:Payments:BaseUrl": "https://payments-api/"`). The key name and host often *are*
   the service name.
2. **Service discovery names**: in Aspire/K8s/`AddServiceDiscovery`, `http://payments-api`
   resolves by logical name — map the host to the matching service doc.
3. **Typed client / Refit interface name**: `IPaymentsClient` → `payments-api` by convention.
4. **External**: if the host is a third party with no service doc (Stripe, an external partner),
   name it and mark the matrix row `external`.

If you can't resolve a base address (value only in a deployment secret), record the call with
`callee: unresolved` and the config key — don't guess.

## Output of this analysis

```
inbound:  [ {method, path, auth, request, response, statusCodes, idempotent} ]
outbound: [ {method, path, calleeServiceId | external | unresolved, baseAddressSource, auth, resilience, purpose} ]
```

The `outbound` list becomes caller rows in `_http-call-matrix.md`; `inbound` becomes the
service's public HTTP interface and the callee side of others' rows.

## Cautions
- A health-check or metrics scrape call to a downstream is not a meaningful data-flow edge —
  exclude infra noise; keep business calls.
- Distinguish the auth *to* the service (inbound) from auth *attached by* the service to its
  downstream calls (outbound). Both belong in the doc, in different sections.
- Watch for `DelegatingHandler`s that add headers/retries globally — they affect every typed
  client and belong in operational notes.
