#!/usr/bin/env bash
# Mirrors canonical agent and skill libraries into .github/ and .claude/ host
# directories.
#
# The canonical source of truth is per-language directories at the repo root,
# each containing agents/ and/or skills/ subdirectories — for example,
# Python/agents/ and Python/skills/. Add more languages as sibling directories.
#
# GitHub Copilot looks under .github/agents and .github/skills.
# Claude Code looks under .claude/agents and .claude/skills.
#
# Because both hosts expect a flat list of agents and a flat list of skill
# folders, this script aggregates the selected language sources into a single
# flat destination per host. Agent files keep their bare names (no language
# prefix), so sync one language at a time — pass --lang to scope the run — to
# avoid cross-language filename collisions in the shared destination.
#
# Agent frontmatter uses portable lowercase tool aliases (read, edit, search,
# execute, web, agent), which GitHub Copilot understands natively. When writing
# the Claude Code copy, this script translates those aliases into Claude Code's
# tool names (Read, Edit, Write, Grep, Glob, Bash, WebSearch, WebFetch, Task).
# Skills are identical across hosts and are copied verbatim.
#
# Usage:
#   ./scripts/sync-to-host.sh                   # sync all hosts, all languages
#   ./scripts/sync-to-host.sh --host claude     # one host only
#   ./scripts/sync-to-host.sh --lang Python     # one language only
#   ./scripts/sync-to-host.sh --clean           # wipe destinations first

set -euo pipefail

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
REPO_ROOT="$( cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd )"

EXCLUDED_DIRS=(.git .github .claude .vscode .idea scripts node_modules)

CLEAN=0
HOSTS=()
LANGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN=1; shift ;;
        --host)
            if [[ "${2:-}" != "copilot" && "${2:-}" != "claude" ]]; then
                echo "--host requires copilot or claude" >&2; exit 2
            fi
            HOSTS+=("$2"); shift 2 ;;
        --lang)
            if [[ -z "${2:-}" ]]; then
                echo "--lang requires a language directory name" >&2; exit 2
            fi
            LANGS+=("$2"); shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--host copilot|claude]... [--lang <name>]... [--clean]" >&2
            exit 2 ;;
    esac
done

if [[ ${#HOSTS[@]} -eq 0 ]]; then
    HOSTS=(copilot claude)
fi

is_excluded() {
    local name="$1"
    for excluded in "${EXCLUDED_DIRS[@]}"; do
        [[ "$name" == "$excluded" ]] && return 0
    done
    return 1
}

discover_languages() {
    local -a found=()
    for dir in "${REPO_ROOT}"/*/; do
        [[ -d "$dir" ]] || continue
        local name; name=$(basename "$dir")
        is_excluded "$name" && continue

        # If --lang was passed, filter.
        if [[ ${#LANGS[@]} -gt 0 ]]; then
            local match=0
            for wanted in "${LANGS[@]}"; do
                [[ "$name" == "$wanted" ]] && match=1
            done
            [[ $match -eq 1 ]] || continue
        fi

        # Only include if it has agents/ or skills/.
        if [[ -d "${dir}/agents" || -d "${dir}/skills" ]]; then
            found+=("$name")
        fi
    done
    printf '%s\n' "${found[@]}"
}

mapfile -t LANG_DIRS < <(discover_languages)

if [[ ${#LANG_DIRS[@]} -eq 0 ]]; then
    echo "No source language directories with agents/ or skills/ found under ${REPO_ROOT}" >&2
    exit 1
fi

echo "Source languages: ${LANG_DIRS[*]}"
echo ""

ensure_dir() { mkdir -p "$1"; }
clear_dir()  { [[ -d "$1" ]] && { echo "  cleaning $1"; rm -rf "$1"; }; mkdir -p "$1"; }

# Rewrites a `tools: [alias, ...]` frontmatter line (portable lowercase aliases)
# into Claude Code's comma-separated tool-name form. Unknown aliases pass through
# unchanged so nothing is silently dropped; files without a tools line are copied
# through untouched. Reads stdin, writes stdout.
translate_tools_for_claude() {
    awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        BEGIN {
            map["read"]    = "Read"
            map["write"]   = "Write"
            map["edit"]    = "Edit, Write"
            map["search"]  = "Grep, Glob"
            map["execute"] = "Bash"
            map["web"]     = "WebSearch, WebFetch"
            map["agent"]   = "Task"
            map["todo"]    = "TodoWrite"
        }
        /^tools:[ \t]*\[.*\][ \t]*$/ {
            line = $0
            sub(/^tools:[ \t]*\[/, "", line)
            sub(/\][ \t]*$/, "", line)
            n = split(line, parts, ",")
            out = ""
            delete seen
            for (i = 1; i <= n; i++) {
                alias = tolower(trim(parts[i]))
                if (alias == "") continue
                mapped = (alias in map) ? map[alias] : trim(parts[i])
                k = split(mapped, toks, ",")
                for (j = 1; j <= k; j++) {
                    t = trim(toks[j])
                    if (t == "" || (t in seen)) continue
                    seen[t] = 1
                    out = (out == "") ? t : out ", " t
                }
            }
            print "tools: " out
            next
        }
        { print }
    '
}

for host in "${HOSTS[@]}"; do
    echo "→ syncing host: ${host}"

    case "$host" in
        copilot)
            agents_dst="${REPO_ROOT}/.github/agents"
            skills_dst="${REPO_ROOT}/.github/skills" ;;
        claude)
            agents_dst="${REPO_ROOT}/.claude/agents"
            skills_dst="${REPO_ROOT}/.claude/skills" ;;
    esac

    if [[ $CLEAN -eq 1 ]]; then
        clear_dir "$agents_dst"
        clear_dir "$skills_dst"
    else
        ensure_dir "$agents_dst"
        ensure_dir "$skills_dst"
    fi

    for lang in "${LANG_DIRS[@]}"; do
        src_agents="${REPO_ROOT}/${lang}/agents"
        src_skills="${REPO_ROOT}/${lang}/skills"

        if [[ -d "$src_agents" ]]; then
            echo "  ${lang}/agents/  →  ${agents_dst}"
            for agent_file in "${src_agents}"/*.md; do
                [[ -f "$agent_file" ]] || continue
                dest="${agents_dst}/$(basename "$agent_file")"
                if [[ "$host" == "claude" ]]; then
                    translate_tools_for_claude < "$agent_file" > "$dest"
                else
                    cp -f "$agent_file" "$dest"
                fi
            done
        fi

        if [[ -d "$src_skills" ]]; then
            echo "  ${lang}/skills/  →  ${skills_dst}"
            for skill_dir in "${src_skills}"/*/; do
                [[ -d "$skill_dir" ]] || continue
                name=$(basename "$skill_dir")
                mkdir -p "${skills_dst}/${name}"
                cp -rf "${skill_dir}/." "${skills_dst}/${name}/"
            done
        fi
    done
done

echo ""
echo "Done. Canonical source: <Language>/agents/, <Language>/skills/"
echo "Edit canonical files; re-run this script to update host directories."
