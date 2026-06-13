# AGENTS.md

Project-level conventions for any AI coding agent working in this repository.
This file follows the [agents.md](https://agents.md) open standard and is read
automatically by Codex, Cursor, Copilot, Claude Code, and other compatible tools.

## What this repo is

A portable library of agent profiles and skills for software engineering,
namespaced by language. Libraries live under `<Language>/agents/` and
`<Language>/skills/` — currently `Python/`, `DotNet/`, and `SQL/`; future languages
get sibling directories at the repo root. There is no application code to run,
build, or test — the deliverables are Markdown definitions consumed by other AI
tools.

## Source of truth

- `<Language>/agents/*.md` and `<Language>/skills/*/SKILL.md` are canonical.
  Edit these.
- `.claude/agents/` and `.claude/skills/` are derived by `scripts/sync-to-host.*`
  and read by **both** Claude Code and GitHub Copilot. They are gitignored build
  artifacts — do not edit them by hand; regenerate with the sync script.
  (`.claude/settings.local.json` is not generated and is kept.)
- If you change a canonical file, re-run the sync script to refresh `.claude/`.

## Setup

No virtualenv or package install is needed to work in this repo. To exercise the
sync script:

```powershell
# Windows
pwsh ./scripts/sync-to-host.ps1
```

```bash
# macOS / Linux
./scripts/sync-to-host.sh
```

## Conventions for adding or editing agent profiles

- Filename is the kebab-case agent identifier with `.md` (e.g.,
  `architect.md`). The `name:` field in the frontmatter must match.
- Frontmatter uses the portable superset documented in `README.md`. Every agent
  declares an explicit `tools` list using the PascalCase names that both Claude
  Code and Copilot accept directly (`Read, Edit, Write, Grep, Glob, Bash,
  WebSearch, WebFetch, Task, TodoWrite`) so the source file is environment-agnostic
  with no translation needed — including full-access read/write agents, which list
  their complete toolset rather than omitting the field. PascalCase is the only
  canonical form; the sync script copies agent files verbatim and does no
  frontmatter rewriting. Do not introduce host-specific fields in canonical files;
  if a host needs a transform, add it in the sync script.
- The `description:` field is what an orchestrator reads to decide whether to
  invoke this agent. Write it as trigger conditions ("Use when …"), not a summary.
- Model aliases only: `opus`, `sonnet`, `haiku`. Do not pin specific model IDs
  unless there's a documented reason — aliases survive model upgrades.
- The body of the file is the system prompt. Write it in second person ("You are
  …"), define inputs/outputs explicitly, and end with an `Output to the
  orchestrator` block that names the deliverable shape.

## Conventions for adding or editing skills

- Folder under `<Language>/skills/` matches the skill name.
- Frontmatter follows the [AgentSkills.io](https://agentskills.io) standard:
  `name` and `description` required. Optional: `license`, `allowed-tools`,
  `metadata`.
- The body is procedural knowledge: how-tos, patterns, idioms, anti-patterns,
  decision tables. Aim for "what a senior engineer would tell a peer in a
  pair-programming session."
- Use code blocks for every non-trivial pattern. Show both the wrong way and the
  right way when the contrast clarifies.

## Code style for examples in agent/skill bodies

When showing Python in code blocks, follow the standards in
[`Python/skills/style/SKILL.md`](Python/skills/style/SKILL.md):

- Type hints on all public signatures.
- Modern syntax (`list[int]`, `X | None`) — assume Python 3.10+ unless the example
  is explicitly about older versions.
- f-strings, `pathlib`, context managers.
- One-line summaries in docstrings, imperative mood.

When showing C# in code blocks, follow the standards in
[`DotNet/skills/style/SKILL.md`](DotNet/skills/style/SKILL.md):

- Nullable reference types enabled; annotations on all public signatures.
- File-scoped namespaces, `sealed` by default, `record` for value-shaped data.
- Modern syntax (primary constructors, collection expressions, pattern matching) —
  assume .NET 8+ / C# 12+ unless the example targets an older version.
- XML doc comments on public API. `ILogger<T>` for logging.

The examples in `DotNet/skills/packaging/SKILL.md` and the `devops-engineer` agent
target **.NET 8 (LTS, released November 2023)** by default. Use a newer target only
when the example specifically needs it.

## Tone

- Direct and concrete. The reader is a busy engineer, not a tutorial student.
- Examples over prose. A decision table beats three paragraphs.
- Name the trap, then show the fix. "Mutable default arguments" → bad/good code.
- No marketing voice. No emoji.

## Testing changes

There is no automated test suite (yet). Manual validation:

1. Run the sync script and confirm `.claude/agents/` and `.claude/skills/` mirror
   the canonical files (one language at a time to avoid name collisions).
2. Open one agent in your editor of choice (Claude Code or Copilot) and confirm
   it loads — descriptions render, model selection takes effect.
3. For a substantive content change, run the agent on a small representative task
   and compare output against the previous version.

## Commit hygiene

- Commit only canonical files (under `<Language>/agents/` and
  `<Language>/skills/`). The `.claude/agents/` and `.claude/skills/` output is
  gitignored — regenerate it locally with the sync script; don't commit it.
- One agent or one skill per commit when practical. Cross-cutting frontmatter
  changes can be bundled.
- Commit messages name the agent/skill with its language directory: `Python/data-engineer: clarify pandera lazy mode`.

## PR conventions

- Title: short, imperative, includes affected agent/skill name.
- Description: what changed, why, and (if applicable) a paste of before/after
  output from an example invocation.

## Out of scope

- Application code. This repo contains definitions only.
- Host-specific extensions (Copilot's MCP server configs, Claude Code's hooks)
  that don't translate across tools. If a host needs them, the sync script is the
  right place to inject them.
