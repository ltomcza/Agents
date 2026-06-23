---
name: code-review
description: Checklist for reviewing C# / .NET diffs — correctness, design, idioms, async discipline, security quick-checks, testing. Apply when reviewing a pull request, diff, or set of changed files.
---

Walk this checklist on every review. Skip categories that don't apply, but state that you skipped them.

## 0. Does it do what it claims?

Before any other check, read the change against the stated intent. Mismatched intent is the most expensive bug to catch later.

This checklist is the source of truth for the `code-reviewer` agent. Keep the agent body focused on review flow, severity model, and output contract.

## 1. Correctness

- [ ] `NullReferenceException` paths — nullable annotations say `string` but runtime can be null?
- [ ] Off-by-one in `Span`, `Range`, `for` loops, LINQ `.Skip`/`.Take`.
- [ ] `==` on reference types where value equality was intended.
- [ ] Iterating a collection while mutating it (`InvalidOperationException`).
- [ ] Resource leaks: `IDisposable` not in `using` declarations.
- [ ] Bare `catch { }` or `catch (Exception) { }` without action.
- [ ] `throw ex;` instead of `throw;` — destroys stack trace.
- [ ] `assert` in production code (use `throw`).
- [ ] Async: `async void` (except event handlers), `.Result`/`.Wait()`, fire-and-forget without retention.

## 2. Nullable reference types

- [ ] `<Nullable>enable</Nullable>` in the project.
- [ ] All public signatures annotated: `string?` where null is valid, `string` where it isn't.
- [ ] No `!` (null-forgiving) used as a shortcut where a null check is warranted.
- [ ] No `object` or `dynamic` where a real type exists.
- [ ] `CancellationToken` on all async public API methods.

## 3. Design

- [ ] Each method does one thing. Name reads without "and."
- [ ] No god objects: classes with too many responsibilities.
- [ ] Inheritance only for is-a, not code reuse.
- [ ] No abstractions with one implementation (premature `IFooService` + `FooService`).
- [ ] Project references flow one direction. No new circular references.
- [ ] No new mutable static state.
- [ ] Records/DTOs instead of dictionaries with magic keys.
- [ ] No Service Locator (`GetService<T>()`) deep in business code.

## 4. Idiomatic C#

- [ ] File-scoped namespaces.
- [ ] `var` when the type is obvious from the RHS; explicit when it isn't.
- [ ] Pattern matching (`is`, `switch` expression) over type-check chains.
- [ ] `using` declarations over `using` blocks.
- [ ] Collection expressions (`[1, 2, 3]`, `[..a, ..b]`) where appropriate.
- [ ] Primary constructors for simple DI injection (C# 12+).
- [ ] `sealed` on new classes not designed for inheritance.
- [ ] `record` for value-shaped data instead of class with manual Equals/GetHashCode.

## 5. Errors

- [ ] Specific exception types, not `Exception`.
- [ ] Caught exceptions handled, logged, or re-raised — not swallowed.
- [ ] `throw;` (not `throw ex;`) to preserve stack trace.
- [ ] Custom exceptions for domain errors.
- [ ] Error paths covered by tests.

## 6. Async discipline

- [ ] No `async void` except event handlers.
- [ ] No `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` in async code paths.
- [ ] `ConfigureAwait(false)` in library code.
- [ ] `CancellationToken` threaded through the entire async call chain.
- [ ] No `Task.Run` wrapping an already-async method.
- [ ] `IAsyncDisposable` used where needed (`await using`).

## 7. Testing

- [ ] New public behavior has tests.
- [ ] Bug fixes have a regression test.
- [ ] Tests assert behavior, not implementation.
- [ ] Tests don't mock the system under test.
- [ ] Test names describe behavior (`Method_WhenCondition_ShouldExpected`).
- [ ] No `Thread.Sleep` in tests; deterministic waits.
- [ ] No `[Skip]` without a reason and ticket.

### Smoke-test detector (BLOCKING)

For each test in the diff, identify the assertions and apply the mutation-test heuristic:

> If the SUT silently returned the wrong value (or did nothing), would this test fail?

If the answer is no, it is a smoke test. Common shapes:

- No assertion at all (the test just calls the SUT).
- Only `.Should().NotBeNull()` or `.Should().BeOfType<X>()` — passes for almost any implementation.
- Broad `try/catch` wrapping that swallows assertion failures.

Flag BLOCKING and route back to test-engineer.

## 8. Logging & observability

- [ ] `ILogger<T>` via DI, not `Console.WriteLine`.
- [ ] No secrets / PII in log messages.
- [ ] Log levels appropriate: `Error` for bugs, `Warning` for recoverable, `Information` for ops events, `Debug` for dev.
- [ ] Structured logging with message templates, not string interpolation in log calls.

## 9. Security quick-pass

(Depth goes to security-auditor, but flag the obvious.)

- [ ] SQL string concatenation/interpolation instead of parameterized queries.
- [ ] `Process.Start` with user-controlled arguments.
- [ ] Hardcoded secrets / connection strings.
- [ ] `[AllowAnonymous]` on endpoints that should be protected.
- [ ] `BinaryFormatter`, `TypeNameHandling.All` on untrusted data.
- [ ] `ServerCertificateCustomValidationCallback = (...) => true`.
- [ ] `Random` (not `RandomNumberGenerator`) for security tokens.

## 10. Performance (when relevant)

- [ ] No O(n^2) where O(n) fits (nested loops / LINQ over the same data).
- [ ] No string concatenation in a loop (use `StringBuilder`).
- [ ] No unnecessary `.ToList()` / `.ToArray()` materialization.
- [ ] No DB query in a loop (N+1).
- [ ] No `new HttpClient()` per call (use `IHttpClientFactory`).
- [ ] `AsNoTracking()` on read-only EF Core queries.

## 11. Documentation

- [ ] Public types and members have XML doc comments.
- [ ] New public types have a `<summary>`.
- [ ] No restating-the-signature docs ("`amount`: A decimal representing the amount").
- [ ] No "TODO" without a ticket.
- [ ] No commented-out code blocks.

### Comment-code drift (BLOCKING)

Every comment that names an action must match what the code below it does. If the comment promises behavior the code doesn't deliver, either fix the code or delete the comment.

## 11b. Domain numbers (MAJOR)

Hardcoded magic numbers in domain logic should live in `IOptions<T>` configuration or a named constant.

- [ ] No bare numeric literals in conditions.
- [ ] No `* 1500`, `/ 60`, `+ 4` in domain code without a constant name.

## 12. Tooling

- [ ] `dotnet format --verify-no-changes` passes.
- [ ] `dotnet build -warnaserror` passes.
- [ ] NuGet packages updated if dependencies changed.
- [ ] No `#pragma warning disable` without a justification comment.

## Severity guide

- **BLOCKING** — must fix before merge: bugs, security, broken contract, missing test on new public API.
- **MAJOR** — should fix before merge: design issues, significant readability problems.
- **MINOR** — fix if you're already there: style nits, naming.
- **NOTE** — observation, not a request.

## Feedback format

```
[SEVERITY] path/to/File.cs:LINE — short title

What's wrong: <one or two sentences>
Why it matters: <impact, when not obvious>
Suggested fix: <code snippet, <=5 lines>
```

Be specific. Cite file and line. Show the fix shape, not the whole solution.
