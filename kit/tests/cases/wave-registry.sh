SANDBOX="$(kit_test_sandbox)"
SCRIPT="$KIT_ROOT/scripts/wave-registry.sh"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t

# --- base：main 上一個共同基底 ---
mkdir -p "$SANDBOX/src"
cat > "$SANDBOX/src/app.txt" <<'EOF'
line-1
line-2
line-3
line-4
line-5
EOF
printf 'k=1\n' > "$SANDBOX/config.txt"
printf '# index\n' > "$SANDBOX/.claude/dev/wave-INDEX.md"
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm base >/dev/null 2>&1
git -C "$SANDBOX" branch -m main >/dev/null 2>&1

# --- 兩個 worktree，各自帶改動 ---
# alpha：改 app.txt 的 line-1、config 加行、INDEX append、獨有檔
git -C "$SANDBOX" worktree add -q -b worktree-alpha "$SANDBOX/.claude/worktrees/alpha" main >/dev/null 2>&1
WA="$SANDBOX/.claude/worktrees/alpha"
sed -i '' 's/line-1/line-1-alpha/' "$WA/src/app.txt" 2>/dev/null || sed -i 's/line-1/line-1-alpha/' "$WA/src/app.txt"
printf 'alpha=1\n' >> "$WA/config.txt"
printf '| alpha | done |\n' >> "$WA/.claude/dev/wave-INDEX.md"
echo only-alpha > "$WA/alpha.txt"
git -C "$WA" add -A >/dev/null 2>&1
git -C "$WA" commit -qm alpha >/dev/null 2>&1

# beta：改 app.txt 的同一行 line-1（→衝突）、config 加不同行（→可自動）、INDEX append
git -C "$SANDBOX" worktree add -q -b worktree-beta "$SANDBOX/.claude/worktrees/beta" main >/dev/null 2>&1
WB="$SANDBOX/.claude/worktrees/beta"
sed -i '' 's/line-1/line-1-beta/' "$WB/src/app.txt" 2>/dev/null || sed -i 's/line-1/line-1-beta/' "$WB/src/app.txt"
printf 'beta=1\n' >> "$WB/config.txt"
printf '| beta | done |\n' >> "$WB/.claude/dev/wave-INDEX.md"
git -C "$WB" add -A >/dev/null 2>&1
git -C "$WB" commit -qm beta >/dev/null 2>&1

# 兩邊各自新建同名檔（add/add，兩套獨立實作）→ 需裁定
echo alpha-impl > "$WA/src/new-widget.txt"
git -C "$WA" add -A >/dev/null 2>&1 && git -C "$WA" commit -qm alpha2 >/dev/null 2>&1
echo beta-impl > "$WB/src/new-widget.txt"
git -C "$WB" add -A >/dev/null 2>&1 && git -C "$WB" commit -qm beta2 >/dev/null 2>&1
echo dirty > "$WB/uncommitted.txt"   # beta 留一個未 commit 檔

run() { (cd "$SANDBOX" && bash "$SCRIPT" "$@" 2>&1); }
rc_of() { (cd "$SANDBOX" && bash "$SCRIPT" "$@" >/dev/null 2>&1); echo $?; }

# --- list ---
out="$(run list)"
assert_contains "$out" "worktree-alpha" "list 應含 alpha"
assert_contains "$out" "worktree-beta" "list 應含 beta"
alpha_line="$(printf '%s\n' "$out" | grep worktree-alpha)"
assert_contains "$alpha_line" "4" "alpha 應有 4 個已改檔"
beta_line="$(printf '%s\n' "$out" | grep worktree-beta)"
assert_contains "$beta_line" "1" "beta 應顯示 1 個未 commit 檔"

# 從 worktree 內呼叫也要解析到主 repo 的全部 worktree（kit_main_repo_root）
out2="$( (cd "$WA" && bash "$SCRIPT" list 2>&1) )"
assert_contains "$out2" "worktree-beta" "worktree 內呼叫 list 也要看得到其他 worktree"

# --- intersect：全對比（四個分級層各有代表檔）---
out="$(run intersect)"
assert_contains "$out" "worktree-alpha ✕ worktree-beta" "intersect 應比對 alpha✕beta"
assert_contains "$out" "交集 4 檔" "共同改動應為 4 檔（app/config/INDEX/new-widget）"
assert_contains "$out" "src/app.txt（merge-tree 衝突" "同一行改動應列需裁定"
assert_contains "$out" "config.txt（兩邊皆純加行" "設定檔尾端各自 append 應列可自動合併（雖 merge-tree 報衝突）"
assert_contains "$out" "wave-INDEX.md（append-only）" "INDEX 應走 append-only allowlist（先於 merge-tree）"
assert_contains "$out" "new-widget.txt（兩邊各自新建同名檔" "add/add 兩套實作應列需裁定"
assert_eq "1" "$(rc_of intersect)" "有需裁定交集應 exit 1"

# --- intersect：裸 id 與完整 branch 名皆可 ---
out="$(run intersect alpha beta)"
assert_contains "$out" "交集 4 檔" "裸 id 應解析為 worktree-<id>"
out="$(run intersect worktree-alpha worktree-beta)"
assert_contains "$out" "交集 4 檔" "完整 branch 名也可"

# --- intersect：無交集配對 → exit 0 ---
git -C "$SANDBOX" worktree add -q -b worktree-gamma "$SANDBOX/.claude/worktrees/gamma" main >/dev/null 2>&1
WG="$SANDBOX/.claude/worktrees/gamma"
echo only-gamma > "$WG/gamma.txt"
git -C "$WG" add -A >/dev/null 2>&1
git -C "$WG" commit -qm gamma >/dev/null 2>&1
out="$(run intersect alpha gamma)"
assert_contains "$out" "無交集" "不相交的兩波應報無交集"
assert_eq "0" "$(rc_of intersect alpha gamma)" "無需裁定交集應 exit 0"

# --- 參數驗證 ---
assert_eq "2" "$(rc_of)" "無子指令應 exit 2"
assert_eq "2" "$(rc_of intersect nosuch alpha)" "不存在的 branch 應 exit 2"
assert_eq "2" "$(rc_of intersect alpha alpha)" "同一條 branch 應 exit 2"
assert_eq "2" "$(rc_of intersect alpha)" "intersect 只給一個參數應 exit 2"

git -C "$SANDBOX" worktree remove --force "$WA" >/dev/null 2>&1
git -C "$SANDBOX" worktree remove --force "$WB" >/dev/null 2>&1
git -C "$SANDBOX" worktree remove --force "$WG" >/dev/null 2>&1
rm -rf "$SANDBOX"
