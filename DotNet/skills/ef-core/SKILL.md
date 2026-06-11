---
name: ef-core
description: EF Core patterns for .NET — DbContext lifetime, Fluent API mapping, relationship modeling (one-to-many, many-to-many skip-nav, owned types), tracking vs no-tracking queries, projections, split queries, compiled queries, ExecuteUpdate/ExecuteDelete, migrations, interceptors (audit, soft delete, timestamps), and common anti-patterns. Apply when modeling entities, writing queries, designing migrations, or reviewing EF Core code.
---

EF Core is the default ORM for .NET OLTP work. Get four things right and the rest follows: lifetime is **Scoped**, mapping is **Fluent**, reads are **no-tracking + projected**, cross-cutting work runs in **interceptors**.

Examples target EF Core 8+ on .NET 8+ unless noted.

## 1. DbContext lifetime

```csharp
// Program.cs
services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));
```

- **Scoped** — the default `AddDbContext` lifetime. One instance per request / per scope. Never share across requests or threads.
- **Singleton** is wrong — `DbContext` is **not thread-safe** and caches change-tracked entities indefinitely.
- **`AddDbContextFactory<T>`** when you need short-lived contexts inside a Singleton (e.g. a `BackgroundService` processing items) — resolve `IDbContextFactory<AppDbContext>` and call `CreateDbContextAsync()` per unit of work.
- **Pooling**: `AddDbContextPool<T>` reuses contexts across requests. Faster on hot APIs; requires `OnConfiguring` to be stateless. Don't pool when interceptors carry per-request state.

## 2. Mapping — Fluent API > Data Annotations

For anything beyond toy projects, configure entities via `IEntityTypeConfiguration<T>` in separate files. Data Annotations don't scale: they leak persistence concerns into domain types and can't express composite keys, shadow properties, owned types, or value converters cleanly.

```csharp
public sealed class OrderConfiguration : IEntityTypeConfiguration<Order>
{
    public void Configure(EntityTypeBuilder<Order> b)
    {
        b.ToTable("orders");
        b.HasKey(o => o.Id);

        b.Property(o => o.Total)
            .HasPrecision(18, 2)
            .IsRequired();

        b.Property(o => o.Status)
            .HasConversion<string>()   // store enum as text, not int
            .HasMaxLength(32);

        b.HasIndex(o => new { o.CustomerId, o.CreatedAt })
            .HasDatabaseName("ix_orders_customer_created");

        b.OwnsOne(o => o.ShippingAddress);   // value object → columns on orders
    }
}

// In OnModelCreating
modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
```

**Always** convert enums explicitly (`HasConversion<string>()` or `HasConversion<int>()`). The default of int-by-ordinal silently corrupts data if anyone reorders the enum.

## 3. Relationships

### One-to-many

```csharp
b.HasMany(c => c.Orders)
    .WithOne(o => o.Customer)
    .HasForeignKey(o => o.CustomerId)
    .OnDelete(DeleteBehavior.Restrict);   // explicit. Never default.
```

### Many-to-many (skip navigations)

```csharp
b.HasMany(p => p.Tags)
    .WithMany(t => t.Products)
    .UsingEntity<ProductTag>();
```

Skip navigations let you traverse `product.Tags` without an explicit join entity, while still allowing a join table with payload columns when you need one.

### Owned types vs value objects

```csharp
b.OwnsOne(o => o.ShippingAddress, sa =>
{
    sa.Property(p => p.Line1).HasColumnName("ship_line1");
    sa.Property(p => p.City).HasColumnName("ship_city");
});
```

Owned types serialize into the owner's table — no separate FK, no separate lifetime. Use for value objects (`Money`, `Address`, `DateRange`). Don't use for entities that have their own identity.

### Soft delete via global query filter

```csharp
b.HasQueryFilter(o => !o.IsDeleted);
```

Every query against this entity gets `WHERE NOT is_deleted` appended automatically. Pair with a `SaveChangesInterceptor` (see section 7) that intercepts `EntityState.Deleted` and switches it to `Modified` + sets `IsDeleted = true`.

## 4. Query patterns

### Reads → `AsNoTracking` + projection

```csharp
// BAD — materializes full Order entities, tracks them, returns more than the API needs
var orders = await db.Orders
    .Where(o => o.CustomerId == customerId)
    .ToListAsync(ct);

// GOOD — no tracking, only the columns the API returns
var orders = await db.Orders
    .AsNoTracking()
    .Where(o => o.CustomerId == customerId)
    .OrderByDescending(o => o.CreatedAt)
    .Select(o => new OrderSummary(o.Id, o.Total, o.Status))
    .ToListAsync(ct);
```

Projection (`Select`) is the single biggest perf lever in EF Core. It collapses the SELECT to the columns you actually use and skips materializing relationships you don't.

### `Include` vs split queries vs projection

```csharp
// Cartesian explosion with multiple Includes:
db.Customers
    .Include(c => c.Orders)
    .Include(c => c.Addresses);
// → one SQL query, Orders × Addresses rows per customer

// Split queries (EF Core 5+):
db.Customers
    .Include(c => c.Orders)
    .Include(c => c.Addresses)
    .AsSplitQuery();
// → three SQL queries, no explosion

// Best: project to a shape that says exactly what you need:
db.Customers
    .Where(c => c.Id == id)
    .Select(c => new CustomerDetail(
        c.Id,
        c.Name,
        c.Orders.Select(o => new OrderRef(o.Id, o.Total)).ToList(),
        c.Addresses.Select(a => new AddressRef(a.Line1, a.City)).ToList()))
    .FirstOrDefaultAsync(ct);
```

Rule of thumb: more than one `Include` → reach for `AsSplitQuery()` or a projection.

### Bulk updates → `ExecuteUpdateAsync` / `ExecuteDeleteAsync`

```csharp
// EF Core 7+. One SQL statement. No tracking, no materialization.
await db.Orders
    .Where(o => o.Status == OrderStatus.Pending && o.CreatedAt < cutoff)
    .ExecuteUpdateAsync(s => s.SetProperty(o => o.Status, OrderStatus.Expired), ct);

await db.Orders
    .Where(o => o.Status == OrderStatus.Cancelled)
    .ExecuteDeleteAsync(ct);
```

Use for set-based operations. Skips interceptors and change tracking — so log/audit explicitly if you need it.

## 5. Performance

- **Compiled queries** (`EF.CompileAsyncQuery`) for hot LINQ queries — caches the translation step.
- **`EF.Functions`** for provider-specific operations: `EF.Functions.ILike`, `EF.Functions.JsonContains`, `EF.Functions.DateDiffDay`.
- **Batching**: EF Core batches `INSERT`/`UPDATE`/`DELETE` from `SaveChanges` automatically (Npgsql, SqlServer). Tune `MaxBatchSize` in provider options.
- **`AsNoTrackingWithIdentityResolution()`** when you need no-tracking reads but still want shared references inside the result graph.
- **Don't materialize then filter**: `db.Orders.ToList().Where(...)` pulls the whole table into memory. Always filter server-side first.

## 6. Migrations

```bash
dotnet ef migrations add AddOrderStatusIndex --project src/MyApp.Infrastructure
dotnet ef database update --project src/MyApp.Infrastructure
dotnet ef migrations script --idempotent --output migration.sql
```

- **One migration per logical change.** Never edit a migration after it has run anywhere — create a new one.
- **Backward-compatible deploys**: any column rename or type change splits into add → backfill → switch reads → drop, across at least two deploys.
- **Apply in CI**, not at app startup, for any non-trivial change. `Database.Migrate()` at startup is fine for small services but races on multi-replica deploys.
- **Idempotent scripts** (`--idempotent`) for environments where you can't track applied migrations in the schema.
- **Test migrations** in CI against a clean containerized database (Testcontainers + `dotnet ef database update`).

## 7. Interceptors

`SaveChangesInterceptor` and `IDbCommandInterceptor` are the right place for cross-cutting persistence concerns.

```csharp
public sealed class AuditInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken ct = default)
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var entry in eventData.Context!.ChangeTracker.Entries<IAuditable>())
        {
            switch (entry.State)
            {
                case EntityState.Added:
                    entry.Entity.CreatedAt = now;
                    entry.Entity.UpdatedAt = now;
                    break;
                case EntityState.Modified:
                    entry.Entity.UpdatedAt = now;
                    break;
                case EntityState.Deleted when entry.Entity is ISoftDeletable sd:
                    entry.State = EntityState.Modified;
                    sd.DeletedAt = now;
                    break;
            }
        }
        return base.SavingChangesAsync(eventData, result, ct);
    }
}

services.AddSingleton<AuditInterceptor>();
services.AddDbContext<AppDbContext>((sp, options) =>
    options.UseNpgsql(connStr)
           .AddInterceptors(sp.GetRequiredService<AuditInterceptor>()));
```

Common uses: audit (`CreatedAt`/`UpdatedAt`), soft-delete promotion, tenant filter injection, query logging with parameter scrubbing, slow-query metrics.

Prefer async overrides — they don't block when interceptor work touches I/O. Note: interceptors don't fire on `ExecuteUpdate`/`ExecuteDelete`.

## 8. Anti-patterns

### N+1 from lazy loading

```csharp
// BAD — one query per order
foreach (var order in await db.Orders.ToListAsync(ct))
    Console.WriteLine(order.Customer.Name);   // lazy load!

// GOOD — eager-load or project
var rows = await db.Orders
    .Select(o => new { o.Id, CustomerName = o.Customer.Name })
    .ToListAsync(ct);
```

Disable lazy loading entirely (`UseLazyLoadingProxies` off — it's off by default in EF Core; keep it that way). If a code path needs related data, project it or `Include` it explicitly.

### `Find` vs `FirstOrDefault`

```csharp
// Find checks the change tracker first, then the DB.
var order = await db.Orders.FindAsync([id], ct);

// FirstOrDefaultAsync always hits the DB (subject to query cache).
var order = await db.Orders.FirstOrDefaultAsync(o => o.Id == id, ct);
```

Use `Find` when you have the PK and may already have the entity tracked. Use `FirstOrDefault` with a predicate when you're filtering on anything else or want predictable SQL.

### Materializing before filtering

```csharp
// BAD — pulls every order into memory
var pending = (await db.Orders.ToListAsync(ct))
    .Where(o => o.Status == OrderStatus.Pending);

// GOOD — filter in SQL
var pending = await db.Orders
    .Where(o => o.Status == OrderStatus.Pending)
    .ToListAsync(ct);
```

If the IDE doesn't show LINQ-to-Entities under your cursor, you're already in-memory. Filter before `ToList`/`ToArray`/`AsEnumerable`.

### `FromSqlRaw` with string interpolation

```csharp
// SQL INJECTION
db.Orders.FromSqlRaw($"SELECT * FROM orders WHERE id = '{id}'");

// Auto-parameterized (EF Core 7+)
db.Orders.FromSql($"SELECT * FROM orders WHERE id = {id}");

// Explicit parameters
db.Orders.FromSqlRaw("SELECT * FROM orders WHERE id = @p0", id);
```

Prefer `FromSql` (interpolated, auto-parameterized) over `FromSqlRaw`.

### Returning `IQueryable<T>` from repositories

A repository that exposes `IQueryable<T>` lets callers compose arbitrary queries — including ones that the repository can't satisfy (DB-specific functions, eager-load misses, N+1 patterns). Return materialized results (`List<T>`, `T?`, projections), or async streams (`IAsyncEnumerable<T>`).

### `Database.EnsureCreated()` in production

`EnsureCreated` doesn't apply migrations. It creates the schema from the model — then you can't migrate forward. Use `Database.Migrate()` (or apply migrations in CI) instead. `EnsureCreated` is fine in tests.
