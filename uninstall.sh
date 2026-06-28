#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect target directory from flags
SKILLS_DIR=""
for arg in "$@"; do
    case "$arg" in
        --codex)   SKILLS_DIR="$HOME/.codex/skills" ;;
        --claude)  SKILLS_DIR="$HOME/.claude/skills" ;;
        --agents)  SKILLS_DIR="$HOME/.agents/skills" ;;
        *)         echo "Unknown flag: $arg"; echo "Usage: ./uninstall.sh [--claude|--codex|--agents]"; exit 1 ;;
    esac
done

if [[ -z "$SKILLS_DIR" ]]; then
    if command -v claude &>/dev/null; then
        SKILLS_DIR="$HOME/.claude/skills"
    elif command -v codex &>/dev/null; then
        SKILLS_DIR="$HOME/.codex/skills"
    else
        SKILLS_DIR="$HOME/.agents/skills"
    fi
fi

echo "Uninstalling from: $SKILLS_DIR"

removed=0

for skill_dir in "$SCRIPT_DIR"/*/; do
    [[ -f "$skill_dir/SKILL.md" ]] || ls "$skill_dir"/skills/*/SKILL.md &>/dev/null || continue
    name="$(basename "$skill_dir")"
    target="$SKILLS_DIR/$name"

    if [[ -L "$target" ]]; then
        real="$(readlink "$target")"
        if [[ "$real" == "$skill_dir"* || "$real" == "${skill_dir%/}" ]]; then
            rm "$target"
            echo "  rm: $name"
            removed=$((removed + 1))
        else
            echo "skip: $name (symlink points elsewhere: $real)"
        fi
    fi
done

echo ""
echo "Done: $removed removed"
