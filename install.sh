#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=false

# Detect target directory from flags
SKILLS_DIR=""
for arg in "$@"; do
    case "$arg" in
        --force)   FORCE=true ;;
        --codex)   SKILLS_DIR="$HOME/.codex/skills" ;;
        --claude)  SKILLS_DIR="$HOME/.claude/skills" ;;
        --agents)  SKILLS_DIR="$HOME/.agents/skills" ;;
        *)         echo "Unknown flag: $arg"; echo "Usage: ./install.sh [--claude|--codex|--agents] [--force]"; exit 1 ;;
    esac
done

# Default: auto-detect runtime
if [[ -z "$SKILLS_DIR" ]]; then
    if command -v claude &>/dev/null; then
        SKILLS_DIR="$HOME/.claude/skills"
    elif command -v codex &>/dev/null; then
        SKILLS_DIR="$HOME/.codex/skills"
    else
        SKILLS_DIR="$HOME/.agents/skills"
    fi
fi

echo "Installing to: $SKILLS_DIR"
mkdir -p "$SKILLS_DIR"

installed=0
skipped=0

for skill_dir in "$SCRIPT_DIR"/*/; do
    # Support both flat (SKILL.md at root) and plugin (skills/*/SKILL.md) structures
    [[ -f "$skill_dir/SKILL.md" ]] || ls "$skill_dir"/skills/*/SKILL.md &>/dev/null || continue
    name="$(basename "$skill_dir")"
    target="$SKILLS_DIR/$name"

    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$FORCE" == true ]]; then
            rm -rf "$target"
        else
            echo "skip: $name (already exists, use --force to override)"
            skipped=$((skipped + 1))
            continue
        fi
    fi

    ln -s "$skill_dir" "$target"
    echo "  ok: $name"
    installed=$((installed + 1))
done

echo ""
echo "Done: $installed installed, $skipped skipped"
