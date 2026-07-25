SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/wave-awareness.sh"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t

cat > "$SANDBOX/app.txt" <<'EOF'
line-1
line-2
EOF
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm base >/dev/null 2>&1
git -C "$SANDBOX" branch -m main >/dev/null 2>&1

run_at() { local d="$1"; (cd "$d" && echo '{}' | bash "$HOOK" 2>&1); }

# --- 0 個活躍 worktree → 靜默 ---
out="$(run_at "$SANDBOX")"
assert_eq "" "$out" "無活躍 worktree 應完全靜默"

# --- 建兩個 worktree，同一行改動（需裁定交集）---
git -C "$SANDBOX" worktree add -q -b worktree-wa "$SANDBOX/.claude/worktrees/wa" main >/dev/null 2>&1
WA="$SANDBOX/.claude/worktrees/wa"
sed -i '' 's/line-1/line-1-wa/' "$WA/app.txt" 2>/dev/null || sed -i 's/line-1/line-1-wa/' "$WA/app.txt"
git -C "$WA" add -A >/dev/null 2>&1 && git -C "$WA" commit -qm wa >/dev/null 2>&1

# --- 1 個活躍、從主 checkout 看 → 列出它（別人的波要感知）---
out="$(run_at "$SANDBOX")"
assert_contains "$out" "另有 1 個活躍 worktree" "主 checkout 應感知唯一活躍波"
assert_contains "$out" "worktree-wa" "應列出該波 branch"

# --- 1 個活躍、從該 worktree 內看 → 靜默（不需要感知自己）---
out="$(run_at "$WA")"
assert_eq "" "$out" "唯一活躍波從自己內部看應靜默"

git -C "$SANDBOX" worktree add -q -b worktree-wb "$SANDBOX/.claude/worktrees/wb" main >/dev/null 2>&1
WB="$SANDBOX/.claude/worktrees/wb"
sed -i '' 's/line-1/line-1-wb/' "$WB/app.txt" 2>/dev/null || sed -i 's/line-1/line-1-wb/' "$WB/app.txt"
git -C "$WB" add -A >/dev/null 2>&1 && git -C "$WB" commit -qm wb >/dev/null 2>&1

# --- 2 個活躍、從 wa 內看 → 只列 wb ＋ 需裁定交集 ---
out="$(run_at "$WA")"
assert_contains "$out" "另有 1 個活躍 worktree" "wa 內只該看到 wb"
assert_contains "$out" "worktree-wb" "應列 wb"
case "$out" in
  *"  worktree-wa"*) TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: 清單不應含自己" ;;
  *) TESTS_RUN=$((TESTS_RUN+1)) ;;
esac
assert_contains "$out" "需裁定交集" "同一行改動應注入需裁定預警"
assert_contains "$out" "app.txt" "需裁定檔名應出現"

# --- 從主 checkout 看 → 列兩個 ＋ 交集 ---
out="$(run_at "$SANDBOX")"
assert_contains "$out" "另有 2 個活躍 worktree" "主 checkout 應看到兩個"
assert_contains "$out" "需裁定交集" "主 checkout 也應看到交集預警"

# --- 交集全為可自動合併時不印預警 ---
git -C "$WB" reset -q --hard main >/dev/null 2>&1   # wb 改動歸零 → 無交集
echo extra > "$WB/only-wb.txt"
git -C "$WB" add -A >/dev/null 2>&1 && git -C "$WB" commit -qm wb2 >/dev/null 2>&1
out="$(run_at "$SANDBOX")"
assert_contains "$out" "另有 2 個活躍 worktree" "清單照列"
case "$out" in
  *需裁定*) TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: 無需裁定交集不應印預警" ;;
  *) TESTS_RUN=$((TESTS_RUN+1)) ;;
esac

git -C "$SANDBOX" worktree remove --force "$WA" >/dev/null 2>&1
git -C "$SANDBOX" worktree remove --force "$WB" >/dev/null 2>&1
rm -rf "$SANDBOX"
