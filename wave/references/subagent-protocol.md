# Subagent-Driven 長跑協議（選 Subagent-Driven 執行方式時適用）

主 session 作為 controller，額外遵循：

## Brief-driven 派工

- 每個 implementer 的 brief 以**第 0 項（執行紀律）開頭**，再接六要素。第 0 項必須是 brief 的**第一段**、逐字含「**違反任一條＝任務失敗**」宣告——實證（2026-07-28 matrix-hardening）：同樣條文寫在 brief 中段被跳過（累計 ≥3 次），提為開頭＋失敗宣告後四個 agent 零違規。controller 組 brief 時直接複製下面這段放最前面：

  > **【第 0 項・執行紀律——違反任一條＝任務失敗】**
  > ①長跑指令（E2E／測試／build）一律**前景執行**、Bash timeout 拉高（600000ms 級）——你等自己的背景 run 永遠不會被喚醒；
  > ②同 worktree 並行工作時 commit 一律 **`git commit -- <pathspec>`** 限定路徑——共用 git index 下無 pathspec commit 會把別人 staged 的檔案掃進你的 commit。

- 六要素：
  1. 需求描述 + 裁定結論
  2. 程式現況（`file:line` 引用，註明「行號可能漂移，以語意定位」）
  3. 驗證合約（從 dashboard 複製該項完整合約）
  4. 硬約束（不可碰的檔案/目錄，如其他波涉及範圍）
  5. 非目標（明確不做的事，至少一條——防順手改、防 scope 蔓延）
  6. 停止條件（遇到即停手回報：要動範圍外檔案、要刪東西、發現機密、與硬約束衝突）
- **Brief 分級**：小項（單檔、合約短）→ 第 0 項＋六要素完整內嵌 Agent prompt 即可；大項（schema 變更、跨系統、多檔）→ 必須落檔 `task-N-brief.md` 並另寫 `task-N-design.md`，**落檔後先派 `/askfable` 審查**（諮詢點 3），再呈使用者 review 才動手（三件套 brief/report/design 放 worktree 的 `.superpowers/sdd/` 下——gitignored scratch 不進版控）
- Subagent 開場指令 =「先讀你的 brief，它就是你的 requirements」（內嵌時 prompt 本身即 brief）——subagent 不依賴 controller 的對話 context
- **模型分層**：派工時依項目性質選 model tier——機械、範圍明確的實作項 → `model: "sonnet"`；瑣碎查證/整理 → `haiku`；跨系統、架構性、難 debug 的項 → 省略（繼承 session 模型）。拿不準就省略。Reviewer 的 tier 不得低於該項 implementer。**每筆派工的 ledger 條目必須帶 model tier**（例：`派工 task-3 implementer（sonnet）`），tier 切換有跡可查
- Implementer 完成**一律**交付 report：大項寫 `task-N-report.md`；小項可改為回填鏡像 Task 的 description 或在回報訊息附完整合約輸出。controller 與 reviewer 都讀

## 管線不斷料（pipeline priming）

趁當前 task 在跑，controller 預寫下一批 brief、做前置預檢（DB 起了沒、測試環境可用嗎）——不閒等。

## 心跳 fallback（ScheduleWakeup）

- 每次派背景 subagent 後，排一個 ScheduleWakeup fallback（環境無此工具則跳過此保險）——背景完成通知失靈時的斷線保險。delay 分兩層：
  - **長跑 implementer**（實作/實驗，10 分鐘以上）→ 1200s+，非短輪詢
  - **數分鐘內將完成的一批 agent**（並行比對/掃描組）→ 短窗輪詢，delay 對齊該批預計完成時間；該批收完換回長層。cache TTL 等環境常數不硬編進排程理由——依當期 harness 說明為準
- Wakeup prompt **完整重述狀態**，不依賴記憶即可續泵。模板見 `references/templates.md` 的「心跳 Wakeup Prompt 模板」節，排 wakeup 時照填。

- **Stale wakeup 核實**：喚醒內容與現實可能脫節（說 X 實作中但其實已 commit）→ 先核 git 真實狀態再行動，不盲從喚醒內容、也不盲從記憶。喚醒內容與使用者最後指示衝突時，問人不擅斷
- 與 `/goal` 分工：goal 判定「做完了沒」，心跳保證「沒做完就繼續動」

## 中斷恢復優先 SendMessage 續跑

曾有實際產出的 agent 因額度上限、網路中斷、環境守門或使用者暫停而停止 → **不重派**，用 SendMessage 對原 agent 續跑（context 全保留）。訊息結構：

```
Controller 通知：[中斷原因 + 現況，如「額度已重置」「網路已恢復（PG 連通、API 回 200，皆已驗證）」]。
先 `git status` + `git log --oneline -3` 核實你已落地與未落地的工作，再從斷點繼續。
[中斷期間有作廢產出時明確指出：「X 被中途 kill，視為無效、重跑」]
```

SendMessage 失敗（agent 已死）或該 agent 屬空跑 → 才走重派。

## Controller 代看門

Subagent 依賴背景等待（Monitor、背景 process 輪詢）卻沒被喚醒 → controller 接管看門（自己盯 process/log），用 SendMessage 代通知「X 已結束，結果在 Y」。同一 agent 第二次失靈 → 後續指令禁用該等待模式（改前景執行），並記入 ERRATA。

## 空跑偵測

Subagent 回傳異常（0 tool uses、秒級返回、無 commit）→ 視為沒實際執行。核 git 確認無半成品後重派，不把空跑當完成。

## Reviewer 不信報告

每 task 的 reviewer 必須**親自重跑**測試/typecheck/lint，不採信 implementer 的 report 文字。權限/安全敏感項升級 security rigor。共用 branch 交錯時，review 範圍用明確 commit SHA 指定，不用 range。
