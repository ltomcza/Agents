---
name: security
description: Security checks for Python — OWASP top 10 mapped to Python idioms, injection, deserialization, secrets, crypto, auth, supply chain. Apply when reviewing code touching user input, network I/O, subprocess, deserialization, or auth.
---

Assume malicious input. Validate at boundaries. Fail closed.

## Injection

### SQL injection

**Bad:**
```python
cursor.execute(f"SELECT * FROM users WHERE id = {user_id}")
cursor.execute("SELECT * FROM users WHERE name = '%s'" % user_name)
cursor.execute("SELECT * FROM users WHERE id = " + str(user_id))
```

**Good:**
```python
cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))   # psycopg
cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))    # sqlite3
session.execute(text("SELECT * FROM users WHERE id = :id"), {"id": user_id})  # SA
```

ORMs are safe by default; raw `.text()` queries with f-strings are not.

### Command injection

**Bad:**
```python
subprocess.run(f"ls {path}", shell=True)
os.system(f"convert {filename} out.png")
```

**Good:**
```python
subprocess.run(["ls", path])              # shell=False (default), list args
subprocess.run(["convert", filename, "out.png"], check=True)
```

If you must use `shell=True` (rare), pre-validate with `shlex.quote` and a strict allowlist. Better: don't.

### Path traversal

**Bad:**
```python
def serve(filename):
    return open(f"./uploads/{filename}").read()  # ../../etc/passwd
```

**Good:**
```python
from pathlib import Path
BASE = Path("./uploads").resolve()

def serve(filename):
    target = (BASE / filename).resolve()
    if not target.is_relative_to(BASE):  # Python 3.9+
        raise PermissionError("escape attempt")
    return target.read_text()
```

### Template injection

**Bad:**
```python
Template(user_input).render()
env = Environment(autoescape=False)  # off by default in raw Jinja2
```

**Good:**
```python
env = Environment(autoescape=select_autoescape(["html", "xml"]))
template = env.get_template("page.html")
template.render(user=user_input)  # rendered as data, not template
```

Never compile a template from user input. Render *into* a template.

## Unsafe deserialization

### Pickle

`pickle.loads` on attacker-controlled data is **remote code execution**.

```python
# NEVER on untrusted data:
pickle.loads(request_body)
```

Use JSON, MessagePack, or Protobuf for cross-trust-boundary data. Pickle is fine for trusted local caches.

### YAML

```python
yaml.load(stream)              # arbitrary code execution
yaml.load(stream, Loader=yaml.Loader)  # same
```

Use `yaml.safe_load(stream)`.

### XML

`xml.etree.ElementTree`, `xml.dom.minidom`, `lxml` are vulnerable to XXE and billion laughs on untrusted input.

```python
from defusedxml import ElementTree  # safe drop-in
tree = ElementTree.parse(file)
```

### Tarfile / Zipfile

Zip Slip / path traversal:

```python
# Bad:
tar.extractall(path)

# Good (Python 3.12+):
tar.extractall(path, filter="data")

# Older:
def safe_members(tar, base):
    base = Path(base).resolve()
    for m in tar.getmembers():
        target = (base / m.name).resolve()
        if not target.is_relative_to(base):
            continue
        yield m
tar.extractall(path, members=safe_members(tar, path))
```

## Secrets

- **Never commit secrets.** `.env` in `.gitignore`. `.env.example` with placeholders is fine.
- **Don't hardcode keys / tokens / passwords** even in tests. Tests use `monkeypatch.setenv` and a known-fake.
- **Don't log secrets.** Filter request bodies, headers, query params with names like `*token*`, `*secret*`, `*password*`, `authorization`.
- **Don't expose stack traces** to clients in production.
- **Read from env or a secret store.** `pydantic-settings`:

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    db_url: str
    api_key: str

    class Config:
        env_file = ".env"
```

Detect leaks with `gitleaks` in pre-commit + CI.

## Crypto

| Don't | Do |
|---|---|
| `hashlib.md5`, `hashlib.sha1` for security | `hashlib.sha256` (or `blake2b`) |
| Plain SHA on passwords | `bcrypt`, `argon2-cffi`, or `passlib` with argon2 |
| `random.random` / `random.choice` for tokens | `secrets.token_hex`, `secrets.token_urlsafe` |
| Custom crypto | `cryptography` library, well-known constructions |
| AES-ECB | AES-GCM (`cryptography.hazmat.primitives.ciphers.aead.AESGCM`) |
| Hardcoded IV / nonce | Per-message random nonce; for GCM, never reuse a nonce with the same key |
| `verify=False` on TLS | TLS verification on. Pin if you have a closed system. |

## Authentication & authorization

- **JWT:** verify the signature. `algorithm="none"` must be rejected. Use `PyJWT` with `algorithms=["RS256"]` or `["HS256"]` — pass an explicit allowlist.
- **Session cookies:** `Secure`, `HttpOnly`, `SameSite=Lax` (or `Strict`).
- **Password reset tokens:** time-limited, single-use, generated with `secrets`.
- **Authn ≠ Authz.** A logged-in user is not authorized to access *every* user's resource. Check object-level access on every read of `/things/{id}` (IDOR).
- **Regenerate session ID on login** to prevent fixation.
- **Rate-limit auth endpoints.** Brute force is the default attack.

## Web framework specifics

### FastAPI

- Use `Depends` for authn dependencies; verify in the dependency, not in the route body (consistency).
- `CORSMiddleware`: do not combine `allow_origins=["*"]` with `allow_credentials=True`. The browser ignores it; if it didn't, you'd be broken.
- Pydantic models on inputs validate types. They don't authorize.
- Don't return ORM objects directly when there are sensitive fields — use a response model.

### Flask

- `@csrf_protect` (Flask-WTF) for state-changing forms.
- Set `app.config["SESSION_COOKIE_SECURE"] = True` in production.
- `app.debug = False` in production. Always.
- `werkzeug` debug PIN is *not* an auth mechanism.

### SSRF

```python
# Bad:
async def proxy(url: str):
    return await httpx.get(url)

# Good:
ALLOWED_HOSTS = {"api.example.com", "files.example.com"}

async def proxy(url: str):
    parsed = urlparse(url)
    if parsed.hostname not in ALLOWED_HOSTS:
        raise PermissionError("host not allowed")
    # also block private IPs, link-local, metadata service
    return await httpx.get(url)
```

The cloud metadata service at `169.254.169.254` is the classic SSRF target.

## Subprocess and filesystem

- `tempfile.mktemp()` is **deprecated** — race condition. Use `NamedTemporaryFile` or `mkstemp`.
- `os.umask(0o077)` before creating sensitive files; or pass `mode` to `open` / `mkstemp`.
- `shutil.unpack_archive` on untrusted input — same Zip Slip risks; validate paths.

## Supply chain

- **Lock dependencies** with hashes (`uv.lock`, `poetry.lock`, `pip-compile --generate-hashes`).
- **Audit** in CI: `pip-audit`, `uv pip audit`, or `osv-scanner`.
- **Be wary of brand-new packages.** Typosquatting is common — verify the source repo.
- **Avoid `--index-url` to a third-party index** without `--extra-index-url` ordering and hash verification — dependency confusion.
- **Don't `pip install` from a URL** in production code.
- **Use Renovate or Dependabot** for known-CVE patches.

## Security headers (web apps)

```python
# FastAPI middleware example
@app.middleware("http")
async def secure_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response
```

For CSP, generate per-app — defaults are too restrictive for most apps.

## Logging hygiene

- Log levels: never `info` a password or token. Even `debug` is risky if logs are aggregated.
- Strip auth headers and cookies in middleware before logging request bodies.
- Don't log full credit card numbers, SSNs, etc. (Mask: `****1234`.)

## Tools

- `bandit` — static analysis for Python security issues.
- `pip-audit` / `uv pip audit` — known CVEs in dependencies.
- `gitleaks` — secret scanner, in pre-commit and CI.
- `safety` — alternative CVE scanner.
- `semgrep` — pattern-based static analysis with security rulesets.

## Severity quick map

| Issue | Severity |
|---|---|
| `pickle.loads` on external data | CRITICAL (RCE) |
| `eval` / `exec` on external data | CRITICAL (RCE) |
| `shell=True` with user input | CRITICAL or HIGH (RCE/cmdi) |
| SQL string concatenation | HIGH (SQLi) |
| `verify=False` in production | HIGH (MITM) |
| Hardcoded production secret | HIGH |
| MD5/SHA1 for passwords | HIGH |
| `random` for security tokens | HIGH |
| JWT `algorithm="none"` accepted | HIGH (auth bypass) |
| Path traversal | HIGH |
| XXE on untrusted XML | HIGH |
| Missing CSRF on state-changing form | MEDIUM |
| MD5 for non-security checksums | LOW (just modernize) |
| Open CORS without credentials | LOW (info, document the choice) |
