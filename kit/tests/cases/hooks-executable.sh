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
