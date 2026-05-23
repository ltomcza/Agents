---
name: solid-principles
description: SOLID design principles applied to C# / .NET — Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion. Apply when designing classes/projects or reviewing object-oriented code. Use with judgment, not as religion.
---

Apply with judgment. SRP is non-negotiable; the others are guidelines that help when applied to the right problem and hurt when applied to the wrong one.

## S — Single Responsibility Principle

A class or method should have one reason to change.

### Smell
- The class name has "And" in it (`UserAndOrderManager`).
- You can't write a one-line summary of what the class does without listing.
- Methods cluster around different concerns: half about persistence, half about validation.
- Compound names: `OrderProcessorValidatorReporter`.
- Method >= 30 lines doing several stages with comment headers like `// validate`, `// transform`, `// save`.

### Apply
- Split by *reason to change*. Persistence rules change -> repository. Validation rules change -> validator. Pricing rules change -> pricer.
- A method that "does X, and then if Y also Z" -> split into composable methods.

### C# specific
- Projects are units of single responsibility too. A 2000-line `Helpers.cs` is the canonical violation.
- A `record` with no behavior is fine — it's a single responsibility (hold data).
- Services registered in DI should have focused responsibilities. A `UserService` with 30 methods is a god class.

## O — Open/Closed Principle

Open to extension, closed to modification. Adding a new case shouldn't require editing existing case handlers.

### Smell
- Long `if/else if` chains on a type tag, repeated across many call sites.
- `switch` statements that get a new `case` every time a new variant is added everywhere.

### Apply
- Polymorphism: each variant implements the same interface.
- Strategy pattern: pass the variant-specific behavior in via DI.
- Plug-in registries: variants register themselves; the dispatcher resolves them.

### C# specific
- Interfaces + DI make OCP natural in .NET. Define `INotificationSender`; register `EmailSender`, `SmsSender`, `PushSender`. Add a new sender without touching existing code.
- `IEnumerable<INotificationSender>` injected by DI to iterate over all registered implementations.
- Don't over-apply: two variants is not a hierarchy. Three call sites of the same `switch` probably is.

## L — Liskov Substitution Principle

Subtypes should be substitutable for their base types without surprising the caller.

### Smell
- Subclass overrides a method to throw `NotSupportedException` for input the base accepts.
- Subclass tightens preconditions the base didn't require.
- The classic: `Square : Rectangle` overrides `Width` setter to also set `Height`.
- Interface implementation that violates the contract documented on the interface.

### Apply
- If you find yourself overriding to "disable" a method, the inheritance is wrong. Use composition.
- Substitutes must accept everything the base accepts and return everything the base promises.

### C# specific
- Variance matters: `IEnumerable<Dog>` is covariant to `IEnumerable<Animal>` (read-only). `List<Dog>` is not assignable to `List<Animal>` (invariant — it has `Add`).
- Interfaces help here — define what the caller needs, then any class implementing those members substitutes.
- `record` types and value objects don't have this problem — they're sealed by default.

## I — Interface Segregation Principle

Don't force clients to depend on methods they don't use.

### Smell
- A class implementing an interface where half the methods throw `NotSupportedException`.
- An interface with 15 methods, but most callers use 2.
- A `IRepository<T>` that mixes `GetById`, `GetAll`, `Add`, `Update`, `Delete` — read-only callers carry the write methods.

### Apply
- Split the interface into what actual callers use.
- `IReadOnlyRepository<T>` for read-only callers. `IWriteRepository<T>` for write callers. `IRepository<T> : IReadOnlyRepository<T>, IWriteRepository<T>` for full access.

### C# specific
- Small interfaces are cheap. `ICanValidate`, `ICanProcess`, `ICanNotify` — each consumer declares its dependencies.
- MediatR's `IRequestHandler<TRequest, TResponse>` is ISP in action — one handler per request, one method.
- CQRS naturally segregates: `IQueryHandler<TQuery, TResult>` vs `ICommandHandler<TCommand>`.

## D — Dependency Inversion Principle

High-level modules should not depend on low-level modules. Both depend on abstractions.

### Smell
- Business logic directly `new`s up a `SqlConnection` or `SmtpClient`.
- Service layer instantiates a concrete `EmailSender`.
- Test doubles are awkward because the dependency is constructed inside the unit under test.
- A project references the database driver directly instead of an abstraction.

### Apply
- Define an interface at the level of the consumer.
- Inject the implementation via constructor injection.
- Compose at the edge — `Program.cs` or a `DependencyInjection.cs` extension wires the real implementations.

### C# specific

```csharp
// The abstraction — lives in Application/Domain layer
public interface IEmailSender
{
    Task SendAsync(string to, string body, CancellationToken ct);
}

// The consumer — doesn't know SMTP exists
internal sealed class OrderConfirmationService(IEmailSender sender) : IOrderConfirmationService
{
    public async Task ConfirmAsync(Order order, CancellationToken ct)
    {
        await sender.SendAsync(order.Email, $"Order {order.Id} confirmed", ct);
    }
}

// The implementation — lives in Infrastructure layer
internal sealed class SmtpEmailSender(IOptions<SmtpOptions> options) : IEmailSender
{
    public async Task SendAsync(string to, string body, CancellationToken ct)
    {
        // actual SMTP work
    }
}

// Wiring — in Program.cs or DependencyInjection.cs
services.AddTransient<IEmailSender, SmtpEmailSender>();
services.AddTransient<IOrderConfirmationService, OrderConfirmationService>();
```

Now `OrderConfirmationService` doesn't know SMTP exists. The test injects a substitute; `Program.cs` injects the real sender.

## Pragmatic notes

- **Don't apply SOLID prophylactically.** "We might need to swap the database" — you won't, and the abstraction will be wrong when you do.
- **Three is the magic number.** One concrete case is just code. Two is a coincidence. Three is a pattern worth abstracting.
- **DI != DI framework.** Constructor injection is DI. You don't need Autofac/Ninject — the built-in `Microsoft.Extensions.DependencyInjection` handles 99% of cases.
- **One interface, one implementation = code smell.** `IFooService` + `FooService` with no other implementor and no test double need is premature abstraction.
- **The best abstraction is sometimes no abstraction.** A 5-line method copied twice is fine. Extract after the third copy.

## Smell -> fix shortcuts

| Smell | Likely fix |
|---|---|
| Class name with "And" | Split (SRP) |
| Long if-else on a type field | Polymorphism / dispatch (OCP) |
| Subclass disables a parent method | Replace with composition (LSP) |
| Interface with `NotSupportedException` stubs | Split into smaller interfaces (ISP) |
| Business code `new`s a driver | Define interface, inject (DIP) |
| Test mocks 5 things to test 1 | Probably DIP missing |
| Same `switch` in 5 places | OCP refactor: strategy + DI |
| `IFooService` with only `FooService` | Remove the interface (premature abstraction) |
