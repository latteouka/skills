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

rm -rf "$SANDBOX"
