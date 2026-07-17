#!/usr/bin/env bash
# wave-lint.sh — wave skill 結構檢查（在 skills repo 根執行）
set -euo pipefail
CORE="wave/SKILL.md"; MAX=800
LINES=$(wc -l < "$CORE")
[ "$LINES" -le "$MAX" ] || { echo "FAIL: core $LINES 行 > 上限 $MAX"; exit 1; }
for f in wave/references/*.md; do
  base=$(basename "$f")
  grep -q "references/$base" "$CORE" || { echo "FAIL: $base 未被 core 載入"; exit 1; }
done
echo "PASS: core $LINES 行（上限 ${MAX}）；references 連結完整"
