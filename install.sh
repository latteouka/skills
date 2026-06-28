#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
FORCE=false

if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

mkdir -p "$SKILLS_DIR"

installed=0
skipped=0

for skill_dir in "$SCRIPT_DIR"/*/; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
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
    echo "  ok: $name → $target"
    installed=$((installed + 1))
done

echo ""
echo "Done: $installed installed, $skipped skipped"
