# Wave 深度材料 — UI 碎片化審計
**Created**: 2026-07-20

> Phase 2 條件觸發的延伸掃描（自動判斷，非使用者手動呼叫）。觸發信號見 core「碎片化審計」條款。

**核心原則：** 使用者說「A 和 B 風格不一致」時，真正的問題幾乎不只 A 和 B——是整個 codebase 缺少某個共用 primitive，所有需要它的地方都各自發明。不做全面審計就直接修 → 修完又被發現其他地方也有同樣問題 → 永遠修不完。審計成本低（grep ＋一個 Explore agent 數分鐘），價值高（使用者看到全貌才能做正確的 scope 決定）。

## 審計程序（四來源掃描收斂後執行）

1. 從使用者指出的具體檔案提取 CSS pattern 簽名（如 `border-b border-border px-3 py-2`、`text-xs font-semibold`、`CardHeader className=...`）
2. 派一個 Explore agent 掃全專案（prompt 模板見下）
3. 分類漂移：哪些用 pattern A、哪些用 pattern B、哪些是 A 的變體
4. 輸出「元件碎片化地圖」併入 Phase 3 規劃——**不加停點**，使用者在 Phase 4 看到完整地圖時做 scope 決定

## Explore agent prompt 模板

```
你的任務是審計一個 codebase 的 UI 元件碎片化程度。

使用者已指出以下區域有「同類元件各自發明風格」的問題：
{使用者指出的區域和具體問題描述}

提取的 CSS pattern 簽名：
{從使用者指出的檔案中提取的具體 className pattern}

請找出專案中 **其他** 使用相同或相似 pattern 的地方。搜尋策略：
A. 用 grep 搜 pattern 簽名在全專案的分布
B. 找所有類似結構的元件（header + body 容器、手風琴、卡片殼、Sheet/Dialog 外殼、loading/empty/error 四態）
C. 對每個發現，標示它與「標準 pattern」的漂移程度

輸出格式：按區域分類，每個發現一行（路徑 + 一句話描述漂移）。
```

## 碎片化地圖輸出格式

「已知（使用者指出）」與「新發現（審計掃出）」分開列，表格逐區域：

| 區域 | 檔案數 | 重複 pattern | 漂移 |
|---|---|---|---|
| Statistics dashboard | 12 | `Card > CardHeader > CardTitle` | 3 個 className 變體 |
| Detail-sheet renderers | 15 | header + Skeleton loading | 完全相同，Skeleton 寬度微漂 |

已存在但沒人用的共用元件也要列一行（它是「該用而未用」的直接證據）。

## Phase 2.5：淺/中/深光譜（brainstorming 加碼時直接呈現）

碎片化統一的設計決策總落在同一光譜，不必從零展開方案——直接給三選項：

| 選項 | 做什麼 | 改動面 | 風險 |
|------|--------|--------|------|
| 淺層 | 只抽容器殼（header + spacing） | 最小——各元件內容不動 | 最低 |
| 中層 | 殼 + 共用狀態 pattern（loading/error/empty） | 中等——需調整 data fetch 結構 | 低 |
| 深層 | 殼 + 狀態 + registry/config 機制 | 最大——引入新抽象層 | 中高 |

預設推薦淺層——先解決視覺不一致，不引入新抽象。

## Phase 3：共用殼工作項 pattern

審計會得到「N 個區域做同一件事但各自發明」的清單，從清單反推需要哪些共用 primitive，按殼組織工作項：

```
每個共用殼 = 一個工作項：
  🤖-N: 建 {殼名} + 遷移 {affected_count} 個檔案

  驗證合約（碎片化統一類的標準合約）：
  1. typecheck → 0 errors
  2. 既有測試全綠（純重構，功能不變）
  3. Happy path: 開目標頁面 → 所有 section/card header 樣式一致（截圖自檢）
  4. Edge case: 空資料態 → 正常顯示
```

這類工作項特徵：
- **不動功能邏輯**——只換殼；行為不變，**不新寫 unit test**（Smart TDD：UI styling 用截圖驗證取代）
- **適合 sonnet tier**——機械式遷移，派工照「模型分層」規則
- **高度可並行**——各殼元件互不依賴
