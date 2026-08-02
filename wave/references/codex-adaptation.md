# Harness 適配（Codex CLI）

> 本 skill 的行為規範 harness 中立，條文預設用 Claude Code 工具名。在 **Codex CLI** 下執行時按下表替換工具呼叫——所有停點規則、驗證合約、品質閘門、長跑規範**一字不變**。

| Claude Code 工具 | Codex CLI 等效 |
|---|---|
| `EnterWorktree({ name })` | **Dispatched 模式（`PORTFOLIO_DISPATCHED=1`）不適用本列**——worktree 已由 supervisor 預建且 cwd 正確，不建、不重開 session，直接開工。其餘情境：`git branch` + `git worktree add` 建立 worktree。接下來兩條路：**路徑 A（建議）**＝結束當前 session、在 worktree 目錄開新 session（`cd <worktree> && codex`），新 session 開場驗證四項：`pwd`、`git rev-parse --show-toplevel` 含 worktrees/wave-{id}、loaded instructions（/status）、hooks 生效；**路徑 B（同 session 繼續）**＝worktree 在 `.claude/worktrees/` 內（sandbox writable root 涵蓋）時可不重開——每次指令以絕對路徑前綴 `cd <worktree> &&` 執行即可（Codex 每次 exec cwd 不延續，AGENTS.md 鐵則 3）。路徑 B 的 trade-off：hooks/AGENTS.md 仍指向主 checkout，若 worktree 的 `.claude/` 結構與主 checkout 一致（wave 慣例下通常如此）則無影響；不一致時退回路徑 A。sandbox 對 `.git` 寫入需 approval 屬預期。**tmux 視窗名**：路徑 A 天然生效（pane_current_path 已在 worktree）；路徑 B 手動 `tmux rename-window wave-{id}` |
| Agent 背景派工＋完成通知 | `spawn_agent` 派子代理 + `wait_agent` 收割。Codex 子代理是**同步收割模型**：派一批 → 期間做 pipeline priming（預寫下批 brief、前置預檢）→ `wait_agent` 逐一收割。不存在「失聯」問題 |
| `SendMessage` 續跑原 agent | `send_input` 對原子代理續話（中斷恢復、諮詢追問同此） |
| `ScheduleWakeup` 心跳 fallback | 不適用——`wait_agent` 阻塞等待，無失聯風險。ledger 記一行「Codex 模式，心跳條款不適用」 |
| `AskUserQuestion` 結構化停點 | 純文字問答（Phase 0 / Phase 4 停點照問，僅呈現格式退化，停點規則不變） |
| `TaskCreate` / `TaskUpdate` 鏡像 | 走既有缺席條款：ledger 記一行「無 Task 工具，跳過鏡像」 |
| `/askfable` 諮詢 | 走既有「相依 Skill 缺席降級」：ledger 記「本波無 Fable 諮詢」，收尾報告品質 caveat 列出 |

**Codex 執行注意：**

- 建議 `approval_policy = "on-request"`——worktree 內 git 寫入（commit、worktree add）會觸發 approval 升級，屬 sandbox 摩擦非錯誤（upstream openai/codex#14338）
- Dashboard / ledger / 驗證合約 / goal condition 全是檔案慣例，兩個 harness 產物同格式——收尾稽核可由任一 harness 親跑重驗
