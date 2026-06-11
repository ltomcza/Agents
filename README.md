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
│       ├── xunit-testing/
│       │   └── SKILL.md
│       ├── async-concurrency/
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
the same destination; agent filenames are scoped by their language directory and
do not require a language prefix.

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
| [`test-engineer`](DotNet/agents/test-engineer.md) | xUnit/NUnit unit/integration/property tests | sonnet |
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
| [`xunit-testing`](DotNet/skills/xunit-testing/SKILL.md) | xUnit fixtures, theory data, mocking, async, coverage |
| [`style`](DotNet/skills/style/SKILL.md) | C# coding standards, modern language features |
| [`code-review`](DotNet/skills/code-review/SKILL.md) | Review checklist with severity guide |
| [`debugging`](DotNet/skills/debugging/SKILL.md) | Repro, stack trace reading, common failure modes |
| [`logging`](DotNet/skills/logging/SKILL.md) | Structured logging, ILogger, Serilog, OpenTelemetry |
| [`packaging`](DotNet/skills/packaging/SKILL.md) | .csproj, Directory.Build.props, CPM, NuGet, Docker, CI |
| [`refactoring`](DotNet/skills/refactoring/SKILL.md) | Behavior-preserving refactoring patterns |
| [`security`](DotNet/skills/security/SKILL.md) | OWASP top 10 mapped to .NET idioms |
| [`solid-principles`](DotNet/skills/solid-principles/SKILL.md) | SOLID applied to C# / .NET, with judgment |
| [`async-concurrency`](DotNet/skills/async-concurrency/SKILL.md) | async/await, Task, Channel, cancellation, common pitfalls |

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
4. Filenames are scoped by their language directory — no language prefix needed.
   When the sync script flattens them into a single host directory, it uses the
   language directory name as a prefix (e.g. `python-architect`) to avoid
   collisions.
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
