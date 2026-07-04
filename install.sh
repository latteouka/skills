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

link_skill() {
    local src="$1" name="$2"
    local target="$SKILLS_DIR/$name"

    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$FORCE" == true ]]; then
            rm -rf "$target"
        else
            echo "skip: $name (already exists, use --force to override)"
            skipped=$((skipped + 1))
            return
        fi
    fi

    ln -s "$src" "$target"
    echo "  ok: $name"
    installed=$((installed + 1))
}

for skill_dir in "$SCRIPT_DIR"/*/; do
    if [[ -f "$skill_dir/SKILL.md" ]]; then
        # Flat structure: SKILL.md at repo root
        link_skill "$skill_dir" "$(basename "$skill_dir")"
    elif ls "$skill_dir"/skills/*/SKILL.md &>/dev/null; then
        # Plugin structure: link each inner skill dir — linking the repo root
        # leaves no top-level SKILL.md and the skill never registers
        for inner in "$skill_dir"/skills/*/; do
            [[ -f "$inner/SKILL.md" ]] || continue
            link_skill "$inner" "$(basename "$inner")"
        done
    fi
done

echo ""
echo "Done: $installed installed, $skipped skipped"
