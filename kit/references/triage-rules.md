# Triage 判斷樹

對 `inbox.md` 中每一筆 `## INB-NNN` 執行下列步驟，結果寫入 `backlog.md`。

## 1. 定位規格條目

```bash
grep -rn "<關鍵詞>" <spec_layer>
```

- 0 筆命中 → 改用 `impl_routes` / `impl_details` 欄位再找一次（路由名、檔名）
- 仍 0 筆 → `type: NEW`，`matrix: （待新增條目）`
- ≥1 筆 → 讀該條 `detail_specs`，進入步驟 2

**`spec_layer` 為空（config 未設）** → 跳過本步與步驟 2，直接進步驟 3；`type` 僅可為 `BUG` / `NEW` / `CHORE`，且必須在 triage 輸出明示「已降級：本專案未設 spec_layer，未做規格對帳」。

## 2. 三分類判定

比對「使用者描述的期望行為」與「`detail_specs` 記載的行為」：

| 情況 | 判定 |
|---|---|
| specs 有寫，程式碼不符 | `BUG`（matrix 不動） |
| specs 有寫，程式碼符合，使用者想改 | `SPEC_CHANGE` ⚠️ |
| specs 未涵蓋此面向，但 RFP `rfp_text` 隱含 | `BUG`（順帶補 detail_specs） |
| specs 未涵蓋，RFP 亦無 | `NEW`（matrix 加 status: planned） |
| 與 `rfp_text` 字面衝突 | `SPEC_CHANGE` ⚠️⚠️ 標「影響驗收」 |
| 使用者要求的是內部改善（重構、清理、效能優化、測試補強），不改對外可觀察行為 | `CHORE`（matrix 填 —） |

判為 `SPEC_CHANGE` 者，`status` 一律先填 `⚠️需客戶確認`，不得直接填 `ready`。

## 3. 去重

與 `backlog.md` 既有項比對（同 matrix 條目 + 語意相近）→ 命中則併入既有項的 `from` 欄，不新增條目。

## 4. 分流判定（flow 欄位）

**以下任一成立即 `flow: spec`，與 type、status 皆無關：**
- 預估動 4 個以上檔案
- 含架構或資料模型決策
- 跨模組

**以上皆不成立 → `flow: direct`。**

三個欄位正交，不可互相推導：
- `type` 決定規格層影響（是否動 matrix），不決定 flow
- `status` 決定能否排波（`⚠️需客戶確認` 的項 wave 取不到），不決定 flow
- `flow` 只衡量工作量規模

例：一個 SPEC_CHANGE 若只改一個預設值，是 `type: SPEC_CHANGE`＋`status: ⚠️需客戶確認`＋`flow: direct` ——客戶確認過後直接進 wave 做掉，不需要寫 spec。一個 BUG 若要動 5 個檔並改資料模型，是 `type: BUG`＋`flow: spec`。

`flow: direct` 的工作項**不需要**先走 brainstorming。這不是在合理化跳過流程——分流判定已在 triage 階段完成，重複 brainstorming 只會產生無人閱讀的 spec 並加劇文件堆積。

## 5. 非回饋內容

除錯對話、技術問答等誤收項 → `status: dropped:{理由}`，保留紀錄不刪行（供日後調整詞庫）。

## 6. 收尾

- 已處理的 `INB-NNN` 從 `inbox.md` 移除（其內容已轉入 backlog 的 `from` 欄）
- 輸出處理摘要：新增 N 筆、併入 M 筆、dropped K 筆、⚠️ 待確認 J 筆
- **若 config 已設 `spec_check` 且本批有任何 `type: SPEC_CHANGE` 或 `NEW` 的項目**（會動到規格層），輸出提醒使用者執行該指令驗證規格檔一致性。若 `spec_check` 為空則跳過此提醒。
