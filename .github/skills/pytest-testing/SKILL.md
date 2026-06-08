---
name: pytest-testing
description: pytest patterns, fixtures, parametrization, mocking, async testing, coverage strategy. Apply when writing tests or designing a test plan.
---

Use pytest as the testing framework. Standard plugins: `pytest-cov`, `pytest-mock`, `pytest-xdist`, `pytest-asyncio`, `hypothesis`.

## File and naming layout

```
tests/
├── conftest.py          # shared fixtures
├── unit/
│   └── test_<module>.py
├── integration/
│   └── test_<flow>.py
└── e2e/                 # if you have these
```

- Test files: `test_*.py`.
- Test functions: `test_*`. Name = behavior: `test_withdraw_raises_when_balance_insufficient`.
- Test classes: `class Test<Unit>` only when fixtures are class-scoped or you really want grouping.
- Mirror source layout: `src/myapp/payments.py` → `tests/unit/test_payments.py`.

## Anatomy of a good test

```python
def test_withdraw_debits_account_when_funds_sufficient(account):
    receipt = account.withdraw(Decimal("10.00"))

    assert account.balance == Decimal("90.00")
    assert receipt.amount == Decimal("10.00")
```

- Arrange / Act / Assert with a blank line between.
- One behavior per test. Multiple `assert` lines verifying the same behavior is fine.
- No `print`, no commented-out code, no "TODO: also test X" — write the test or open a ticket.

## Fixtures

```python
import pytest

@pytest.fixture
def account():
    return Account(balance=Decimal("100.00"))

@pytest.fixture
def account_factory():
    def _make(**kwargs):
        defaults = {"balance": Decimal("100.00")}
        return Account(**{**defaults, **kwargs})
    return _make
```

- Default scope is `function`. Use `module` or `session` only when setup is genuinely expensive (DB schema, file generation).
- Factory fixtures (return a function) when tests need parameterized objects.
- `yield` for teardown:
  ```python
  @pytest.fixture
  def temp_db():
      db = create_db()
      yield db
      db.close()
  ```
- Put shared fixtures in `conftest.py` at the appropriate level. Closer to the tests = better.
- Built-in fixtures you reach for: `tmp_path`, `monkeypatch`, `capsys`, `caplog`, `mocker` (from pytest-mock).

## Parametrize

```python
@pytest.mark.parametrize(
    ("balance", "amount", "expected"),
    [
        (Decimal("100"), Decimal("10"), Decimal("90")),
        (Decimal("10"),  Decimal("10"), Decimal("0")),
        pytest.param(Decimal("0"), Decimal("0"), Decimal("0"), id="zero_amount_no_op"),
    ],
)
def test_withdraw_balance(balance, amount, expected):
    account = Account(balance=balance)
    account.withdraw(amount)
    assert account.balance == expected
```

- Use `pytest.param(..., id="...")` to give meaningful test IDs for non-trivial cases.
- Mark expected failures: `pytest.param(..., marks=pytest.mark.xfail(reason="..."))`.
- Stack `@parametrize` for combinatorial cases (one per axis).

## Mocking — pytest-mock's `mocker`

```python
def test_send_email_calls_smtp(mocker):
    smtp = mocker.patch("myapp.notifications.smtplib.SMTP")
    send_email("a@b.com", "hi")
    smtp.return_value.__enter__.return_value.send_message.assert_called_once()
```

- Patch where the name is *used*, not where it's defined.
- Mock at the boundary. Don't mock the system under test.
- Prefer real objects: a real `dict` beats a `MagicMock` for config.
- `mocker.spy(obj, "method")` for "did it get called" without replacing behavior.
- `mocker.MagicMock(spec=Class)` when you want the mock to have the same attributes — catches typos.

## Mark expected exceptions

```python
def test_withdraw_raises_when_overdraft():
    account = Account(balance=Decimal("0"))
    with pytest.raises(InsufficientFunds, match="balance is 0"):
        account.withdraw(Decimal("1"))
```

- Always use `match=` to verify the message — catches regressions where the wrong type is raised.
- The match is a regex. Escape special chars or use `re.escape`.

## Async tests

```python
import pytest

@pytest.mark.asyncio
async def test_fetch_returns_payload(mocker):
    mocker.patch("myapp.api.httpx.AsyncClient.get", return_value=...)
    result = await fetch("/users/1")
    assert result.id == 1
```

In `pyproject.toml`:
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

With `asyncio_mode = "auto"`, every async function is treated as a test — drop the marker.

## Property-based tests with hypothesis

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_is_idempotent(xs):
    assert sorted(sorted(xs)) == sorted(xs)
```

- Use for invariants on data-shaped code: parsers, encoders, math, serializers.
- Doesn't replace example-based tests — adds to them.
- Cap example count for slow tests with `@settings(max_examples=50)`.

## Coverage

```bash
pytest --cov=myapp --cov-branch --cov-report=term-missing
```

- Branch coverage > line coverage. Always pass `--cov-branch`.
- Target: 80–90% on critical business logic, 100% on payment / auth / security paths.
- Don't chase 100% by writing meaningless tests. Use `# pragma: no cover` only for unreachable defensive code.

## Speed

- `pytest -n auto` (xdist) for parallel runs. Make sure tests are isolated first.
- `pytest --lf` (last failed) and `--ff` (failed first) during dev.
- `pytest -x` to stop at first failure.
- Tag slow tests: `@pytest.mark.slow`, then run `pytest -m "not slow"` for the fast loop.

## The smoke-test anti-pattern

A smoke test calls the SUT and asserts nothing — or only `is not None`. It verifies the import works, not the behavior. **These are not acceptable.** Apply the mutation heuristic before handing back: *if the SUT silently returned the wrong value, would this test fail?* If no, rewrite it.

```python
# BAD — no assertion
def test_sound_manager_plays():
    sm = SoundManager()
    sm.play("shoot")

# BAD — passes for any non-None result, including a bug
def test_enemy_fires():
    fired = enemy.maybe_fire()
    assert fired is not None

# BAD — broad raises swallows test bugs
def test_collision_handles_bullet():
    with pytest.raises(Exception):
        engine.handle_collision(bullet, wall)

# GOOD — asserts on values the SUT computed
def test_enemy_fires_bullet_at_aim_angle():
    enemy = build_enemy(angle=0.0, position=(0, 0))
    bullet = enemy.maybe_fire()
    assert bullet.position == (0, 0)
    assert bullet.velocity_angle == pytest.approx(0.0)
    assert bullet.owner is enemy

# GOOD — narrow exception + message
def test_collision_raises_invalid_geometry_when_bullet_overlaps_wall():
    with pytest.raises(InvalidGeometry, match="bullet inside wall"):
        engine.handle_collision(bullet, wall)
```

## Testing stateful systems (games, simulators, agents)

Stateful systems are where smoke tests breed: real setup is painful, so tests degrade to "did it crash?" Build a deterministic minimal world up front and the rest falls into place.

```python
@pytest.fixture
def world_factory():
    """Build a minimal deterministic game world.

    - Seeded RNG so spawns/AI are reproducible.
    - Fixed clock; tests advance it explicitly with world.tick(dt).
    - No display, no audio, no file I/O.
    """
    def _make(*, seed: int = 0, size: tuple[int, int] = (64, 64)) -> World:
        rng = random.Random(seed)
        return World(rng=rng, clock=FakeClock(), size=size)
    return _make


def test_player_facing_north_moves_y_decreases(world_factory):
    world = world_factory()
    player = world.spawn_player(at=(32, 32), facing="N")

    player.move_forward(dt=0.1)

    assert player.position.x == 32
    assert player.position.y < 32


@pytest.mark.parametrize(
    ("inputs", "expected_score"),
    [
        pytest.param([("fire",)], 0, id="fire_misses"),
        pytest.param([("aim", 0.0), ("fire",), ("tick", 1.0)], 100, id="fire_hits_at_zero_angle"),
        pytest.param([("aim", 3.14), ("fire",), ("tick", 1.0)], 0, id="fire_wrong_direction"),
    ],
)
def test_score_after_input_sequence(world_factory, inputs, expected_score):
    world = world_factory(seed=42)
    target = world.spawn_target(at=(40, 32))
    player = world.spawn_player(at=(32, 32), facing="E")

    for action in inputs:
        world.apply(player, action)

    assert world.score == expected_score
```

Key patterns:

- **Builder fixtures** with keyword overrides — no global state, no per-test boilerplate.
- **Seeded RNG + fake clock** — every test is deterministic and reproducible.
- **Parametrize over input sequences** — one test body covers many scenarios.
- **Assert on post-state** — entity positions, scores, health, queue contents — not "no exception."

## What NOT to do

- Don't test third-party libraries.
- Don't test private helpers in isolation if they're covered through the public API.
- Don't assert on implementation details (`mock.call_count == 3`) unless the contract specifies it.
- Don't use module-level state in tests. It leaks between tests and breaks parallel runs.
- Don't `time.sleep` to wait for an event. Poll with a timeout, or use a deterministic mock.
- Don't share mutable fixtures across tests at session scope.
- Don't have tests that pass when run alone but fail in the suite. That's a fixture leak — fix it, don't reorder.
- **Don't ship smoke tests.** A test with no assertion or only `is not None` adds zero signal and false confidence.

## pyproject.toml minimum config

```toml
[tool.pytest.ini_options]
addopts = "-ra --strict-markers --strict-config"
testpaths = ["tests"]
markers = [
    "slow: tests that take >1s",
    "integration: requires external services",
]
asyncio_mode = "auto"

[tool.coverage.run]
branch = true
source = ["src"]

[tool.coverage.report]
show_missing = true
skip_covered = false
fail_under = 80
```
