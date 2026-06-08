---
name: xunit-testing
description: xUnit / NUnit testing patterns for .NET — test structure, fixtures, theory data, mocking, async testing, integration testing with WebApplicationFactory and Testcontainers, coverage strategy. Apply when writing tests or designing a test plan.
---

Use xUnit as the default testing framework. Standard packages: `xunit`, `Microsoft.NET.Test.Sdk`, `coverlet.collector`, `FluentAssertions`, `NSubstitute` (or `Moq`), `FsCheck.Xunit`.

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
[Fact]
public void Withdraw_WhenFundsSufficient_ReducesBalance()
{
    var account = new Account(balance: 100m);

    account.Withdraw(10m);

    account.Balance.Should().Be(90m);
}
```

- Arrange / Act / Assert with a blank line between.
- One behavior per test. Multiple `Assert` / `.Should()` lines verifying the same behavior is fine.
- No `Console.WriteLine`, no commented-out code, no "TODO: also test X" — write the test or open a ticket.

## Fixtures and lifecycle

### xUnit

- **Constructor** for per-test setup. `IDisposable` / `IAsyncLifetime` for teardown.
- **`IClassFixture<T>`** for one-time-per-class shared state (expensive DB setup, test server).
- **`ICollectionFixture<T>`** for cross-class shared state.

```csharp
public sealed class TransferServiceTests : IAsyncLifetime
{
    private readonly TransferService _sut;

    public TransferServiceTests()
    {
        _sut = new TransferService(new InMemoryLedger());
    }

    public Task InitializeAsync() => Task.CompletedTask;
    public Task DisposeAsync() => Task.CompletedTask;
}
```

### NUnit

- `[SetUp]` / `[TearDown]` per test.
- `[OneTimeSetUp]` / `[OneTimeTearDown]` per class.

Default to per-test isolation. Use class/collection scope only when setup is genuinely expensive.

## Theory data — parametrize aggressively

```csharp
[Theory]
[InlineData(100, 10, 90)]
[InlineData(10, 10, 0)]
[InlineData(0, 0, 0)]
public void Withdraw_ReducesBalanceByAmount(decimal balance, decimal amount, decimal expected)
{
    var account = new Account(balance);

    account.Withdraw(amount);

    account.Balance.Should().Be(expected);
}

// Complex data via MemberData
[Theory]
[MemberData(nameof(InvalidTransfers))]
public void Transfer_RejectsInvalidInput(TransferRequest req, Type expectedEx)
{
    var act = () => _sut.Transfer(req);
    act.Should().Throw<Exception>().And.Should().BeOfType(expectedEx);
}

public static TheoryData<TransferRequest, Type> InvalidTransfers => new()
{
    { new TransferRequest(Guid.Empty, Guid.NewGuid(), 10), typeof(ArgumentException) },
    { new TransferRequest(Guid.NewGuid(), Guid.NewGuid(), -1), typeof(ArgumentOutOfRangeException) },
};
```

Don't write five near-identical tests — write one `[Theory]` with five `[InlineData]` rows.

## Mocking — NSubstitute or Moq

```csharp
[Fact]
public async Task Transfer_LogsCompletion()
{
    var ledger = Substitute.For<ILedger>();
    var logger = Substitute.For<ILogger<TransferService>>();
    var sut = new TransferService(ledger, logger);

    await sut.TransferAsync(new TransferRequest(src, dst, 10m), CancellationToken.None);

    ledger.Received(1).TransferAsync(Arg.Any<TransferRequest>(), Arg.Any<CancellationToken>());
}
```

- Mock at the boundary of the unit under test, not deep in the dependency tree.
- Never mock the system under test.
- Prefer real objects: a real `Dictionary<,>` beats a mock for a lookup.
- Prefer `TimeProvider` + `FakeTimeProvider` (Microsoft.Extensions.TimeProvider.Testing) over mocking `DateTime`.

## Async tests

```csharp
[Fact]
public async Task GetAccount_ReturnsNotFound_WhenMissing()
{
    var result = await _sut.GetAccountAsync(Guid.Empty, CancellationToken.None);

    result.Should().BeNull();
}
```

- Async test methods return `Task`. `async void` is forbidden — exceptions vanish.
- `await` everything. `.Result` in a test can deadlock.
- xUnit v3: use `TestContext.Current.CancellationToken` for cancellation tests.

## Integration tests — WebApplicationFactory

```csharp
public sealed class AccountsApiTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task GetAccount_ReturnsNotFound_WhenAccountMissing()
    {
        var client = factory.WithWebHostBuilder(b => b.ConfigureServices(s =>
        {
            s.RemoveAll<IAccountStore>();
            s.AddSingleton<IAccountStore>(new InMemoryAccountStore());
        })).CreateClient();

        var response = await client.GetAsync("/accounts/00000000-0000-0000-0000-000000000000");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }
}
```

- `WebApplicationFactory<Program>` for the in-process server.
- Replace services for test doubles via `ConfigureServices`.

## Integration tests — Testcontainers

```csharp
public sealed class DatabaseFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder()
        .WithImage("postgres:17-alpine")
        .Build();

    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        // Run EF Core migrations
    }

    public Task DisposeAsync() => _container.DisposeAsync().AsTask();
}

[Collection("Database")]
public sealed class OrderRepositoryTests(DatabaseFixture db)
{
    [Fact]
    public async Task Add_PersistsOrder()
    {
        using var context = CreateContext(db.ConnectionString);
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

- Use for invariants on data-shaped code: parsers, encoders, math, serializers.
- Doesn't replace example-based tests — adds to them.

## Mark expected exceptions

```csharp
[Fact]
public void Withdraw_WhenOverdraft_ThrowsInsufficientFunds()
{
    var account = new Account(balance: 0);

    var act = () => account.Withdraw(1m);

    act.Should().Throw<InsufficientFundsException>()
       .WithMessage("*balance is 0*");
}

// Async
[Fact]
public async Task Transfer_WhenTimeout_ThrowsAcmeServiceException()
{
    var act = () => _sut.TransferAsync(req, CancellationToken.None);

    await act.Should().ThrowAsync<AcmeServiceException>();
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

## Speed

- xUnit runs test classes in parallel by default. Make sure tests are isolated.
- `dotnet test --filter "FullyQualifiedName~Unit"` to run only unit tests.
- `dotnet test --filter "Category!=Integration"` to skip slow tests.
- `[Trait("Category", "Integration")]` to tag slow tests.

## The smoke-test anti-pattern

A smoke test calls the SUT and asserts nothing — or only `.Should().NotBeNull()`. It verifies the constructor works, not the behavior. **These are not acceptable.** Apply the mutation heuristic: *if the SUT silently returned the wrong value, would this test fail?* If no, rewrite it.

```csharp
// BAD — no assertion
[Fact]
public void SoundManager_Plays()
{
    var sm = new SoundManager();
    sm.Play("shoot");
}

// BAD — passes for any non-null result
[Fact]
public void Enemy_Fires()
{
    var bullet = enemy.MaybeFire();
    bullet.Should().NotBeNull();
}

// GOOD — behavioral assertions
[Fact]
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
    <TargetFramework>net10.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="NSubstitute" />
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
- Don't assert on implementation details (`Received(3)` on a mock) unless the contract specifies it.
- Don't use `Thread.Sleep` to wait for an event. Use `TaskCompletionSource`, polling with timeout, or `FakeTimeProvider`.
- Don't share mutable state across tests at class/collection scope.
- Don't have tests that pass when run alone but fail in parallel. That's a fixture leak.
- **Don't ship smoke tests.** A test with no assertion or only `.NotBeNull()` adds zero signal.
