#!/usr/bin/env bash
# no-midwave-questions.sh — Stop hook：wave 執行期不得以問句結束 turn。
#
# 母題（2026-07-26 使用者原話「要做就是要做」「不需要問我是要 subagent 還是
# inline」）：wave SKILL.md 唯一停點制早已明文禁止執行期問「要不要繼續」，
# 但條文擋不住違規（0725 裁定：寫得清楚 ≠ 會被執行，能攔截的做成 hook）。
# 本 hook 把它機器化：
#   cwd 在 wave worktree（*/.claude/worktrees/wave-*）＝ wave 執行期
#   ＋ transcript 最後一則 assistant 文字訊息以問句收尾 → exit 2 block 一次。
#
# 為何只看「最後一行」：合法輸出中段可能引述問題或提到「要不要」字樣
# （例如轉述使用者裁定），只有收尾問句才代表「以提問結束 turn 等輸入」。
#
# stop_hook_active=true（本回合已被 Stop hook 擋過、續跑後再次結束）→
# exit 0 放行——真正的合法停點（阻塞一切的需人裁定、merge 裁定）維持
# 原輸出再結束一次 turn 即可通過，成本一輪；預設不問。
#
# 規劃期不受影響：Phase 0 Align / Phase 4 範圍確認發生在主 checkout，
# cwd 不在 wave worktree，本 hook 直接放行。
#
# fail-open：無 jq / transcript 缺失 / 解析失敗 → exit 0。pass 靜默。
# bash 3.2 相容：不用 mapfile / 關聯陣列；中文比對用 case 純字串。

set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat 2>/dev/null)" || exit 0
[ -n "${input}" ] || exit 0

active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "${active}" = "true" ] && exit 0

cwd="$(printf '%s' "${input}" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "${cwd}" ] || cwd="${PWD}"
case "${cwd}" in
  */.claude/worktrees/wave-*) : ;;
  *) exit 0 ;;
esac

transcript="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
[ -n "${transcript}" ] && [ -r "${transcript}" ] || exit 0

# 取 transcript 尾端窗口內最後一則非空 assistant 文字（tool_use-only 訊息
# 會被 select(length>0) 濾掉）。窗口 400 行防大 transcript 全檔解析。
last_text="$(tail -n 400 "${transcript}" 2>/dev/null | jq -rs '
  [ .[]?
    | select(.type == "assistant")
    | .message.content
    | if type == "array" then (map(select(.type == "text") | .text) | join("\n")) else tostring end
    | select(length > 0)
  ] | last // empty' 2>/dev/null)"
[ -n "${last_text}" ] || exit 0

tail_line="$(printf '%s\n' "${last_text}" | sed -e 's/[[:space:]]*$//' | grep -v '^[[:space:]]*$' | tail -n 1)"
[ -n "${tail_line}" ] || exit 0

hit=""
case "${tail_line}" in
  *"？" | *"?") hit="問號收尾" ;;
  *"要不要"*   | *"需不需要"*) hit="徵詢句式" ;;
  *"是否要"*   | *"是否需要"*) hit="徵詢句式" ;;
  *"需要我"*"嗎"* | *"要現在"*"嗎"*) hit="徵詢句式" ;;
esac
[ -n "${hit}" ] || exit 0

excerpt="$(printf '%s' "${tail_line}" | cut -c1-120)"
{
  echo "[no-midwave-questions] 唯一停點制：wave 執行期不得以問句結束 turn（偵測到${hit}：「${excerpt}」）。"
  echo "計畫內步驟（Playwright／E2E／dev server 啟動／執行方式選擇）一律直接執行，不徵詢；"
  echo "需人裁定事項按長跑行為規範第 5 條記 dashboard、批次呈報，僅當其阻塞所有剩餘工作時才停。"
  echo "若此問確為合法例外（阻塞一切的需人裁定／merge 裁定），維持原輸出再次結束 turn 即會放行。"
} >&2
exit 2
