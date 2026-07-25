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

# 建 git repo 與 wave-INDEX.md（模擬已刪除的波，包含各種期間格式）
git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1

# 建立 INDEX 包含多種期間格式：
# 1. 標準期間（YYYY-MM-DD~YYYY-MM-DD）
# 2. 單日期（YYYY-MM-DD）
# 3. 簡短期間（YYYY~YYYY）
# 4. unknown / ?（推不出日期時）
printf '# Wave 歷史索引\n\n| wave | 期間 | 一句話結果 | 取回 |\n|---|---|---|---|\n' > "$DEV/wave-INDEX.md"
printf '| w1 | 2026-01-01~2026-01-15 | 完成地圖改版 | `git show abc:.claude/dev/wave-w1.md` |\n' >> "$DEV/wave-INDEX.md"
printf '| w2 | 2026-07-14 | 單日期波 | `git show def:.claude/dev/wave-w2.md` |\n' >> "$DEV/wave-INDEX.md"
printf '| w3 | 2026~2026 | 簡短期間 | `git show ghi:.claude/dev/wave-w3.md` |\n' >> "$DEV/wave-INDEX.md"
printf '| w4 | unknown | 推不出日期 | `git show jkl:.claude/dev/wave-w4.md` |\n' >> "$DEV/wave-INDEX.md"
printf '| w5 | ? | 缺期間 | `git show mno:.claude/dev/wave-w5.md` |\n' >> "$DEV/wave-INDEX.md"

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
assert_contains "$R" "5 個" "報出波數（已刪除 5 個，各種期間格式都計入）"

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

# --- 驗證計數方法（git show vs ~）
# 構造一份 INDEX：只有 2 行含 ~，但有 5 個取回指令
# 確認計數報 5 不是 2
lines_with_tilde="$(grep -c '~' "$DEV/wave-INDEX.md")"
lines_with_git_show="$(grep -c 'git show' "$DEV/wave-INDEX.md")"
assert_eq "2" "$lines_with_tilde" "INDEX 中只有 2 行含波浪號"
assert_eq "5" "$lines_with_git_show" "INDEX 中有 5 個 git show 取回指令"
assert_contains "$R" "5 個" "使用 git show 計數才能得到正確的波數"

# --- 邊界條件：無 .claude/dev（fail-open）
(cd "$SANDBOX/.." && rm -rf "$SANDBOX/.claude/dev" && mkdir -p "$SANDBOX/.other" && bash "$GEN") >/dev/null 2>&1
# 應該 gracefully exit 0，不爆炸

# --- 清理
rm -rf "$SANDBOX"
