SANDBOX="$(kit_test_sandbox)"
GEN="$KIT_ROOT/scripts/gen-readme.sh"
DEV="$SANDBOX/.claude/dev"

# 建置測試資料
printf -- '---\nwave_id: a\nstatus: active\n---\n# A 波\n' > "$DEV/wave-a.md"
printf '# 品質閘門說明\n> 品質檢查框架\n' > "$DEV/quality-gates.md"
mkdir -p "$SANDBOX/.claude"
printf '{"hooks":{"Stop":[{"hooks":[{"command":"x/archive.sh"}]}]}}' > "$SANDBOX/.claude/settings.json"
mkdir -p "$SANDBOX/.husky"
printf '#!/bin/bash\nbash scripts/x.sh\nbash scripts/y.sh\n' > "$SANDBOX/.husky/pre-commit"
chmod +x "$SANDBOX/.husky/pre-commit"

# 建 git repo 與 wave-INDEX.md（模擬已刪除的波）
git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1

printf '# Wave 歷史索引\n\n| wave | 期間 | 一句話結果 | 取回 |\n|---|---|---|---|\n| old | 2026-01-01~2026-01-15 | 完成地圖改版 | `git show abc:...` |\n' > "$DEV/wave-INDEX.md"

# 執行生成器
(cd "$SANDBOX" && bash "$GEN") >/dev/null 2>&1

R="$(cat "$DEV/README.md")"

# --- 驗證內容
assert_contains "$R" "wave-a.md" "列出熱區檔案"
assert_contains "$R" "quality-gates.md" "列出常駐檔"
assert_contains "$R" "active" "wave 檔顯示狀態"
assert_contains "$R" "archive.sh" "列出已裝 hook"
assert_contains "$R" "x.sh" "列出 pre-commit 閘門中的 script"
assert_contains "$R" "y.sh" "列出第二個 pre-commit script"
assert_contains "$R" "wave-INDEX.md" "列出歷史索引"
assert_contains "$R" "1 個" "報出波數（已刪除 1 個）"

# --- 快照機制：無變化時不重寫
cp "$DEV/README.md" "$DEV/README.before"
mtime_before="$(stat -f%m "$DEV/README.md" 2>/dev/null || stat -c%Y "$DEV/README.md" 2>/dev/null || echo 0)"
sleep 0.1  # 確保時間充分流逝
(cd "$SANDBOX" && bash "$GEN") >/dev/null 2>&1
mtime_after="$(stat -f%m "$DEV/README.md" 2>/dev/null || stat -c%Y "$DEV/README.md" 2>/dev/null || echo 0)"
assert_eq "$mtime_before" "$mtime_after" "無變化時不改寫檔案"
assert_eq "$(cat "$DEV/README.before")" "$(cat "$DEV/README.md")" "檔案內容保持不變"

# --- 邊界條件：無 settings.json
rm "$SANDBOX/.claude/settings.json"
(cd "$SANDBOX" && bash "$GEN") >/dev/null 2>&1
R="$(cat "$DEV/README.md")"
assert_contains "$R" "無 settings.json" "缺 settings.json 時報出"

# --- 邊界條件：無 .husky/pre-commit
rm "$SANDBOX/.husky/pre-commit"
(cd "$SANDBOX" && bash "$GEN") >/dev/null 2>&1
R="$(cat "$DEV/README.md")"
assert_contains "$R" "無 .husky/pre-commit" "缺 pre-commit 時報出"

# --- 邊界條件：無 .claude/dev（fail-open）
(cd "$SANDBOX/.." && rm -rf "$SANDBOX/.claude/dev" && mkdir -p "$SANDBOX/.other" && bash "$GEN") >/dev/null 2>&1
# 應該 gracefully exit 0，不爆炸

# --- 清理
rm -rf "$SANDBOX"
