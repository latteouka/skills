SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/capture.sh"
INBOX="$SANDBOX/.claude/dev/inbox.md"
: > "$INBOX"

run_capture() {
    printf '{"hook_event_name":"UserPromptSubmit","prompt":%s}' "$1" \
        | (cd "$SANDBOX" && bash "$HOOK")
}

# --- 強信號：#bug → 直接寫入 inbox
out="$(run_capture '"#bug 證物列表排序點兩次才生效"')"
assert_contains "$out" "INB-001" "強信號注入含編號"
assert_contains "$(cat "$INBOX")" "證物列表排序點兩次才生效" "強信號原話寫入 inbox"
assert_contains "$(cat "$INBOX")" "## INB-001" "強信號建立條目"

# --- 強信號：! 前綴 → 直接寫入，編號遞增
out="$(run_capture '"!排序預設應該時間降序"')"
assert_contains "$out" "INB-002" "第二筆編號遞增"
assert_contains "$(cat "$INBOX")" "排序預設應該時間降序" "! 前綴原話寫入"

# --- 強信號：raw 不含觸發標記本身
assert_not_contains "$(cat "$INBOX")" "#bug" "寫入的 raw 已去除 #bug 標記"

# --- 弱信號：注入提醒但不寫檔
before="$(cat "$INBOX")"
out="$(run_capture '"這個排序好像沒反應耶"')"
assert_contains "$out" "疑似回饋" "弱信號注入提醒"
assert_contains "$out" "沒反應" "提醒含命中詞"
assert_eq "$before" "$(cat "$INBOX")" "弱信號不寫檔"

# --- 無信號：完全無輸出
out="$(run_capture '"幫我看一下 case router 的型別"')"
assert_eq "" "$out" "無信號靜默"

# --- 惡意輸入：含雙引號與換行不破壞 JSON 輸出
out="$(run_capture '"#bug 他說\"壞了\"\n換行測試"')"
assert_contains "$out" "INB-003" "特殊字元不影響編號"

# --- fail-open：非 git 目錄不報錯
NONGIT="$(mktemp -d)"
out="$(printf '{"prompt":"#bug x"}' | (cd "$NONGIT" && bash "$HOOK"); echo "rc=$?")"
assert_contains "$out" "rc=0" "非 git 目錄 exit 0"
rm -rf "$NONGIT"

# --- [NEW] Important 1: 換行過濾——防止偽造條目與編號劫持
# 偽造條目格式：換行 + ## 號 + 偽造欄位
before_count="$(grep -c '^## INB-' "$INBOX" || echo 0)"
out="$(run_capture '"#bug 正常回報\n## INB-999\n- when: 偽造\n- from: 偽造\n- raw: 偽造內容"')"
after_count="$(grep -c '^## INB-' "$INBOX" || echo 0)"
# 確認 ## INB- 只增加 1 行（不是 2+ 行），表示換行被正規化，未產生偽造條目
assert_eq "1" "$((after_count - before_count))" "換行過濾防止偽造條目"
# 確認下一個編號正確遞增（INB-005），而非跳號
out="$(run_capture '"#bug 下一筆"')"
assert_contains "$out" "INB-005" "編號正確遞增無跳號"

# --- [NEW] Important 2: ! 前綴 + 內嵌標記都剝除
out="$(run_capture '"!排序 #bug 有問題"')"
inbox_raw="$(tail -1 "$INBOX")"
assert_not_contains "$inbox_raw" "#bug" "! 前綴內嵌 #bug 需剝除"
# 由於標記被移除留下兩個空格，這裡檢查 raw 中包含 排序 和 有問題
assert_contains "$inbox_raw" "排序" "! 前綴剝除標記後保留主詞"
assert_contains "$inbox_raw" "有問題" "! 前綴剝除標記後保留述詞"

# --- [NEW] Important 3: 寫入失敗時不謊報成功（inbox 權限不足）
SANDBOX_NO_PERM="$(kit_test_sandbox)"
INBOX_NO_PERM="$SANDBOX_NO_PERM/.claude/dev/inbox.md"
: > "$INBOX_NO_PERM"
chmod 444 "$INBOX_NO_PERM"
out="$(printf '{"prompt":"#bug 應該失敗"}' | (cd "$SANDBOX_NO_PERM" && bash "$HOOK"); echo "rc=$?")"
# exit 0（fail-open）+ 訊息明確表達失敗，不含「已自動收錄」
assert_contains "$out" "rc=0" "寫入失敗仍 exit 0"
assert_contains "$out" "寫入失敗" "失敗訊息明確表達"
assert_not_contains "$out" "已自動收錄" "失敗訊息不謊報成功"
chmod 755 "$INBOX_NO_PERM"
rm -rf "$SANDBOX_NO_PERM"

# --- [NEW] C3：使用者原話引用既有編號（如「這跟 INB-042 是同一個問題」）
# 要完整保留，不可再被全域抹掉——kit_next_id 現在只認 ^## 標題行，
# 引用文字混在 raw 裡不會污染下一個編號的計算。
out="$(run_capture '"!這跟 INB-042 是同一個問題"')"
inbox_raw="$(tail -1 "$INBOX")"
assert_contains "$inbox_raw" "INB-042" "raw 保留使用者對既有編號的引用（不再整串抹掉）"

# --- [NEW] N1：長篇工具輸出／報告內文中間出現 #bug 字樣，不應被自動收錄
# 2026-07-25 實戰教訓：一份 6KB 的 subagent review 報告因說明文字裡提到
# #bug，整篇被寫進 inbox（INB-007，事後人工移除）。真正的強信號用法是
# 「打字打 #bug 開頭」，不會出現在幾百字之後。
before_inbox="$(cat "$INBOX")"
FILLER_MID="$(printf 'x%.0s' $(seq 1 600))"
out="$(run_capture "\"這是一份很長的 review 報告。${FILLER_MID}這一段提到 #bug 這個字，但只是在說明文字裡，不是要回報問題。\"")"
assert_eq "$before_inbox" "$(cat "$INBOX")" "長篇文字中間出現 #bug 不被自動收錄"
assert_eq "" "$out" "長篇文字中間出現 #bug 靜默（不觸發強信號提示）"

# --- [NEW] N1：開頭有 #bug 標記，但整則訊息長度遠超合理範圍，也不自動收錄
# （避免「剛好開頭 50 字內含 #bug」的長篇貼文繞過開頭位置檢查）
FILLER_LONG="$(printf 'y%.0s' $(seq 1 600))"
out="$(run_capture "\"#bug 開頭有標記但後面接超長內容：${FILLER_LONG}\"")"
assert_eq "$before_inbox" "$(cat "$INBOX")" "開頭有 #bug 但總長度過長仍不自動收錄"

# --- [NEW] 多 worktree：從 worktree 內執行 capture，應寫入主 checkout 的
# inbox，不是 worktree 自己那份副本（2026-07-25 自我審查發現：hook 用
# kit_repo_root 在 worktree 內執行時只會拿到 worktree 自己的路徑，導致
# 多個 worktree／主 checkout 各自累積一份 inbox，彼此分裂）。
# 用真正的 `git worktree add` 建立 fixture（而非手造目錄），確保
# kit_repo_root 在裡面真的會回傳 worktree 自己的 toplevel，貼近正式環境。
WT_MAIN="$(kit_test_sandbox)"
git -C "$WT_MAIN" config user.email t@t.t
git -C "$WT_MAIN" config user.name t
: > "$WT_MAIN/.claude/dev/inbox.md"
git -C "$WT_MAIN" add -A >/dev/null 2>&1
git -C "$WT_MAIN" commit -qm init >/dev/null 2>&1

mkdir -p "$WT_MAIN/.claude/worktrees"
git -C "$WT_MAIN" worktree add -q -b kit-test-capture-wt "$WT_MAIN/.claude/worktrees/wt-a" >/dev/null 2>&1

WT_SUB="$WT_MAIN/.claude/worktrees/wt-a"
WT_MAIN_INBOX="$WT_MAIN/.claude/dev/inbox.md"
WT_SUB_INBOX="$WT_SUB/.claude/dev/inbox.md"

printf '{"prompt":"#bug 多worktree寫入測試"}' | (cd "$WT_SUB" && bash "$HOOK") >/dev/null 2>&1

assert_contains "$(cat "$WT_MAIN_INBOX" 2>/dev/null)" "多worktree寫入測試" \
    "worktree 內觸發 capture 寫入主 checkout 的 inbox"
assert_not_contains "$(cat "$WT_SUB_INBOX" 2>/dev/null)" "多worktree寫入測試" \
    "worktree 自己的 inbox 副本未被寫入（避免分裂）"

git -C "$WT_MAIN" worktree remove -f "$WT_MAIN/.claude/worktrees/wt-a" >/dev/null 2>&1
rm -rf "$WT_MAIN"

rm -rf "$SANDBOX"
