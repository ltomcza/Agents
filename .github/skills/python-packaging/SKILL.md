---
name: python-packaging
description: Modern Python packaging — pyproject.toml, uv/poetry/pip-tools, build backends, wheels, version pinning, lockfiles, Docker, CI. Apply when setting up a new project, adding a dependency, or hardening the build.
---

Modern Python packaging is `pyproject.toml` + a lockfile + a fast resolver. `setup.py` is legacy. `requirements.txt` alone is a lockfile, not a project file.

## pyproject.toml — everything in one place

```toml
[project]
name = "myproject"
version = "0.1.0"
description = "One-line description"
readme = "README.md"
requires-python = ">=3.11"
license = { text = "MIT" }
authors = [{ name = "Your Name", email = "you@example.com" }]
classifiers = [
    "Programming Language :: Python :: 3",
    "License :: OSI Approved :: MIT License",
]
dependencies = [
    "fastapi>=0.115,<0.120",
    "pydantic>=2,<3",
    "httpx>=0.27,<0.30",
]

[project.optional-dependencies]
dev = [
    "pytest>=8",
    "pytest-cov",
    "pytest-mock",
    "pytest-asyncio",
    "ruff",
    "mypy",
    "pre-commit",
]
docs = ["mkdocs-material", "mkdocstrings[python]"]

[project.scripts]
myproject = "myproject.cli:main"

[project.urls]
Homepage = "https://github.com/you/myproject"
Issues = "https://github.com/you/myproject/issues"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/myproject"]
```

### Version pinning strategy

- In `pyproject.toml`: pin a *range* (`>=2,<3`). Allow patch and minor updates within a major; lock against breaking changes.
- In the lockfile (`uv.lock`, `poetry.lock`, `requirements.lock`): pin *exact* versions with hashes.
- Never pin `==X.Y.Z` only in `pyproject.toml`. That's what the lockfile is for.

## Choose a dependency manager

| Tool | When |
|---|---|
| **uv** | New projects. 10–100× faster than pip. Drop-in for `pip`/`pip-tools`/`virtualenv`. Native lockfile (`uv.lock`). |
| **poetry** | Existing Poetry projects. Strong dependency resolver. Slower than uv. |
| **pip-tools** (`pip-compile`) | Legacy or simple projects sticking to plain `requirements.txt`. |
| **pip** + manual venv | Don't, in 2026. |

### uv basics

```bash
# init
uv init myproject
cd myproject

# add a dep
uv add fastapi pydantic

# add dev dep
uv add --dev pytest mypy ruff

# install (creates .venv, syncs to lock)
uv sync

# run something in the env
uv run pytest

# lock without installing
uv lock

# upgrade a dep
uv lock --upgrade-package httpx
```

`uv.lock` is platform-aware and includes hashes. Commit it.

## Choose a build backend

| Backend | When |
|---|---|
| **hatchling** | Default for new projects. Fast, simple, modern. |
| **setuptools** | Legacy, complex builds with C extensions, or you need `setup.py` shenanigans. |
| **poetry-core** | If you're using Poetry. |
| **flit-core** | Tiny pure-Python libraries. |
| **scikit-build-core** | Native code (CMake-based). |
| **maturin** | Rust extensions (`pyo3`). |

## Project layout — `src/` layout

```
myproject/
├── pyproject.toml
├── README.md
├── LICENSE
├── .gitignore
├── .env.example
├── uv.lock
├── src/
│   └── myproject/
│       ├── __init__.py
│       ├── __main__.py
│       └── ...
├── tests/
│   ├── conftest.py
│   ├── unit/
│   └── integration/
└── docs/
```

`src/`-layout prevents the import-from-cwd trap (where `python` finds your unbuilt package via `sys.path[0] = ""` and tests pass for the wrong reason).

## Lockfiles

- **Always commit them.**
- `uv.lock` (uv), `poetry.lock` (Poetry), `requirements.lock` or compiled `requirements.txt` (pip-tools).
- Lockfile must include hashes when downloaded from the public index.
- CI installs from the lockfile, not from `pyproject.toml`. `uv sync --frozen`, `poetry install --no-update`, `pip install -r requirements.lock --require-hashes`.

## Pre-commit

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.7.0
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-added-large-files
      - id: detect-private-key
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.4
    hooks:
      - id: gitleaks
```

```bash
uv add --dev pre-commit
uv run pre-commit install
uv run pre-commit run --all-files
```

## CI — GitHub Actions

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: ["3.11", "3.12"]
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v3
        with:
          enable-cache: true
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: uv sync --frozen --all-extras
      - run: uv run ruff check .
      - run: uv run ruff format --check .
      - run: uv run mypy .
      - run: uv run pytest --cov --cov-report=xml
```

Caching makes the second run ~5× faster. `--frozen` ensures the lockfile isn't drifted.

## Docker — production image

```dockerfile
# syntax=docker/dockerfile:1.7

FROM python:3.12-slim AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
WORKDIR /app
ENV UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1

# Cache deps separately from code
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY . .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /app /app
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# non-root
RUN useradd -m -u 1000 app
USER app

CMD ["python", "-m", "myproject"]
```

- Multi-stage: builder has the toolchain, final stage has only what runs.
- Pinned base image tag.
- Non-root user.
- No dev deps in final image.
- Bytecode pre-compiled for cold-start speed.

## .gitignore essentials

```
# Python
__pycache__/
*.py[cod]
.pytest_cache/
.mypy_cache/
.ruff_cache/
.coverage
coverage.xml
htmlcov/

# Build
build/
dist/
*.egg-info/

# Env
.venv/
venv/
.env
.env.local

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db
```

Always `.env` ignored. `.env.example` committed.

## Publishing to PyPI

```bash
# build
uv build       # produces dist/*.whl and dist/*.tar.gz
# OR with hatch
uvx hatch build

# upload
uvx twine upload dist/*
```

For CI publish, use OIDC trusted publisher (no API tokens). GitHub Actions: `pypi-publish` action with `id-token: write`.

## Dependency hygiene

- `uv pip list --outdated` to see what's behind.
- `pip-audit` (or `uv pip audit`) for known vulnerabilities. Run in CI.
- Renovate or Dependabot to PR updates automatically.
- Keep `requires-python` honest — bump it when you start using newer features.

## What to avoid

- `setup.py` for new projects. Use `pyproject.toml` only.
- `pip install` at runtime in application code.
- Pinning only in `pyproject.toml` with `==`. Use ranges + lockfile.
- `pip install -r requirements.txt` without a lock or hashes in production.
- Building images with `pip install` and no lockfile — versions drift between builds.
- Putting your package code in the project root with no `src/` — import-path traps.
- A virtualenv inside the repo at a non-standard location.
