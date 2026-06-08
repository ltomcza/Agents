---
name: solid-principles
description: SOLID design principles applied to Python — Single Responsibility, Open/Closed, Liskov, Interface Segregation, Dependency Inversion. Apply when designing classes/modules or reviewing object-oriented code. Use with judgment, not as religion.
---

Apply with judgment. SRP is non-negotiable; the others are guidelines that help when applied to the right problem and hurt when applied to the wrong one.

## S — Single Responsibility Principle

A class or function should have one reason to change.

### Smell
- The class name has "and" in it (`UserAndOrderManager`).
- You can't write a one-line summary of what the class does without listing.
- Methods cluster around different concerns: half about persistence, half about validation.
- Compound names: `OrderProcessorValidatorReporter`.
- Function ≥30 lines doing several stages with comment headers like `# validate`, `# transform`, `# save`.

### Apply
- Split by *reason to change*. Persistence rules change → repository. Validation rules change → validator. Pricing rules change → pricer.
- A function that "does X, and then if Y also Z" → split into compose-able functions.

### Python-specific
- Modules are units of single responsibility too. A 1000-line `utils.py` is the canonical violation.
- A `dataclass` with no behavior is fine — it's a single responsibility (hold data).

## O — Open/Closed Principle

Open to extension, closed to modification. Adding a new case shouldn't require editing existing case handlers.

### Smell
- Long `if/elif` chains on a type tag, repeated across many call sites.
- `match` statements that get a new `case` every time a new variant is added everywhere.

### Apply
- Polymorphism: each variant implements the same interface.
- Strategy pattern: pass the variant-specific behavior in.
- Plug-in registries: variants register themselves; the dispatcher looks them up.

### Python-specific
- `@functools.singledispatch` for type-based dispatch on the first argument.
- `typing.Protocol` for structural interfaces.
- Don't over-apply: two variants is not a hierarchy. Three call sites of the same `if` chain probably is.

## L — Liskov Substitution Principle

Subtypes should be substitutable for their base types without surprising the caller.

### Smell
- Subclass overrides a method to raise `NotImplementedError` for input the base accepts.
- Subclass tightens preconditions ("but only if amount > 0") that the base didn't require.
- Subclass returns a narrower type that the caller expected to be the base type.
- The classic: `Square(Rectangle)` overrides `set_width` to also set height.

### Apply
- If you find yourself overriding to "disable" a method, the inheritance is wrong. Use composition.
- Substitutes must accept everything the base accepts and return everything the base promises.

### Python-specific
- Variance matters: a `list[Dog]` is not a `list[Animal]` (lists are invariant). Use `Sequence[Animal]` if you mean "read-only animals."
- Protocols (`typing.Protocol`) help here — define what the caller actually needs, then any class with those methods substitutes.

## I — Interface Segregation Principle

Don't force clients to depend on methods they don't use.

### Smell
- A class implementing an interface where half the methods raise `NotImplementedError`.
- An abstract base class with 15 methods, but most callers use 2.
- A `Repository` interface that mixes "read" and "write" — read-only callers carry the write methods.

### Apply
- Split the interface into the bits actual callers use.
- For Python, write a small `Protocol` for each consumer of the dependency. Each consumer documents the surface it depends on.

### Python-specific
- Protocols are cheap. Make them per-caller.
- ABCs with 15 methods = monolithic. Composition of small protocols = segregated.

## D — Dependency Inversion Principle

High-level modules should not depend on low-level modules. Both depend on abstractions.

### Smell
- Business logic imports `psycopg2` directly.
- Service layer instantiates a concrete `SmtpEmailSender`.
- Test doubles are awkward because the dependency is constructed inside the unit under test.

### Apply
- Define an interface (`Protocol`) at the level of the consumer.
- Inject the implementation. Constructor injection is usually cleanest in Python.
- Compose at the edge — `main.py` wires the real implementations to the abstractions.

### Python-specific
```python
from typing import Protocol

class EmailSender(Protocol):
    def send(self, to: str, body: str) -> None: ...

class OrderConfirmationService:
    def __init__(self, sender: EmailSender) -> None:
        self._sender = sender

    def confirm(self, order: Order) -> None:
        self._sender.send(order.email, f"Order {order.id} confirmed")
```

Now `OrderConfirmationService` doesn't know SMTP exists. The test injects a stub; `main.py` injects the real sender.

## Pragmatic notes

- **Don't apply SOLID prophylactically.** "We might need to swap the database" — you won't, and the abstraction will be wrong when you do.
- **Three is the magic number.** One concrete case is just code. Two is a coincidence. Three is a pattern worth abstracting.
- **DI ≠ DI framework.** Plain constructor arguments are dependency injection. You don't need a container.
- **Inheritance is rarely the answer in Python.** Composition + protocols + module-level functions handles 95% of what other languages use inheritance for.
- **The best abstraction is sometimes no abstraction.** A 5-line function copied twice is fine. Extracting a helper after the third copy is fine. Extracting before the second is over-engineering.

## Smell → fix shortcuts

| Smell | Likely fix |
|---|---|
| Class name with "And" | Split (SRP) |
| Long if-elif on a type field | Polymorphism / dispatch (OCP) |
| Subclass disables a parent method | Replace with composition (LSP) |
| Interface with `NotImplementedError` stubs | Split into smaller interfaces (ISP) |
| Business code imports a driver | Define a protocol, inject (DIP) |
| Test mocks 5 things to test 1 | Probably DIP missing |
| Same `if` chain in 5 places | OCP refactor: dispatch table |
