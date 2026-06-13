# Agents & Skills

A portable library of AI **agent profiles** and **skills**, namespaced by language
(Python, .NET / C#, and SQL / T-SQL today; add sibling directories for other
languages as needed).
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
│   │   ├── architect.md
│   │   ├── developer.md
│   │   ├── orchestrator.md
│   │   └── ...
│   └── skills/              # canonical skills (one folder per skill)
│       ├── testing/
│       │   └── SKILL.md
│       ├── async-concurrency/
│       │   └── SKILL.md
│       └── ...
├── DotNet/
│   ├── agents/              # .NET / C# agent profiles
│   │   ├── architect.md
│   │   ├── developer.md
│   │   ├── orchestrator.md
│   │   └── ...
│   └── skills/              # .NET / C# skills
│       ├── nunit-testing/
│       │   └── SKILL.md
│       ├── async-concurrency/
│       │   └── SKILL.md
│       └── ...
├── scripts/
│   ├── sync-to-host.ps1     # generate .claude/ (read by both hosts) on Windows
│   └── sync-to-host.sh      # same, POSIX shells
├── AGENTS.md                # project conventions (read by any agent)
└── README.md
```

The files under `<Language>/agents/` and `<Language>/skills/` are the **single
source of truth**. The sync script generates one `.claude/` directory that **both**
Claude Code and GitHub Copilot read — treat it as a gitignored build artifact and
do not edit it directly. Both hosts expect a flat list, so the script copies the
selected language's files into the destination under their bare names (no language
prefix). Sync one language at a time (pass `-Languages` / `--lang`) so
identically-named files from different languages don't collide in the shared host
directory.

## Roster

### Agents

| Agent | Role | Model |
|---|---|---|
| [`orchestrator`](Python/agents/orchestrator.md) | Coordinates the team for non-trivial Python work | opus |
| [`architect`](Python/agents/architect.md) | Designs systems, module layout, API contracts (read-only) | opus |
| [`researcher`](Python/agents/researcher.md) | Investigates codebase and libraries before changes (read-only) | sonnet |
| [`developer`](Python/agents/developer.md) | Implements features against a contract | sonnet |
| [`test-engineer`](Python/agents/test-engineer.md) | pytest unit/integration/property tests | sonnet |
| [`code-reviewer`](Python/agents/code-reviewer.md) | Reviews diffs for correctness, design, idiom | sonnet |
| [`security-auditor`](Python/agents/security-auditor.md) | OWASP-mapped security findings (read-only) | sonnet |
| [`debugger`](Python/agents/debugger.md) | Root-cause failures (read-only) | sonnet |
| [`performance-engineer`](Python/agents/performance-engineer.md) | Profile and rank optimizations (read-only) | sonnet |
| [`refactorer`](Python/agents/refactorer.md) | Behavior-preserving restructuring | sonnet |
| [`docs-writer`](Python/agents/docs-writer.md) | Docstrings, READMEs, ADRs | sonnet |
| [`devops-engineer`](Python/agents/devops-engineer.md) | pyproject, CI, packaging, lockfiles | sonnet |
| [`api-integrator`](Python/agents/api-integrator.md) | Typed HTTP clients, auth, retries, webhooks | sonnet |
| [`data-engineer`](Python/agents/data-engineer.md) | pandas/polars, SQL, ETL, schema migrations | sonnet |

### Skills

| Skill | Topic |
|---|---|
| [`testing`](Python/skills/testing/SKILL.md) | pytest fixtures, parametrization, mocking, async, coverage |
| [`style`](Python/skills/style/SKILL.md) | PEP 8 + modern idioms (3.10+) |
| [`code-review`](Python/skills/code-review/SKILL.md) | Review checklist with severity guide |
| [`debugging`](Python/skills/debugging/SKILL.md) | Repro, traceback reading, common failure modes |
| [`logging`](Python/skills/logging/SKILL.md) | Structured logging, contextvars, dictConfig |
| [`packaging`](Python/skills/packaging/SKILL.md) | pyproject.toml, uv, lockfiles, Docker, CI |
| [`refactoring`](Python/skills/refactoring/SKILL.md) | Behavior-preserving refactoring patterns |
| [`security`](Python/skills/security/SKILL.md) | OWASP top 10 mapped to Python idioms |
| [`solid-principles`](Python/skills/solid-principles/SKILL.md) | SOLID applied to Python, with judgment |
| [`async-concurrency`](Python/skills/async-concurrency/SKILL.md) | asyncio, TaskGroup, cancellation, sync↔async bridging |

### .NET / C# Agents

| Agent | Role | Model |
|---|---|---|
| [`orchestrator`](DotNet/agents/orchestrator.md) | Coordinates the team for non-trivial .NET work | opus |
| [`architect`](DotNet/agents/architect.md) | Designs systems, project layout, API contracts (read-only) | opus |
| [`researcher`](DotNet/agents/researcher.md) | Investigates codebase and libraries before changes (read-only) | sonnet |
| [`developer`](DotNet/agents/developer.md) | Implements features against a contract | sonnet |
| [`test-engineer`](DotNet/agents/test-engineer.md) | NUnit unit/integration/property tests | sonnet |
| [`code-reviewer`](DotNet/agents/code-reviewer.md) | Reviews diffs for correctness, design, idiom | sonnet |
| [`security-auditor`](DotNet/agents/security-auditor.md) | OWASP-mapped security findings (read-only) | sonnet |
| [`debugger`](DotNet/agents/debugger.md) | Root-cause failures (read-only) | sonnet |
| [`performance-engineer`](DotNet/agents/performance-engineer.md) | Profile and rank optimizations (read-only) | sonnet |
| [`refactorer`](DotNet/agents/refactorer.md) | Behavior-preserving restructuring | sonnet |
| [`docs-writer`](DotNet/agents/docs-writer.md) | XML doc comments, READMEs, ADRs | sonnet |
| [`devops-engineer`](DotNet/agents/devops-engineer.md) | .csproj, CI, NuGet, Docker, EditorConfig | sonnet |
| [`api-integrator`](DotNet/agents/api-integrator.md) | Typed HttpClient, auth, Polly retries, webhooks | sonnet |
| [`data-engineer`](DotNet/agents/data-engineer.md) | EF Core, Dapper, SQL, schema migrations | sonnet |

### .NET / C# Skills

| Skill | Topic |
|---|---|
| [`nunit-testing`](DotNet/skills/nunit-testing/SKILL.md) | NUnit fixtures, test-case data, mocking, async, coverage |
| [`style`](DotNet/skills/style/SKILL.md) | C# coding standards, modern language features |
| [`code-review`](DotNet/skills/code-review/SKILL.md) | Review checklist with severity guide |
| [`debugging`](DotNet/skills/debugging/SKILL.md) | Repro, stack trace reading, common failure modes |
| [`logging`](DotNet/skills/logging/SKILL.md) | Structured logging, ILogger, Serilog, OpenTelemetry |
| [`packaging`](DotNet/skills/packaging/SKILL.md) | .csproj, Directory.Build.props, CPM, NuGet, Docker, CI |
| [`refactoring`](DotNet/skills/refactoring/SKILL.md) | Behavior-preserving refactoring patterns |
| [`security`](DotNet/skills/security/SKILL.md) | OWASP top 10 mapped to .NET idioms |
| [`solid-principles`](DotNet/skills/solid-principles/SKILL.md) | SOLID applied to C# / .NET, with judgment |
| [`async-concurrency`](DotNet/skills/async-concurrency/SKILL.md) | async/await, Task, Channel, cancellation, common pitfalls |
| [`dependency-injection`](DotNet/skills/dependency-injection/SKILL.md) | Lifetimes, captive deps, keyed services, IOptions, composition root |
| [`ef-core`](DotNet/skills/ef-core/SKILL.md) | DbContext lifetime, Fluent mapping, query patterns, migrations, interceptors |

### SQL / T-SQL Agents

| Agent | Role | Model |
|---|---|---|
| [`tsql-orchestrator`](SQL/agents/tsql-orchestrator.md) | Coordinates the team for non-trivial T-SQL work | opus |
| [`tsql-architect`](SQL/agents/tsql-architect.md) | Designs schemas, object boundaries, contracts (read-only) | opus |
| [`tsql-developer`](SQL/agents/tsql-developer.md) | Implements procs, functions, views, DDL/DML against a contract | sonnet |
| [`tsql-test-engineer`](SQL/agents/tsql-test-engineer.md) | tSQLt unit/integration tests, fake tables, spies | sonnet |
| [`tsql-code-reviewer`](SQL/agents/tsql-code-reviewer.md) | Reviews diffs for anti-patterns, idiom, design (read-only) | sonnet |
| [`tsql-security-auditor`](SQL/agents/tsql-security-auditor.md) | Injection, dynamic SQL, permissions, OWASP DB (read-only) | sonnet |
| [`tsql-debugger`](SQL/agents/tsql-debugger.md) | Root-cause query errors, deadlocks, anomalies (read-only) | sonnet |
| [`tsql-performance-tuner`](SQL/agents/tsql-performance-tuner.md) | Execution plans, waits, Query Store; ranked tuning (read-only) | sonnet |
| [`tsql-refactorer`](SQL/agents/tsql-refactorer.md) | Cursor→set-based, behavior-preserving restructuring | sonnet |
| [`tsql-docs-writer`](SQL/agents/tsql-docs-writer.md) | Object headers, extended properties, data dictionaries | sonnet |
| [`tsql-migration-engineer`](SQL/agents/tsql-migration-engineer.md) | Version-controlled DDL, safe deploys, rollback strategy | sonnet |
| [`tsql-index-advisor`](SQL/agents/tsql-index-advisor.md) | Index recommendations from query and plan analysis | sonnet |
| [`tsql-etl-engineer`](SQL/agents/tsql-etl-engineer.md) | ETL/ELT proc chains, SSIS, staging, incremental loads | sonnet |

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
containing `agents/` or `skills/`), aggregates them, and writes a single `.claude/`
directory that **both** GitHub Copilot and Claude Code read. Pass
`-Languages Python` / `--lang Python` to restrict the sync to a subset. The
generated directory is gitignored — re-run the script after pulling or editing a
canonical file.

### Claude Code

After syncing, Claude Code picks the agents up at `.claude/agents/` and the skills at
`.claude/skills/`. Invoke an agent with the Task tool or `/agents`; skills load on
demand based on their description.

### GitHub Copilot (VS Code / Cloud)

Copilot discovers custom agents under `.claude/agents/` and skills under
`.claude/skills/` (the same files Claude Code uses), so no separate copy is needed.
They're available in Copilot Chat (`@agent-name`) and in the cloud agent runner. See
[GitHub's custom agents docs](https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-custom-agents)
and [agent skills docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills).

### Other hosts

Most modern coding agents now support the
[Agent Skills open standard](https://agentskills.io). If your tool reads `SKILL.md`
files from a known location, point it at the language-specific skills directory
you care about (e.g. `Python/skills/`), or run the sync script and point at
`.claude/skills/`.

For agent profiles, the in-frontmatter conventions match Copilot's and Claude Code's;
extend `scripts/sync-to-host.*` to target additional hosts (e.g. a `.github/` copy)
if needed.

## Frontmatter convention

Every agent under `<Language>/agents/` uses this portable superset:

```yaml
---
name: <kebab-case identifier>
description: "<when to use this agent — trigger conditions, not just a summary>"
tools: Read, Grep, Glob, WebSearch, WebFetch   # required — explicit PascalCase list on every agent
model: opus | sonnet | haiku
---
```

- **`name`** — must match the filename (without `.md`).
- **`description`** — used by the orchestrator/host to decide when to invoke this
  agent. Write trigger conditions, not a marketing blurb. Be specific about what's
  in scope and what's out.
- **`tools`** — required; declared explicitly on **every** agent. Use the
  PascalCase, comma-separated tool names that **both** hosts accept directly:
  `Read`, `Edit`, `Write`, `Grep`, `Glob`, `Bash`, `WebSearch`, `WebFetch`, `Task`,
  `TodoWrite`. Claude Code reads these natively, and GitHub Copilot recognizes each
  as one of its documented tool aliases — so the source file is environment-agnostic
  with no translation needed. Restricted agents (read-only reviewers, auditors, the
  orchestrator) list only what they need; full-access read/write agents list their
  complete toolset rather than omitting the field, so the granted set is explicit
  and host-independent. PascalCase is the only canonical form — the sync script
  copies agent files verbatim and does no frontmatter rewriting.
- **`model`** — alias (`opus` / `sonnet` / `haiku`). Claude Code honors these;
  Copilot falls back to its model picker if the alias isn't one of its IDs. Avoid
  pinning exact model IDs unless you have a reason — aliases survive model upgrades.

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
4. Filenames use bare kebab-case names — no language prefix. The sync script copies
   them into the host directory unchanged, so sync one language at a time
   (`-Languages` / `--lang`) to avoid collisions with same-named agents in another
   language.
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
