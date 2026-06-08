---
name: python-code-review
description: Checklist for reviewing Python diffs — correctness, design, idioms, security quick-checks, testing. Apply when reviewing a pull request, diff, or set of changed files.
---

Walk this checklist on every review. Skip categories that don't apply, but state that you skipped them.

## 0. Does it do what it claims?

Before any other check, read the change against the stated intent. Mismatched intent is the most expensive bug to catch later.

## 1. Correctness

- [ ] Mutable default arguments? `def f(x=[])` is a bug.
- [ ] Off-by-one in slicing, ranges, indices.
- [ ] Floating-point equality (`==` on floats). Use `math.isclose`.
- [ ] `is` vs `==`. `is` is only for `None`, `True`, `False`, sentinels.
- [ ] Iterating a collection while mutating it.
- [ ] Resource leaks: files/sockets/locks not in `with` blocks.
- [ ] Bare `except:` or `except Exception:` without action.
- [ ] `assert` for runtime validation (asserts are stripped with `-O`).
- [ ] Generators consumed twice.
- [ ] Race conditions in async or threaded code.
- [ ] Broken hash/eq invariant (objects equal but hash differently).

## 2. Type hints

- [ ] All public signatures hinted.
- [ ] No `Any` as a shortcut where a real type fits.
- [ ] Modern syntax: `list[int]`, `X | None` (Python 3.10+).
- [ ] Forward refs handled correctly (`from __future__ import annotations` or string quotes).
- [ ] `mypy --strict` (or project's level) passes on changed files.

## 3. Design

- [ ] Each function does one thing. Name reads without "and."
- [ ] No god objects: classes with too many responsibilities.
- [ ] Inheritance only for is-a, not for code reuse.
- [ ] No abstractions with one implementation (premature).
- [ ] Module imports flow one direction. No new circular imports.
- [ ] No new global mutable state.
- [ ] Dataclasses / pydantic models replacing dict-with-magic-keys.
- [ ] Functions ≤4 positional args (use keyword-only beyond that).

## 4. Pythonic

- [ ] Comprehensions over append-loops (when comprehension stays readable).
- [ ] `enumerate` / `zip` over manual indexing.
- [ ] `pathlib.Path` over `os.path` string ops.
- [ ] f-strings over `%` or `.format`.
- [ ] Context managers for cleanup (no manual try/finally where `with` works).
- [ ] `dict.get(k, default)` over `try/except KeyError`.

## 5. Errors

- [ ] Specific exception types, not `Exception`.
- [ ] Caught exceptions are handled, logged, or re-raised — not swallowed.
- [ ] `raise X from Y` to preserve cause when wrapping.
- [ ] Custom exceptions for domain errors.
- [ ] Error paths covered by tests.

## 6. Testing

- [ ] New public behavior has tests.
- [ ] Bug fixes have a regression test.
- [ ] Tests assert behavior, not implementation.
- [ ] Tests don't mock the system under test.
- [ ] Test names describe behavior.
- [ ] No `time.sleep` in tests; deterministic waits.
- [ ] No `xfail` / `skip` without a reason and (ideally) ticket.

### Smoke-test detector (BLOCKING)

For each test in the diff, identify the assertions and apply the mutation-test heuristic:

> If the SUT silently returned the wrong value (or did nothing), would this test fail?

If the answer is no, it is a smoke test. Common shapes:

- No `assert` at all (the test just calls the SUT).
- Only `assert result is not None` / `assert result is True` / `assert isinstance(result, X)` — these pass for almost any non-broken implementation.
- `pytest.raises(Exception)` (broad) — catches the test's own bugs as "passes."
- "Did not raise" tests with no positive assertion afterward.

A test whose mutation-test score is 0% is a smoke test by definition. Flag BLOCKING and route back to test-engineer.

## 7. Logging & observability

- [ ] Module-level logger, not `print`.
- [ ] No secrets / PII in logs.
- [ ] Log levels appropriate: `error` for bugs, `warning` for recoverable problems, `info` for ops events, `debug` for dev.
- [ ] Long operations have timing/progress info if relevant.

## 8. Security quick-pass

(Depth goes to security-auditor, but flag the obvious.)

- [ ] `subprocess` with `shell=True` and any non-literal input.
- [ ] SQL string-built (`f"SELECT ... {x}"`) instead of parameter binding.
- [ ] `pickle.loads`, `eval`, `exec`, `yaml.load` (use `safe_load`) on external data.
- [ ] Hardcoded secrets / API keys.
- [ ] HTTPS verification disabled (`verify=False`).
- [ ] Weak hashes (`md5`, `sha1`) for security purposes.
- [ ] `random` (not `secrets`) for tokens.

## 9. Performance (when relevant)

- [ ] No O(n²) where O(n) fits (nested loops over the same data).
- [ ] No string `+=` in a loop (use `"".join`).
- [ ] No unnecessary list materialization (`list(generator)` then iterating once).
- [ ] No DB query in a loop (N+1).
- [ ] No expensive work inside a hot path that could be cached.

## 10. Documentation

- [ ] Public functions/classes have docstrings stating contract.
- [ ] New public modules have a module docstring.
- [ ] No restating-the-signature docstrings ("amount: An amount").
- [ ] No "TODO" without a ticket.
- [ ] No commented-out code blocks.

### Comment–code drift (BLOCKING)

Every comment that names an action — "push enemies away from the spawn," "retry on failure," "cache for one minute" — must match what the code below it does. If the comment promises behavior the code doesn't deliver, that's a half-finished change masquerading as complete. Either fix the code or delete the comment. Do not let it ship.

## 10b. Domain numbers (MAJOR)

Hardcoded magic numbers in domain logic — timeouts, thresholds, multipliers, retry counts, tuning constants embedded in algorithms — should live in a `settings` module or a named module-level constant.

- [ ] No bare numeric literals in conditions like `if self._stuck_timer > 0.8:` — name it.
- [ ] No `* 1500`, `// 60`, `+ 4` in domain code without a `# unit` comment or a constant.
- [ ] Single-use literals where the call shape documents intent (`range(3)`) are fine.

The bar: would another reader know what this number *means* without reading the surrounding code?

## 11. Tooling

- [ ] Lint passes (`ruff check`).
- [ ] Format applied (`ruff format` or `black`).
- [ ] Type-check passes (`mypy` or `pyright`).
- [ ] Lockfile updated if dependencies changed.
- [ ] No `# noqa` / `# type: ignore` without a comment.

## Severity guide

- **BLOCKING** — must fix before merge: bugs, security, broken contract, missing test on new public API.
- **MAJOR** — should fix before merge: design issues, significant readability problems.
- **MINOR** — fix if you're already there: style nits, naming.
- **NOTE** — observation, not a request.

If everything is BLOCKING you're nitpicking. Most reviews have ≤2 BLOCKING items.

## Feedback format

```
[SEVERITY] path/to/file.py:LINE — short title

What's wrong: <one or two sentences>
Why it matters: <impact, when not obvious>
Suggested fix: <code snippet, ≤5 lines>
```

Be specific. Cite file and line. Show the fix shape, not the whole solution.
