# 守衛測試：所有 hooks 必須具備可執行位元（100755）
# 防止 Claude Code 直接路徑呼叫時失敗（exit 126）。

HOOKS_DIR="$KIT_ROOT/hooks"

# --- 遍歷所有 .sh 檔案，檢查可執行位元
for hook_file in "$HOOKS_DIR"/*.sh; do
    [ -f "$hook_file" ] || continue
    hook_name="$(basename "$hook_file")"
    if [ -x "$hook_file" ]; then
        # 通過：可執行
        TESTS_RUN=$((TESTS_RUN + 1))
    else
        # 失敗：不可執行
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "FAIL: ${hook_name} 缺少可執行位元"
        echo "  fix: chmod +x $hook_file"
    fi
done

# --- skills-hint.sh 行為測試（2026-07-25 補：取代 superpowers plugin 的觸發注入）
_hint="$KIT_ROOT/hooks/skills-hint.sh"
out="$(printf '{"hook_event_name":"SessionStart"}' | bash "$_hint" 2>/dev/null)"
assert_contains "$out" "flow" "hint 提及 flow 分流"
assert_contains "$out" "/debug" "hint 提及 debug skill"
assert_contains "$out" "/sdd" "hint 提及 sdd skill"
# 未安裝 skill 時應靜默（避免在沒裝 kit 的環境印無用訊息）
out_missing="$(HOME=/tmp/kit-no-skills-$$ bash "$_hint" </dev/null 2>/dev/null)"
assert_eq "" "$out_missing" "skill 未安裝時靜默"
