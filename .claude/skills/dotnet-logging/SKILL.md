---
name: dotnet-logging
description: Logging best practices for .NET / C# — structured logging with ILogger, log levels, Serilog/OpenTelemetry, correlation IDs, sensitive-data scrubbing, high-performance logging with LoggerMessage.Define, configuration. Apply when adding logging to new code, reviewing log output, or debugging missing/noisy logs.
---

Logging is the only debugger you have in production. Get it right once, then forget about it.

## 1. ILogger<T> via DI

Every class gets its logger via constructor injection. Never call a static logger or `Console.WriteLine`.

```csharp
internal sealed class TransferService(ILedger ledger, ILogger<TransferService> log)
    : ITransferService
{
    public async Task<TransferReceipt> TransferAsync(TransferRequest req, CancellationToken ct)
    {
        log.LogInformation("transfer.start {SourceAccount} {TargetAccount} {Amount}",
            req.SourceAccount, req.TargetAccount, req.Amount);

        var receipt = await ledger.TransferAsync(req, ct);

        log.LogInformation("transfer.complete {TransferId} {DurationMs}",
            receipt.Id, receipt.DurationMs);

        return receipt;
    }
}
```

- `ILogger<T>` scopes the category name to the class — operators filter by namespace.
- Library code should **never** configure logging. Configuration belongs to the host application.

## 2. Levels — when to use which

| Level | Meaning | Example |
|---|---|---|
| `Trace` | Verbose diagnostic noise. Off in production. | "Entering method X with args Y" |
| `Debug` | Developer-only diagnostics. | "Computed angle=0.42 from input=(3, 5)" |
| `Information` | State transitions an operator cares about. | "User logged in", "Job completed" |
| `Warning` | Something is degraded but functional. | "Retry 1/3 succeeded after timeout" |
| `Error` | A request/operation failed. | "Payment declined: insufficient funds" |
| `Critical` | Service-wide outage; immediate page. | "DB connection pool exhausted" |

Default production level: `Information`. Don't ship `Debug`/`Trace` to production — it floods storage.

## 3. Structured logging with message templates

**Use message templates, not string interpolation.**

```csharp
// GOOD — structured, filterable, deferred formatting
log.LogInformation("transfer.complete {TransferId} {Amount} {DurationMs}",
    receipt.Id, req.Amount, sw.ElapsedMilliseconds);

// BAD — string interpolation runs even when the level is filtered out
log.LogInformation($"transfer.complete {receipt.Id} {req.Amount} {sw.ElapsedMilliseconds}");
```

The `{TransferId}` placeholders become structured properties in the log event — queryable in Seq, Datadog, Grafana, Application Insights.

Conventions:
- Message is an event name (dot-separated), not a sentence. `"transfer.complete"` not `"Transfer completed for account."`.
- All variable data goes in template parameters, never interpolated into the message.
- Stable property names across the codebase: `RequestId`, `UserId`, `DurationMs`, `ErrorType`.

## 4. High-performance logging — LoggerMessage.Define

For hot paths (request pipeline, tight loops), `LoggerMessage.Define` avoids boxing and allocation:

```csharp
internal static partial class LogMessages
{
    [LoggerMessage(Level = LogLevel.Information, Message = "transfer.complete {TransferId} {DurationMs}")]
    public static partial void TransferComplete(this ILogger logger, Guid transferId, long durationMs);
}

// Usage
log.TransferComplete(receipt.Id, sw.ElapsedMilliseconds);
```

Source-generated (C# 12+ / .NET 8+). Zero allocation. Compile-time validation of parameters.

## 5. Correlation / request IDs

In a server, every log line should carry the request ID.

### ASP.NET Core — built-in

ASP.NET Core populates `Activity.Current` with trace/span IDs automatically when `app.UseHttpLogging()` or OpenTelemetry is configured. Serilog and the OpenTelemetry exporter pick these up.

### Manual via ILogger scopes

```csharp
using (logger.BeginScope(new Dictionary<string, object>
{
    ["RequestId"] = httpContext.TraceIdentifier,
    ["UserId"] = httpContext.User.FindFirst("sub")?.Value ?? "anonymous",
}))
{
    await next(httpContext);
}
```

Scopes propagate to all log calls within the `using` block, including async continuations.

## 6. Serilog (popular structured logging library)

```csharp
// Program.cs
builder.Host.UseSerilog((context, config) => config
    .ReadFrom.Configuration(context.Configuration)
    .Enrich.FromLogContext()
    .Enrich.WithMachineName()
    .WriteTo.Console(new RenderedCompactJsonFormatter())
    .WriteTo.Seq("http://localhost:5341"));
```

Serilog advantages over built-in:
- Richer enrichers (machine name, thread, environment).
- Sinks for every destination (Seq, Datadog, Elasticsearch, file).
- `Destructure` for complex objects without manual property listing.

Use Serilog *or* the built-in `ILogger` pipeline — both work through `ILogger<T>`.

## 7. OpenTelemetry logging

```csharp
builder.Logging.AddOpenTelemetry(options =>
{
    options.SetResourceBuilder(ResourceBuilder.CreateDefault()
        .AddService("MyApp"));
    options.AddOtlpExporter();
});
```

Correlates logs with traces and metrics. The `Activity.TraceId` and `Activity.SpanId` are automatically attached.

## 8. Sensitive-data scrubbing

Never log secrets, tokens, connection strings, full PANs, or PII.

```csharp
// At the call site: mask before logging
log.LogInformation("auth.token_refreshed {ClientId} {TokenPrefix}",
    clientId, token[..8] + "...");

// Safety net: Serilog destructuring policy
.Destructure.ByTransforming<HttpRequestMessage>(r => new
{
    r.Method,
    Url = r.RequestUri?.GetLeftPart(UriPartial.Path),
    // Omit headers and body
})
```

Filter middleware that strips `Authorization`, `Cookie`, `X-API-Key` headers before logging request details.

## 9. Exception logging

```csharp
// GOOD — pass the exception as the first parameter
try
{
    await DoThingAsync();
}
catch (IntegrityException ex)
{
    log.LogError(ex, "transfer.failed {TransferId}", transferId);
    throw;
}

// BAD — loses the stack trace
catch (IntegrityException ex)
{
    log.LogError("transfer.failed: {Message}", ex.Message);
}
```

`LogError(exception, ...)` attaches the full exception including stack trace. The `ex.Message` version loses everything useful.

## 10. Configuration

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore.Database.Command": "Information",
      "MyApp": "Debug"
    }
  }
}
```

- Per-namespace level control. Noisy frameworks (`Microsoft.AspNetCore`) get `Warning`; your app gets `Debug` in development.
- Override via environment variable: `Logging__LogLevel__Default=Debug`.
- Serilog: use `MinimumLevel.Override("Microsoft", LogEventLevel.Warning)`.

## Anti-patterns

- `Console.WriteLine` in production code. It writes to stdout without level, structure, or context.
- `log.LogError(ex.ToString())` instead of `log.LogError(ex, "message")`.
- `catch (Exception ex) { log.LogError(ex, "error"); }` without re-throw — swallows the exception silently.
- String interpolation in log calls (`$"..."`) — computes the string even when the level is filtered.
- Logging objects with huge `ToString()` (full entity graphs, request bodies). Log the ID, not the body.
- `Console.WriteLine` for debugging that gets committed. Use conditional `Debug.WriteLine` or `ILogger` at `Debug` level.
- Logging inside hot loops without checking `IsEnabled(LogLevel)` first.
- Not propagating `Activity`/correlation IDs — makes distributed tracing impossible.
