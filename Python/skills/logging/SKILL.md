---
name: logging
description: Logging best practices for Python — structured logging, log levels, contextual logging via contextvars/LoggerAdapter, sensitive-data scrubbing, async-safe handlers, configuration via dictConfig. Apply when adding logging to new code, reviewing log output, or debugging missing/noisy logs.
---

Logging is the only debugger you have in production. Get it right once, then forget about it.

## 1. Per-module loggers

Every module gets its own logger. Never call `logging.info` directly on the root logger.

```python
import logging

logger = logging.getLogger(__name__)

def transfer(account, amount):
    logger.info("transfer.start", extra={"account_id": account.id, "amount": str(amount)})
```

- `__name__` gives you a hierarchy (`myapp.payments.transfer`) which lets users filter by subsystem.
- Library code **never** calls `logging.basicConfig`. Configuration belongs to the application.
- Inside library code, attach a `NullHandler` so `No handlers could be found` warnings don't appear:
  ```python
  logging.getLogger(__name__).addHandler(logging.NullHandler())
  ```

## 2. Levels — when to use which

| Level | Meaning | Example |
|---|---|---|
| `DEBUG` | Developer-only diagnostic noise. | "computed angle=0.42 from input=(3, 5)" |
| `INFO` | State transitions an operator cares about. | "user logged in", "job completed" |
| `WARNING` | Something is degraded but functional. Auto-recovered errors. | "retry 1/3 succeeded after timeout" |
| `ERROR` | A request/operation failed. Caller didn't get what they asked for. | "payment declined: insufficient funds" |
| `CRITICAL` | Service-wide outage; immediate page. | "DB connection pool exhausted" |

Default production level: `INFO`. Don't ship `DEBUG` to production — it floods storage.

## 3. Structured logging (JSON, key-value)

Plain text logs require regex to query. Structured logs let your log aggregator filter by field.

Use `python-json-logger` for stdlib, or `structlog` for richer ergonomics.

```python
# stdlib + python-json-logger
import logging
from pythonjsonlogger import jsonlogger

handler = logging.StreamHandler()
handler.setFormatter(jsonlogger.JsonFormatter("%(asctime)s %(name)s %(levelname)s %(message)s"))
logging.getLogger().addHandler(handler)

logger = logging.getLogger(__name__)
logger.info("transfer.complete", extra={"account_id": "acc_123", "amount": "10.00", "duration_ms": 42})
```

Output: `{"asctime": "...", "name": "myapp.payments", "levelname": "INFO", "message": "transfer.complete", "account_id": "acc_123", "amount": "10.00", "duration_ms": 42}`.

Conventions:

- `message` is an event name (snake_case), not a sentence. `"transfer.complete"` not `"Transfer for account acc_123 completed in 42ms"`.
- All variable data goes in `extra=`, never interpolated into the message string.
- Stable keys across modules: `request_id`, `user_id`, `duration_ms`, `error_type`. Document them once.

## 4. Lazy interpolation in hot paths

If you must use the `%`-style format (no JSON formatter, hot path), pass args separately so interpolation only runs when the level is enabled:

```python
# Good — interpolation deferred; cheap when DEBUG is disabled
logger.debug("computed angle=%s for input=%s", angle, point)

# Bad — f-string runs even when DEBUG is filtered out
logger.debug(f"computed angle={angle} for input={point}")
```

For non-hot paths, f-strings are fine. The rule matters only for high-frequency loops.

## 5. Contextual logging — request/correlation IDs

In a server, every log line should carry the request ID. Two patterns:

### `LoggerAdapter` (simple, sync)

```python
class RequestAdapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        kwargs.setdefault("extra", {}).update(self.extra)
        return msg, kwargs

def handle_request(req):
    log = RequestAdapter(logger, {"request_id": req.id, "user_id": req.user_id})
    log.info("request.start")
    ...
    log.info("request.complete")
```

### `contextvars` + filter (works with async)

```python
import contextvars

request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar("request_id", default=None)

class ContextFilter(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_var.get()
        return True

logging.getLogger().addFilter(ContextFilter())

# Set per-request in middleware:
async def middleware(request, call_next):
    token = request_id_var.set(request.headers.get("X-Request-ID", new_id()))
    try:
        return await call_next(request)
    finally:
        request_id_var.reset(token)
```

`contextvars` propagate through `await` and `asyncio.create_task`; thread-locals do not.

## 6. Async-safe handlers

`logging` handlers run in the calling thread/coroutine. Slow handlers (HTTP, network syslog) block the event loop. Wrap them with a `QueueHandler` + `QueueListener`:

```python
import logging.handlers
import queue

log_queue: queue.Queue = queue.Queue(-1)
queue_handler = logging.handlers.QueueHandler(log_queue)
slow_handler = HTTPHandler(...)  # the actual destination

listener = logging.handlers.QueueListener(log_queue, slow_handler)
listener.start()  # background thread drains the queue

logging.getLogger().addHandler(queue_handler)
```

The application logs to the in-memory queue (fast); the listener thread ships records to the slow destination.

## 7. Sensitive-data scrubbing

Never log secrets, tokens, full PANs, or PII. Two layers:

- **At the call site:** redact before logging. Build helpers (`safe_email("a@b.com") -> "a***@b.com"`).
- **As a safety net:** add a filter that scrubs known-sensitive keys.

```python
SENSITIVE_KEYS = {"password", "token", "authorization", "ssn", "credit_card"}

class RedactFilter(logging.Filter):
    def filter(self, record):
        if isinstance(record.args, dict):
            record.args = {k: "***" if k.lower() in SENSITIVE_KEYS else v for k, v in record.args.items()}
        return True
```

A filter is a backstop — don't rely on it as the primary defense.

## 8. `logger.exception` — always inside `except`

```python
# Good
try:
    do_thing()
except IntegrityError:
    logger.exception("transfer.failed")  # auto-attaches traceback
    raise

# Bad — loses the traceback
except IntegrityError as e:
    logger.error("transfer.failed: %s", e)
```

`logger.exception` adds `exc_info=True` automatically; only call it inside an `except` block.

## 9. Configuration with `dictConfig`

Configure logging once at application startup, from a TOML or YAML file — never hardcoded across modules.

```python
# logging_config.py
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "filters": {
        "context": {"()": "myapp.logging.ContextFilter"},
        "redact": {"()": "myapp.logging.RedactFilter"},
    },
    "formatters": {
        "json": {"()": "pythonjsonlogger.jsonlogger.JsonFormatter",
                 "format": "%(asctime)s %(name)s %(levelname)s %(message)s %(request_id)s"},
    },
    "handlers": {
        "stdout": {"class": "logging.StreamHandler", "formatter": "json",
                   "filters": ["context", "redact"]},
    },
    "root": {"level": "INFO", "handlers": ["stdout"]},
    "loggers": {
        "myapp": {"level": "INFO", "propagate": True},
        "uvicorn.access": {"level": "WARNING", "propagate": True},
    },
}

# main.py
import logging.config
from .logging_config import LOGGING

logging.config.dictConfig(LOGGING)
```

For 12-factor apps, allow level overrides via env var:

```python
import os
LOGGING["root"]["level"] = os.environ.get("LOG_LEVEL", "INFO")
```

## 10. Anti-patterns

- `print()` in production code. It writes to stdout without level, structure, or context.
- `logger.error(traceback.format_exc())` instead of `logger.exception()`.
- `except Exception: logger.error(e); pass` — swallowing exceptions and *also* hiding them under a useless message.
- `logging.basicConfig()` inside library code or imported modules — clobbers the application's config.
- F-string interpolation in hot-path debug logs (computes the string even when DEBUG is filtered).
- Logging objects with huge `__repr__` (full DB rows, request bodies). Log the ID, not the body.
- Per-request `logging.getLogger(...)` calls — cache the logger at module top level.
- Sending logs straight to a slow network handler from the request path (blocks the event loop).
