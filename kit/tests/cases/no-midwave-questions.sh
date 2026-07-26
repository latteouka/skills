SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/no-midwave-questions.sh"

WAVETREE="$SANDBOX/.claude/worktrees/wave-test"
mkdir -p "$WAVETREE"

# mk_transcript <file> <text...>：每個 text 參數一則 assistant 訊息（JSONL 一行）
mk_transcript() {
    local f="$1"; shift
    : > "$f"
    local t
    for t in "$@"; do
        jq -cn --arg t "$t" '{type:"assistant", message:{content:[{type:"text",text:$t}]}}' >> "$f"
    done
}

# run_hook <cwd> <transcript> <active>：stdout 帶 hook 輸出，最後一行 exit:N
run_hook() {
    local out rc
    out="$(printf '{"stop_hook_active":%s,"cwd":"%s","transcript_path":"%s"}' "$3" "$1" "$2" | bash "$HOOK" 2>&1)"
    rc=$?
    printf '%s\nexit:%s' "$out" "$rc"
}

T="$SANDBOX/t.jsonl"

# --- ① 故意違規必命中：執行期問「要現在跑 Playwright 嗎？」---
mk_transcript "$T" "Task 3 完成。下一步：Task 4 Playwright E2E 需要啟動 dev server + 瀏覽器。要現在跑 Playwright 驗證嗎？"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:2" "執行期問句收尾應 block"
assert_contains "$out" "唯一停點制" "block 訊息應引唯一停點制"

# --- ① 故意違規必命中：subagent 還是 inline ---
mk_transcript "$T" "工作清單如上。要用 subagent 還是 inline 執行？"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:2" "執行方式徵詢應 block"

# --- ① 句號結尾的徵詢句式也命中 ---
mk_transcript "$T" "接下來要不要我先跑 typecheck。"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:2" "「要不要」徵詢句式應 block"

# --- ② 語意相近不該攔：中段提到「要不要」但收尾是陳述 ---
mk_transcript "$T" "使用者先前裁定過要不要問的原則：不問。
Task 4 完成：Playwright 3 條 spec 全綠，已 commit abc1234。"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:0" "中段字樣不攔，只看收尾"
assert_not_contains "$out" "唯一停點制" "合法輸出應靜默"

# --- ② 合法陳述收尾不攔 ---
mk_transcript "$T" "C1 checkpoint 完成：3 項全綠，dashboard 已更新，繼續 C2。"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:0" "陳述收尾應放行"

# --- ② 多則訊息取最後一則：舊問句＋新陳述 → 放行 ---
mk_transcript "$T" "要現在跑嗎？" "已直接執行完畢，全部通過。"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:0" "應取最後一則 assistant 訊息判斷"

# --- ③ 規劃期（主 checkout cwd）問句不攔——Phase 0/4 合法停點 ---
mk_transcript "$T" "這波有新素材要帶入嗎？"
out="$(run_hook "$SANDBOX" "$T" false)"
assert_contains "$out" "exit:0" "非 wave worktree cwd 應放行"

# --- ④ stop_hook_active=true 二次放行（合法例外通道）---
mk_transcript "$T" "merge 衝突需裁定：A 改法還是 B 改法？"
out="$(run_hook "$WAVETREE" "$T" true)"
assert_contains "$out" "exit:0" "第二次 stop 應放行"

# --- ⑤ fail-open：transcript 缺失 ---
out="$(run_hook "$WAVETREE" "$SANDBOX/no-such.jsonl" false)"
assert_contains "$out" "exit:0" "transcript 缺失應 fail-open"

# --- ⑤ tool_use-only 訊息被濾掉，取其前的文字訊息 ---
mk_transcript "$T" "全部完成，已 commit。"
jq -cn '{type:"assistant", message:{content:[{type:"tool_use",name:"Bash",input:{}}]}}' >> "$T"
out="$(run_hook "$WAVETREE" "$T" false)"
assert_contains "$out" "exit:0" "tool_use-only 末則應回看前一則文字"

rm -rf "$SANDBOX"
