---
name: dotnet-service-discovery
description: "How to extract a .NET/C# service's structure by static reading — HTTP endpoints (controllers + Minimal API), DI registrations, hosted/background workers, configuration keys (appsettings/IOptions), and persistence (EF Core/Dapper entities and tables). Apply when analyzing a C# service to document its surface, before writing the service doc. Grep patterns plus what each signal means."
---

You are reading code to document it, not to change it. Goal: a faithful inventory of the
service's surface — entry points, what it exposes, what it touches. Work from the project
file inward.

## 0. Orient from the project file

Read the `.csproj` first. It tells you what kind of service this is:
- `<Project Sdk="Microsoft.NET.Sdk.Web">` → HTTP service (API).
- `Microsoft.NET.Sdk.Worker` or a `BackgroundService`/`IHostedService` → worker.
- `Microsoft.NET.Sdk` plain, no entry point → library.
- `<TargetFramework>` → the `runtime` frontmatter value.
- `PackageReference`s reveal the stack: `Microsoft.EntityFrameworkCore.*` (EF), `Dapper`,
  `Refit`, `Polly`, the messaging client / custom wrapper, `Swashbuckle` (OpenAPI present).

Read `Program.cs` next — in modern .NET it is the composition root and wires everything.

## 1. HTTP endpoints

**Minimal API** — search for endpoint mappings:
```
MapGet|MapPost|MapPut|MapDelete|MapPatch|MapMethods
```
Each `app.MapPost("/v1/transfers", handler)` is an endpoint. Capture route, the handler's
parameters (request DTO), and return type (response DTO). `.RequireAuthorization()`,
`.WithName()`, `[FromBody]`/`[FromRoute]`/`[FromQuery]` qualify it.

**Controllers** — search:
```
\[ApiController\]|\[Route|\[HttpGet|\[HttpPost|\[HttpPut|\[HttpDelete|ControllerBase
```
The class `[Route("v1/[controller]")]` + each action's `[HttpPost("transfers")]` compose the
path. Action parameters = request shape; `ActionResult<T>`/`Results<...>` = response shape;
`[ProducesResponseType]` = status codes.

For each endpoint record: method, full path, auth requirement, request type, response type,
status codes, and whether it reads an `Idempotency-Key` header.

## 2. DI registrations (what the service depends on)

In `Program.cs` / `*ServiceCollectionExtensions` / `AddXxx()` methods:
```
AddScoped|AddSingleton|AddTransient|AddHttpClient|AddDbContext|AddHostedService|Configure<
```
- `AddHttpClient<TClient>()` / `AddRefitClient` → an **outbound HTTP dependency** (hand to
  `http-flow-analysis`).
- `AddDbContext<T>` → persistence (EF). The `UseSqlServer`/`UseNpgsql` call names the store.
- `AddHostedService<T>` → a background worker; read `ExecuteAsync` for what it does on a loop.
- registrations of the messaging client / custom wrapper → hand to `messaging-flow-analysis`.
- `Configure<TOptions>(config.GetSection("X"))` → a configuration section to document.

## 3. Background / worker entry points

```
: BackgroundService|IHostedService|ExecuteAsync\(|StartAsync\(
```
A worker's "interface" is not HTTP — it's its trigger (timer, message subscription, queue
poll) and its effects. Read `ExecuteAsync`/`StartAsync` to find the trigger, then trace what
it publishes/calls. These are the inbound side of the data flow for non-HTTP services.

## 4. Configuration keys

- `appsettings.json` / `appsettings.*.json` — read the key tree. Document **names and
  defaults**, never secret values.
- `IConfiguration["Section:Key"]`, `GetValue<T>("...")`, `GetConnectionString("...")`,
  `GetSection("...")`, and `IOptions<T>` POCOs (their properties are the keys).
- Environment variables: `Environment.GetEnvironmentVariable` and `__`-style overrides.

Record: key, default, required (no default + dereferenced = required), purpose.

## 5. Persistence / domain model

**EF Core:**
```
DbSet<|: DbContext|modelBuilder.Entity|\[Table\(|HasMany|HasOne|ToTable
```
Each `DbSet<Order> Orders` = an entity + its table. `OnModelCreating` / `IEntityTypeConfiguration`
mappings give table names and relationships.

**Dapper / ADO.NET:**
```
QueryAsync<|ExecuteAsync\(|new SqlConnection|FromSqlRaw
```
Table names appear in the SQL string literals. Extract entity-shaped types from the generic
arguments.

Record the handful of **key** entities (name, purpose, store) — not every DTO.

## 6. Internal structure (for the Architecture & how-it-works section)

Beyond the surface, capture how the service is built internally so the doc can explain how it
works and draw a C4-lite component diagram. Stay at architecture-overview depth — layers and
the main path, not every class.

**Layering** — the project/folder structure usually *is* the layering. Map projects to layers
(`*.Api`/`*.Web` → API, `*.Application` → handlers, `*.Domain` → domain, `*.Infrastructure` →
persistence/integration). Note the reference direction (outer → inner).

**Processing pipeline** — what a request/message passes through, in order:
```
UseMiddleware|IMiddleware|app.Use|IActionFilter|IEndpointFilter|AddOpenBehavior|IPipelineBehavior
IRequestHandler<|INotificationHandler<|MediatR|: IRequest|Handle\(|HandleAsync\(
```
- ASP.NET middleware (`app.Use...`, custom `IMiddleware`) and filters
  (`IActionFilter`/`IEndpointFilter`).
- MediatR `IPipelineBehavior<,>` (validation, logging, transaction) and the
  `IRequestHandler<,>` that does the work. The handler → domain service → repository chain is
  the spine of the component diagram.

**Transaction boundaries** — where a unit of work commits:
```
SaveChangesAsync|SaveChanges\(|BeginTransaction|TransactionScope|IDbContextTransaction|IUnitOfWork
```
Note what's atomic and whether there's an **outbox** (a table/row written in the same
`SaveChanges` as the domain change, drained by a worker) — that's the durability story for
"DB write + publish."

**Concurrency & state:**
```
Channel\.Create|SemaphoreSlim|lock \(|Interlocked|Parallel\.|ConcurrentDictionary|BackgroundService|PeriodicTimer
```
Singleton state, in-memory caches (`IMemoryCache`), producer/consumer channels, background
loops, locks. Determines what a caller can assume about ordering/races.

**Error handling:**
```
UseExceptionHandler|IExceptionHandler|ProblemDetails|AddProblemDetails|Polly|AddPolicyHandler|catch \(
```
Global exception middleware / `ProblemDetails`, Polly resilience policies, message
nack/redelivery/DLQ.

**Design patterns** — name the ones that shape the design (CQRS/MediatR, repository, outbox,
pipeline behaviors, hosted-service workers, strategy/factory) and point at a representative
type. Don't pattern-hunt; only what's actually load-bearing.

## Output of this analysis

A structured inventory the `service-doc-writer` turns into sections 5-10 of the service doc:
```
Type: http-api | worker | library | hybrid
Runtime: net8.0
Endpoints: [ {method, path, auth, request, response, statusCodes} ]
Workers: [ {name, trigger, effect} ]
Config: [ {key, default, required, purpose} ]
Entities: [ {name, purpose, store} ]
Outbound HTTP clients: [ ... ]   # → http-flow-analysis
Messaging registrations: [ ... ] # → messaging-flow-analysis

InternalArchitecture:               # → architecture-diagrams (component diagram + how-it-works)
  Layers: [ {layer, project, references} ]
  Pipeline: [ ordered: middleware → filters → handler → behaviors → domain → persistence/publish ]
  KeyComponents: [ {name, layer, role} ]    # real types — the component-diagram boxes
  TransactionBoundaries: [ {where, atomicScope, outbox: yes|no} ]
  Concurrency: [ {primitive, purpose} ]
  ErrorHandling: [ {mechanism, behavior} ]
  Patterns: [ {pattern, exampleType} ]
  uncertain: [ ... ]                # structure you couldn't verify statically — flag, don't invent
```

## Cautions
- Don't guess at runtime behavior from names alone — open the method and confirm.
- Generated code (`*.g.cs`, `*.Designer.cs`, `obj/`) is noise; skip it.
- A `hybrid` service has both HTTP endpoints and a worker/subscriber — document both surfaces.
