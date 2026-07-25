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

rm -rf "$SANDBOX"
