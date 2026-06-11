---
name: dependency-injection
description: Dependency injection patterns for .NET — service lifetimes (Transient / Scoped / Singleton), captive dependencies, keyed services, the IOptions family (IOptions / IOptionsSnapshot / IOptionsMonitor), composition root, factory patterns, anti-patterns (service locator, BuildServiceProvider, scope capture), and DI in tests. Apply when registering services, choosing lifetimes, debugging captive-dependency or circular-dependency issues, or designing the composition root.
---

`Microsoft.Extensions.DependencyInjection` is the default container. It's deliberately minimal — it doesn't auto-wire decorators, named instances (until .NET 8 keyed services), or interception. That minimalism is a feature: registration is explicit and the composition root is one place.

Examples target .NET 8+ unless noted.

## 1. Lifetimes

| Lifetime | One instance per | Use for |
|---|---|---|
| **Transient** | Resolution (new each time) | Cheap stateless services, lightweight helpers |
| **Scoped** | DI scope (per HTTP request in ASP.NET Core; per `IServiceScope` elsewhere) | Anything tied to a unit of work — `DbContext`, request-bound caches, current-user accessors |
| **Singleton** | Application | Caches, configuration, factories, clients that internally pool (`HttpClient` via `IHttpClientFactory`, `NpgsqlDataSource`) |

Decision rule: **start Scoped**, drop to Singleton only when the type is genuinely stateless or owns expensive resources, drop to Transient only when each call site genuinely needs an independent instance (rare).

### Captive dependency — the classic trap

A longer-lived service captures a shorter-lived one and pins it for its whole lifetime.

```csharp
// BAD — Singleton captures Scoped DbContext for the life of the app
services.AddDbContext<AppDbContext>(...);            // Scoped
services.AddSingleton<UserCache>();                  // Singleton

public sealed class UserCache(AppDbContext db) { }   // captive!
```

The `AppDbContext` resolved into `UserCache` is the one from the first request. Forever. Memory leaks, stale data, thread-safety bugs.

**Detect**: enable validation in `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Host.UseDefaultServiceProvider((ctx, options) =>
{
    options.ValidateScopes = true;
    options.ValidateOnBuild = true;
});
```

**Fix**: inject `IServiceScopeFactory` and create a scope per use (see section 4).

## 2. Registration patterns

### Standard registrations

```csharp
services.AddSingleton<IClock, SystemClock>();
services.AddScoped<IOrderService, OrderService>();
services.AddTransient<IIdGenerator, GuidIdGenerator>();
```

### Factory registrations — when construction needs the container

```csharp
services.AddSingleton<IEventBus>(sp =>
{
    var options = sp.GetRequiredService<IOptions<BusOptions>>().Value;
    return new RabbitMqEventBus(options.ConnectionString,
                                 sp.GetRequiredService<ILogger<RabbitMqEventBus>>());
});
```

Use a factory when the constructor needs runtime configuration that isn't itself a DI service.

### Keyed services (.NET 8+)

```csharp
services.AddKeyedSingleton<IPaymentProcessor, StripeProcessor>("stripe");
services.AddKeyedSingleton<IPaymentProcessor, AdyenProcessor>("adyen");

public sealed class CheckoutService(
    [FromKeyedServices("stripe")] IPaymentProcessor processor) { }
```

Cleaner than registering a single `IPaymentProcessorRegistry` that does string lookups. Reach for keyed services when you have a small fixed set of named implementations; fall back to a factory/registry pattern when the set is open or driven by config.

### `IEnumerable<T>` — collection of implementations

```csharp
services.AddSingleton<IHealthCheck, DbHealthCheck>();
services.AddSingleton<IHealthCheck, ApiHealthCheck>();

public sealed class HealthService(IEnumerable<IHealthCheck> checks) { }
```

All registrations for the same interface are resolved as `IEnumerable<T>`. Useful for plug-in style fan-out.

## 3. The `IOptions` family

Configuration objects bound from `appsettings.json` or environment variables. Three accessors with different reload semantics.

| Accessor | Lifetime | Reload on file change? | Use for |
|---|---|---|---|
| `IOptions<T>` | Singleton | **No** — value captured once at startup | Most services; defaults |
| `IOptionsSnapshot<T>` | Scoped | Reloaded per scope (per HTTP request) | Per-request config that may change between requests |
| `IOptionsMonitor<T>` | Singleton | Yes, push notification via `OnChange` | Long-lived services (Singletons, `BackgroundService`) that need live reload |

```csharp
services.Configure<EmailOptions>(builder.Configuration.GetSection("Email"));

// Singleton, value never reloads
public sealed class Mailer(IOptions<EmailOptions> options) { }

// Per request — picks up appsettings changes between requests
public sealed class RequestPolicy(IOptionsSnapshot<PolicyOptions> options) { }

// Long-lived background worker — reacts to live reload
public sealed class Reaper(IOptionsMonitor<ReaperOptions> options) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var current = options.CurrentValue;
        using var sub = options.OnChange(newValue => current = newValue);
        // ...
    }
}
```

Validate on bind so misconfiguration fails at startup, not at first use:

```csharp
services.AddOptions<EmailOptions>()
    .Bind(builder.Configuration.GetSection("Email"))
    .ValidateDataAnnotations()
    .ValidateOnStart();
```

## 4. Composition root

The composition root is the **one place** registrations happen — typically `Program.cs` or a small `*ServiceCollectionExtensions` file per module.

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddInfrastructure(builder.Configuration)
    .AddDomain()
    .AddWebApi();

var app = builder.Build();
```

```csharp
// Infrastructure/DependencyInjection.cs
public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services, IConfiguration config)
    {
        services.AddDbContext<AppDbContext>(o => o.UseNpgsql(
            config.GetConnectionString("Default")));
        services.AddSingleton<IClock, SystemClock>();
        return services;
    }
}
```

Outside the composition root, **never** call `IServiceProvider.GetService<T>()` from business code. Inject what you need via the constructor. The exceptions are framework integrations and `BackgroundService`-style hosts that genuinely need to span scopes (see below).

### Resolving Scoped from Singleton

```csharp
public sealed class WorkProcessor(IServiceScopeFactory scopeFactory) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            using var scope = scopeFactory.CreateScope();
            var handler = scope.ServiceProvider.GetRequiredService<IWorkHandler>();
            await handler.HandleAsync(stoppingToken);
        }
    }
}
```

`BackgroundService` is a Singleton. To use Scoped services (`DbContext`, `IUnitOfWork`), inject `IServiceScopeFactory` and create one scope per unit of work.

## 5. Anti-patterns

### Service locator

```csharp
// BAD — hides dependencies, breaks testability, fragile to refactors
public sealed class CheckoutService(IServiceProvider sp)
{
    public async Task RunAsync()
    {
        var payments = sp.GetRequiredService<IPaymentProcessor>();
        var shipping = sp.GetRequiredService<IShippingProvider>();
        // ...
    }
}

// GOOD — declare dependencies in the constructor
public sealed class CheckoutService(
    IPaymentProcessor payments,
    IShippingProvider shipping) { }
```

### `BuildServiceProvider()` mid-setup

```csharp
// BAD — creates a second container, captured singletons get duplicated
services.AddSingleton<IFoo, Foo>();
var sp = services.BuildServiceProvider();   // DON'T
var foo = sp.GetRequiredService<IFoo>();
services.AddSingleton(new BarUsing(foo));
```

Use factory registrations (`services.AddSingleton<IBar>(sp => new BarUsing(sp.GetRequiredService<IFoo>()))`) instead.

### Capturing Scoped in Singleton via constructor

Covered above — turn on `ValidateScopes = true` and the container throws at startup.

### `new`-ing dependencies inside a service

```csharp
// BAD — uncontrollable in tests, can't share connection pools, breaks DI
public sealed class WeatherService
{
    private readonly HttpClient _http = new();
}

// GOOD
public sealed class WeatherService(HttpClient http) { /* registered via AddHttpClient */ }
```

### Circular dependencies

`A` constructor takes `B`, `B` takes `A` → container throws at first resolution. Don't paper over with `Lazy<T>` or property injection — it almost always indicates a missing third type that owns the shared responsibility. Extract it.

## 6. Decorators and pipelines

`Microsoft.Extensions.DependencyInjection` doesn't ship decorator support. Two options:

1. **Manual factory**:
   ```csharp
   services.AddSingleton<IEmailSender, SmtpEmailSender>();
   services.Decorate<IEmailSender, RetryingEmailSender>();   // via Scrutor
   services.Decorate<IEmailSender, LoggingEmailSender>();
   ```
   Add the [Scrutor](https://www.nuget.org/packages/Scrutor) package for `Decorate`. It's a 50-line helper that the built-in container should ship but doesn't.

2. **Middleware-style pipelines** (`IHttpClientFactory`, MediatR's `IPipelineBehavior<,>`) — these have first-class composition built in.

## 7. DI in tests

### Overriding registrations in `WebApplicationFactory`

```csharp
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IPaymentProcessor>();
            services.AddSingleton<IPaymentProcessor, FakePaymentProcessor>();

            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(o => o.UseSqlite("DataSource=:memory:"));
        });
    }
}
```

`RemoveAll<T>` before `AddSingleton<T>` — otherwise you have two registrations and resolution order is undefined.

### Direct construction in unit tests

For unit tests of a single class, **don't** spin up a container. Construct it directly with test doubles:

```csharp
var sut = new CheckoutService(
    payments: new FakePaymentProcessor(),
    shipping: new FakeShippingProvider());
```

DI is a runtime composition concern; unit tests construct what they need. Save the container setup for integration tests via `WebApplicationFactory`.
