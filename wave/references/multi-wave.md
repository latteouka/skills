# 多波並行

> 支援多波同時在同專案內開發——各自獨立規劃、獨立 dashboard、獨立 session，互不干擾。

## 隔離策略

Worktree 建立的具體步驟見 **Phase 6 Step 1**。這裡說明設計理由和並行安全保證。

**為什麼不在 main 工作：** 使用者經常在多個 tmux session 同時對同專案開 wave。如果有「單波在 main」的路徑，兩個 session 同時啟動就會 race condition——都以為自己是第一個。一律 worktree 從設計上消除這個問題，不需要偵測、不需要旗標。單波也一樣——規則統一才不會有漏洞。

**並行安全保證：**
1. 所有波在獨立 worktree 工作，互不影響 working tree
2. 每個波只讀寫自己的 `wave-{id}.md`
3. `playwright-guide.md` 併發寫入處理：每個 worktree 維護自己的副本，merge 回 main 時自動合併（append-only 格式天然可合併）
4. `prisma/schema.prisma` 等共用檔案的衝突在 merge 階段處理（見合併協助段落）

## `/wave batch` — 批次規劃多波（backlog 一次排完）

使用者說「讀 backlog 看能開幾波」「全部排波」「一次給我所有 wave prompt」＝進本模式。

1. **取料**：讀 `backlog.md` 全部 `ready` 項（⚠️ 硬閘門照舊：`⚠️需客戶確認` 不取）
2. **分波**：依每項預期動到的檔案範圍分組——不相交的組＝可並行各開一波；相交的項合進同一波；
   有依賴關係的標啟動順序（後波在前波 merge 後開）。分組結果連同「預測交集」表**先派 `/askfable` 審查**（諮詢點 4：檔案範圍分組有無漏算的相交、依賴順序有無成環或顛倒、「可並行組合」是否高估），修正後再呈使用者過目
   （此時無 commit 可 diff，交集是預測非實測，標明）
3. **逐波產出**：每波各走 Phase 3～5（工作項＋合約＋dashboard `wave-{id}.md`＋session prompt
   ＋goal condition）——batch 只改「一次規劃幾波」，不簡化任何單波的管線
4. **總表收尾**：波數、每波一句話範圍、建議啟動順序、可同時開的組合。使用者拿各 prompt
   分別開 session；各 session 開場的多波感知 hook（wave-awareness）會自動接手實測交集

## `/wave status` — 全局概覽

任何時候可呼叫，動態掃描所有波次狀態：

**資料來源：** `bash <kit>/scripts/wave-registry.sh list`（branch、已改檔數、未 commit 數、最後 commit 時間）+ 各 worktree / main 的 `.claude/dev/wave-*.md`。

輸出格式見 `references/templates.md` 的「`/wave status` 輸出範例」節，動態填入實際掃描結果。

找不到 dashboard 的波標「資訊不可用」。🗑️ 狀態的波不顯示。

## `/wave drop {id}` — 放棄一波

1. 把 `wave-{id}.md` 狀態標 🗑️
2. `/wave status` 不再顯示該波
3. 不自動刪 worktree 或檔案——使用者想清理就手動清

## 合併協助

> **Dispatched 模式（`PORTFOLIO_DISPATCHED=1`）不適用本節**：executor 只 push branch，merge／worktree 清理由 portfolio supervisor 承擔（typecheck → diff 分流 → auto-merge；完整品質閘門在 merge 後 deep lane 背景跑），見 wave skill `references/dispatched-mode.md`。

每波在 worktree 完成後，merge 回 main：

1. merge 本波 branch 到 main——branch 名以 ledger 開工記錄為準（手動流程＝`wave/{id}`，原生 EnterWorktree＝harness 命名如 `worktree-wave-{id}`），不憑記憶猜
2. 加法衝突（兩波各加不同欄位到同檔案）→ 自動合併
3. 改法矛盾（同一行改成不同東西）→ 列出衝突 + 兩波原始意圖，使用者裁定
4. **Merge typecheck（強制，貼輸出才算合併完成）**：在 main 上跑專案 typecheck（~90 秒，同步）——任何紅燈先修再宣告合併完成。理由：merge 殘留 TS 錯誤曾多次上 main。E2E 子集與完整品質閘門不在此跑——由 merge 後 deep lane 承擔（`wave-gate.sh baseline`，紅燈寫 inbox 開單）。手動波與 dispatched 模式的 merge 前檢查標準統一為 typecheck-only
5. **UX 補跑回收**：本波品質閘門若觸發降級規則（「待 UX 補跑」），此時 dev server 可用——立即補跑並回寫 wave-{id}.md，補跑完成才把狀態升級為「✅ 完成」
6. 清理 worktree：環境有 `ExitWorktree` 工具用 `ExitWorktree({ action: "remove" })`；`discard_changes` 屬破壞性選項，僅在親自確認 worktree 無未合併變更後使用

不自動 force merge——有矛盾必停，呈現衝突 + 推薦方案，使用者確認才執行。
