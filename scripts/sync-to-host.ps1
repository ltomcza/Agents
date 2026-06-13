#!/usr/bin/env pwsh
<#
.SYNOPSIS
Mirrors canonical agent and skill libraries into .github/ and .claude/ host directories.

.DESCRIPTION
The canonical source of truth is per-language directories at the repo root, each
containing agents/ and/or skills/ subdirectories — for example, Python/agents/ and
Python/skills/. Add more languages as sibling directories (Go/, JavaScript/, ...).

GitHub Copilot looks under .github/agents and .github/skills.
Claude Code looks under .claude/agents and .claude/skills.

Because both hosts expect a flat list of agents and a flat list of skill folders,
this script aggregates the selected language sources into a single flat destination
per host. Agent files keep their bare names (no language prefix), so sync one
language at a time — pass -Languages to scope the run — to avoid cross-language
filename collisions in the shared destination.

Agent frontmatter uses portable lowercase tool aliases (read, edit, search,
execute, web, agent), which GitHub Copilot understands natively. When writing the
Claude Code copy, this script translates those aliases into Claude Code's tool
names (Read, Edit, Write, Grep, Glob, Bash, WebSearch, WebFetch, Task). Skills are
identical across hosts and are copied verbatim.

.PARAMETER Hosts
Limit the sync to a subset of hosts. Default: both copilot and claude.

.PARAMETER Languages
Limit the sync to a subset of source languages. Default: every top-level
directory containing an agents/ or skills/ subfolder.

.PARAMETER Clean
Wipe destination directories before syncing.

.EXAMPLE
pwsh scripts/sync-to-host.ps1

.EXAMPLE
pwsh scripts/sync-to-host.ps1 -Hosts claude -Clean

.EXAMPLE
pwsh scripts/sync-to-host.ps1 -Languages Python
#>
[CmdletBinding()]
param(
    [ValidateSet('copilot', 'claude')]
    [string[]] $Hosts = @('copilot', 'claude'),

    [string[]] $Languages,

    [switch] $Clean
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# Directories at repo root that are never source languages.
$ExcludedRootDirs = @('.git', '.github', '.claude', '.vscode', '.idea', 'scripts', 'node_modules')

function Get-LanguageDirs {
    $candidates = Get-ChildItem -Path $RepoRoot -Directory |
        Where-Object { $_.Name -notin $ExcludedRootDirs }

    if ($Languages) {
        $candidates = $candidates | Where-Object { $_.Name -in $Languages }
        if (-not $candidates) {
            throw "No matching language directories found for: $($Languages -join ', ')"
        }
    }

    # Keep only directories that actually contain agents/ or skills/.
    $candidates | Where-Object {
        (Test-Path (Join-Path $_.FullName 'agents')) -or
        (Test-Path (Join-Path $_.FullName 'skills'))
    }
}

$HostTargets = @{
    copilot = @{
        agents = Join-Path $RepoRoot '.github/agents'
        skills = Join-Path $RepoRoot '.github/skills'
    }
    claude = @{
        agents = Join-Path $RepoRoot '.claude/agents'
        skills = Join-Path $RepoRoot '.claude/skills'
    }
}

function Ensure-Dir {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Clear-Dir {
    param([string] $Path)
    if (Test-Path $Path) {
        Write-Host "  cleaning $Path"
        Remove-Item $Path -Recurse -Force
    }
    Ensure-Dir $Path
}

# Maps the portable lowercase tool aliases (Copilot-native) to Claude Code's tool
# names. Order is preserved and the expansion is de-duplicated.
$ClaudeToolMap = [ordered]@{
    'read'    = @('Read')
    'write'   = @('Write')
    'edit'    = @('Edit', 'Write')
    'search'  = @('Grep', 'Glob')
    'execute' = @('Bash')
    'web'     = @('WebSearch', 'WebFetch')
    'agent'   = @('Task')
    'todo'    = @('TodoWrite')
}

# Rewrites a `tools: [alias, ...]` line in the leading YAML frontmatter into
# Claude Code's comma-separated tool-name form. Unknown aliases pass through
# unchanged so nothing is silently dropped. Content without a tools line is
# returned as-is.
function Convert-ToolsForClaude {
    param([string] $Content)

    $evaluator = {
        param($match)
        $tools = [System.Collections.Generic.List[string]]::new()
        $aliases = $match.Groups['list'].Value -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        foreach ($alias in $aliases) {
            $key = $alias.ToLowerInvariant()
            $mapped = if ($ClaudeToolMap.Contains($key)) { $ClaudeToolMap[$key] } else { @($alias) }
            foreach ($tool in $mapped) {
                if (-not $tools.Contains($tool)) { $tools.Add($tool) }
            }
        }
        "tools: $($tools -join ', ')"
    }

    return [regex]::Replace(
        $Content,
        '(?m)^tools:[ \t]*\[(?<list>[^\]]*)\][ \t]*$',
        $evaluator)
}

$languageDirs = @(Get-LanguageDirs)
if (-not $languageDirs) {
    throw "No source language directories with agents/ or skills/ found under $RepoRoot."
}

Write-Host "Source languages: $($languageDirs.Name -join ', ')"
Write-Host ""

foreach ($name in $Hosts) {
    $targets = $HostTargets[$name]
    Write-Host "→ syncing host: $name"

    if ($Clean) {
        Clear-Dir $targets.agents
        Clear-Dir $targets.skills
    } else {
        Ensure-Dir $targets.agents
        Ensure-Dir $targets.skills
    }

    foreach ($lang in $languageDirs) {
        $srcAgents = Join-Path $lang.FullName 'agents'
        $srcSkills = Join-Path $lang.FullName 'skills'

        if (Test-Path $srcAgents) {
            Write-Host "  $($lang.Name)/agents/  →  $($targets.agents)"
            foreach ($agentFile in Get-ChildItem -Path $srcAgents -Filter '*.md' -File) {
                $dest = Join-Path $targets.agents $agentFile.Name
                if ($name -eq 'claude') {
                    $content = Get-Content -Path $agentFile.FullName -Raw
                    Set-Content -Path $dest -Value (Convert-ToolsForClaude $content) -NoNewline
                } else {
                    Copy-Item -Path $agentFile.FullName -Destination $dest -Force
                }
            }
        }

        if (Test-Path $srcSkills) {
            Write-Host "  $($lang.Name)/skills/  →  $($targets.skills)"
            Get-ChildItem -Path $srcSkills -Directory | ForEach-Object {
                $destSkill = Join-Path $targets.skills $_.Name
                Ensure-Dir $destSkill
                Copy-Item -Path (Join-Path $_.FullName '*') -Destination $destSkill -Recurse -Force
            }
        }
    }
}

Write-Host ""
Write-Host "Done. Canonical source: <Language>/agents/, <Language>/skills/"
Write-Host "Edit canonical files; re-run this script to update host directories."
