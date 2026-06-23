---
name: debugging
description: Systematic debugging for Python — repro construction, traceback reading, common failure modes, pdb/breakpoint, logging, profiling. Apply when investigating failures, regressions, or wrong outputs.
---

Diagnosis before fix. Repro before theory. One hypothesis at a time.

## The procedure

1. **Get the symptom precisely.** Exact error, exact command, exact input. If it's "it's slow," what input, what threshold, what's the current measurement?
2. **Reproduce locally.** No repro = no diagnosis. Write a 5-line script if you have to.
3. **Read the traceback bottom-up.** Last line names the exception; frames above show the path. Don't skip.
4. **Bisect.** Disable code paths until the symptom vanishes. Add prints/logging at boundaries. `git bisect` for regressions with a known good commit.
5. **Form one hypothesis. Test it.** Don't change two things at once.
6. **Find the root cause, not the symptom.** The exception fires in `f()`, but `g()` produced the bad value. Trace it back.

## Easy wins to check first

- **Stale cache.** `find . -name __pycache__ -exec rm -rf {} +` (Linux/macOS) or remove `__pycache__` directories on Windows.
- **Wrong virtual env.** `which python` / `where python`. `python --version`.
- **Wrong dependencies.** `pip list` / `uv pip list`. Lockfile mismatch?
- **Recently changed files.** `git log --since="1 week ago" --stat`.
- **Environment variable missing.** `printenv | grep MYAPP_` / `Get-ChildItem env:`.

## Reading tracebacks

```
Traceback (most recent call last):
  File "app.py", line 42, in main
    result = process(payload)
  File "app.py", line 28, in process
    user = users[payload["id"]]
KeyError: 'id'
```

- Last line: type and message.
- Bottom frame: where the exception was raised.
- Frames above: the call chain. Top frame: where execution started.
- For chained exceptions (`raise X from Y`), `During handling of the above exception, another exception occurred` separates them. Both are real.

## Common Python failure modes

| Symptom | Likely cause |
|---|---|
| `'NoneType' object has no attribute X` | Function silently returned `None` on an unhandled branch. Check return statements. |
| `UnboundLocalError` | Variable assigned in a conditional, used unconditionally. Or `global`/`nonlocal` missing. |
| Function returns wrong value second time it's called | Mutable default argument. `def f(x=[])`. |
| Lambdas in loop all behave the same | Late binding closure. Use `lambda x=x:` or a comprehension. |
| `KeyError` on a key that's "in" the dict | `__hash__` and `__eq__` mismatch on the key class. |
| Iterating once works, twice gives nothing | Generator exhausted. Materialize with `list()` if you need re-iteration. |
| `UnicodeDecodeError` | Default encoding. Always `open(..., encoding="utf-8")`. |
| Path joins look wrong on Windows | `Path` + relative `Path` works; `Path` + string sometimes doesn't. Use `Path` for both. |
| Tests pass alone, fail in suite | Shared global state, fixture scope wrong, monkeypatch leaking. |
| Import fails with "X cannot be imported" | Circular import. Or import-time side effect crashed the module. |
| Memory grows over time | `lru_cache` on bound methods (caches `self`). Logger holding references. Closures capturing big state. |
| `0.1 + 0.2 != 0.3` | Floats. Use `math.isclose` or `Decimal`. |
| Async function "doesn't run" | Missing `await`. Coroutine created and dropped. |
| `RuntimeError: There is no current event loop` | Calling async from sync. Use `asyncio.run`. |
| Random test flake | Time-dependent test, ordering assumption, network race. |

## Debugging tools

### `breakpoint()`

```python
def process(x: int) -> int:
    breakpoint()  # drops into pdb here
    return x + 1
```

In pdb: `n` next, `s` step, `c` continue, `l` list, `p var` print, `pp var` pretty-print, `w` where (stack), `u`/`d` up/down stack frame, `b file:line` breakpoint, `q` quit.

Set `PYTHONBREAKPOINT=ipdb.set_trace` for nicer pdb (if `ipdb` is installed). `PYTHONBREAKPOINT=0` disables all.

### pytest debugging

```bash
pytest -x --tb=short        # stop at first fail, short traceback
pytest -k name              # run only tests matching name
pytest --pdb                # drop into pdb at first failure
pytest --pdb --maxfail=1    # combined
pytest -s                   # don't capture stdout (see your prints)
pytest --lf                 # last failed only
pytest --ff                 # failed first, then the rest
```

### Logging

```python
import logging
logging.basicConfig(level=logging.DEBUG, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

log.debug("payload=%r user=%r", payload, user)
```

Use `%`-style format with logging — args are only formatted if the level fires. Beats f-strings for hot paths.

### Dev mode and warnings

```bash
python -X dev script.py     # enables ResourceWarning, etc.
python -W error script.py   # warnings become exceptions
python -W error::DeprecationWarning script.py  # only this kind
```

### Performance

- `python -m cProfile -o prof.out script.py` then `snakeviz prof.out` for a flamegraph.
- `pyinstrument script.py` for a sampling profiler with cleaner output.
- `python -X importtime script.py` to find slow imports.
- `tracemalloc` for "where is memory growing":
  ```python
  import tracemalloc
  tracemalloc.start()
  # ... run code ...
  snapshot = tracemalloc.take_snapshot()
  for stat in snapshot.statistics("lineno")[:10]:
      print(stat)
  ```

### Memory and reference issues

- `gc.get_referrers(obj)` to see what holds an object.
- `objgraph.show_growth()` (third-party) to track leaks across iterations.
- `weakref.ref` for caches that shouldn't pin objects.

### Asyncio specific

- `asyncio.run(coro, debug=True)` enables warnings about slow callbacks, never-awaited coroutines.
- `PYTHONASYNCIODEBUG=1` env var has the same effect for the default loop.

## Bisecting a regression

```bash
git bisect start
git bisect bad                   # current commit is broken
git bisect good <known-good-sha>
# git checks out a midpoint; you test:
pytest tests/test_thing.py
git bisect good   # or bad
# repeat until git names the offending commit
git bisect reset
```

Run an automated bisect with a script:
```bash
git bisect run pytest tests/test_thing.py -k test_repro
```

## What good diagnosis looks like

```
Symptom: process() returns None instead of a User when payload has no 'email'.

Repro:
    process({"id": 1, "name": "x"})  # returns None

Root cause:
- File: app/users.py:42
- _build_user falls through without returning when 'email' is missing.
- The early-return on line 38 should be unconditional, but is gated by `if email_required`.

Evidence:
- Added `print(email_required)` before line 38: prints False on the failing input.
- The flag was introduced in commit a1b2c3 (refactor on 2026-04-12), which moved the email check behind a feature flag that defaults to False.

Fix direction:
- _build_user should always return a User, even when optional fields are missing.
- The flag's default is wrong, but that may be intentional — confirm with the author of a1b2c3.
```

That's a diagnosis. "Probably None somewhere" is not.
