---
name: packaging
description: Modern .NET project setup and packaging — SDK-style .csproj, Directory.Build.props, Central Package Management, global.json, NuGet, EditorConfig, CI, Docker. Apply when setting up a new project, adding a dependency, or hardening the build.
---

Modern .NET project setup is SDK-style `.csproj` + Central Package Management + `global.json` + EditorConfig. No `packages.config`. No old-style project files.

## Solution structure

```
MySolution/
├── MySolution.sln (or .slnx)
├── global.json
├── Directory.Build.props
├── Directory.Packages.props
├── .editorconfig
├── .gitignore
├── README.md
├── src/
│   ├── MyApp/
│   │   ├── MyApp.csproj
│   │   └── Program.cs
│   └── MyApp.Domain/
│       └── MyApp.Domain.csproj
├── tests/
│   ├── MyApp.Tests.Unit/
│   │   └── MyApp.Tests.Unit.csproj
│   └── MyApp.Tests.Integration/
│       └── MyApp.Tests.Integration.csproj
└── docs/
```

## global.json — pin the SDK

```json
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature",
    "allowPrerelease": false
  }
}
```

Every developer and CI agent uses the same SDK major.minor. `latestFeature` allows patch updates.

## Directory.Build.props — shared settings

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <AnalysisMode>All</AnalysisMode>
  </PropertyGroup>
</Project>
```

Lives at the solution root. Every `.csproj` inherits these. Don't repeat common properties in individual projects.

## Directory.Packages.props — Central Package Management

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.Extensions.Hosting" Version="10.0.0" />
    <PackageVersion Include="Serilog.AspNetCore" Version="9.0.0" />
    <PackageVersion Include="xunit" Version="2.9.3" />
    <PackageVersion Include="FluentAssertions" Version="7.1.0" />
    <PackageVersion Include="NSubstitute" Version="5.3.0" />
    <PackageVersion Include="coverlet.collector" Version="6.0.4" />
  </ItemGroup>
</Project>
```

Individual `.csproj` files reference packages **without** version:
```xml
<PackageReference Include="xunit" />
```

Version drift across projects is eliminated. Update one file to bump a version everywhere.

## .csproj — SDK style only

### Application project

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Serilog.AspNetCore" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />
  </ItemGroup>
</Project>
```

### Library project

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <PackageId>MyCompany.MyApp.Domain</PackageId>
    <Version>1.0.0</Version>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
```

### Test project

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="xunit" />
    <PackageReference Include="xunit.runner.visualstudio" />
    <PackageReference Include="coverlet.collector" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\MyApp\MyApp.csproj" />
  </ItemGroup>
</Project>
```

## CI — GitHub Actions

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          global-json-file: global.json
      - uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: nuget-${{ runner.os }}-${{ hashFiles('**/*.csproj', '**/Directory.Packages.props') }}
          restore-keys: nuget-${{ runner.os }}-
      - run: dotnet restore
      - run: dotnet format --verify-no-changes --no-restore
      - run: dotnet build --no-restore -warnaserror
      - run: dotnet test --no-build --collect:"XPlat Code Coverage"
```

Cache NuGet packages. Pin SDK via `global.json`. Run format, build, and test.

## Docker — production image

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY global.json Directory.Build.props Directory.Packages.props ./
COPY **/*.csproj ./
RUN dotnet restore

COPY . .
RUN dotnet publish src/MyApp/MyApp.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine
WORKDIR /app
COPY --from=build /app/publish .
RUN adduser -D -u 1000 appuser
USER appuser
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

Multi-stage. Non-root. Pinned base. Alpine for small image. No SDK in final image.

## .gitignore essentials

```
# Build
bin/
obj/

# IDE
.vs/
.idea/
*.user
*.suo
*.DotSettings.user
.vscode/

# Test
TestResults/
coverage/

# NuGet
*.nupkg
*.snupkg

# Secrets
appsettings.*.json
!appsettings.json
!appsettings.Development.json

# OS
.DS_Store
Thumbs.db
```

## NuGet package management

```bash
# List outdated packages
dotnet list package --outdated

# Check for vulnerable packages
dotnet list package --vulnerable

# Add a package (version goes in Directory.Packages.props)
dotnet add package Serilog.AspNetCore

# Update a package version (edit Directory.Packages.props)
```

## Publishing to NuGet

```bash
dotnet pack -c Release
dotnet nuget push bin/Release/*.nupkg --source https://api.nuget.org/v3/index.json --api-key $NUGET_KEY
```

For CI: use OIDC or API key from secrets. Never commit API keys.

## EditorConfig minimum

```ini
root = true

[*]
indent_style = space
indent_size = 4
end_of_line = crlf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.cs]
csharp_style_namespace_declarations = file_scoped:warning
csharp_style_var_for_built_in_types = true:suggestion
csharp_prefer_simple_using_statement = true:warning
csharp_style_prefer_primary_constructors = true:suggestion

[*.{json,yml,yaml}]
indent_size = 2
```

## What to avoid

- Old-style `.csproj` with `<Reference>` and `packages.config`.
- `PackageReference` with version in individual `.csproj` files (without CPM).
- Missing `global.json` — "works on my machine" with different SDK versions.
- `dotnet restore` without a lock or cache in CI — versions can drift.
- Putting test projects in the same directory as source projects.
- `<TreatWarningsAsErrors>false</TreatWarningsAsErrors>` to make the build green. Fix the warnings.
- `#pragma warning disable` globally. Suppress per-occurrence with justification.
