---
name: async-concurrency
description: Async and concurrency in Python — asyncio, TaskGroup, timeouts, cancellation, structured concurrency, synchronization primitives, mixing sync+async, contextvars, common pitfalls. Apply when writing or reviewing code that uses async/await, threads, or processes.
---

Async is for I/O-bound concurrency. Threads are for blocking C extensions. Processes are for CPU-bound parallelism. Get the dimension right before reaching for a primitive.

## Decision tree

| Workload | Reach for |
|---|---|
| Many concurrent I/O calls (HTTP, DB, files) | `asyncio` + async libraries |
| Blocking C-extension call (`PIL`, legacy DB driver) you can't replace | Thread via `asyncio.to_thread` / `ThreadPoolExecutor` |
| CPU-bound numerical work | `ProcessPoolExecutor` or vectorize with numpy/polars |
| Single blocking call inside an async app | `asyncio.to_thread(func, *args)` |
| Mixed sync + async codebase you can't unify | Pick one as primary; bridge with `asyncio.run_in_executor` or `anyio` |

The GIL doesn't make threads faster for Python work. If profiling shows CPU as the bottleneck, threads are the wrong tool.

## Entry points

```python
import asyncio

async def main() -> None:
    await do_work()

if __name__ == "__main__":
    asyncio.run(main())
```

- **`asyncio.run(...)` once per process.** It creates the loop, runs the coroutine, closes the loop. Don't call `get_event_loop()` in new code.
- **`asyncio.run(main(), debug=True)`** during development — warns about slow callbacks, never-awaited coroutines, missing cancellation handling.

## Structured concurrency — TaskGroup (3.11+)

```python
async def fan_out(urls: list[str]) -> list[Response]:
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch(u)) for u in urls]
    return [t.result() for t in tasks]
```

- **Use `TaskGroup` over `asyncio.gather`** in new code (3.11+). It guarantees:
  - All tasks run to completion or are cancelled together on failure.
  - Exceptions become `ExceptionGroup` — no silent loss.
  - No orphaned tasks if the parent exits.
- **`gather(return_exceptions=True)`** is the old way. It collects exceptions but doesn't cancel siblings. Use only when you genuinely need independent best-effort fan-out.
- **Never `gather(...)` without awaiting it.** A coroutine left unattached fires a `RuntimeWarning: coroutine ... was never awaited` and silently does nothing.

## Timeouts — `asyncio.timeout` (3.11+)

```python
async def fetch_with_deadline(url: str) -> Response:
    async with asyncio.timeout(5.0):
        return await fetch(url)
```

- **`asyncio.timeout(...)`** wraps a block. On expiry, raises `TimeoutError` (the stdlib one, since 3.11; same as `asyncio.TimeoutError`).
- **`asyncio.timeout_at(when)`** for absolute deadlines — better for nested timeouts that share a budget.
- The old `asyncio.wait_for(coro, timeout)` still works but is awkward inside a `TaskGroup`. Prefer `timeout(...)`.
- Always set timeouts on outbound I/O. "It just hung" is the single most common async failure.

## Cancellation — the rules

1. A task is cancelled by sending it a `CancelledError`. **`CancelledError` is not an `Exception`** in 3.8+; it's a `BaseException`. Don't catch `Exception` thinking it includes cancellation — it doesn't.
2. If you must catch it (cleanup), re-raise: `except CancelledError: cleanup(); raise`.
3. To make a critical section uncancellable: `async with asyncio.shield(coro): ...`.
4. Cancellation propagates through `await`. If you're between `await`s in pure Python, you're not interruptible — keep work between awaits short.

```python
async def upload(payload: bytes) -> None:
    try:
        await client.upload(payload)
    except asyncio.CancelledError:
        logger.warning("upload cancelled, undoing local state")
        await rollback()
        raise
```

## Synchronization primitives

| Primitive | When |
|---|---|
| `asyncio.Lock` | Mutual exclusion in a single event loop. |
| `asyncio.Semaphore(n)` | Limit concurrency (e.g., max 10 concurrent HTTP calls). |
| `asyncio.Event` | One-shot "thing happened" signaling. |
| `asyncio.Condition` | Wait-until-predicate (rare; usually a queue is what you want). |
| `asyncio.Queue` | Producer/consumer hand-off. The right primitive 80% of the time. |
| `contextvars.ContextVar` | Per-task state (request ID, user) that propagates across `await`. |

```python
sem = asyncio.Semaphore(10)

async def bounded_fetch(url: str) -> Response:
    async with sem:
        return await fetch(url)
```

- These work across coroutines in **one** event loop. They do **not** synchronize across threads or processes — use `threading.Lock` or a real broker for that.

## Mixing sync and async

### Blocking call inside async

```python
def cpu_blocking(data: bytes) -> bytes:
    return heavy_lib.process(data)  # synchronous, releases GIL? maybe not

async def handler(req: Request) -> Response:
    result = await asyncio.to_thread(cpu_blocking, req.body)  # off the loop
    return Response(result)
```

- **`asyncio.to_thread(fn, *args)`** (3.9+) runs `fn` in the default executor and returns an awaitable. Don't block the loop.
- If you don't, every other coroutine on the loop stalls. The hardest async bugs are "the service freezes for 800ms periodically" — a blocking call in the hot path.

### Calling async from sync

```python
result = asyncio.run(my_async_fn(arg))  # creates a fresh loop each call — heavy
```

- Acceptable in CLI entry points. Bad inside a long-running sync server (each call spins up + tears down a loop, no connection pooling).
- For a real "sync wraps async" bridge, use `anyio.from_thread.run(my_async_fn, arg)` or run a dedicated background loop with `asyncio.run_coroutine_threadsafe`.

### `contextvars` propagate across await; thread-locals don't

```python
import contextvars

request_id: contextvars.ContextVar[str] = contextvars.ContextVar("request_id")

async def handle(req):
    token = request_id.set(req.id)
    try:
        await do_work()  # request_id is visible inside; survives create_task
    finally:
        request_id.reset(token)
```

- Use `ContextVar` for per-request state in async code. `threading.local` will *not* work across `await`.
- `asyncio.create_task(coro)` copies the current context — children see the parent's vars.

## Async context managers & iterators

```python
class AsyncFile:
    async def __aenter__(self) -> "AsyncFile": ...
    async def __aexit__(self, *exc) -> None: ...

    def __aiter__(self) -> AsyncIterator[str]: ...
    async def __anext__(self) -> str: ...
```

- `async with` and `async for` are the async equivalents of `with` and `for`.
- Prefer `contextlib.asynccontextmanager` over hand-writing `__aenter__/__aexit__`:
  ```python
  from contextlib import asynccontextmanager

  @asynccontextmanager
  async def session():
      s = await Session.open()
      try:
          yield s
      finally:
          await s.close()
  ```

## Async libraries to know

| Need | Library |
|---|---|
| HTTP client | `httpx.AsyncClient` |
| Postgres | `asyncpg` (driver) or `sqlalchemy[asyncio]` + `asyncpg` |
| SQLite | `aiosqlite` |
| Redis | `redis.asyncio` |
| Kafka | `aiokafka` |
| File I/O | `aiofiles` (modest win; OS file I/O is fast) |
| DNS / sockets | stdlib `asyncio` |
| WebSocket | `websockets` |
| HTTP server | `uvicorn`/`hypercorn` running `fastapi` / `starlette` / `litestar` |

If a library is synchronous and blocks, wrap with `asyncio.to_thread` — don't fake an async interface around blocking calls.

## anyio / trio — alternatives

`anyio` provides a portable structured-concurrency API that runs on either asyncio or trio. If you're writing a library that wants to support both, target `anyio`. For application code, plain asyncio is fine in 2026 — the structured-concurrency primitives are now in stdlib.

`trio` pioneered structured concurrency in Python and remains excellent for code that prioritizes correctness over ecosystem breadth.

## Common pitfalls

### Missing `await`

```python
# Bug: coroutine created and dropped — never runs.
fetch(url)

# Bug: returning the coroutine, not its result.
def handler(req):
    return fetch(req.url)  # returns a coroutine object, not a Response
```

`python -W error` and `asyncio.run(main(), debug=True)` will catch most of these as `RuntimeWarning: coroutine was never awaited`. Make warnings errors in development.

### Blocking the event loop

- `time.sleep(1)` in async code → freezes the entire loop. Use `asyncio.sleep(1)`.
- Heavy CPU work (parsing huge JSON, image processing) → `asyncio.to_thread` or `ProcessPoolExecutor`.
- Synchronous DB calls inside async handlers → wrap in executor or switch to async driver.

### Fire-and-forget tasks

```python
asyncio.create_task(background_work())  # no reference — task may be GC'd!
```

`asyncio.create_task` returns a `Task`. If nothing holds a reference, the GC can collect it, cancelling mid-execution. Either:

```python
self._tasks: set[asyncio.Task] = set()

task = asyncio.create_task(background_work())
self._tasks.add(task)
task.add_done_callback(self._tasks.discard)
```

…or use a `TaskGroup`. Don't fire-and-forget without retention.

### Exception swallowing in gather

```python
results = await asyncio.gather(*coros, return_exceptions=True)
# results contains exceptions — if you don't inspect them, they vanish silently.
```

Either iterate and re-raise selectively, or switch to `TaskGroup`, which raises `ExceptionGroup`.

### Sync I/O inside async tests

`pytest-asyncio` runs the event loop, but a forgotten `time.sleep` or a sync DB call inside the test stalls real time. Tests pass but the production code has the same hidden block.

### `asyncio.wait` vs `asyncio.gather` vs `TaskGroup`

- `gather(*coros)` — wait for all, propagate first exception.
- `gather(*coros, return_exceptions=True)` — wait for all, collect exceptions.
- `wait(tasks, return_when=...)` — flexible; rarely what you want.
- `TaskGroup` — wait for all, cancel siblings on exception, gather into `ExceptionGroup`. Default choice (3.11+).

## Testing async code

```python
import pytest

@pytest.mark.asyncio
async def test_fetch_returns_payload(respx_mock):
    respx_mock.get("https://api/x").respond(json={"id": 1})
    result = await fetch("https://api/x")
    assert result.id == 1
```

- `pytest-asyncio` with `asyncio_mode = "auto"` in `pyproject.toml` so every `async def test_*` is collected.
- Mock at the boundary: `respx` for `httpx`, `aioresponses` for `aiohttp`.
- **Don't `time.sleep`** in tests — use a fake clock (`freezegun` or `pytest-freezer`) and `asyncio.sleep` controllable via `asyncio.get_event_loop().slow_callback_duration`.
- For race-condition tests, drive the loop manually with `asyncio.wait_for(...)` and assertions on event ordering.

## Debugging

- `asyncio.run(main(), debug=True)` — warnings for slow callbacks, never-awaited coroutines, blocking calls.
- `PYTHONASYNCIODEBUG=1` env var — same, for default loop.
- `asyncio.current_task()` to label/inspect in logs.
- `asyncio.all_tasks()` to dump every live task at a checkpoint.
- `py-spy dump --pid <pid>` for a stack snapshot of every coroutine in a running process.

## Anti-patterns

- **`async def` functions that don't `await` anything.** That's a sync function with extra steps — just `def` it.
- **`asyncio.sleep(0)` to "yield" control.** Usually a hack around a missing primitive. Find the right one.
- **`while True: await asyncio.sleep(0.01)` polling loops.** Wait on an `Event` or `Queue` instead.
- **Catching `BaseException` instead of `Exception`** — swallows `CancelledError`, `KeyboardInterrupt`, `SystemExit`. Catch `Exception` (and re-raise `CancelledError` if you must catch it).
- **Spawning unbounded tasks from a webhook** — open file descriptors, sockets, memory. Use a `Semaphore` or a queue.
- **Running async tests with `loop.run_until_complete(coro)`** — `pytest-asyncio` handles the loop; don't fight it.
- **Mixing `requests` and `httpx.AsyncClient`** — every `requests.get` blocks your loop. Use the async client everywhere.

## Quick reference

```python
# Bounded concurrency
sem = asyncio.Semaphore(20)
async def bounded(coro):
    async with sem: return await coro

# Timeout + group
async with asyncio.timeout(10):
    async with asyncio.TaskGroup() as tg:
        for u in urls:
            tg.create_task(fetch(u))

# Blocking call in async
result = await asyncio.to_thread(blocking_fn, *args)

# Background task with retention
self._bg.add(t := asyncio.create_task(work()))
t.add_done_callback(self._bg.discard)

# Per-request context
token = ctx_var.set(value)
try:
    await handle()
finally:
    ctx_var.reset(token)
```
