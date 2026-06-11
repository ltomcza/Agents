---
name: style
description: PEP 8 + modern Python style standards — naming, formatting, imports, type hints, idioms. Apply when writing or editing any Python code. Also use when reviewing code for style.
---

Apply these standards to every Python file you write or edit.

## Naming

- `snake_case` for functions, variables, methods, modules.
- `PascalCase` for classes and type variables.
- `UPPER_SNAKE_CASE` for module-level constants.
- `_leading_underscore` for module-private; double underscore only for name mangling, never for "extra private."
- One letter only for short loop indices (`i`, `j`) and very short comprehension vars (`x` in a 1-line comp). Otherwise full words.
- No abbreviations unless the abbreviation is a domain term or already universal (`url`, `http`, `db`).
- Names describe *what*, not *type*. `users` not `user_list`. `is_active` not `active_flag`.

## Layout

- 4 spaces per indent. Never tabs. Never mixed.
- Line length: 100 chars (modern default with `ruff` / `black`). 79 only if the project mandates it.
- Two blank lines between top-level functions and classes; one between methods.
- One blank line to separate logical sections inside a function. Don't use them as a substitute for extracting a function.
- Files end with a single newline.

## Imports

- Three groups, separated by blank lines, in this order:
  1. Standard library
  2. Third-party
  3. Local / first-party
- Within each group, alphabetical, `import` before `from`.
- One import per line for `import x`. `from x import a, b, c` is fine if it stays on one line.
- No wildcard imports (`from x import *`) outside `__init__.py` re-exports.
- Absolute imports for first-party code. Relative imports (`from .util import x`) only for sibling modules in a package.
- `ruff`'s `I` rules handle ordering automatically — let the tool sort.

## Strings

- f-strings for formatting: `f"hello {name}"`. Never `%` or `.format()` in new code.
- Double quotes by default (matches `black` / `ruff format`).
- Triple-double for docstrings: `"""..."""`.
- Use `str.join` over `+=` in loops.

## Type hints

- All public functions, methods, class attributes have hints.
- Modern syntax (Python 3.10+):
  - `list[int]` not `List[int]`
  - `dict[str, int]` not `Dict[str, int]`
  - `X | None` not `Optional[X]`
  - `X | Y` not `Union[X, Y]`
- `Any` is a code smell. If you need it, leave a comment explaining why.
- `from __future__ import annotations` at the top of library code that needs to support older Pythons or wants string-style postponed evaluation.
- `typing.Protocol` for structural typing; ABCs only when you need runtime checks.
- `TypedDict` for dict-shaped data with known keys; better, use a dataclass.
- `Self` (Python 3.11+) for methods that return their own type.

## Idioms — prefer left over right

| Use | Avoid |
|---|---|
| `for i, x in enumerate(xs):` | `for i in range(len(xs)): x = xs[i]` |
| `for a, b in zip(xs, ys):` | index-paired loops |
| `if x:` / `if not x:` | `if len(x) > 0:` / `if x == None:` |
| `if x is None:` | `if x == None:` |
| comprehensions | append-loops, when comprehension stays readable |
| `dict.get(k, default)` | `try: dict[k] except KeyError: default` |
| `pathlib.Path` | `os.path` string ops |
| `with open(path) as f:` | `f = open(path); ... f.close()` |
| context managers | manual try/finally for cleanup |
| `dataclass` / `pydantic.BaseModel` | dicts with magic keys |
| `secrets.token_hex()` | `random.choice` for security |
| f-strings | `%`, `.format` |

## Functions

- One job per function. If you can't name it without "and," split.
- ≤30 lines is a guideline, not a rule. The line that matters is "can I read this without scrolling and understand it."
- ≤4 positional args. Beyond that, force keyword-only with `*`: `def f(a, b, *, opt1, opt2):`.
- Default args are immutable: `None`, numbers, strings, frozensets, tuples. Never `[]`, `{}`, `set()`.
- Return early. Guard clauses beat nested ifs.
- Either always return a value or always return `None`. Don't return a value on the happy path and fall off the end on the error path.

## Classes

- Inherit only for is-a. Use composition for has-a.
- Prefer `@dataclass(frozen=True)` for value objects. Pydantic for data crossing trust boundaries.
- `__slots__` for high-volume small objects (only if you measured memory).
- `@property` for cheap, side-effect-free attribute-like access. If it does I/O or is expensive, make it a method.
- `__repr__` on every non-trivial class. Make it eval-able when reasonable.

## Errors

- Raise specific exceptions. Define your own when stdlib doesn't fit.
- Catch the narrowest type that handles the case. `except Exception:` only at the top of a long-running loop with logging.
- `raise X from Y` to preserve cause when re-raising as a different type.
- Never `except: pass`. Either handle, log, or re-raise.
- `assert` is for invariants you'd accept removing in production. Use `raise` for input validation.

## Comments and docstrings

- Module docstring at the top of every module: 1–5 lines on what's in here.
- Public functions, classes, public methods: docstring stating contract (Google or NumPy style — match project).
- Inline comments for *why*, not *what*. Code already says what.
- No "TODO" without a ticket reference.
- Delete commented-out code. Git remembers.

## Concurrency

- `asyncio` for I/O concurrency. Don't mix sync blocking calls inside async (use `run_in_executor` if you must).
- `concurrent.futures.ProcessPoolExecutor` for CPU-bound parallelism.
- Threads only for blocking C extensions. The GIL doesn't make them faster for Python work.

## Tools

These are the formatter and linter rules. Run them; don't argue with them.

```toml
[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP", "C4", "SIM", "RUF", "N"]
```

- `E`/`W`/`F` — pycodestyle / pyflakes basics
- `I` — import order
- `B` — bugbear (real bugs)
- `UP` — pyupgrade (modern syntax)
- `C4` — comprehension simplifications
- `SIM` — simplifications
- `RUF` — ruff-specific
- `N` — naming conventions

If `ruff` flags something, fix it. Don't `# noqa` without a comment explaining why.
