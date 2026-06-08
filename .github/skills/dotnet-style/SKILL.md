---
name: dotnet-style
description: C# coding standards and modern language features — naming, formatting, type hints, nullable annotations, idioms, async patterns, records, pattern matching. Apply when writing or editing any C# code. Also use when reviewing code for style.
---

Apply these standards to every C# file you write or edit.

## Naming

- `PascalCase` for types, methods, properties, events, namespaces, public fields, constants.
- `camelCase` for parameters and local variables.
- `_camelCase` for private fields (underscore prefix).
- `IPascalCase` for interfaces (always `I` prefix).
- `TPascalCase` for type parameters (`T`, `TKey`, `TValue`).
- No abbreviations unless the abbreviation is a domain term or already universal (`Url`, `Http`, `Db`, `Id`).
- Names describe *what*, not *type*. `users` not `userList`. `isActive` not `activeFlag`.
- `Async` suffix on all async methods: `GetUserAsync`, `TransferAsync`.
- No Hungarian notation. No `str`, `int`, `lst` prefixes.

## Layout

- 4 spaces per indent. Never tabs. Never mixed.
- One class per file (exceptions: nested types, closely related small records).
- File name matches the primary type name: `TransferService.cs` for `TransferService`.
- File-scoped namespaces: `namespace MyApp.Services;` (one less indent level).
- Brace on new line (Allman style) — the .NET convention.
- Files end with a single newline.

## Using directives

- `ImplicitUsings` enabled — the common namespaces (`System`, `System.Collections.Generic`, `System.Linq`, `System.Threading.Tasks`, etc.) are auto-imported.
- Additional `using` directives at the top, alphabetical.
- `global using` directives in a `GlobalUsings.cs` file for project-wide imports.
- No `using static` except for very commonly used static members (`Math`, test assertion helpers).

## Nullable reference types

- `<Nullable>enable</Nullable>` in `Directory.Build.props` — applies to all projects.
- Annotate honestly: `string?` where null is valid, `string` where it isn't.
- Don't `!` (null-forgiving) your way past warnings. If you need `!`, the code needs a null check or redesign.
- Public APIs returning `null` for "not found" must use `T?` in the signature.
- Constructor parameters: non-nullable = required, nullable = optional with `= null` default.

## Type system

- **`record`** for value-shaped data: DTOs, commands, events, value objects.
  ```csharp
  public sealed record TransferRequest(Guid SourceAccount, Guid TargetAccount, decimal Amount);
  ```
- **`record struct`** for small, frequently allocated value types (avoid GC pressure).
  ```csharp
  public readonly record struct Money(decimal Amount, string Currency);
  ```
- **`class`** only when you need identity, mutability, or inheritance.
- **`sealed`** by default on classes not designed for inheritance.
- **`readonly`** fields, `init`-only properties for immutable members.
- **`required`** keyword (C# 11+) for properties that must be set at construction.

## var and type inference

- `var` when the type is obvious from the right-hand side:
  ```csharp
  var users = new List<User>();          // obvious
  var account = await GetAccountAsync(); // return type visible in method name
  ```
- Explicit type when it isn't obvious:
  ```csharp
  IReadOnlyList<Order> orders = GetOrders();  // return type is ambiguous from the name
  ```

## Pattern matching

```csharp
// Instead of type checks + casts
return shape switch
{
    Circle c    => Math.PI * c.Radius * c.Radius,
    Rectangle r => r.Width * r.Height,
    null        => throw new ArgumentNullException(nameof(shape)),
    _           => throw new NotSupportedException($"Unknown: {shape.GetType()}"),
};

// Guard conditions
if (response is { StatusCode: HttpStatusCode.OK, Content.Length: > 0 } ok)
{
    Process(ok.Content);
}

// Null checks
if (user is not null) { ... }
if (result is null) { ... }
```

## Collection expressions (C# 12+)

```csharp
int[] numbers = [1, 2, 3, 4, 5];
List<string> names = ["Alice", "Bob"];
ReadOnlySpan<byte> buffer = [0x00, 0xFF];
int[] combined = [..first, ..second, extra];
```

Prefer over `new List<T> { ... }` and `new[] { ... }`.

## Primary constructors (C# 12+)

```csharp
// DI injection — clean, no boilerplate fields
internal sealed class TransferService(ILedger ledger, ILogger<TransferService> log)
    : ITransferService
{
    public async Task<TransferReceipt> TransferAsync(TransferRequest req, CancellationToken ct)
    {
        log.LogInformation("transfer.start {Amount}", req.Amount);
        return await ledger.TransferAsync(req, ct);
    }
}
```

Use for constructor-injection classes where you don't need to validate or transform parameters.

## Async patterns

- `async`/`await` end-to-end. No `.Result`, `.Wait()`, `.GetAwaiter().GetResult()`.
- `CancellationToken` parameter on every async method, last position.
- `ConfigureAwait(false)` in library code.
- `async void` only for top-level event handlers — exceptions vanish otherwise.
- `ValueTask<T>` on hot paths that usually complete synchronously.
- `IAsyncEnumerable<T>` for streaming results instead of materializing to `List<T>`.

## Functions and methods

- One job per method. If you can't name it without "and," split.
- <= 30 lines is a guideline. "Can I read this without scrolling?" is the real bar.
- <= 4 positional parameters. Beyond that, use a parameter object (record).
- Return early. Guard clauses beat nested ifs.
- Expression-bodied members for single-line methods:
  ```csharp
  public decimal Total => Items.Sum(i => i.Price * i.Quantity);
  ```

## LINQ

- Use LINQ for collection transformations: `.Where`, `.Select`, `.GroupBy`, `.OrderBy`, `.Any`, `.All`.
- Chain stays readable up to ~3-4 calls. Beyond that, extract intermediate variables.
- Prefer method syntax over query syntax for most cases.
- Don't use LINQ for side effects (`.ForEach` on `List<T>` is fine; LINQ should be side-effect-free).
- Watch for deferred execution: `.ToList()` only when you need to materialize.

## Errors

- Throw specific exceptions. Define your own when BCL doesn't fit.
- Catch the narrowest type.
- `throw;` to re-throw (preserves stack trace). Never `throw ex;`.
- `catch (Exception ex) when (ex is not OperationCanceledException)` for "catch everything except cancellation."
- `ArgumentNullException.ThrowIfNull(param)` for null-guard boilerplate.

## Comments and XML docs

- XML doc comments on public types and members: `/// <summary>`.
- No restating-the-signature comments ("`amount`: A decimal representing the amount").
- Inline comments for *why*, not *what*. Code already says what.
- No "TODO" without a ticket reference.
- No commented-out code blocks. Git remembers.

## DI and configuration

- Constructor injection. Always.
- Register with the narrowest lifetime: `AddTransient` > `AddScoped` > `AddSingleton`. Don't default to singleton.
- `IOptions<T>` for configuration. Bind from `appsettings.json` with `.ValidateDataAnnotations().ValidateOnStart()`.
- Never read `IConfiguration["key"]` deep in business code. Bind to a typed options class.

## Tools

These are the formatter and analyzer rules. Run them; don't argue with them.

```bash
dotnet format                        # format code
dotnet format --verify-no-changes    # check without modifying
dotnet build -warnaserror            # treat warnings as errors
```

EditorConfig + Roslyn analyzers handle the mechanical checks. If the analyzer flags something, fix it. Don't `#pragma warning disable` without a justification comment.
