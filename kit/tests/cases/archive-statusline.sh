SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/archive.sh"
DEV="$SANDBOX/.claude/dev"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
cat > "$DEV/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

OLD_DATE="2026-01-01T12:00:00 +0800"

mk() {
    # mk <id> <狀態行前綴> <狀態內容>
    cat > "$DEV/wave-$1.md" <<EOF
# Wave $1 — 2026-01-01 測試波

## Metadata
- 涉及: src/**

$2$3
EOF
}

# ① 狀態行 ✅、無「待」、無 branch → 該被清
mk sl-done "## 狀態：" "✅ 完成（8/8 全過）"
echo "# ledger" > "$DEV/wave-sl-done-ledger.md"
# ② ✅ 但帶「待」→ 不清
mk sl-pending "## 狀態：" "✅ 實作完成（待使用者：人眼驗收）"
# ③ 🟡 → 不清
mk sl-active "## 狀態：" "🟡 執行中"
# ④ ✅ 但 branch 有未併入 commit → 不清
mk sl-unmerged "## 狀態：" "✅ 完成"
# ⑤ 粗體格式 **狀態**: ✅ → 該被清
mk sl-bold "**狀態**: " "✅ 完成"
# ⑥ 無狀態行也無 frontmatter → 不動（既有政策）
printf '# 沒有任何狀態的舊檔\n' > "$DEV/wave-sl-legacy.md"

GIT_AUTHOR_DATE="$OLD_DATE" GIT_COMMITTER_DATE="$OLD_DATE" \
    git -C "$SANDBOX" add -A >/dev/null 2>&1
GIT_AUTHOR_DATE="$OLD_DATE" GIT_COMMITTER_DATE="$OLD_DATE" \
    git -C "$SANDBOX" commit -qm old-fixtures >/dev/null 2>&1
git -C "$SANDBOX" branch -m main >/dev/null 2>&1

# ④ 的未併入 branch
git -C "$SANDBOX" branch worktree-sl-unmerged >/dev/null 2>&1
git -C "$SANDBOX" checkout -q worktree-sl-unmerged >/dev/null 2>&1
echo x > "$SANDBOX/extra.txt"
git -C "$SANDBOX" add -A >/dev/null 2>&1 && git -C "$SANDBOX" commit -qm unmerged >/dev/null 2>&1
git -C "$SANDBOX" checkout -q main >/dev/null 2>&1

# ⑦ ✅ 但 commit 未逾期（今天）→ 不清（寬限期）
mk sl-fresh "## 狀態：" "✅ 完成"
git -C "$SANDBOX" add -A >/dev/null 2>&1 && git -C "$SANDBOX" commit -qm fresh >/dev/null 2>&1

printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1

ex() { [ -f "$DEV/wave-$1.md" ] && echo 1 || echo 0; }
assert_eq "0" "$(ex sl-done)"     "狀態行 ✅ 且已逾期、無 branch → 已清除"
assert_eq "0" "$([ -f "$DEV/wave-sl-done-ledger.md" ] && echo 1 || echo 0)" "ledger 一併清除"
assert_eq "1" "$(ex sl-pending)"  "✅ 但帶「待」→ 不清"
assert_eq "1" "$(ex sl-active)"   "🟡 → 不清"
assert_eq "1" "$(ex sl-unmerged)" "branch 有未併入 commit → 不清"
assert_eq "0" "$(ex sl-bold)"     "**狀態**: ✅ 粗體格式 → 已清除"
assert_eq "1" "$(ex sl-legacy)"   "無狀態行無 frontmatter → 不動"
assert_eq "1" "$(ex sl-fresh)"    "未逾期（寬限期內）→ 不清"

# INDEX 摘要應為狀態行、opened 取標題日期、closed 取 commit 日期
line="$(grep '| sl-done |' "$DEV/wave-INDEX.md")"
assert_contains "$line" "✅ 完成（8/8 全過）" "INDEX 摘要取狀態行"
assert_contains "$line" "2026-01-01~2026-01-01" "opened 取標題日期、closed 取檔案最後 commit 日"
assert_contains "$line" "git show" "INDEX 含取回指令"

# 取回指令實測可還原
spec="$(printf '%s' "$line" | sed 's/.*`git show \([^`]*\)`.*/\1/')"
lines="$( (cd "$SANDBOX" && git show "$spec" 2>/dev/null | wc -l) | tr -d ' ')"
[ "${lines:-0}" -gt 0 ] && r=yes || r=no
assert_eq "yes" "$r" "取回指令實際取得回內容"

# 冪等：再跑一次不重複寫
before="$(grep -c '| sl-done |' "$DEV/wave-INDEX.md")"
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1
after="$(grep -c '| sl-done |' "$DEV/wave-INDEX.md")"
assert_eq "$before" "$after" "重跑不重複寫 INDEX"

rm -rf "$SANDBOX"
