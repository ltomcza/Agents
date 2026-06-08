---
name: dotnet-async-concurrency
description: Async and concurrency in .NET / C# — async/await, Task, ValueTask, CancellationToken, Channel, Parallel.ForEachAsync, SemaphoreSlim, ConfigureAwait, common pitfalls (sync-over-async, async void, fire-and-forget). Apply when writing or reviewing async code, concurrent data structures, or parallel processing.
---

Async is for I/O-bound concurrency. `Parallel`/`Task.Run` is for CPU-bound parallelism. Get the dimension right before reaching for a primitive.

## Decision tree

| Workload | Reach for |
|---|---|
| Many concurrent I/O calls (HTTP, DB, files) | `async`/`await` end-to-end |
| CPU-bound work off the request thread | `Task.Run` to offload, or `Parallel.ForEachAsync` |
| Bounded concurrent I/O | `SemaphoreSlim` or `Channel<T>` |
| Producer/consumer pipeline | `Channel<T>` + `BackgroundService` |
| Fire-and-forget that must complete | `Channel<T>` or `BackgroundService` (not `Task.Run` without retention) |
| Blocking library you can't replace | `Task.Run(blocking)` from async, or dedicate a thread |

The `async`/`await` model does not use threads for waiting — it frees the thread to handle other requests. This is why ASP.NET Core scales well.

## Async fundamentals

```csharp
public async Task<Order> GetOrderAsync(Guid id, CancellationToken ct)
{
    var order = await _context.Orders
        .AsNoTracking()
        .FirstOrDefaultAsync(o => o.Id == id, ct);

    return order ?? throw new OrderNotFoundException(id);
}
```

### Rules

- `async` methods return `Task`, `Task<T>`, `ValueTask<T>`, or `IAsyncEnumerable<T>`. Never `void`.
- `CancellationToken` on every async method, last parameter, defaulted only on public API entry points.
- `ConfigureAwait(false)` in library code — ASP.NET Core has no `SynchronizationContext`, but library code that may run elsewhere should opt out explicitly.
- `await` everything. Never `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` in async code paths — they deadlock classic ASP.NET and waste threads in Core.

### async void — the exception

`async void` is only for top-level event handlers (WPF/WinForms/Blazor events). Exceptions from `async void` methods crash the process — they can't be observed or caught by the caller.

```csharp
// ONLY acceptable use
private async void OnButtonClick(object sender, EventArgs e)
{
    try { await DoWorkAsync(); }
    catch (Exception ex) { ShowError(ex); }
}
```

## Cancellation

```csharp
public async Task ProcessBatchAsync(IEnumerable<Item> items, CancellationToken ct)
{
    foreach (var item in items)
    {
        ct.ThrowIfCancellationRequested();
        await ProcessItemAsync(item, ct);
    }
}
```

- Thread `CancellationToken` through the entire call chain.
- `ct.ThrowIfCancellationRequested()` in CPU loops between I/O calls.
- ASP.NET Core: `HttpContext.RequestAborted` is the request's cancellation token. Use it for all downstream calls.
- `CancellationTokenSource` for timeouts: `new CancellationTokenSource(TimeSpan.FromSeconds(30))`.
- Link tokens: `CancellationTokenSource.CreateLinkedTokenSource(ct, timeout.Token)`.

## ValueTask vs Task

```csharp
// Hot path that usually completes synchronously (cache hit)
public ValueTask<User?> GetCachedUserAsync(Guid id, CancellationToken ct)
{
    if (_cache.TryGetValue(id, out var user))
        return ValueTask.FromResult(user);  // no Task allocation

    return GetFromDatabaseAsync(id, ct);    // rare path allocates
}
```

- `ValueTask<T>` saves a `Task` allocation when the result is often synchronous (cached, pooled).
- **Rules:** a `ValueTask` must be `await`ed exactly once. No `.Result`. No storing and awaiting later. No `.WhenAll()`.
- Use `Task<T>` by default. Switch to `ValueTask<T>` only when profiling shows the allocation matters.

## Concurrency primitives

### SemaphoreSlim — bounded concurrency

```csharp
private readonly SemaphoreSlim _semaphore = new(maxConcurrency: 10);

public async Task ProcessAsync(Item item, CancellationToken ct)
{
    await _semaphore.WaitAsync(ct);
    try
    {
        await DoWorkAsync(item, ct);
    }
    finally
    {
        _semaphore.Release();
    }
}
```

Limits concurrent operations. Use for rate-limiting outbound HTTP, DB connections, or any shared resource.

### Channel<T> — producer/consumer

```csharp
var channel = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(100)
{
    FullMode = BoundedChannelFullMode.Wait,
});

// Producer
await channel.Writer.WriteAsync(item, ct);

// Consumer (in a BackgroundService)
await foreach (var item in channel.Reader.ReadAllAsync(ct))
{
    await ProcessAsync(item, ct);
}
```

- `Channel<T>` is the async-native producer/consumer queue. Thread-safe, allocation-efficient.
- Bounded channels provide backpressure. Unbounded channels risk memory exhaustion.
- Prefer over `ConcurrentQueue<T>` + polling.

### Parallel.ForEachAsync — bounded parallelism

```csharp
await Parallel.ForEachAsync(items, new ParallelOptions
{
    MaxDegreeOfParallelism = 10,
    CancellationToken = ct,
}, async (item, token) =>
{
    await ProcessItemAsync(item, token);
});
```

For fan-out over a collection with bounded concurrency. Simpler than managing `SemaphoreSlim` + `Task.WhenAll` manually.

### Lock and SemaphoreSlim for mutual exclusion

```csharp
// For synchronous critical sections
private readonly Lock _lock = new();  // .NET 9+ Lock type

public void UpdateState()
{
    lock (_lock)
    {
        // critical section
    }
}

// For async critical sections
private readonly SemaphoreSlim _asyncLock = new(1, 1);

public async Task UpdateStateAsync(CancellationToken ct)
{
    await _asyncLock.WaitAsync(ct);
    try
    {
        // async critical section
    }
    finally
    {
        _asyncLock.Release();
    }
}
```

- `lock` for sync-only code. **Never `lock` around an `await`** — it doesn't work and throws.
- `SemaphoreSlim(1, 1)` for async mutual exclusion.
- .NET 9+: `Lock` type is more efficient than `lock (object)`.

## IAsyncEnumerable — streaming

```csharp
public async IAsyncEnumerable<User> ListUsersAsync(
    [EnumeratorCancellation] CancellationToken ct = default)
{
    string? cursor = null;
    do
    {
        var page = await _client.GetPageAsync(cursor, ct);
        foreach (var user in page.Items)
            yield return user;
        cursor = page.NextCursor;
    } while (cursor is not null);
}

// Consuming
await foreach (var user in ListUsersAsync(ct))
{
    Process(user);
}
```

Return `IAsyncEnumerable<T>` when the caller should process items as they arrive, not wait for the full collection.

## Common pitfalls

### Sync-over-async (BLOCKING)

```csharp
// DEADLOCK in classic ASP.NET; thread waste in Core
var result = GetDataAsync().Result;
var result = GetDataAsync().GetAwaiter().GetResult();
GetDataAsync().Wait();
```

Never block on async code. If you must call async from sync (rare), use `Task.Run(() => GetDataAsync()).GetAwaiter().GetResult()` as a last resort, or restructure to be async end-to-end.

### Fire-and-forget without retention

```csharp
// BAD — task may be GC'd, exceptions vanish
_ = DoBackgroundWorkAsync();
Task.Run(() => DoBackgroundWorkAsync());
```

If the work must complete, use `Channel<T>` + `BackgroundService`, or hold a reference and observe completion:

```csharp
// Acceptable pattern with error handling
_ = Task.Run(async () =>
{
    try { await DoBackgroundWorkAsync(); }
    catch (Exception ex) { _logger.LogError(ex, "Background work failed"); }
});
```

### Async lambda pitfalls

```csharp
// BAD — async void lambda, exceptions crash the process
items.ForEach(async item => await ProcessAsync(item));

// GOOD — use Parallel.ForEachAsync or select + WhenAll
await Task.WhenAll(items.Select(item => ProcessAsync(item, ct)));
```

### Task.Run misuse

```csharp
// BAD — wrapping an already-async method in Task.Run (async-over-async)
await Task.Run(() => GetDataAsync());

// GOOD — just await it
await GetDataAsync();
```

`Task.Run` is for offloading CPU-bound work from the request thread. Wrapping async I/O in `Task.Run` adds overhead for no benefit.

### Missing ConfigureAwait in libraries

```csharp
// Library code — add ConfigureAwait(false)
var data = await _client.GetAsync(url, ct).ConfigureAwait(false);
```

Without `ConfigureAwait(false)`, library code captures the caller's `SynchronizationContext`. In ASP.NET Core (no sync context) this doesn't matter, but the library might be used from WPF/WinForms/Blazor where it does.

## Testing async code

```csharp
[Fact]
public async Task Transfer_CompletesSuccessfully()
{
    var result = await _sut.TransferAsync(request, CancellationToken.None);

    result.Should().NotBeNull();
    result.TransferId.Should().NotBeEmpty();
}

[Fact]
public async Task Transfer_WhenCancelled_ThrowsOperationCancelled()
{
    using var cts = new CancellationTokenSource();
    cts.Cancel();

    var act = () => _sut.TransferAsync(request, cts.Token);

    await act.Should().ThrowAsync<OperationCanceledException>();
}
```

- Async test methods return `Task`.
- Use `FakeTimeProvider` (Microsoft.Extensions.TimeProvider.Testing) for time-dependent tests.
- Use `TaskCompletionSource<T>` to control async completion in tests.

## Quick reference

```csharp
// Bounded concurrency over a collection
await Parallel.ForEachAsync(items, new() { MaxDegreeOfParallelism = 10 }, async (item, ct) =>
    await ProcessAsync(item, ct));

// Timeout
using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
await DoWorkAsync(cts.Token);

// Linked cancellation (request + timeout)
using var linked = CancellationTokenSource.CreateLinkedTokenSource(requestCt, timeoutCt);

// Async lock
await _semaphore.WaitAsync(ct);
try { /* critical section */ }
finally { _semaphore.Release(); }

// Producer/consumer
await channel.Writer.WriteAsync(item, ct);
await foreach (var item in channel.Reader.ReadAllAsync(ct)) { }

// Streaming results
await foreach (var user in ListUsersAsync(ct)) { Process(user); }
```

## Anti-patterns

- **`async void`** methods (except event handlers) — exceptions crash the process.
- **`.Result` / `.Wait()`** — deadlocks and thread waste.
- **`Task.Run` around async I/O** — overhead for no benefit.
- **Fire-and-forget without error handling** — exceptions vanish silently.
- **`async` methods that don't `await`** — just return `Task` directly, or make it sync.
- **`lock` around `await`** — compiler error, but `Monitor.Enter` + `await` compiles and breaks.
- **`ConcurrentDictionary` + async lambdas in `GetOrAdd`** — the factory runs outside the lock, causing duplicate work. Use `Lazy<Task<T>>` or `SemaphoreSlim`.
- **Unbounded `Task.WhenAll`** — launching 10,000 tasks exhausts the thread pool. Use `Parallel.ForEachAsync` with `MaxDegreeOfParallelism`.
