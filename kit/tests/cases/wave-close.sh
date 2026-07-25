SANDBOX="$(kit_test_sandbox)"
SCRIPT="$KIT_ROOT/scripts/wave-close.sh"
DEV="$SANDBOX/.claude/dev"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t

mk_wave() {
    # mk_wave <id> <狀態行>
    cat > "$DEV/wave-$1.md" <<EOF
# Wave $1 — 2026-07-01 測試波

## Metadata
- **涉及檔案/目錄**: \`src/**\`

## 狀態：$2
EOF
    echo "# $1 的 ledger" > "$DEV/wave-$1-ledger.md"
}

mk_wave done1 "✅ 完成（測試）"
mk_wave done2 "✅ 完成"
mk_wave dirty "✅ 完成"
mkdir -p "$SANDBOX/docs/plans"
cat > "$SANDBOX/docs/plans/done1-plan.md" <<'EOF'
---
wave_id: done1
---
# done1 的 plan
EOF
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1

run() { (cd "$SANDBOX" && bash "$SCRIPT" "$@" 2>&1); }
rc_of() { (cd "$SANDBOX" && bash "$SCRIPT" "$@" >/dev/null 2>&1); echo $?; }

# --- dry-run 不得動檔 ---
out="$(run done1 --dry-run)"
assert_contains "$out" "將清除 3 個檔案" "dry-run 應列出 dashboard+ledger+plan"
assert_eq "0" "$(rc_of done1 --dry-run)" "dry-run 應 exit 0"
[ -f "$DEV/wave-done1.md" ] && r=yes || r=no
assert_eq "yes" "$r" "dry-run 不得刪除 dashboard"
[ -f "$SANDBOX/docs/plans/done1-plan.md" ] && r=yes || r=no
assert_eq "yes" "$r" "dry-run 不得刪除 plan"

# --- 守衛：有未提交修改 → 中止且不刪任何檔 ---
echo "未提交的新內容" >> "$DEV/wave-dirty.md"
out="$(run dirty)"
assert_contains "$out" "無法安全取回" "有未提交修改應中止"
assert_contains "$out" "有未提交的修改" "應指出是哪一種不安全"
assert_eq "1" "$(rc_of dirty)" "守衛觸發應 exit 1"
[ -f "$DEV/wave-dirty.md" ] && r=yes || r=no
assert_eq "yes" "$r" "守衛觸發時 dashboard 不得被刪"
[ -f "$DEV/wave-dirty-ledger.md" ] && r=yes || r=no
assert_eq "yes" "$r" "守衛觸發時 ledger 也不得被刪（整波中止，不留半刪狀態）"

# --- 守衛：未提交過的新波（cat-file 取不到）→ 中止 ---
mk_wave fresh "✅ 完成"
out="$(run fresh)"
assert_contains "$out" "尚未提交" "未提交過的檔應被守衛擋下"
assert_eq "1" "$(rc_of fresh)" "未提交過應 exit 1"
rm -f "$DEV/wave-fresh.md" "$DEV/wave-fresh-ledger.md"

# --- 正常清除 ---
out="$(run done1)"
assert_contains "$out" "已清除 3 個檔案" "正常路徑應清除三個檔"
[ -f "$DEV/wave-done1.md" ] && r=yes || r=no
assert_eq "no" "$r" "dashboard 應已刪除"
[ -f "$DEV/wave-done1-ledger.md" ] && r=yes || r=no
assert_eq "no" "$r" "ledger 應已刪除"
[ -f "$SANDBOX/docs/plans/done1-plan.md" ] && r=yes || r=no
assert_eq "no" "$r" "同 wave_id 的 plan 應已刪除"

# --- INDEX 內容：摘要取狀態行，取回指令可用 ---
index="$(cat "$DEV/wave-INDEX.md")"
assert_contains "$index" "| done1 |" "INDEX 應有該波一列"
assert_contains "$index" "✅ 完成（測試）" "摘要應取狀態行而非 Metadata 首行"
assert_contains "$index" "git show" "INDEX 應含取回指令"
assert_contains "$index" "2026-07-01" "opened 應取自標題行日期"

# 取回指令必須真的取得回內容——只檢查字串存在會漏掉 hash/路徑錯誤
spec="$(printf '%s' "$index" | grep '| done1 |' | sed 's/.*`git show \([^`]*\)`.*/\1/')"
lines="$( (cd "$SANDBOX" && git show "$spec" 2>/dev/null | wc -l) | tr -d ' ')"
[ "${lines:-0}" -gt 0 ] && r=yes || r=no
assert_eq "yes" "$r" "INDEX 的取回指令必須實際取得回檔案內容"

# --- 冪等：同一個 id 再跑（檔案已不在）→ 不重複寫 INDEX ---
before="$(grep -c '| done1 |' "$DEV/wave-INDEX.md")"
run done1 >/dev/null 2>&1
after="$(grep -c '| done1 |' "$DEV/wave-INDEX.md")"
assert_eq "$before" "$after" "重跑不得重複寫入 INDEX"

# --- 參數驗證 ---
assert_eq "2" "$(rc_of)" "不給 wave-id 應 exit 2"
assert_eq "2" "$(rc_of a b)" "給兩個 wave-id 應 exit 2"
assert_eq "2" "$(rc_of --bogus)" "未知選項應 exit 2"
assert_eq "1" "$(rc_of nosuchwave)" "不存在的波應 exit 1"

# --- 沒有 ledger 的波也要能清 ---
rm -f "$DEV/wave-done2-ledger.md"
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm rm-ledger >/dev/null 2>&1
out="$(run done2)"
assert_contains "$out" "已清除 1 個檔案" "無 ledger 的波應只清 dashboard"

rm -rf "$SANDBOX"
