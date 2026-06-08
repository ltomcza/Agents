---
name: python-refactoring
description: Behavior-preserving refactoring patterns for Python — extract function, replace conditional with guard clauses, extract module, modernize idioms. Apply when restructuring existing code without changing behavior.
---

The contract: tests pass before and after. Every refactoring is one named pattern. Verify with the test suite at every step.

## Preconditions

1. Test suite covers the code you're touching. If not, add characterization tests first.
2. Working tree is clean.
3. You have a stated reason — duplication, complexity, a planned change needing the ground prepared.

## Patterns — eliminate duplication

### Extract Function

**Smell:** the same 5–10 lines appear in three places.

**Steps:**
1. Identify the shared chunk and what varies between sites.
2. Name the chunk by what it does (`validate_payload`, `format_address`).
3. Extract with the variable bits as parameters.
4. Replace each site with the call.
5. Run tests.

**Trap:** if the "shared" code has subtle differences at each site, those differences are real behavior. Extract only the part that's truly identical.

### Extract Module

**Smell:** a file has grown to 500+ lines covering several topics. `utils.py` with 30 unrelated helpers.

**Steps:**
1. Group the functions/classes by what they do.
2. Move each group to a new module.
3. Update imports. Run tests after each module move.

### Replace Magic Number/String with Named Constant

```python
# before
timeout = 30
status = "active"

# after
DEFAULT_TIMEOUT_SECONDS = 30
STATUS_ACTIVE = "active"

timeout = DEFAULT_TIMEOUT_SECONDS
```

For sets of related strings, use `enum.StrEnum` (3.11+) or `enum.Enum`.

## Patterns — reduce complexity

### Replace Conditional with Guard Clauses

**Before:**
```python
def process(order):
    if order.is_valid:
        if order.has_inventory:
            if not order.is_paid:
                charge(order)
                return ship(order)
            return ship(order)
        raise OutOfStock()
    raise InvalidOrder()
```

**After:**
```python
def process(order):
    if not order.is_valid:
        raise InvalidOrder()
    if not order.has_inventory:
        raise OutOfStock()
    if not order.is_paid:
        charge(order)
    return ship(order)
```

The happy path is flat. Errors leave early.

### Replace Flag Argument with Separate Functions

**Before:**
```python
def fetch(url, parse_json=False):
    response = http.get(url)
    if parse_json:
        return response.json()
    return response.text
```

**After:**
```python
def fetch_text(url): return http.get(url).text
def fetch_json(url): return http.get(url).json()
```

Callers read better. No conditional inside the function.

### Replace Primitive Obsession with a Type

**Before:**
```python
def transfer(from_account: tuple[str, str, int], to_account: tuple[str, str, int], amount: int):
    ...
```

**After:**
```python
@dataclass(frozen=True)
class Account:
    owner: str
    institution: str
    balance: int

def transfer(from_: Account, to: Account, amount: int): ...
```

Three call sites passing the same tuple shape = a type wants to exist.

### Split God Function

**Smell:** function ≥30 lines, with comment headers like `# validate`, `# transform`, `# save`.

**Steps:**
1. Each comment-headed section becomes a private function.
2. The original becomes a thin orchestrator that reads top-to-bottom like the comments did.

```python
def import_user(payload):
    data = _validate(payload)
    user = _transform(data)
    return _save(user)
```

## Patterns — Pythonic upgrades

Apply only when they don't reduce clarity.

| Before | After |
|---|---|
| `for i in range(len(xs)): ... xs[i] ...` | `for i, x in enumerate(xs): ... x ...` |
| `result = []` + `result.append(f(x))` for each x | `result = [f(x) for x in xs]` |
| `result = {}` + `result[k] = v` loop | `result = {k: v for k, v in pairs}` |
| `if x in d: return d[x]` else default | `return d.get(x, default)` |
| Manual `try/finally` close | `with` and a context manager |
| `f = open(p); ... f.close()` | `with open(p) as f: ...` |
| `os.path.join` chain | `pathlib.Path` operations |
| `"%s" % x` / `"{}".format(x)` | `f"{x}"` |
| `class Foo: ...` with only `__init__` and one method | function |

## Patterns — modernize for current Python

If `requires-python = ">=3.10"`:

| Before | After |
|---|---|
| `from typing import List, Dict, Optional` | drop the imports |
| `List[int]` | `list[int]` |
| `Optional[X]` | `X \| None` |
| `Union[X, Y]` | `X \| Y` |
| `collections.OrderedDict()` | `dict()` (3.7+ preserves order) |
| `from typing import Tuple` | `tuple` |

If `>=3.12`:
- `type Alias = ...` syntax for type aliases.
- Generic syntax: `def f[T](x: T) -> T:` instead of `TypeVar`.

## Workflow

1. State the smell: "lines 40–80 of `service.py` and 110–150 of `api.py` duplicate validation."
2. State the refactoring: "Extract Function → `validate_payload` in `validation.py`."
3. Run tests. Green.
4. Apply one pattern.
5. Run tests. Green. If red, revert.
6. Repeat.
7. Run full suite + linter before reporting done.

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

- `ruff check --fix` for mechanical fixes.
- `ruff check --select UP` (pyupgrade rules) modernizes idioms.
- `pytest` + coverage to verify behavior preserved.
- Your IDE's "rename symbol" / "extract function" — let it do the mechanical work.
