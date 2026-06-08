---
name: dotnet-debugging
description: Systematic debugging for .NET / C# — repro construction, stack trace reading, common failure modes, diagnostics tools (dotnet-trace, dotnet-dump, dotnet-counters), logging, profiling. Apply when investigating failures, regressions, or wrong outputs.
---

Diagnosis before fix. Repro before theory. One hypothesis at a time.

## The procedure

1. **Get the symptom precisely.** Exact exception, exact command, exact input. If it's "it's slow," what input, what threshold, what's the current measurement?
2. **Reproduce locally.** No repro = no diagnosis. Write a minimal console app or test if you have to.
3. **Read the stack trace.** Inner exception first — that's usually the real cause. Outer exceptions are wrappers.
4. **Bisect.** Disable code paths until the symptom vanishes. Add logging at boundaries. `git bisect` for regressions.
5. **Form one hypothesis. Test it.** Don't change two things at once.
6. **Find the root cause, not the symptom.** The exception fires in `Process()`, but `Initialize()` produced the bad value. Trace it back.

## Easy wins to check first

- **Stale build.** `dotnet clean && dotnet build`. Old `bin`/`obj` artifacts cause phantom bugs.
- **Wrong SDK version.** `dotnet --info`. Does `global.json` pin a version that's not installed?
- **NuGet restore issues.** `dotnet restore --force-evaluate`. Version mismatch between packages?
- **Recently changed files.** `git log --since="1 week ago" --stat`.
- **Missing configuration.** `appsettings.json` key missing? Environment variable not set? `IOptions<T>` binding silently returns defaults for missing keys.
- **DI registration missing.** `InvalidOperationException: Unable to resolve service for type 'IFoo'`. Check `Program.cs` / `DependencyInjection.cs`.

## Reading stack traces

```
System.InvalidOperationException: Sequence contains no elements
   at System.Linq.ThrowHelper.ThrowNoElementsException()
   at System.Linq.Enumerable.First[TSource](IEnumerable`1 source)
   at MyApp.Services.OrderService.GetLatestOrder(Guid customerId) in /src/Services/OrderService.cs:line 42
   at MyApp.Api.OrdersController.GetLatest(Guid id) in /src/Api/OrdersController.cs:line 18
```

- Last line of the exception message: what went wrong.
- Innermost frame (first `at` line): where it was thrown.
- Your code frames (with file paths): where you need to look.
- For `AggregateException` / `ExceptionGroup`: check `.InnerExceptions` — the first one is usually the important one.

## Common .NET failure modes

| Symptom | Likely cause |
|---|---|
| `NullReferenceException` | Method returned null on unhandled branch; nullable annotations wrong; missing null check. |
| `InvalidOperationException: Sequence contains no elements` | `.First()` / `.Single()` on empty collection. Use `.FirstOrDefault()` + null check. |
| `ObjectDisposedException` | Using `DbContext` / `HttpClient` / scoped service after scope ended. Common in background tasks. |
| `InvalidCastException` / `JsonException` | Deserialization mismatch — JSON shape doesn't match C# model. |
| Deadlock / app hangs | `.Result` / `.Wait()` in code with a `SynchronizationContext`. Or truly deadlocked `SemaphoreSlim`. |
| `TaskCanceledException` | Client disconnect, `CancellationToken` fired, or `HttpClient.Timeout` exceeded. |
| `DbUpdateException` | DB constraint violation. Read the `InnerException` for the actual constraint name. |
| `InvalidOperationException: entity is already tracked` | EF Core: attaching an entity that's already tracked by the `DbContext`. |
| `InvalidOperationException: Unable to resolve service` | DI registration missing, wrong lifetime, or circular dependency. |
| `StackOverflowException` | Recursive property getter, infinite mutual recursion, deeply nested EF include. |
| `AmbiguousMatchException` in routing | Two endpoints with the same route template. |
| Auth doesn't work | Middleware ordering: `UseAuthentication()` must precede `UseAuthorization()` which must precede `MapControllers()`. |
| Config values are null/default | `IOptions<T>` binds silently. Missing key = default value. Use `ValidateOnStart()`. |
| Tests pass alone, fail in suite | Shared static state, `DbContext` not reset, `IClassFixture` scope wrong. |
| Path issues on Linux vs Windows | `Path.Combine("a", "/b")` returns `/b` on Linux. Use `Path.Join` or normalize. |

## Debugging tools

### dotnet CLI diagnostics

```bash
# List running .NET processes
dotnet-counters ps

# Real-time runtime counters (GC, threadpool, exceptions)
dotnet-counters monitor --process-id <pid> --counters System.Runtime

# Collect a trace (CPU, events)
dotnet-trace collect --process-id <pid> --duration 00:00:30

# Collect a memory dump
dotnet-dump collect --process-id <pid>

# Analyze a dump
dotnet-dump analyze <dump-file>
# Commands: dumpheap -stat, gcroot <addr>, pe (print exception)
```

### Visual Studio / Rider

- Breakpoints: conditional, hit-count, action (log without stopping).
- Exception Settings: break on first chance for specific exception types.
- Watch / Immediate window for evaluating expressions.
- Parallel Stacks for async/threaded debugging.
- Memory profiler for allocation analysis.

### Logging

```csharp
logger.LogDebug("Processing order {OrderId} for customer {CustomerId}",
    order.Id, customer.Id);
```

Use structured logging with message templates — not string interpolation. Templates allow log aggregation tools to group by pattern.

### Environment inspection

```bash
dotnet --info              # SDK, runtime, architecture
dotnet --list-sdks         # installed SDK versions
dotnet --list-runtimes     # installed runtimes
dotnet nuget list source   # configured NuGet sources
```

## Bisecting a regression

```bash
git bisect start
git bisect bad                   # current commit is broken
git bisect good <known-good-sha>
# git checks out a midpoint; you test:
dotnet test --filter "FullyQualifiedName~TestName"
git bisect good   # or bad
# repeat until git names the offending commit
git bisect reset
```

Automated bisect:
```bash
git bisect run dotnet test --filter "FullyQualifiedName~TestName"
```

## What good diagnosis looks like

```
Symptom: GetLatestOrder throws InvalidOperationException for customers with no orders.

Repro:
    await sut.GetLatestOrder(customerWithNoOrders.Id)

Root cause:
- File: src/Services/OrderService.cs:42
- `.First()` called on a query that returns zero rows when the customer has no orders.
- The nullable annotation claims `Order` (non-null return), but the query can legitimately return nothing.

Evidence:
- Added a test with a customer that has zero orders — throws InvalidOperationException.
- Changed `.First()` to `.FirstOrDefault()` in a scratch branch — exception goes away, but callers don't handle null.

Fix direction:
- Change return type to `Order?` and use `.FirstOrDefault()`, or throw a domain-specific `OrderNotFoundException`.
- The decision depends on whether "no orders" is an error or a valid state — architect should weigh in.

Side effects to watch:
- Three callers of GetLatestOrder assume non-null return. They need null checks or the domain exception.
```

That's a diagnosis. "Probably null somewhere" is not.
