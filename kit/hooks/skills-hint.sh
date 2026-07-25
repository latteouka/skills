#!/usr/bin/env bash
# SessionStart hook — 注入 kit skill 的觸發規則。
#
# 為什麼需要這支：superpowers plugin 的「always 會用 skill」不是 skill 檔案的能力，
# 是它的 SessionStart hook 每次把 using-superpowers 全文（約 1,500 token 的
# <EXTREMELY_IMPORTANT> 強制措辭）注入 context。2026-07-25 停用該 plugin、把四個
# 核心 skill 抄進 kit 後，註冊層等價（symlink 到 ~/.claude/skills/，Skill 工具叫得到），
# 但觸發層歸零——skill 清單那一行 description 的強度遠不及每次貼在臉上的注入。
#
# 本 hook 是等價機制的輕量版：約 150 token，只講「什麼情況叫哪個」與分流規則，
# 不複製 superpowers 那套紅旗表與反覆叮嚀。
#
# 噪音紀律：本 hook 是 informational 例外（比照 session-debt-summary.sh），
# 每次都印。但只印在 kit skill 實際安裝的環境——找不到 skill 就靜默。
#
# fail-open：任何錯誤路徑 exit 0。

set -u

cat >/dev/null 2>&1 || true

# 只在四個 skill 都裝好時才注入（未安裝的環境印了也沒用）
_missing=""
for s in brainstorm plans sdd debug; do
    [ -e "${HOME}/.claude/skills/${s}" ] || _missing=1
done
[ -z "$_missing" ] || exit 0

cat <<'EOF'
kit skill 觸發規則（取代已停用的 superpowers plugin 注入）：

- 實作前先判 flow：`direct`（<4 檔、無架構或資料模型決策、不跨模組）直接做；
  `spec` 走 `/brainstorm` → `/plans`。判準見 ~/projects/skills/kit/references/triage-rules.md 步驟 4。
  來自 backlog 且已標 `flow: direct` 的工作項不需要再 brainstorm——分流已在 triage 完成。
- 遇 bug、測試失敗、非預期行為 → `/debug`（四階段：根因調查→模式分析→假設測試→實作），
  在提出修法之前，不是之後。
- 執行含多個獨立 task 的實作計畫 → `/sdd`（每 task 一個 fresh subagent + review loop + ledger）。

這三條是判斷依據不是儀式：符合條件才用，不符合就直接做。
EOF
exit 0
