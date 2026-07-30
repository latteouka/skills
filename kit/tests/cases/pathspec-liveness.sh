# pathspec-liveness.sh — engines/pathspec-liveness.sh 合約五場景＋目錄行補測
#
# ①恆 0 命中必紅＋點名該檔 ②全命中綠＋inspected:N 精確值 ③conf 缺失 fail-closed
# ④cd 母題重現（cd sub 後 root-relative pathspec 必紅；:(top) 錨定對照必綠）
# ⑤conf 列的檔不存在 fail-closed。補測：目錄行＝掃全部 *.sh（script 形態解析器）。

PL_ENGINE="$KIT_ROOT/engines/pathspec-liveness.sh"

PL_REPO="$(mktemp -d)"
git -C "$PL_REPO" init -q
git -C "$PL_REPO" config user.email kit-test@example.com
git -C "$PL_REPO" config user.name kit-test
mkdir -p "$PL_REPO/.claude/kit" "$PL_REPO/src" "$PL_REPO/sub" "$PL_REPO/hooks"
echo "app" > "$PL_REPO/src/app.ts"
echo "readme" > "$PL_REPO/README.md"
echo "inner" > "$PL_REPO/sub/inner.txt"
git -C "$PL_REPO" add -A
git -C "$PL_REPO" commit -qm init

PL_DECL="$PL_REPO/.claude/kit"
PL_CONF="$PL_DECL/pathspec-targets.conf"

# --- ① conf 列一個 hook 檔，檔內 pathspec 恆 0 命中 → 紅＋點名該檔
cat > "$PL_REPO/hooks/pre-push" <<'EOF'
git diff --cached --name-only -- ':(top)nonexistent/**/*.zzz'
EOF
printf 'hooks/pre-push\n' > "$PL_CONF"
PL_OUT1="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC1=$?
assert_eq "1" "$PL_RC1" "①恆 0 命中 exit 1"
assert_contains "$PL_OUT1" "hooks/pre-push" "①輸出點名該檔"
assert_contains "$PL_OUT1" "nonexistent/**/*.zzz" "①輸出點名 pathspec"
assert_contains "$PL_OUT1" "hits=0" "①輸出標示 hits=0"

# --- ② 全部 pathspec 命中 → 綠＋inspected:N 精確值（conf 含註解行與空行）
cat > "$PL_REPO/hooks/pre-commit" <<'EOF'
git diff --name-only -- ':(top)src/' ':(top)README.md'
EOF
cat > "$PL_CONF" <<'EOF'
# 掃描目標宣告（測試 fixture）——註解行必須被跳過

hooks/pre-commit
EOF
PL_OUT2="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC2=$?
assert_eq "0" "$PL_RC2" "②全命中 exit 0"
assert_eq "inspected:2" "$(printf '%s\n' "$PL_OUT2" | grep -o 'inspected:[0-9]*')" "②inspected:N 精確值"
assert_contains "$PL_OUT2" "PASS" "②PASS 訊息"

# --- ②b 目錄行＝掃該目錄全部 *.sh（script 形態：(cd … && git diff) 子 shell）
mkdir -p "$PL_REPO/hooks2"
cat > "$PL_REPO/hooks2/check.sh" <<'EOF'
(cd sub && git diff --quiet -- 'inner.txt')
EOF
printf 'hooks2\n' > "$PL_CONF"
PL_OUT2B="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC2B=$?
assert_eq "0" "$PL_RC2B" "②b 目錄行＋script 解析器 exit 0"
assert_eq "inspected:1" "$(printf '%s\n' "$PL_OUT2B" | grep -o 'inspected:[0-9]*')" "②b inspected:N 精確值"
assert_contains "$PL_OUT2B" "hooks2/check.sh" "②b 目錄行展開點名檔案"

# --- ③ conf 缺失 → fail-closed 紅
PL_OUT3="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_REPO/.claude/no-such-kit" 2>&1)"
PL_RC3=$?
assert_eq "1" "$PL_RC3" "③conf 缺失 exit 1（fail-closed）"
assert_contains "$PL_OUT3" "不存在" "③訊息點名不存在"

# --- ④ cd 母題重現：hook 先 cd sub 再寫 root-relative pathspec → 必紅
#（上游事故同構：cwd=sub 下 'sub/inner.txt' 被解成 sub/sub/inner.txt，恆 0 命中）
cat > "$PL_REPO/hooks/cd-hook" <<'EOF'
cd sub
git diff --name-only -- 'sub/inner.txt'
EOF
printf 'hooks/cd-hook\n' > "$PL_CONF"
PL_OUT4="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC4=$?
assert_eq "1" "$PL_RC4" "④cd 母題 exit 1"
assert_contains "$PL_OUT4" "hits=0" "④恆 0 被抓"
assert_contains "$PL_OUT4" "cwd=sub" "④點名實際 cwd"
assert_contains "$PL_OUT4" "sub/inner.txt" "④點名肇事 pathspec"
# 對照組：同 pathspec 加 :(top) 錨 → cwd 無關，必綠（上游修法的反向驗證）
cat > "$PL_REPO/hooks/cd-hook" <<'EOF'
cd sub
git diff --name-only -- ':(top)sub/inner.txt'
EOF
PL_OUT4B="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC4B=$?
assert_eq "0" "$PL_RC4B" "④對照：:(top) 錨定後同 pathspec 必綠"

# --- ⑤ conf 列的檔不存在 → fail-closed 紅
printf 'hooks/ghost-hook\n' > "$PL_CONF"
PL_OUT5="$(bash "$PL_ENGINE" --repo-root "$PL_REPO" --decl-dir "$PL_DECL" 2>&1)"
PL_RC5=$?
assert_eq "1" "$PL_RC5" "⑤目標檔不存在 exit 1（fail-closed）"
assert_contains "$PL_OUT5" "不存在" "⑤訊息點名不存在"

rm -rf "$PL_REPO"
