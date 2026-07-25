#!/usr/bin/env bash
# UserPromptSubmit hook — 回饋捕捉。
#
# 強信號（! 前綴 / #bug / #todo / #idea）→ 直接 append inbox.md，零 LLM 參與。
# 弱信號（patterns.txt 命中）→ 注入提醒，由 Claude 判斷語意後決定是否寫入。
#
# fail-open 契約：任何錯誤路徑 exit 0 且無輸出。捕捉失敗絕不能讓使用者的
# prompt 消失（exit 2 會擦掉 prompt）。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)" || exit 0
[ -n "$prompt" ] || exit 0

# inbox.md 是跨 worktree 共用的單一收件匣——多 worktree 情境下一律寫主
# checkout，不寫目前所在 worktree 自己的副本（否則各 worktree 各自累積，
# 彼此看不到對方回報的內容；2026-07-25 自我審查發現）。
root="$(kit_main_repo_root)" || exit 0
[ -n "$root" ] || exit 0
inbox="${root}/.claude/dev/inbox.md"
[ -f "$inbox" ] || exit 0

# 以 jq 產生 JSON，確保引號／換行正確跳脫
emit_context() {
    printf '%s' "$1" | jq -R -s '{
        hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: .
        }
    }' 2>/dev/null || true
}

# ---- 強信號判定 -------------------------------------------------------
# `!` 前綴是使用者在訊息開頭明確打的動作，不論長度都當強信號。
# #bug/#todo/#idea 則不同：這三個詞可能只是「剛好出現在一段長文字裡」
# （貼上的 log、subagent 報告、程式碼片段），不代表使用者要回報東西。
# 2026-07-25 實戰教訓：一份 6KB 的 review 報告因說明文字裡提到 #bug 字樣，
# 整篇被當強信號寫進 inbox。真實的標記用法是「打字打 #bug 開頭」，不會
# 出現在幾千字之後——因此只有「標記在開頭附近」且「整則訊息長度合理」
# 兩條件同時成立才觸發自動寫入；否則最多落到下面的弱信號提醒（不寫檔，
# 由 Claude 判斷語意）。
raw=""
case "$prompt" in
    '!'*)
        raw="${prompt#!}"
        ;;
    *)
        head_chunk="${prompt:0:50}"
        case "$head_chunk" in
            *'#bug'*|*'#todo'*|*'#idea'*)
                prompt_len=${#prompt}
                if [ "$prompt_len" -le 500 ]; then
                    raw="$prompt"
                fi
                ;;
        esac
        ;;
esac

if [ -n "$raw" ]; then
    # 剝除標記（兩條分支都必須做）
    raw="$(printf '%s' "$raw" | sed 's/#bug//g; s/#todo//g; s/#idea//g')"
    
    # 正規化空白：前後 trim + 將換行替換為 |
    raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    raw="$(printf '%s' "$raw" | tr '\n' '|')"
    # 上面這行已把換行拍平成 |，使用者原話裡不可能再冒出獨立一行的
    # 「## INB-999」去偽造條目標題；kit_next_id 現在也只認 ^## 開頭的標題行
    # （見 lib/common.sh），兩層防護疊加，因此這裡不再需要把使用者引用既有
    # 編號的文字整個抹掉（2026-07-25 修正：舊版 sed 全域移除 INB-NNN 會把
    # 「這跟 INB-042 是同一個問題」這種合理引用也吃掉，造成資料損失）。

    [ -n "$raw" ] || exit 0

    lockdir="${root}/.claude/dev/.inbox.lock"
    if ! kit_lock_acquire "$lockdir" 20; then
        emit_context "收件匣忙碌中，本則未自動收錄。如為回饋請手動 append inbox.md。"
        exit 0
    fi
    trap 'kit_lock_release "$lockdir"' EXIT

    id="$(kit_next_id "$inbox" INB)"
    {
        printf '\n## %s\n' "$id"
        printf -- '- when: %s\n' "$(date '+%Y-%m-%d %H:%M')"
        printf -- '- from: 口述\n'
        printf -- '- raw: %s\n' "$raw"
    } >> "$inbox"

    # 驗證寫入是否成功
    if grep -q "^## ${id}$" "$inbox"; then
        kit_lock_release "$lockdir"
        trap - EXIT
        emit_context "已自動收錄至收件匣：${id}。回覆時簡短告知使用者即可，不需重複內容。"
        exit 0
    else
        kit_lock_release "$lockdir"
        trap - EXIT
        emit_context "收件匣寫入失敗，本則未收錄，請檢查 .claude/dev/inbox.md 權限。"
        exit 0
    fi
fi

# ---- 弱信號判定 -------------------------------------------------------
patterns="${KIT_ROOT}/references/patterns.txt"
[ -f "$patterns" ] || exit 0

hit=""
while IFS= read -r word; do
    case "$word" in ''|'#'*) continue ;; esac
    case "$prompt" in
        *"$word"*) hit="$word"; break ;;
    esac
done < "$patterns"

[ -n "$hit" ] || exit 0

emit_context "本則訊息疑似回饋（命中詞：${hit}）。若確為使用者回報的 bug／需求／改善建議，先 append 至 .claude/dev/inbox.md（欄位 when/from/raw，編號接續最大值）再回答；若只是除錯討論或技術問答則忽略此提示。"
exit 0
