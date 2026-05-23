---
name: dotnet-security
description: Security checks for .NET / C# — OWASP top 10 mapped to .NET idioms, injection, deserialization, secrets, crypto, auth, ASP.NET Core specifics, supply chain. Apply when reviewing code touching user input, network I/O, process execution, deserialization, or auth.
---

Assume malicious input. Validate at boundaries. Fail closed.

## Injection

### SQL injection

**Bad:**
```csharp
var sql = $"SELECT * FROM users WHERE id = {userId}";
context.Database.ExecuteSqlRaw(sql);
```

**Good:**
```csharp
context.Database.ExecuteSql($"SELECT * FROM users WHERE id = {userId}");  // EF Core 7+ auto-parameterizes
context.Database.ExecuteSqlRaw("SELECT * FROM users WHERE id = @p0", userId);  // explicit
await conn.QueryAsync<User>("SELECT * FROM users WHERE id = @Id", new { Id = userId });  // Dapper
```

`ExecuteSql` (not `ExecuteSqlRaw`) with interpolated strings auto-parameterizes in EF Core 7+. `ExecuteSqlRaw` with interpolated strings is **SQL injection**.

### Command injection

**Bad:**
```csharp
Process.Start("cmd", $"/c dir {userPath}");
Process.Start(new ProcessStartInfo { FileName = "cmd", Arguments = $"/c {userInput}", UseShellExecute = true });
```

**Good:**
```csharp
Process.Start(new ProcessStartInfo
{
    FileName = "dir",
    Arguments = validatedPath,
    UseShellExecute = false,
    RedirectStandardOutput = true,
});
```

Never pass user input to a shell. If you must invoke a process, use argument arrays or pre-validate with a strict allowlist.

### Path traversal

**Bad:**
```csharp
var path = Path.Combine(uploadsDir, userFilename);
return File.ReadAllText(path);  // ../../etc/passwd
```

**Good:**
```csharp
var basePath = Path.GetFullPath(uploadsDir);
var targetPath = Path.GetFullPath(Path.Combine(uploadsDir, userFilename));
if (!targetPath.StartsWith(basePath, StringComparison.OrdinalIgnoreCase))
    throw new UnauthorizedAccessException("Path traversal attempt");
return File.ReadAllText(targetPath);
```

### Open redirect

**Bad:**
```csharp
return Redirect(Request.Query["returnUrl"]);
```

**Good:**
```csharp
if (!Url.IsLocalUrl(returnUrl))
    return Redirect("/");
return Redirect(returnUrl);
```

## Unsafe deserialization

### BinaryFormatter

**Removed in .NET 9.** In older versions, `BinaryFormatter.Deserialize` on attacker-controlled data is **remote code execution**. Flag as CRITICAL.

### Newtonsoft.Json

```csharp
// CRITICAL — RCE via gadget chains
var settings = new JsonSerializerSettings { TypeNameHandling = TypeNameHandling.All };
var obj = JsonConvert.DeserializeObject<object>(untrustedJson, settings);
```

Use `TypeNameHandling.None` (default) or switch to `System.Text.Json`.

### XML — XXE

```csharp
// Bad — vulnerable to XXE
var doc = XDocument.Load(untrustedStream);

// Good
var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit };
using var reader = XmlReader.Create(untrustedStream, settings);
var doc = XDocument.Load(reader);
```

### ZipFile

```csharp
// Bad — Zip Slip
ZipFile.ExtractToDirectory(archive, destination);

// Good — validate each entry
using var zip = ZipFile.OpenRead(archive);
var basePath = Path.GetFullPath(destination);
foreach (var entry in zip.Entries)
{
    var targetPath = Path.GetFullPath(Path.Combine(destination, entry.FullName));
    if (!targetPath.StartsWith(basePath))
        throw new InvalidDataException("Zip entry escapes target directory");
    entry.ExtractToFile(targetPath, overwrite: false);
}
```

## Secrets

- **Never commit secrets.** Use User Secrets locally (`dotnet user-secrets`), Key Vault / environment variables in production.
- **`appsettings.json`** in source should have placeholders or development-only values. Real connection strings belong in environment variables.
- **Don't log secrets.** Filter `Authorization` headers, `Cookie`, API keys before logging request details.
- **Don't expose stack traces** to clients. Use `app.UseExceptionHandler()` in production, not `app.UseDeveloperExceptionPage()`.

## Crypto

| Don't | Do |
|---|---|
| `MD5`, `SHA1` for security | `SHA256`, `SHA512`, `HMACSHA256` |
| Plain SHA on passwords | `Rfc2898DeriveBytes` (PBKDF2) with >= 600k iterations, or `BCrypt.Net`, or `Argon2id` |
| `Random` / `Random.Shared` for tokens | `RandomNumberGenerator.GetBytes()`, `RandomNumberGenerator.GetHexString()` |
| Custom crypto | `System.Security.Cryptography` or `libsodium` |
| AES-ECB | AES-GCM (`AesGcm`) or AES-CBC with HMAC |
| Hardcoded IV / nonce | Per-message random nonce via `RandomNumberGenerator` |
| `ServerCertificateCustomValidationCallback = (...) => true` | TLS verification on. Configure CA bundle if needed. |

## Authentication & authorization

- **`[Authorize]`** on every controller/endpoint that needs auth. `[AllowAnonymous]` only on genuinely public endpoints.
- **JWT validation:** `ValidateIssuerSigningKey = true`, `ValidateLifetime = true`, `ValidateIssuer = true`, `ValidateAudience = true`. Never disable validation.
- **`[Authorize(Policy = "CanEditOrder")]`** for fine-grained authorization. Role-based (`[Authorize(Roles = "Admin")]`) is coarse — prefer policies.
- **Object-level authorization (IDOR):** check that the authenticated user owns the resource before returning it. `GET /orders/{id}` must verify `order.OwnerId == currentUser.Id`.
- **Anti-forgery tokens:** `builder.Services.AddAntiforgery()` + `[ValidateAntiForgeryToken]` on state-changing form endpoints. Minimal APIs: use `IAntiforgery`.
- **Rate limiting:** `app.UseRateLimiter()` on auth endpoints to prevent brute force.
- **Cookie settings:** `CookieAuthenticationOptions.Cookie.SecurePolicy = CookieSecurePolicy.Always`, `HttpOnly = true`, `SameSite = SameSiteMode.Strict` (or `Lax`).

## ASP.NET Core specifics

- **Middleware ordering matters.** `UseAuthentication()` -> `UseAuthorization()` -> endpoint mapping. Wrong order = unauthenticated requests reaching endpoints.
- **`UseDeveloperExceptionPage()`** — development only. In production, use `UseExceptionHandler("/error")`.
- **CORS:** never `AllowAnyOrigin()` with `AllowCredentials()`. The CORS spec forbids it.
- **HSTS:** `app.UseHsts()` in production. Strict-Transport-Security header.
- **SSRF:** outbound HTTP from user-supplied URL must check an allowlist and block private IPs (10.x, 172.16.x, 192.168.x, 169.254.169.254 metadata service).
- **Kestrel limits:** configure `MaxRequestBodySize`, `MaxRequestHeadersTotalSize` for your API's needs. Defaults may be too generous.
- **Static files:** `app.UseStaticFiles()` only serves from `wwwroot`. Don't reconfigure to serve from a user-writable directory.

## Supply chain

- **Central Package Management** (`Directory.Packages.props`) for version consistency.
- **`dotnet list package --vulnerable`** in CI to catch known CVEs.
- **Be wary of new/low-download packages** on NuGet — typosquatting is real.
- **NuGet package signing:** enable signature verification for production feeds.
- **Don't `dotnet tool install` at runtime** in application code.
- **Dependabot / Renovate** for automated CVE patches.

## Security headers (web apps)

```csharp
app.Use(async (context, next) =>
{
    context.Response.Headers.Append("X-Content-Type-Options", "nosniff");
    context.Response.Headers.Append("X-Frame-Options", "DENY");
    context.Response.Headers.Append("Referrer-Policy", "no-referrer");
    context.Response.Headers.Append("Permissions-Policy", "camera=(), microphone=()");
    await next();
});

app.UseHsts();  // Strict-Transport-Security
```

Or use the `NetEscapades.AspNetCore.SecurityHeaders` package for a cleaner API.

## Severity quick map

| Issue | Severity |
|---|---|
| `BinaryFormatter` on untrusted data | CRITICAL (RCE) |
| `TypeNameHandling.All` on untrusted JSON | CRITICAL (RCE) |
| `Process.Start` with user input, `UseShellExecute = true` | CRITICAL (RCE) |
| SQL string concatenation/interpolation in `ExecuteSqlRaw` | HIGH (SQLi) |
| `ServerCertificateCustomValidationCallback = true` | HIGH (MITM) |
| Hardcoded production secret | HIGH |
| MD5/SHA1 for passwords | HIGH |
| `Random` for security tokens | HIGH |
| JWT validation disabled | HIGH (auth bypass) |
| Path traversal | HIGH |
| XXE on untrusted XML | HIGH |
| Missing anti-forgery on state-changing endpoints | MEDIUM |
| `UseDeveloperExceptionPage()` in production | MEDIUM (info disclosure) |
| Open CORS without credentials | LOW |
