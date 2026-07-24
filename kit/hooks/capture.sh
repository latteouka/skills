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

root="$(kit_repo_root)" || exit 0
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
raw=""
case "$prompt" in
    '!'*)          raw="${prompt#!}" ;;
    *'#bug'*|*'#todo'*|*'#idea'*)
        raw="$(printf '%s' "$prompt" | sed 's/#bug//g; s/#todo//g; s/#idea//g')"
        ;;
esac

if [ -n "$raw" ]; then
    raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
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

    kit_lock_release "$lockdir"
    trap - EXIT
    emit_context "已自動收錄至收件匣：${id}。回覆時簡短告知使用者即可，不需重複內容。"
    exit 0
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
