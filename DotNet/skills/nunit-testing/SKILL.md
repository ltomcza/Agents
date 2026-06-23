---
name: nunit-testing
description: NUnit testing patterns for .NET — test structure, fixtures, test-case data, mocking, async testing, integration testing with WebApplicationFactory and Testcontainers, coverage strategy. Apply when writing tests or designing a test plan.
---

Use **NUnit 4.x** as the testing framework. Standard packages: `NUnit`, `NUnit3TestAdapter`, `NUnit.Analyzers`, `Microsoft.NET.Test.Sdk`, `coverlet.collector`, `FluentAssertions`, `Moq`, `FsCheck.NUnit`.

This checklist is the source of truth for the `test-engineer` agent. Keep the agent body focused on test-planning flow, coverage goals, and the output contract.

## Assertion library

| | FluentAssertions | NUnit native (`Assert.That` constraint model) |
|---|---|---|
| Reach for | Default on new projects, anything with rich domain objects | Lightweight projects, libraries that want zero extra deps, single-invariant tests |
| Strength | Readable chains (`Should().BeEquivalentTo`, `Should().BeOfType`), high-quality failure messages, deep object graph compare | No extra dependency, ships with NUnit, expressive constraints (`Is.EqualTo`, `Is.InstanceOf`, `Has.Member`, `Throws.TypeOf`) |
| Weakness | License changed in v8 (free for OSS / paid for commercial — pin to v7.1.0 if that matters) | Verbose for deep object graph compare; failure messages thinner than FluentAssertions |

Pick one per project and stick with it — mixing reads as drift. When in doubt: FluentAssertions v7.1.0 (last permissive version) for app code, NUnit native (`Assert.That`) for library projects that ship to NuGet.

## File and naming layout

```
tests/
├── MyApp.Tests.Unit/
│   ├── Services/
│   │   └── TransferServiceTests.cs
│   └── Models/
│       └── MoneyTests.cs
├── MyApp.Tests.Integration/
│   ├── Api/
│   │   └── AccountsApiTests.cs
│   └── Fixtures/
│       └── DatabaseFixture.cs
└── MyApp.Tests.Architecture/     # optional: ArchUnitNET
    └── LayerTests.cs
```

- Test projects: `<ProjectName>.Tests.Unit`, `<ProjectName>.Tests.Integration`.
- Test classes: `<ClassUnderTest>Tests.cs`.
- Test methods: `MethodName_WhenCondition_ShouldExpected`.
- Mirror source layout: `src/MyApp/Services/TransferService.cs` -> `tests/MyApp.Tests.Unit/Services/TransferServiceTests.cs`.

## Anatomy of a good test

```csharp
[Test]
public void Withdraw_WhenFundsSufficient_ReducesBalance()
{
    var account = new Account(balance: 100m);

    account.Withdraw(10m);

    account.Balance.Should().Be(90m);
}
```

- Arrange / Act / Assert with a blank line between.
- One behavior per test. Multiple `Assert.That` / `.Should()` lines verifying the same behavior is fine.
- No `Console.WriteLine`, no commented-out code, no "TODO: also test X" — write the test or open a ticket.

## Fixtures and lifecycle

- **`[SetUp]` / `[TearDown]`** — run before/after each test in the fixture. Use for per-test arrange and cleanup.
- **`[OneTimeSetUp]` / `[OneTimeTearDown]`** — run once per fixture class. Use for expensive shared state (Testcontainers DB, in-process web host).
- **`[SetUpFixture]`** — class-level attribute at namespace scope. The `[OneTimeSetUp]` / `[OneTimeTearDown]` methods inside run once per namespace, across every fixture in it. Use for cross-class shared state.
- Default to per-test isolation. Reach for class or namespace scope only when setup is genuinely expensive.

```csharp
public sealed class TransferServiceTests
{
    private TransferService _sut = null!;
    private InMemoryLedger _ledger = null!;

    [SetUp]
    public void SetUp()
    {
        _ledger = new InMemoryLedger();
        _sut = new TransferService(_ledger);
    }

    [TearDown]
    public async Task TearDownAsync()
    {
        await _ledger.DisposeAsync();
    }
}
```

`[TearDown]` may be async — return `Task` directly. NUnit awaits it.

## Test-case data — parametrize aggressively

```csharp
[TestCase(100, 10, 90)]
[TestCase(10, 10, 0)]
[TestCase(0, 0, 0)]
public void Withdraw_ReducesBalanceByAmount(decimal balance, decimal amount, decimal expected)
{
    var account = new Account(balance);

    account.Withdraw(amount);

    account.Balance.Should().Be(expected);
}

// Complex data via TestCaseSource
[TestCaseSource(nameof(InvalidTransfers))]
public void Transfer_RejectsInvalidInput(TransferRequest req, Type expectedEx)
{
    var act = () => _sut.Transfer(req);
    act.Should().Throw<Exception>().Which.Should().BeOfType(expectedEx);
}

public static IEnumerable<TestCaseData> InvalidTransfers =>
[
    new TestCaseData(new TransferRequest(Guid.Empty, Guid.NewGuid(), 10m), typeof(ArgumentException))
        .SetName("source account is empty"),
    new TestCaseData(new TransferRequest(Guid.NewGuid(), Guid.NewGuid(), -1m), typeof(ArgumentOutOfRangeException))
        .SetName("amount is negative"),
];
```

Don't write five near-identical tests — write one method with five `[TestCase]` rows. Use `[TestCaseSource]` when the data shape exceeds attribute literals (complex objects, computed values).

`SetName(...)` on `TestCaseData` gives each row a readable name in the runner output.

## Mocking — Moq

```csharp
[Test]
public async Task Transfer_LogsCompletion()
{
    var ledger = new Mock<ILedger>();
    var logger = new Mock<ILogger<TransferService>>();
    var sut = new TransferService(ledger.Object, logger.Object);

    await sut.TransferAsync(new TransferRequest(src, dst, 10m), CancellationToken.None);

    ledger.Verify(
        l => l.TransferAsync(It.IsAny<TransferRequest>(), It.IsAny<CancellationToken>()),
        Times.Once);
}
```

- Mock at the boundary of the unit under test, not deep in the dependency tree.
- Never mock the system under test.
- Prefer real objects: a real `Dictionary<,>` beats a mock for a lookup.
- Prefer `TimeProvider` + `FakeTimeProvider` (Microsoft.Extensions.TimeProvider.Testing) over mocking `DateTime`.

## Async tests

```csharp
[Test]
public async Task GetAccount_ReturnsNotFound_WhenMissing()
{
    var result = await _sut.GetAccountAsync(Guid.Empty, CancellationToken.None);

    result.Should().BeNull();
}
```

- Async test methods return `Task`. `async void` is forbidden — exceptions vanish.
- `await` everything. `.Result` in a test can deadlock.
- For cancellation tests, pass `TestContext.CurrentContext.CancellationToken` or a `CancellationTokenSource` you own.
- NUnit 4 ships `[CancelAfter(milliseconds)]` for per-test timeout cancellation — the framework cancels the token surfaced through `TestContext.CurrentContext.CancellationToken` when the timeout elapses.

```csharp
[Test, CancelAfter(5_000)]
public async Task SlowOperation_RespectsCancellation(CancellationToken ct)
{
    await _sut.LongRunningAsync(ct);
}
```

## Integration tests — WebApplicationFactory

```csharp
public sealed class AccountsApiTests
{
    private WebApplicationFactory<Program> _factory = null!;
    private HttpClient _client = null!;

    [OneTimeSetUp]
    public void SetUpFactory()
    {
        _factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.ConfigureServices(s =>
            {
                s.RemoveAll<IAccountStore>();
                s.AddSingleton<IAccountStore>(new InMemoryAccountStore());
            }));
        _client = _factory.CreateClient();
    }

    [OneTimeTearDown]
    public void TearDownFactory()
    {
        _client.Dispose();
        _factory.Dispose();
    }

    [Test]
    public async Task GetAccount_ReturnsNotFound_WhenAccountMissing()
    {
        var response = await _client.GetAsync("/accounts/00000000-0000-0000-0000-000000000000");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

- `WebApplicationFactory<Program>` for the in-process server. Build it once per fixture in `[OneTimeSetUp]`; tear it down explicitly in `[OneTimeTearDown]`.
- Replace services for test doubles via `ConfigureServices`.

## Integration tests — Testcontainers

Use a namespace-scoped `[SetUpFixture]` so one container serves every fixture in that namespace.

```csharp
[SetUpFixture]
public sealed class DatabaseFixture
{
    public static PostgreSqlContainer Container { get; private set; } = null!;
    public static string ConnectionString => Container.GetConnectionString();

    [OneTimeSetUp]
    public async Task StartAsync()
    {
        Container = new PostgreSqlBuilder()
            .WithImage("postgres:17-alpine")
            .Build();
        await Container.StartAsync();
        // Run EF Core migrations here.
    }

    [OneTimeTearDown]
    public Task StopAsync() => Container.DisposeAsync().AsTask();
}

public sealed class OrderRepositoryTests
{
    [Test]
    public async Task Add_PersistsOrder()
    {
        using var context = CreateContext(DatabaseFixture.ConnectionString);
        var repo = new OrderRepository(context);

        await repo.AddAsync(new Order { Total = 42m });
        await context.SaveChangesAsync();

        var orders = await repo.GetAllAsync();
        orders.Should().ContainSingle(o => o.Total == 42m);
    }
}
```

Don't substitute SQLite for Postgres — dialect mismatches breed false greens.

## Property tests — FsCheck

```csharp
[Property]
public Property Sort_IsIdempotent(int[] xs)
{
    var sorted = xs.OrderBy(x => x).ToArray();
    var sortedTwice = sorted.OrderBy(x => x).ToArray();
    return sorted.SequenceEqual(sortedTwice).ToProperty();
}
```

Add the `FsCheck.NUnit` package; `[Property]` integrates with the NUnit runner.

- Use for invariants on data-shaped code: parsers, encoders, math, serializers.
- Doesn't replace example-based tests — adds to them.

## Mark expected exceptions

```csharp
[Test]
public void Withdraw_WhenOverdraft_ThrowsInsufficientFunds()
{
    var account = new Account(balance: 0);

    var act = () => account.Withdraw(1m);

    act.Should().Throw<InsufficientFundsException>()
       .WithMessage("*balance is 0*");
}

// Async
[Test]
public async Task Transfer_WhenTimeout_ThrowsAcmeServiceException()
{
    var act = () => _sut.TransferAsync(req, CancellationToken.None);

    await act.Should().ThrowAsync<AcmeServiceException>();
}

// NUnit native constraint, no FluentAssertions
[Test]
public void Withdraw_WhenOverdraft_ThrowsInsufficientFunds_Native()
{
    var account = new Account(balance: 0);

    Assert.That(() => account.Withdraw(1m),
        Throws.TypeOf<InsufficientFundsException>()
              .With.Message.Contains("balance is 0"));
}
```

Always verify the exception type *and* the message when the message carries contract info.

## Coverage

```bash
dotnet test --collect:"XPlat Code Coverage" -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura
# HTML report
dotnet tool run reportgenerator -reports:**/coverage.cobertura.xml -targetdir:coverage-report
```

- Branch coverage > line coverage.
- Target: 80-90% on critical business logic, 100% on payment / auth / security paths.
- Don't chase 100% by writing meaningless tests. Use `[ExcludeFromCodeCoverage]` only for generated code or truly unreachable defensive paths.
- Mutation testing: **Stryker.NET** for proof that tests catch bugs.

## Speed and parallelism

NUnit 4 runs fixtures sequentially by default. Opt into parallelism explicitly:

```csharp
// Assembly-level: opt every fixture in this assembly into parallel-by-fixture execution.
[assembly: Parallelizable(ParallelScope.Fixtures)]
[assembly: LevelOfParallelism(4)]
```

Per-fixture or per-test attributes (`[Parallelizable(ParallelScope.Self)]`, `[NonParallelizable]`) override the assembly default.

- `dotnet test --filter "FullyQualifiedName~Unit"` to run only unit tests.
- `dotnet test --filter "TestCategory!=Integration"` to skip slow tests.
- `[Category("Integration")]` to tag slow tests — `TestCategory` is the filter trait NUnit exposes through VSTest.

## The smoke-test anti-pattern

A smoke test calls the SUT and asserts nothing — or only `.Should().NotBeNull()`. It verifies the constructor works, not the behavior. **These are not acceptable.** Apply the mutation heuristic: *if the SUT silently returned the wrong value, would this test fail?* If no, rewrite it.

```csharp
// BAD — no assertion
[Test]
public void SoundManager_Plays()
{
    var sm = new SoundManager();
    sm.Play("shoot");
}

// BAD — passes for any non-null result
[Test]
public void Enemy_Fires()
{
    var bullet = enemy.MaybeFire();
    bullet.Should().NotBeNull();
}

// GOOD — behavioral assertions
[Test]
public void Enemy_Fires_BulletAtAimAngle()
{
    var enemy = BuildEnemy(angle: 0.0, position: (0, 0));

    var bullet = enemy.MaybeFire();

    bullet.Should().NotBeNull();
    bullet!.Position.Should().Be((0, 0));
    bullet.VelocityAngle.Should().BeApproximately(0.0, precision: 1e-6);
    bullet.Owner.Should().BeSameAs(enemy);
}
```

## Test project .csproj minimum

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="NUnit" />
    <PackageReference Include="NUnit3TestAdapter" />
    <PackageReference Include="NUnit.Analyzers" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="Moq" />
    <PackageReference Include="coverlet.collector" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp\MyApp.csproj" />
  </ItemGroup>
</Project>
```

## What NOT to do

- Don't test BCL / third-party libraries.
- Don't test `internal` helpers in isolation if they're covered through the public API.
- Don't assert on implementation details (`Verify(..., Times.Exactly(3))` on a mock) unless the contract specifies it.
- Don't use `Thread.Sleep` to wait for an event. Use `TaskCompletionSource`, polling with timeout, or `FakeTimeProvider`.
- Don't share mutable state across tests at fixture / namespace scope.
- Don't write tests that pass when run alone but fail in parallel. That's a fixture leak — fix the leak, don't paper over with `[NonParallelizable]`.
- **Don't ship smoke tests.** A test with no assertion or only `.NotBeNull()` adds zero signal.
