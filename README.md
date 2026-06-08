# Agents & Skills

A portable library of AI **agent profiles** and **skills**, namespaced by language
(Python today; add sibling directories for other languages as needed).
Host-independent: the same files work in Claude Code, GitHub Copilot, Codex CLI,
Cursor, OpenCode, Goose, and any other tool that reads agent profiles or
[Agent Skills](https://agentskills.io) from disk.

## Layout

Canonical definitions are namespaced by language. Add a new language by creating a
sibling directory at the repo root containing `agents/` and/or `skills/` — the sync
script auto-discovers it.

```
.
├── Python/
│   ├── agents/              # canonical agent profiles (one file per agent)
│   │   ├── python-architect.md
│   │   ├── python-developer.md
│   │   ├── python-orchestrator.md
│   │   └── ...
│   └── skills/              # canonical skills (one folder per skill)
│       ├── pytest-testing/
│       │   └── SKILL.md
│       ├── python-async-concurrency/
│       │   └── SKILL.md
│       └── ...
├── DotNet/
│   ├── agents/              # .NET / C# agent profiles
│   │   ├── dotnet-architect.md
│   │   ├── dotnet-developer.md
│   │   ├── dotnet-orchestrator.md
│   │   └── ...
│   └── skills/              # .NET / C# skills
│       ├── xunit-testing/
│       │   └── SKILL.md
│       ├── dotnet-async-concurrency/
│       │   └── SKILL.md
│       └── ...
├── scripts/
│   ├── sync-to-host.ps1     # mirror to .github/ and .claude/ on Windows
│   └── sync-to-host.sh      # same, POSIX shells
├── AGENTS.md                # project conventions (read by any agent)
└── README.md
```

The files under `<Language>/agents/` and `<Language>/skills/` are the **single
source of truth**. The `.github/` and `.claude/` directories are derived by the
sync script — treat them as build artifacts and do not edit them directly. Both
hosts expect a flat list, so the script aggregates every language directory into
the same destination; keep agent filenames globally unique (the `python-` prefix
on Python agents handles this).

## Roster

### Agents

| Agent | Role | Model |
|---|---|---|
| [`python-orchestrator`](Python/agents/python-orchestrator.md) | Coordinates the team for non-trivial Python work | opus |
| [`python-architect`](Python/agents/python-architect.md) | Designs systems, module layout, API contracts (read-only) | opus |
| [`python-researcher`](Python/agents/python-researcher.md) | Investigates codebase and libraries before changes (read-only) | sonnet |
| [`python-developer`](Python/agents/python-developer.md) | Implements features against a contract | sonnet |
| [`python-test-engineer`](Python/agents/python-test-engineer.md) | pytest unit/integration/property tests | sonnet |
| [`python-code-reviewer`](Python/agents/python-code-reviewer.md) | Reviews diffs for correctness, design, idiom | sonnet |
| [`python-security-auditor`](Python/agents/python-security-auditor.md) | OWASP-mapped security findings (read-only) | sonnet |
| [`python-debugger`](Python/agents/python-debugger.md) | Root-cause failures (read-only) | sonnet |
| [`python-performance-engineer`](Python/agents/python-performance-engineer.md) | Profile and rank optimizations (read-only) | sonnet |
| [`python-refactorer`](Python/agents/python-refactorer.md) | Behavior-preserving restructuring | sonnet |
| [`python-docs-writer`](Python/agents/python-docs-writer.md) | Docstrings, READMEs, ADRs | sonnet |
| [`python-devops-engineer`](Python/agents/python-devops-engineer.md) | pyproject, CI, packaging, lockfiles | sonnet |
| [`python-api-integrator`](Python/agents/python-api-integrator.md) | Typed HTTP clients, auth, retries, webhooks | sonnet |
| [`python-data-engineer`](Python/agents/python-data-engineer.md) | pandas/polars, SQL, ETL, schema migrations | sonnet |

### Skills

| Skill | Topic |
|---|---|
| [`pytest-testing`](Python/skills/pytest-testing/SKILL.md) | pytest fixtures, parametrization, mocking, async, coverage |
| [`python-style`](Python/skills/python-style/SKILL.md) | PEP 8 + modern idioms (3.10+) |
| [`python-code-review`](Python/skills/python-code-review/SKILL.md) | Review checklist with severity guide |
| [`python-debugging`](Python/skills/python-debugging/SKILL.md) | Repro, traceback reading, common failure modes |
| [`python-logging`](Python/skills/python-logging/SKILL.md) | Structured logging, contextvars, dictConfig |
| [`python-packaging`](Python/skills/python-packaging/SKILL.md) | pyproject.toml, uv, lockfiles, Docker, CI |
| [`python-refactoring`](Python/skills/python-refactoring/SKILL.md) | Behavior-preserving refactoring patterns |
| [`python-security`](Python/skills/python-security/SKILL.md) | OWASP top 10 mapped to Python idioms |
| [`solid-principles`](Python/skills/solid-principles/SKILL.md) | SOLID applied to Python, with judgment |
| [`python-async-concurrency`](Python/skills/python-async-concurrency/SKILL.md) | asyncio, TaskGroup, cancellation, sync↔async bridging |

### .NET / C# Agents

| Agent | Role | Model |
|---|---|---|
| [`dotnet-orchestrator`](DotNet/agents/dotnet-orchestrator.md) | Coordinates the team for non-trivial .NET work | opus |
| [`dotnet-architect`](DotNet/agents/dotnet-architect.md) | Designs systems, project layout, API contracts (read-only) | opus |
| [`dotnet-researcher`](DotNet/agents/dotnet-researcher.md) | Investigates codebase and libraries before changes (read-only) | sonnet |
| [`dotnet-developer`](DotNet/agents/dotnet-developer.md) | Implements features against a contract | sonnet |
| [`dotnet-test-engineer`](DotNet/agents/dotnet-test-engineer.md) | xUnit/NUnit unit/integration/property tests | sonnet |
| [`dotnet-code-reviewer`](DotNet/agents/dotnet-code-reviewer.md) | Reviews diffs for correctness, design, idiom | sonnet |
| [`dotnet-security-auditor`](DotNet/agents/dotnet-security-auditor.md) | OWASP-mapped security findings (read-only) | sonnet |
| [`dotnet-debugger`](DotNet/agents/dotnet-debugger.md) | Root-cause failures (read-only) | sonnet |
| [`dotnet-performance-engineer`](DotNet/agents/dotnet-performance-engineer.md) | Profile and rank optimizations (read-only) | sonnet |
| [`dotnet-refactorer`](DotNet/agents/dotnet-refactorer.md) | Behavior-preserving restructuring | sonnet |
| [`dotnet-docs-writer`](DotNet/agents/dotnet-docs-writer.md) | XML doc comments, READMEs, ADRs | sonnet |
| [`dotnet-devops-engineer`](DotNet/agents/dotnet-devops-engineer.md) | .csproj, CI, NuGet, Docker, EditorConfig | sonnet |
| [`dotnet-api-integrator`](DotNet/agents/dotnet-api-integrator.md) | Typed HttpClient, auth, Polly retries, webhooks | sonnet |
| [`dotnet-data-engineer`](DotNet/agents/dotnet-data-engineer.md) | EF Core, Dapper, SQL, schema migrations | sonnet |

### .NET / C# Skills

| Skill | Topic |
|---|---|
| [`xunit-testing`](DotNet/skills/xunit-testing/SKILL.md) | xUnit fixtures, theory data, mocking, async, coverage |
| [`dotnet-style`](DotNet/skills/dotnet-style/SKILL.md) | C# coding standards, modern language features |
| [`dotnet-code-review`](DotNet/skills/dotnet-code-review/SKILL.md) | Review checklist with severity guide |
| [`dotnet-debugging`](DotNet/skills/dotnet-debugging/SKILL.md) | Repro, stack trace reading, common failure modes |
| [`dotnet-logging`](DotNet/skills/dotnet-logging/SKILL.md) | Structured logging, ILogger, Serilog, OpenTelemetry |
| [`dotnet-packaging`](DotNet/skills/dotnet-packaging/SKILL.md) | .csproj, Directory.Build.props, CPM, NuGet, Docker, CI |
| [`dotnet-refactoring`](DotNet/skills/dotnet-refactoring/SKILL.md) | Behavior-preserving refactoring patterns |
| [`dotnet-security`](DotNet/skills/dotnet-security/SKILL.md) | OWASP top 10 mapped to .NET idioms |
| [`solid-principles`](DotNet/skills/solid-principles/SKILL.md) | SOLID applied to C# / .NET, with judgment |
| [`dotnet-async-concurrency`](DotNet/skills/dotnet-async-concurrency/SKILL.md) | async/await, Task, Channel, cancellation, common pitfalls |

## Using these files in your editor

The agents and skills are plain Markdown files with YAML frontmatter. Most agent
tooling reads them from a host-specific directory. Run the sync script to populate
those directories:

```powershell
# Windows / PowerShell
pwsh ./scripts/sync-to-host.ps1
```

```bash
# macOS / Linux
./scripts/sync-to-host.sh
```

The script auto-discovers every language directory at the repo root (anything
containing `agents/` or `skills/`), aggregates them, and copies into both
`.github/` (for GitHub Copilot) and `.claude/` (for Claude Code). Pass
`-Languages Python` / `--lang Python` to restrict the sync to a subset.

### Claude Code

After syncing, Claude Code picks the agents up at `.claude/agents/` and the skills at
`.claude/skills/`. Invoke an agent with the Task tool or `/agents`; skills load on
demand based on their description.

### GitHub Copilot (VS Code / Cloud)

After syncing, the agents are at `.github/agents/` and the skills at
`.github/skills/`. They're available in Copilot Chat (`@agent-name`) and in the cloud
agent runner. See
[GitHub's custom agents docs](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-custom-agents).

### Other hosts

Most modern coding agents now support the
[Agent Skills open standard](https://agentskills.io). If your tool reads `SKILL.md`
files from a known location, point it at the language-specific skills directory
you care about (e.g. `Python/skills/`), or run the sync script and point at
`.github/skills/` or `.claude/skills/`.

For agent profiles, the in-frontmatter conventions match Copilot's and Claude Code's;
extend `scripts/sync-to-host.*` to target additional hosts if needed.

## Frontmatter convention

Every agent under `<Language>/agents/` uses this portable superset:

```yaml
---
name: <kebab-case identifier>
description: "<when to use this agent — trigger conditions, not just a summary>"
tools: [read, edit, search, execute, web, agent]
model: opus | sonnet | haiku
---
```

- **`name`** — must match the filename (without `.md`).
- **`description`** — used by the orchestrator/host to decide when to invoke this
  agent. Write trigger conditions, not a marketing blurb. Be specific about what's
  in scope and what's out.
- **`tools`** — lowercase aliases shared by Copilot and (case-insensitively) by
  Claude Code. Valid values: `read`, `edit`, `write`, `search`, `execute`/`bash`,
  `web`, `agent`. Omit if the agent should inherit the host's full toolset.
- **`model`** — alias (`opus` / `sonnet` / `haiku`). Hosts that don't support
  per-agent model selection ignore the field. Avoid pinning exact model IDs unless
  you have a reason — aliases survive model upgrades.

Every skill in `<Language>/skills/<name>/SKILL.md` uses the AgentSkills.io standard:

```yaml
---
name: <kebab-case, must match folder>
description: "<trigger conditions for when this skill applies>"
---
```

Optional standard fields if you need them: `license`, `allowed-tools`, `metadata`.

## Adding a new agent

1. Create `<Language>/agents/<name>.md` with the frontmatter above.
2. The body becomes the agent's system prompt — describe its role, what it does,
   what it doesn't do, and the output format.
3. Read existing agents in the same language directory for tone and structure.
4. Keep the filename globally unique across all language directories — both
   hosts see a flat aggregated list. Prefixing with the language (`python-`,
   `go-`, …) is the convention.
5. Run `scripts/sync-to-host.*` so it's available in your editor.
6. Cross-reference it from the language's orchestrator agent if the team should
   know about it.

## Adding a new skill

1. Create `<Language>/skills/<name>/SKILL.md`. The folder name must match the
   frontmatter `name`. Skill folder names must be globally unique across
   languages.
2. The body holds the procedural knowledge. Skills are typically read on demand
   when the description matches the user's intent.
3. Run the sync script.

## Adding a new language

1. Create a sibling directory at the repo root (e.g. `Go/`, `JavaScript/`).
2. Inside it, create `agents/` and/or `skills/` matching the same conventions
   the Python library uses.
3. Run `scripts/sync-to-host.*` — the sync script auto-discovers any top-level
   directory containing `agents/` or `skills/`.

## Project conventions

See [AGENTS.md](AGENTS.md) for repo-level conventions every agent should follow.

## License

MIT. See `LICENSE` if present.
