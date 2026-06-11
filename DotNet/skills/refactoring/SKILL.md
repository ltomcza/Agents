---
name: refactoring
description: Behavior-preserving refactoring patterns for C# / .NET — extract method, guard clauses, replace conditional with polymorphism, modernize idioms, primary constructors, records. Apply when restructuring existing code without changing behavior.
---

The contract: tests pass before and after. Every refactoring is one named pattern. Verify with the test suite at every step.

## Preconditions

1. Test suite covers the code you're touching. If not, add characterization tests first.
2. Working tree is clean.
3. You have a stated reason — duplication, complexity, a planned change needing the ground prepared.

## Patterns — eliminate duplication

### Extract Method

**Smell:** the same 5-10 lines appear in three places.

**Steps:**
1. Identify the shared chunk and what varies between sites.
2. Name the chunk by what it does (`ValidatePayload`, `FormatAddress`).
3. Extract with the variable bits as parameters.
4. Replace each site with the call.
5. Run tests.

### Extract Class / Service

**Smell:** a class has grown past ~300 lines covering several topics. `Helpers.cs` with 30 unrelated methods.

**Steps:**
1. Group methods by what they do.
2. Move each group to a new class.
3. Register in DI if needed. Update callers. Run tests after each move.

### Replace Magic Number/String with Named Constant

```csharp
// before
var timeout = 30;
var status = "active";

// after
private const int DefaultTimeoutSeconds = 30;
private const string StatusActive = "active";

var timeout = DefaultTimeoutSeconds;
```

For sets of related strings, use `enum` or `static class` with `const` fields.

## Patterns — reduce complexity

### Replace Conditional with Guard Clauses

**Before:**
```csharp
public Order Process(Order order)
{
    if (order.IsValid)
    {
        if (order.HasInventory)
        {
            if (!order.IsPaid)
                Charge(order);
            return Ship(order);
        }
        throw new OutOfStockException();
    }
    throw new InvalidOrderException();
}
```

**After:**
```csharp
public Order Process(Order order)
{
    if (!order.IsValid) throw new InvalidOrderException();
    if (!order.HasInventory) throw new OutOfStockException();
    if (!order.IsPaid) Charge(order);
    return Ship(order);
}
```

The happy path is flat. Errors leave early.

### Replace Flag Argument with Separate Methods

**Before:**
```csharp
public string Fetch(string url, bool parseJson)
{
    var response = _client.Get(url);
    return parseJson ? response.Json() : response.Text;
}
```

**After:**
```csharp
public string FetchText(string url) => _client.Get(url).Text;
public T FetchJson<T>(string url) => _client.Get(url).Json<T>();
```

### Replace Primitive Obsession with a Type

**Before:**
```csharp
void Transfer(string fromAccount, string toAccount, decimal amount)
```

**After:**
```csharp
public sealed record AccountId(string Value);
public sealed record Money(decimal Amount, string Currency);

void Transfer(AccountId from, AccountId to, Money amount)
```

Three call sites passing the same string-shaped data = a type wants to exist.

### Split God Method

**Smell:** method >= 30 lines with comment headers like `// validate`, `// transform`, `// save`.

**Steps:**
1. Each section becomes a private method.
2. The original becomes a thin orchestrator.

```csharp
public async Task<ImportResult> ImportUserAsync(UserPayload payload, CancellationToken ct)
{
    var data = Validate(payload);
    var user = Transform(data);
    return await SaveAsync(user, ct);
}
```

## Patterns — idiomatic C# upgrades

Apply only when they don't reduce clarity.

| Before | After |
|---|---|
| Block-scoped namespace | File-scoped namespace |
| `new ClassName()` (type obvious) | Target-typed `new()` |
| `if (x != null)` | `if (x is not null)` |
| `(x as T)?.Method()` | `if (x is T t) t.Method()` |
| `switch` statement | `switch` expression |
| `using (var x = ...) { }` | `using var x = ...;` |
| `class` with value equality overrides | `record` |
| `Tuple<string, int>` | `(string Name, int Age)` named tuple |
| `new List<int> { 1, 2, 3 }` | `[1, 2, 3]` collection expression (C# 12+) |
| Manual ctor + field assignment for DI | Primary constructor (C# 12+) |
| `string.Format("...", x)` | `$"...{x}"` interpolation |
| `StringBuilder` for simple concat | Interpolated string (not in loops) |

## Patterns — modernize for current .NET

If targeting .NET 8+ / C# 12+:
- Primary constructors for DI injection classes.
- Collection expressions `[..]`.
- `TimeProvider` instead of `DateTime.Now` / `DateTimeOffset.UtcNow`.
- `FrozenDictionary<,>` / `FrozenSet<>` for read-heavy lookup tables.
- `IOptions<T>` with `ValidateOnStart()` instead of raw `IConfiguration` reads.

If targeting .NET 9+ / C# 13+:
- `params ReadOnlySpan<T>` for zero-alloc params.
- `Lock` type instead of `object` for `lock` statements.

## Workflow

1. State the smell: "lines 40-80 of `OrderService.cs` and 110-150 of `OrderApi.cs` duplicate validation."
2. State the refactoring: "Extract Method -> `ValidateOrder` in `OrderValidation.cs`."
3. Run tests. Green.
4. Apply one pattern.
5. Run tests. Green. If red, revert.
6. Repeat.
7. Run full suite + `dotnet format --verify-no-changes` + `dotnet build -warnaserror` before reporting done.

## What you do NOT change in a refactor

- Public API signatures, return types, exception types. (That's a redesign.)
- Behavior in edge cases — even "obvious bugs." File a bug; don't sneak fixes in.
- Performance characteristics that tests rely on. Note any change.

## What is NOT a refactoring

- Adding a feature.
- Fixing a bug.
- Changing public behavior.
- Speculative abstraction ("we might need this"). YAGNI.
- Renaming for personal preference where the existing name is fine.

## Tools

- `dotnet format` for mechanical formatting fixes.
- Rider / Visual Studio refactoring tools — Rename, Extract Method, Move Type, Inline Variable.
- Roslyn analyzers with code fixes — let the tooling do the mechanical work.
- `dotnet test` + coverage to verify behavior preserved.
