#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

removed=0

for skill_dir in "$SCRIPT_DIR"/*/; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
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
