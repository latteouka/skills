---
name: wave
description: 規劃並啟動一波工作。自動偵測開發/通用模式，讀 requirements → 偵測是否需要 align 新素材 → 分類自主/人判斷項 → 產出 living dashboard + goal condition → 選執行方式後原地開工。所有 wave 一律在獨立 worktree 中執行。觸發詞：/wave、開新波、新一波、plan wave、啟動開發、啟動工作。子指令：/wave status（全局概覽）、/wave drop {id}（放棄一波）。旗標：--dev（強制開發模式）、--general（強制通用模式）。
argument-hint: "（選填）逐字稿路徑、會議檔案、或簡述這波方向"
---

# Wave — 開發波次規劃與啟動

一次呼叫完成：對齊新資訊 → 規劃工作項 → 產出可直接貼入的 session prompt + goal condition。

## Core Principles

- **Wave 是唯一入口。** 使用者不需要記「要不要先 align」、「要不要看 requirements」——Wave 自動判斷並串接。
- **一波帶走。** 所有掃出的未完成項都排進這一波，不建議延後。遇到真正的 blocker 在該項旁邊標註原因讓使用者決定，但不主動歸類為「建議延後」。
- **做好比做快重要。** 不趕進度、不跳過測試、不為了早點結束而降低覆蓋。一個功能做兩小時但零 bug，勝過六個功能做完三個要回頭修。Session 跑再久都沒關係，品質是唯一標準。
- **唯一停點制。** 全流程只有兩個合法停點（Align 問題、Phase 4 範圍確認）。其餘階段轉換、項與項之間一律自動接續——不停、不問、不結束 turn。詳見「停點規則」。

## 停點規則（唯一停點制）

> **CRITICAL: 全流程僅有兩個合法停點。除此之外不停下等待輸入、不問「要不要繼續」、不結束 turn。**

**合法停點：**

1. **Phase 0 Align 問題**——「這波有新素材要帶入嗎？」（`/wave` 帶參數時跳過，此時全程零規劃停點；**無參數時必問，不可自答「沒有素材」代跳**）
2. **Phase 4 範圍確認**——工作清單 + UX 審計清單 + 交集預警 + **執行方式選擇**一次問完

**停點提問形式：** 環境有 `AskUserQuestion` 工具時，兩個停點的提問用它結構化呈現——Align 用固定三選項；Phase 4 用「執行方式」單選 + 「UX 審計清單」multiSelect（工作清單本體仍以文字完整列出，選項只承載決策）。無此工具則文字問答。

**自動接續（不停、不問、不結束 turn）：**

- Phase 1 → 2 → 2.5 → 3
- Phase 4 確認後 → Phase 5 產出 → Phase 6 建 worktree → 設 goal → 開工
- 執行期項與項之間
- 品質閘門 → 稽核 → 收尾

**Turn 結束前自檢：** 結束 turn 前檢查最後一段輸出——若是計畫、問題、下一步清單、或「我接下來會…」的承諾 → 立刻用 tool call 做掉，不准就此結束 turn。（本節所列合法停點與例外的提問不在此限。）

**Phase 2.5 例外：** brainstorming / grill 是本來就需要人的訪談，不算違規停點，但完成後自動回到 Phase 3，不重新等指令。

**合併協助例外：** merge 回 main 時遇到改法矛盾衝突需使用者裁定（見「合併協助」節）——那發生在 wave 完成後的合併階段，且屬破壞性裁定，不受本節限制。

**需人裁定例外：** 執行期遇到需人裁定的事項，按「長跑行為規範」第 5 條非阻塞升級處理——僅當其阻塞所有剩餘工作時才停下。

## Workflow

### Phase 0: 多波偵測 + Align 判斷

**Step 0: Mode 偵測**

自動偵測工作模式（不問使用者）：

```bash
# 偵測開發專案特徵
ls package.json Makefile Cargo.toml go.mod pyproject.toml requirements.txt pom.xml build.gradle 2>/dev/null
ls -d src/ lib/ app/ 2>/dev/null
```

- **命中任一** → `mode = dev`，走完整開發流程（驗證合約 + 安全/UX 閘門）
- **全未命中** → `mode = general`，走輕量流程（checklist review）
- 使用者可覆寫：`/wave --dev` 強制開發模式、`/wave --general` 強制通用模式

偵測邏輯寬鬆——寧可多判成 dev 也不要漏。偵測結果在 Phase 4 向使用者顯示，使用者可當場改。

**Step 1: 動態重建 Registry**

掃描現有波次狀態（不讀檔，每次動態重建）：

```bash
# 掃 main 的 wave dashboard
ls .claude/dev/wave-*.md 2>/dev/null

# 掃所有 worktree 的 wave dashboard
git worktree list | while read path _; do
  ls "$path/.claude/dev/wave-"*.md 2>/dev/null
done
```

如果有其他 🟢（待啟動）或 🟡（執行中）的波，顯示概覽：

> ## 🌊 現有進行中的波
> | ID | 簡述 | 狀態 | 進度 | 涉及檔案 |
> |---|------|------|------|---------|
> | orders-api | 訂單 API | 🟡 執行中 | 3/5 | src/server/api/routers/order* |

**Step 2: 自動命名本波**

Claude 從工作項方向自動生成 ID（如 `suspect-merge`、`report-ui`），不問使用者。使用者不滿意才改。無其他波在跑時也可用日期 ID（`wave-0630`）。

Dashboard 檔名：`.claude/dev/wave-{id}.md`

**向下相容：** 如果已有舊的 `.claude/dev/wave.md`（單波模式），自動遷移成 `wave-legacy.md`。

**Step 3: Align 判斷**

問使用者一個問題：

> 這波有新素材要帶入嗎？（逐字稿、會議紀錄、客戶回饋、新規格）
> - 有 → 請貼上或告訴我檔案路徑
> - 沒有，從現有 requirements 繼續
> - 我想重新對齊某份舊逐字稿 → 告訴我哪份

如果使用者在 `/wave` 後面直接帶了參數（檔案路徑或文字），跳過這個問題直接進 Phase 1。

### Phase 1: Align（有新素材時）

執行簡化版 align：

1. **Digest** — 讀取素材，摘出行為承諾 / 需求變更 / 新決策
2. **Diff** — 比對 `docs/requirements/` 現有內容，分三類：
   - 🆕 新增（requirements 沒有的）
   - ⚠️ 衝突（與現有描述矛盾）
   - ✅ 一致（已對齊）
3. **確認衝突** — 只有 ⚠️ 項需要使用者裁定（逐條，附推薦方案）
4. **落檔** — 更新 `docs/requirements/` 對應檔案

如果沒有新素材，跳過此 Phase。

### Phase 2: 掃描工作項（loop-until-dry）

> 掃描必須在 Align（Phase 0 Step 3 / Phase 1）**之後**執行——新素材要先落檔 requirements 才掃得到，順序顛倒會掃到舊狀態。Phase 0 不預跑掃描。

> **CRITICAL: 掃描完備優先於掃描速度。四個來源各掃一輪後再掃一輪，連續兩輪無新工作項才准停。防「掃到夠交差就停」。**

自動執行（不問使用者），四個來源：

```bash
# 來源 1：requirements 未完成項
find docs/requirements/ -name "*.md" -exec grep -l "🔴\|🟡\|❓" {} \;

# 來源 2：程式內待辦標記
grep -rn "TODO\|FIXME" src/ lib/ app/ 2>/dev/null | head -50

# 來源 3：所有舊 wave 的延後決策
grep -A 20 "📋 延後決策" .claude/dev/wave-*.md 2>/dev/null

# 來源 4：git log 近況（找做一半的工作）
git log --oneline -20
```

從四來源收集所有未完成項（🔴 未實作 / 🟡 部分實作 / ❓ 未決 / 延後決策 / 半成品）。

**Loop-until-dry 規則：** 四來源掃完一輪後，帶著已找到的工作項**再掃一輪**（第二輪常因理解了脈絡而多挖出關聯項）。連續兩輪無新項 → 掃描完成。

> **CRITICAL: 規模與時長脫鉤。工作項數量以完整覆蓋為準，禁止以「session 會太長」「先做核心」「這波先做一部分」為由在規劃期縮範圍。真 blocker 在該項旁標註原因交使用者裁定。**

**交集分析（多波時）：** 如果 Phase 0 偵測到其他進行中的波，對比本波工作項預期動到的檔案與其他波的涉及檔案。有交集的記錄下來，Phase 4 會顯示預警。

### Phase 2.5: 判斷是否需要 brainstorming / grill-me

掃完工作項後，**先判斷再分類**——不要急著進 Phase 3。

| 情境 | 觸發 | 理由 |
|---|---|---|
| 工作項包含**新功能或從零開始的模組** | `/brainstorming` | 設計方向未定，需要探索多方案再選 |
| 工作項包含**多個有效做法、架構選擇、或 UX 決策** | `/brainstorming` | 先展開 trade-off 再寫合約，避免合約鎖死錯誤方向 |
| 這波**規模大（≥5 項）或有高風險項**（資料遷移、權限變更、跨系統串接） | `/grill-me` | 用逐題訪談壓力測試計畫，提早抓出盲點 |
| 工作項牽涉到**既有文件需同步更新**（CONTEXT.md / ADR） | `/grill-with-docs` | 訪談同時更新文件，避免計畫和文件脫節 |
| 全部都是**明確的 bug fix、config 變更、CRUD 擴充** | 直接進 Phase 3 | 設計方向已定，不需要展開 |

**執行方式：**
- 符合多個條件時，先 brainstorming（展開方向）再 grill-me（壓力測試）
- 完成後帶著結論進 Phase 3，結論直接影響合約的覆蓋場景設計
- 向使用者說明觸發了什麼、為什麼：「這波有 2 個新功能設計方向未定，先跑 /brainstorming 對齊再規劃合約。」

### Phase 3: 分類、排序、寫驗證合約

> **CRITICAL: 每個工作項在規劃階段就必須寫好驗證合約——具體的指令 + 預期輸出。執行時按合約跑，不是自由心證。**

> 以下依 mode 分流。dev 模式走完整驗證合約，general 模式走輕量 checklist。

#### mode = dev

將工作項分類，並為每項寫驗證合約：

**🤖 自主可完成（Claude 獨立完成 + 自驗）：**
- 有明確行為描述 + 可寫測試驗證
- 純後端邏輯（API、計算、資料處理）
- UI 功能可用 Playwright 自動驗證（按鈕點擊→結果出現）
- Bug fix 有明確重現步驟

**🤖👁️ E2E 先驗再交人（Claude 實作 + E2E 跑過 → 僅交出 E2E 無法覆蓋的殘項）：**
- UX 流程——Claude 先用 Playwright 跑完整操作流程確認功能正確，只把「操作感受」交人
- 跨系統整合——Claude 先 E2E 驗證可觸及的部分，標註哪些環節因環境限制無法自動驗證
- 文字/語意——Claude 先驗排版渲染正確（元素存在、內容非空），語氣恰當性交人

**👁️ 純人眼（E2E 結構性無法覆蓋）：**
- 視覺微調（間距感受、對齊美感、顏色搭配、動畫流暢度）
- 這類項目 Claude 仍須先 screenshot 自檢，確認元素存在、佈局不破版

#### 驗證合約格式

每個工作項必須在規劃階段附帶驗證合約。合約 = 可執行的指令 + 預期輸出 + 覆蓋場景。

```markdown
### 🤖-1: 訂單篩選 API
**驗證合約：**
1. `pnpm vitest run src/server/api/routers/order.test.ts` → ≥5 tests passed
2. Happy path：空篩選回全部 / 多條件交集 / 無結果回空陣列
3. Edge case：日期範圍頭尾相同 / 金額為 0
4. 誤用：不存在的篩選欄位 → 400 / SQL injection 字串 → 安全處理

### 🤖-2: 訂單篩選 UI
**驗證合約：**
1. `pnpm vitest run src/server/api/routers/order.test.ts` → passed（API 層）
2. `pnpm playwright test tests/order-filter.spec.ts` → passed
3. Happy path：選篩選條件→表格更新 / 清除篩選→回全部 / 無結果顯示空狀態
4. 誤用：快速連點篩選按鈕 → 不重複發 request / 篩選中切頁再回來 → 狀態保持

### 🤖-3: API token 驗證機制
**驗證合約：**
1. `pnpm vitest run src/server/auth.test.ts` → ≥3 tests passed
2. Happy path：valid token → 200 / expired token → 401
3. Edge case：malformed token / empty string / null
4. 誤用：token 洩露到 response body / log
5. 🔒 `/insecure-defaults` 掃描 auth 相關檔案 → 0 high/critical
6. 🔒 `/sharp-edges` 掃描 API 設計 → 0 high/critical

### 🤖👁️-1: 訂單詳情頁
**驗證合約：**
1. `pnpm playwright test tests/order-detail.spec.ts` → passed
2. Happy path：導航到詳情→資料正確 / 編輯→儲存成功
3. 誤用：未儲存就離開→提示 / 必填欄位清空→擋提交 / 權限不足→導轉或禁用
4. 殘項交人：頁面資訊密度是否太擠、欄位排列是否直覺
```

#### 安全 Skill 合約規則（🔒 標記步驟）

依工作項性質，在驗證合約中自動加入安全審計步驟：

| 工作項性質 | 自動加入的安全 skill |
|-----------|---------------------|
| API route / tRPC router / middleware | `/insecure-defaults` + `/sharp-edges` |
| Auth / 權限 / session / crypto | 三個全開（含 `/static-analysis`） |
| 新增 dependency / config 變更 | `/insecure-defaults` |
| 任何 `.ts/.tsx` 程式碼變更 | `/static-analysis`（semgrep baseline） |

**🔒 步驟的效力：**
- high / critical findings → **blocking**，必須修到 0 才能 commit
- medium / low findings → 記錄到 wave-{id}.md「🔒 安全審計結果」區塊，不阻擋 commit

**合約寫法規則：**
- 指令必須是可複製貼上直接跑的（含完整路徑）
- 預期輸出寫具體（`≥3 tests passed`，不是 `tests pass`）
- 🤖👁️ 項的合約必須同時列出 E2E 覆蓋範圍和殘項
- 覆蓋場景必須涵蓋三個角度（缺一不可）：
  1. **Happy path** — 正常操作流程
  2. **Edge case** — 邊界值、空值、超長輸入、併發
  3. **誤用場景** — 使用者會犯的錯：重複提交、亂填格式、跳過步驟、無權限硬闖、中途離開再回來

排序原則：
1. 先做有測試可驗的後端邏輯
2. 再做 Playwright 可驗的 UI 功能
3. 再做 🤖👁️ 項（E2E 先驗 → 殘項交人）
4. 最後做 👁️ 純人眼微調

#### Grill/Spec 決策審計（Phase 2.5 有觸發 grill 時必做）

> **CRITICAL: 分類完工作項後，必須回頭比對 grill/brainstorming 產出的所有決策。沒有對應工作項的決策 = 延後決策，必須明確追蹤。**

1. **收集決策源** — 讀取 Phase 2.5 的 grill/brainstorming 紀錄（spec 文件、grill 對話中的共識）
2. **逐條比對** — 每個決策是否有對應的工作項（🤖 / 🤖👁️ / 👁️）
3. **建立延後清單** — 沒有對應工作項的決策列入「📋 延後決策」，每項記錄：
   - 決策內容（一句話）
   - 來源（spec 哪段 / grill 哪題）
   - 延後原因（scope cut / blocker / 依賴未就緒）
   - 建議優先順序（🔴 安全相關 / 🟡 功能完整性 / 🟢 nice-to-have）
4. **零延後也要寫** — 如果所有決策都有對應工作項，明確寫「本波涵蓋所有 grill/spec 決策，無延後項」

沒有跑 grill/brainstorming 的波不需要這步。

#### mode = general

將工作項分類（二分法，不需要 🤖👁️ 中間態）：

**🤖 自主可完成：**
- 有明確產出物（文件、簡報、表格、摘要、翻譯）
- 完成標準可客觀判斷（檔案存在、結構完整、內容涵蓋指定要點）

**👁️ 需人判斷：**
- 品質需主觀評估（語氣、美感、策略方向）
- 涉及外部資訊 Claude 無法驗證（數字正確性、人名職稱、內部政策）

##### Checklist 格式

每個工作項附一份完成 checklist（不需要三角度覆蓋）：

```markdown
### 🤖-1: [工作項名稱]
**完成 checklist：**
- [ ] 產出物：`[路徑]` 已建立
- [ ] 結構：包含 [列出必要段落/章節]
- [ ] 內容：涵蓋 [列出關鍵要點]
- [ ] 👁️ 交人：[列出需人判斷的點，沒有則寫「無」]
```

排序原則：
1. 先做 🤖 自主項
2. 再做 👁️ 需人判斷項（Claude 先完成可自主的部分）

### Phase 4: 向使用者確認範圍

輸出工作清單，問使用者：

> ## 這波工作範圍
> 
> ### 🤖-1: [功能名] — [一句話描述]
> 來源：[requirements 哪個檔/哪行]
> **驗證合約：**
> 1. `[指令]` → [預期輸出]
> 2. Happy path：[場景]
> 3. Edge case：[場景]
> 4. 誤用：[場景]
>
> ### 🤖-2: ...
>
> ### 🤖👁️-1: [功能名] — [一句話描述]
> **驗證合約：**
> 1. `[指令]` → [預期輸出]
> 2. Happy path：[場景]
> 3. 誤用：[場景]
> 4. 殘項交人：[E2E 無法覆蓋的點]
>
> ### 👁️-1: [功能名] — [一句話描述]
> 需要人看：[具體判斷點]
> 自檢：截圖確認元素存在 + 不破版
> 
> ---
> **預估規模**：約 N 個 commit（規模以完整覆蓋為準，不以 session 長度為準）
> **Checkpoint 分段**：每 3 項一段（C1: 🤖-1~3 / C2: 🤖-4~🤖👁️-1 / ...），執行期 re-grounding 以段為錨點
>
> **執行方式**（本次確認一併選定，Phase 6 不再另問）：
> 1. **Subagent-Driven**（推薦）— 每個工作項派獨立 subagent，中間 checkpoint review
> 2. **Inline Execution** — 在此 session 直接逐項執行，每項完成後 checkpoint review
> 
> 要調整嗎？（移除某些項 / 改合約覆蓋範圍 / 改優先序 / 換執行方式）

**以下 UX 審計推薦僅 mode = dev 時顯示：**

如果這波有前端工作項，在工作清單後面多輸出 UX 審計推薦：

> ## 🎨 UX 品質閘門（完成所有項後批次執行）
> 
> 根據這波工作項性質，推薦以下審計：
> - ✅ `/ui-test` — 有 N 個 UI 功能項，跑對抗性功能測試
> - ✅ `/wcag-accessibility-audit` — 新增表單元件，檢查無障礙
> - ⬚ `/nielsen-heuristics-audit` — 無新頁面，不推薦
> - ⬚ `/ux-audit-rethink` — 非大改版，不推薦
> 
> 要調整嗎？（打勾/取消任一項）

**UX 審計推薦規則：**

| 工作項性質 | 推薦的 UX skill |
|-----------|----------------|
| 有 UI 功能（任何前端工作項） | `/ui-test`（必推） |
| 新增表單 / 互動元件 / 導航變更 | `/wcag-accessibility-audit` |
| 新頁面 / 新流程 / 新 layout | `/nielsen-heuristics-audit` |
| 整頁重設計 / 大量 UX 改版 | `/ux-audit-rethink` |

**檔案交集預警（多波時）：** 如果交集分析發現與其他波有重疊檔案，在工作清單後插入預警：

> ## ⚠️ 檔案交集預警
>
> | 檔案 | 與哪波重疊 | 該波狀態 |
> |------|-----------|---------|
> | prisma/schema.prisma | orders-api | 🟡 執行中 |
>
> 本波將在獨立 worktree 中執行，合併時 Claude 會協助處理衝突。

不阻擋，純資訊。無交集時不顯示。

使用者確認工作範圍 + UX 審計清單 + 執行方式後進入 Phase 5。

**mode = general 時：** 不顯示 UX 審計推薦、不顯示檔案交集預警（非開發不需要）。直接確認工作範圍 + 執行方式後進入 Phase 5。

### Phase 5: 產出三份輸出

#### 輸出 1: `.claude/dev/wave-{id}.md`（Living Dashboard）

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單，用於交集分析]
- **Checkpoint 分段**: C1: [項] / C2: [項] / ...（每 3 項一段，re-grounding 錨點）
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-{id}-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑

## 狀態：🟢 規劃完成，待啟動

## 🎯 Goal Condition
（貼 Phase 5 輸出 3 全文 (1)-(10)；收尾時逐條打勾）

## 🤖 自主項
| # | 功能 | 狀態 | 合約指令 | 合約結果 | commit |
|---|------|------|---------|---------|--------|
| 1 | ... | ⏳ 待做 | `pnpm vitest run ...` | （貼輸出） | — |

### 🤖-1 驗證合約
（從 Phase 3 複製完整合約，含 happy/edge/誤用場景）

## 🤖👁️ E2E 先驗再交人
| # | 功能 | 實作 | 合約結果 | 殘項（交人） | 人測結果 |
|---|------|------|---------|-------------|---------|
| 1 | ... | ⏳ 待做 | （貼 E2E 輸出） | （E2E 無法覆蓋的點） | ⏳ 待測 |

### 🤖👁️-1 驗證合約
（從 Phase 3 複製完整合約）

## 👁️ 純人眼
| # | 功能 | 實作 | 自檢截圖 | 需要人看什麼 | 人測結果 |
|---|------|------|---------|-------------|---------|
| 1 | ... | ⏳ 待做 | （附截圖路徑） | （具體判斷點） | ⏳ 待測 |

## 🔒 安全審計結果
| 工作項 | Skill | Findings | High/Critical | 狀態 |
|--------|-------|----------|--------------|------|
| 🤖-3 | insecure-defaults | 0 | 0 | ✅ |
| 🤖-3 | sharp-edges | 1 medium | 0 | ✅ (advisory) |

## 🎨 UX 審計結果
| Skill | 執行範圍 | Findings 數 | 重點發現 |
|-------|---------|------------|---------|
| ui-test | 全站 | — | （貼摘要） |
| wcag-accessibility-audit | 新增元件 | — | （貼摘要） |

### 詳細 Findings
（每個 finding 附 severity / 位置 / 建議修法）

## 🕵️ 稽核結果（收尾稽核 subagent 填寫）
| 工作項 | 合約重跑 | 場景抽查 | 判定 |
|--------|---------|---------|------|
| 🤖-1 | （貼稽核實跑輸出） | happy/edge/誤用 各有 case | ✅/❌ |

**漏項掃描**：（requirements 有標記但無對應工作項的清單，無則寫「無漏項」）

## 📋 延後決策（Deferred from grill/spec）
<!-- Phase 2.5 有觸發 grill/brainstorming 時必填此區塊；沒觸發時整區刪除 -->
| # | 決策 | 來源 | 延後原因 | 優先順序 |
|---|------|------|---------|---------|
| 1 | [決策內容] | [spec §N / grill Q#] | [scope cut / blocker] | 🔴/🟡/🟢 |
<!-- 無延後項時寫：「本波涵蓋所有 grill/spec 決策，無延後項。」 -->

## 📋 Feedback（人測後填寫區）
（使用者只需測上面「殘項」和「人看什麼」欄位列出的項目，其餘 Claude 已按合約驗過）
```

**mode = general 時 Dashboard 格式：**

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **Mode**: general
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-{id}-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑

## 狀態：🟢 規劃完成，待啟動

## 🎯 Goal Condition
（貼 Phase 5 輸出 3 全文 (1)-(5)；收尾時逐條打勾）

## 🤖 自主項
| # | 工作項 | 狀態 | Checklist | 產出物 |
|---|--------|------|-----------|--------|
| 1 | ... | ⏳ 待做 | 0/4 ✅ | — |

## 👁️ 需人判斷
| # | 工作項 | 狀態 | Claude 已完成 | 交人判斷什麼 | 人 review |
|---|--------|------|--------------|-------------|----------|
| 1 | ... | ⏳ 待做 | — | — | ⏳ 待 review |

## 🕵️ 稽核結果（輕量稽核 subagent 填寫）
（核對各項產出物存在/結構/內容的結果，有缺列出）

## 📋 Feedback
（人 review 後填寫區）
```

#### 輸出 2: Session Context（寫入 wave-{id}.md 備查，不需要使用者複製）

Wave 規劃過程中 Claude 已經擁有完整脈絡（工作項、合約、決策、相關檔案），不需要輸出一份 session prompt 讓使用者複製貼上。改為：

1. 把關鍵脈絡摘要寫入 `wave-{id}.md` 的 Metadata 區（供中斷恢復用）
2. 多波時額外記錄並行規則到 Metadata：

```markdown
## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單]
- **並行波**: [其他波 ID + 狀態]
- **並行規則**: 只碰 wave-{id}.md，不動 [列出其他波涉及檔案]
```

#### 輸出 3: Goal Condition（Claude 自動設定）

遵循 goal condition 五原則：
- 可觀測、可驗證、有範圍、有約束、簡短
- 完成條件只包含自主項 + 人測項「已實作已標記」
- 不把人測通過當作完成條件

> **CRITICAL: goal condition 必須寫入 wave-{id}.md 的「🎯 Goal Condition」區塊。/goal 是使用者的 CLI 指令，Claude 無法自行執行——使用者有下 /goal 就同步，沒下也以 dashboard 區塊為準，收尾時逐條自核。**

**mode = dev 格式：**
```
Wave {id} 全部完成。完成標準：
(1) 所有 🤖 項合約指令全部跑過，輸出貼在 wave-{id}.md 對應合約結果欄
(2) 所有 🤖👁️ 項 E2E 合約全過，輸出貼在 wave-{id}.md，殘項已列出
(3) 所有 👁️ 項已實作+commit + 自檢截圖，wave-{id}.md 填入需人看什麼
(4) 每項覆蓋 happy path + edge case + 誤用場景（合約內列的全部跑過）
(5) 品質閘門通過：🔒 安全 skill 0 high/critical，🎨 UX 審計已執行並記錄到 wave-{id}.md
(6) requirements 對應項狀態已更新
(7) wave-{id}.md「📋 延後決策」區已填寫（有 grill 時列出所有未落地決策 + 優先順序；無 grill 時寫「未觸發 grill」）
(8) wave-{id}.md 狀態更新為「待人測」
(9) 🕵️ 收尾稽核 subagent 已跑且全 ✅，結果貼在 wave-{id}.md「🕵️ 稽核結果」區塊
(10) 全程遵守唯一停點制——除「停點規則」所列合法停點與例外（Align、範圍確認、Phase 2.5 訪談、破壞性操作確認、阻塞全部剩餘工作的需人裁定）外未曾停下等待輸入
約束：不動其他波正在處理的檔案（[列出其他波 ID: 涉及檔案]）。不碰其他 wave-*.md。
合約輸出必須是本輪實際跑出的，不可憑記憶填。
```

**mode = general 時 Goal Condition 格式：**

```
Wave {id} 全部完成。完成標準：
(1) 所有 🤖 項 checklist 全勾 ✅，產出物已建立
(2) 所有 👁️ 項已完成可自主部分，交人問題已具體列出
(3) requirements 對應項狀態已更新
(4) wave-{id}.md 狀態更新為「待人 review」
(5) 輕量稽核 subagent 已核對產出物存在/結構/內容，結果貼在 wave-{id}.md
約束：[同現有多波約束]
```

### Phase 6: 建立 Worktree → 開工

> **CRITICAL: 不要叫使用者 /clear 再貼 prompt。規劃完直接在本 session 繼續。**

> **CRITICAL: 所有 wave 一律在獨立 worktree 中執行，不在 main 工作。無例外。不管是單波還是多波、不管專案大小、不管工作項多少。這是硬性規則，不是建議。**

**Step 1: 建立 Worktree（開工前的強制動作）**

在輸出啟動宣告之前，先建立 worktree。**優先用原生工具**：環境有 `EnterWorktree` 工具時，直接 `EnterWorktree({ name: "wave-{id}" })`——harness 建立並追蹤 worktree，cwd 不會漂移。

無原生工具時 fallback 手動流程：

```bash
# 建立 wave branch + worktree
git branch wave/{id} 2>/dev/null || true
git worktree add .claude/worktrees/wave-{id} wave/{id}
cd .claude/worktrees/wave-{id}
```

> ⚠️ **守衛檢查（手動流程必做；原生工具建立後做一次確認即可）：在 worktree 內執行 `git rev-parse --show-toplevel`，確認輸出路徑包含 `worktrees/wave-{id}`。不在 worktree 內就停下來，不往下走。**

把 Phase 5 產出的 `.claude/dev/wave-{id}.md` 寫入 worktree（不是 main），同時建立 `.claude/dev/wave-{id}-ledger.md`（格式見「狀態外部化」節）。

**Gitignore 防護（建 worktree 後立即檢查）：** 專案 `.gitignore` 必須含 `.claude/worktrees/` 與 `.superpowers/` 兩條——缺哪條補哪條，隨本波首個 commit 進版控。防止 worktree（embedded git repo）與 SDD scratch 被 `git add -A` 吃進 git。註：`wave-{id}.md` 與 ledger **刻意不 ignore**——下波掃描延後決策、多波 registry、中斷接手都依賴它們在版控內。

**開工前基線綠燈（dev mode）：** 開工第一個動作 = 跑一次現有測試基線（輸出帶唯一標記字串確認是本輪跑出的），把結果記進 ledger 第一行（例：`基線：153 檔 / 1503 tests passed`）。之後任何紅燈都可歸因是本波引入還是既存問題。general mode 跳過此步。

**Task 系統鏡像（環境有 TaskCreate 工具時）：** 開工時把工作項逐項 `TaskCreate`（subject = 項名，description 含合約要點），執行中用 `TaskUpdate` 推進 in_progress / completed——使用者在 UI 上看得到的即時進度層。Dashboard + ledger 仍是唯一 source of truth（版控、跨 session 持久）；Task 系統只是鏡像，兩者不一致以 dashboard 為準。無此工具則跳過。

**Step 2: 宣告後直接開工（不停）**

執行方式已在 Phase 4 選定。輸出啟動宣告後**直接進入 Step 3，不等待回覆**：

```
✅ Wave {id} 規劃完成，直接開工。

🌿 Worktree: .claude/worktrees/wave-{id} (branch: wave/{id})
🚀 執行方式: [Phase 4 選定的方式]

📋 Goal Condition:
[貼出 goal condition 內容]
```

如果有其他並行的波，額外顯示：
```
⚠️ 並行波：[列出其他波 ID + 狀態]
```

**Step 3: 開工**

依 Phase 4 選定的方式：

**選 1 — Subagent-Driven：**
1. 確認 goal condition 已寫入 wave-{id}.md「🎯 Goal Condition」區塊（使用者若下 /goal 則同步；沒下也以此區塊為準）
2. 觸發 `/subagent-driven-development` 或 `/dispatching-parallel-agents`（依工作項獨立性判斷）
3. 每個 subagent 完成一項後回報，Claude review 合約結果
4. 全部完成後跑品質閘門 + 收尾流程

**選 2 — Inline Execution：**
1. 確認 goal condition 已寫入 wave-{id}.md「🎯 Goal Condition」區塊（使用者若下 /goal 則同步；沒下也以此區塊為準）
2. 按工作項排序逐項執行（遵循執行泵行為規範）
3. 每項 commit 後更新 wave-{id}.md
4. 全部完成後跑品質閘門 + 收尾流程

兩種方式都遵循同一套執行泵行為規範（見下方），差別只在並行度。**所有檔案操作都在 worktree 內進行。**

---

## 執行泵的行為規範

以下規則在 /goal 執行時 Claude 自動遵循（無論 Subagent-Driven 或 Inline Execution）：

> 以下規範依 mode 分區。「共用」段落 dev + general 都適用；「mode = dev」段落只在 dev 模式適用；「mode = general」段落只在 general 模式適用。

### Worktree 守衛（每次執行動作前）

> **CRITICAL: 寫任何檔案之前，確認 cwd 在 worktree 內。**

```bash
# 守衛檢查——不在 worktree 就停
[[ "$(git rev-parse --show-toplevel)" == *worktrees/wave-* ]] || { echo "ERROR: 不在 worktree 內，停止執行"; exit 1; }
```

如果發現自己在 main 工作目錄而非 worktree，**立即停下**，先執行 Phase 6 Step 1 建立 worktree 再繼續。不要在 main 寫任何程式碼。

### 開工前必讀（每個 wave session 啟動時）

- **`.claude/dev/playwright-guide.md`** — 專案的 Playwright 使用指南（不存在就跳過）。寫 E2E 前必讀，按裡面的 pattern 寫。

### 品質優先——不趕不跳

> **CRITICAL: 做好比做快重要。寧可這波只完成 3 項全部零 bug，也不要 6 項完成但 3 項要回頭修。**

- 一個功能做完 → 跑完驗證合約全部場景 → 合約全過才 commit
- 合約沒過 = 功能沒做完，不是「先 commit 再修」
- 不為了趕進度跳過誤用場景測試
- Session 時間不是限制，品質才是

### 長跑行為規範（dev + general 共用）

> **CRITICAL: 以下七條在整個執行期持續生效。長 session、compaction、跨 session 續跑都不豁免。**

**1. 自主運作——反提早收尾**
- 可逆且在 goal 範圍內的動作直接做，不問「要不要繼續？」「需要我做 X 嗎？」
- 只有破壞性操作（rm / reset / 大範圍覆寫）或真 scope 變更才停下確認
- 結束 turn 前執行「停點規則」的 turn 自檢

**2. 證據式進度**
- 任何「完成／通過／已 commit」宣稱前，逐條對照**本輪實際跑出的 tool 輸出**
- 輸出可疑、像重播、或與預期矛盾 → 用唯一標記字串 + 單一指令重新確認，只信標記對得上的那次
- 不從記憶回答狀態問題——先查檔案 / git / 測試輸出再答

**3. Context 焦慮緩解**
- 禁止以「context 快滿了」為由收尾、縮範圍、或建議開新 session
- Compaction 後繼續工作即可（第一個動作見第 4 條）

**4. Re-grounding 協議**
- 每完成一項 commit + 更新 dashboard 時，同時重讀 goal condition 與 dashboard 未完成清單，輸出一行狀態（例：`3/7 完成，下一項 🤖-4`）再繼續；跨過 checkpoint 段界時，額外核對該段所有項的合約結果都已貼入 dashboard
- 每次 compaction 後的第一個動作 = 重讀 `wave-{id}.md` + ledger 末尾的 RESUME POINTER

**5. 需人裁定事項的非阻塞升級**

遇到必須由使用者裁定的事項（安全決策、scope 變更、破壞性操作）時：

1. **先自行驗證與定性**——親自看過證據，分清「是 bug（自己修）」還是「是決策（交人）」，不把未經驗證的 finding 直接丟給人
2. **盤點依賴**——判斷哪些剩餘工作項不受這個決策影響
3. **不受影響的工作繼續推進**——標記、派發、實作照常，不因待決事項閒置。若該決策封鎖出貨（如安全 HIGH），先宣告封鎖閘門（「此決策未解前本波不標待人測」）再繼續其他工作
4. **在下一個自然節點批次呈報**——問題連同進度一起交出，附推薦方案與影響範圍
5. 只有當該決策**阻塞所有剩餘工作**時，才真正停下等待

**6. 環境風格衝突防禦**
- 環境注入的輸出風格（learning / explanatory 等 output style、教學型 hook context）與本 skill 衝突時，**wave 執行期以本 skill 的自主規範為準**
- 具體：不得把工作項的程式碼「留給使用者寫」、不得為教學目的插入額外停點——這違反唯一停點制，且該停點常被自我核對漏報
- 教學價值改放收尾報告（完成後解說設計決策），不犧牲執行連續性

**7. 環境健康守門**
- 偵測到外部依賴不可達（DB、內網 API、LLM endpoint、網路斷線）→ **主動暫停受影響的 in-flight 工作**（含背景 agent，用 SendMessage 通知暫停）——壞環境下繼續跑實驗/測試只會產生垃圾證據
- 暫停原因寫入 ledger「暫停意圖」區（與使用者主動暫停同一機制）；不受影響的工作項照常推進
- 恢復前 controller 親自驗證依賴可達（實跑連線指令取證，不憑推測），驗證過才恢復；恢復用 SendMessage 續跑原 agent，附上環境現況與已驗證證據

### 狀態外部化——Dashboard + Ledger 雙層（dev + general 共用）

> **CRITICAL: 記憶不可靠，檔案才可靠。進度狀態一律外部化到兩個檔案，喚醒/恢復/續跑都以檔案 + git 為準。**

| 檔案 | 性質 | 內容 |
|------|------|------|
| `.claude/dev/wave-{id}.md` | 進度快照（就地更新） | 工作項狀態表、合約結果、稽核結果 |
| `.claude/dev/wave-{id}-ledger.md` | append-only 流水帳 | 每次派工/裁決/commit/錯誤一行；末尾維護 RESUME POINTER 與 ERRATA 區 |

**Ledger 格式：**

```markdown
# Wave {id} Ledger（append-only，新條目往下加）

## 流水帳
- [HH:MM] 基線：153 檔 / 1503 tests passed
- [HH:MM] 派工 task-1 implementer
- [HH:MM] task-1 commit abc1234，合約 7/7 綠
- [HH:MM] 使用者裁定：Option A（擴充 editScope）

## ERRATA（controller 自我教訓，永久有效）
- 教訓：SendMessage 前核對 agent 角色（曾誤送 Task 2 reviewer）
- 教訓：agent-X 的 Monitor 兩次未喚醒——其等待改前景執行，controller 代看門

## 暫停意圖
（使用者下節流/暫停指令時寫入；「可以繼續」時清除。有內容時不派新工作）

## RESUME POINTER（隨進度更新，下個 session 照抄接手）
1. cd .claude/worktrees/wave-{id}
2. git log --oneline -10 + git status 核實真實狀態
3. 讀 wave-{id}.md 比對，不一致以 git 修正文件
4. 下一步：[具體指出下一個未完成項與動作]
```

**Ledger 使用規則：**
- **每次派工、裁決、commit、錯誤後立即 append 一行**——不等收尾才補
- **ERRATA**：controller 犯錯（誤送訊息、漏跑合約、錯判狀態）→ 記一行「教訓：...」。之後每個心跳 prompt（見 Subagent-Driven 長跑協議）必須帶上全部 ERRATA 條目——一次性錯誤變永久約束
- **暫停意圖外部化**：使用者下節流/暫停指令（「usage 快爆了先停」）→ 讓 in-flight 工作跑完、不派新工作，並把暫停意圖寫進 ledger，防止喚醒後誤判為斷線而繼續派工。使用者說「可以繼續」才清除

**中斷恢復協議（git 為準）：**

任何新 session 續跑步驟：
1. cd 進 worktree
2. **先核實 git 真實狀態**：`git log` + `git status` 找已 commit 項與未 commit 半成品——以 git 為準，不以文件記載或記憶為準
3. 讀 `wave-{id}.md` + ledger RESUME POINTER，比對 git 狀態，不一致以 git 修正文件
4. 從第一個真正未完成項續跑

長工作不受單一 session 存活限制。

### Subagent-Driven 長跑協議（選 Subagent-Driven 執行方式時適用）

主 session 作為 controller，額外遵循：

**Brief-driven 派工：**
- 派 implementer subagent 前，先寫 `task-N-brief.md`（三件套 brief/report/design 一律放 worktree 的 `.superpowers/sdd/` 下——該目錄 gitignored，屬一次性 scratch 不進版控），內容：
  1. 需求描述 + 裁定結論
  2. 程式現況（`file:line` 引用，註明「行號可能漂移，以語意定位」）
  3. 驗證合約（從 dashboard 複製該項完整合約）
  4. 硬約束（不可碰的檔案/目錄，如其他波涉及範圍）
- Subagent 開場指令 =「先讀你的 brief，它就是你的 requirements」——subagent 不依賴 controller 的對話 context
- **模型分層**：派工時依項目性質選 model tier——機械、範圍明確的實作項 → `model: "sonnet"`；瑣碎查證/整理 → `haiku`；跨系統、架構性、難 debug 的項 → 省略（繼承 session 模型）。拿不準就省略。Reviewer 與收尾稽核的 tier 不得低於該項 implementer
- 大項（schema 變更、跨系統）另寫 `task-N-design.md`，設計過使用者 review 才動手
- Implementer 完成寫 `task-N-report.md`，controller 與 reviewer 都讀

**管線不斷料（pipeline priming）：**
趁當前 task 在跑，controller 預寫下一批 brief、做前置預檢（DB 起了沒、測試環境可用嗎）——不閒等。

**心跳 fallback（ScheduleWakeup）：**
- 每次派背景 subagent 後，排一個 ScheduleWakeup fallback（環境無此工具則跳過此保險）——背景完成通知失靈時的斷線保險。delay 分兩層：
  - **長跑 implementer**（實作/實驗，10 分鐘以上）→ 1200s+，非短輪詢
  - **數分鐘內將完成的一批 agent**（並行比對/掃描組）→ ≤270s 短窗輪詢，保 prompt cache（5 分鐘 TTL）；該批收完換回長層。**避開 300s 附近**——cache 已失效又沒攤平成本
- Wakeup prompt **完整重述狀態**，不依賴記憶即可續泵。模板：

```
Wave {id} SDD 執行泵 fallback。已完成：[task 清單+commit]。進行中：[task+agent]。
後續序列：[N→N+1→...]。封鎖閘門：[如「安全 HIGH 未解不得標待人測」，無則寫無]。
ERRATA：[ledger ERRATA 全部條目]。
喚醒後：先核 git 真實狀態與 ledger，暫停意圖區有內容則只記錄不派工。
```

- **Stale wakeup 核實**：喚醒內容與現實可能脫節（說 X 實作中但其實已 commit）→ 先核 git 真實狀態再行動，不盲從喚醒內容、也不盲從記憶。喚醒內容與使用者最後指示衝突時，問人不擅斷
- 與 `/goal` 分工：goal 判定「做完了沒」，心跳保證「沒做完就繼續動」

**中斷恢復優先 SendMessage 續跑：**
曾有實際產出的 agent 因額度上限、網路中斷、環境守門或使用者暫停而停止 → **不重派**，用 SendMessage 對原 agent 續跑（context 全保留）。訊息結構：

```
Controller 通知：[中斷原因 + 現況，如「額度已重置」「網路已恢復（PG 連通、API 回 200，皆已驗證）」]。
先 `git status` + `git log --oneline -3` 核實你已落地與未落地的工作，再從斷點繼續。
[中斷期間有作廢產出時明確指出：「X 被中途 kill，視為無效、重跑」]
```

SendMessage 失敗（agent 已死）或該 agent 屬空跑 → 才走重派。

**Controller 代看門：**
Subagent 依賴背景等待（Monitor、背景 process 輪詢）卻沒被喚醒 → controller 接管看門（自己盯 process/log），用 SendMessage 代通知「X 已結束，結果在 Y」。同一 agent 第二次失靈 → 後續指令禁用該等待模式（改前景執行），並記入 ERRATA。

**空跑偵測：**
Subagent 回傳異常（0 tool uses、秒級返回、無 commit）→ 視為沒實際執行。核 git 確認無半成品後重派，不把空跑當完成。

**Reviewer 不信報告：**
每 task 的 reviewer 必須**親自重跑**測試/typecheck/lint，不採信 implementer 的 report 文字。權限/安全敏感項升級 security rigor。共用 branch 交錯時，review 範圍用明確 commit SHA 指定，不用 range。

### 以下僅 mode = dev（現有規範不動）

### 驗證合約執行規則

> **CRITICAL: 每個工作項 commit 前，必須按合約跑完所有指令，把實際輸出貼到 wave-{id}.md。**

每個功能完成時：
1. **跑合約指令** — 逐條執行合約裡列的指令
2. **貼實際輸出** — 把終端輸出貼到 wave-{id}.md 的「合約結果」欄（不是寫「passed」，是貼實際輸出）
3. **比對預期** — 輸出 ≠ 預期 → 修到符合，不是改預期
4. **覆蓋場景檢查（自審）** — 合約列的 happy path / edge case / 誤用場景，逐條比對測試裡的對應 test case 與實際輸出。**缺一場景 = 該項未完成**，不可遺漏、不可「大致有覆蓋」
5. **全過才 commit**

### Wave Dashboard 即時更新

每完成一個功能項的 commit：
1. 更新 `.claude/dev/wave-{id}.md` 對應行的狀態（⏳→✅ 或 ⏳→❌）
2. 填入 commit hash + 合約輸出
3. 如果是 👁️ 人測項，填入**操作步驟級的驗收清單**
4. **多波時：只碰自己的 `wave-{id}.md`，不碰其他 `wave-*.md`**

### 驗收清單格式（👁️ 人測項）

```markdown
### 👁️-1: [功能名]

**前置**：登入 kymo_admin，進入 [路由]

1. 打開 [具體頁面 URL]
2. 點擊 [具體按鈕/元素]
3. 填入 [具體值]
4. 按 [具體按鈕]
5. ✅ 預期：[具體可觀察的結果]
6. ❌ 預期不出現：[不應該發生的事]

**Edge cases：**
- 空值提交 → 預期：[錯誤提示文字]
- 無權限 → 預期：[行為]

**Claude 已自驗（Playwright）：**
- ✅ 按鈕可點擊、toast 出現
- ✅ 資料存入 DB（API 回傳 200）
- 👁️ 無法自驗：間距/對齊視覺效果、文字語氣是否恰當
```

### 品質閘門（所有工作項完成後）

> **CRITICAL: 所有工作項 commit 完畢、合約全過後，必須跑品質閘門才能標「待人測」。**

#### 安全閘門（合約內已逐項執行）

安全 skill 已寫進各工作項合約（🔒 標記步驟），逐項 commit 時已跑完。
此處只做最終確認：wave-{id}.md 所有 🔒 步驟是否都有輸出且 0 high/critical。
如有遺漏 → 補跑，不可跳過。

#### UX 閘門（批次執行）

依 Phase 4 使用者確認的 UX 審計清單，逐一呼叫：
1. 呼叫對應 skill（`/ui-test`、`/wcag-accessibility-audit`、`/nielsen-heuristics-audit`、`/ux-audit-rethink`）
2. 收集 findings，寫入 wave-{id}.md「🎨 UX 審計結果」區塊
3. 每個 finding 標 severity + 位置 + 建議修法
4. **Advisory 不阻擋**——全部記錄，使用者下波決定是否處理
5. 例外：`/ui-test` 跑出的**功能 bug**（按鈕點不動、表單送不出、頁面 crash）→ 視同合約失敗，必須修

#### 閘門結果影響 wave 狀態

- 安全 0 high/critical + UX 審計已跑完記錄 → 品質閘門通過，進入收尾流程（標「待人測」前仍須通過收尾稽核 subagent）
- 安全有 high/critical 殘留 → **不可標「待人測」**，回去修
- UX findings 不影響狀態流轉，但必須記錄（不可跳過不跑）

### E2E 驗證責任制

> **CRITICAL: 人測項不是「實作完丟給人」。Claude 必須先 E2E 跑到沒問題，只交出 E2E 結構性無法覆蓋的殘項。**

每個 🤖👁️ 項實作完：
1. **寫 E2E 測試**覆蓋完整操作流程（導航→操作→結果斷言）
2. **跑 E2E 直到綠燈** — 測試失敗代表功能有 bug，修到過為止
3. **列出殘項** — E2E 跑過但無法判斷的點（視覺感受、語氣、操作順暢度）
4. 在 wave-{id}.md 填入：E2E 覆蓋了什麼 ✅ / 殘項交人看什麼 👁️
5. **殘項為空 = 這項升級為 🤖 自主項**，不需要人測

每個 👁️ 純人眼項實作完：
1. 用 Playwright 截圖自檢，確認元素存在、佈局不破版
2. 在 wave-{id}.md 附截圖路徑 + 明確寫出「需要人判斷什麼」

### Playwright 使用指南（自動累積）

> **CRITICAL: E2E 不是每次從零 try and error。開工前讀指南，解決問題後寫回指南。**

**檔案位置：** `.claude/dev/playwright-guide.md`（專案級，每個專案各自維護一份）

**開工前讀：**
- 寫任何 Playwright 測試之前，先讀 `.claude/dev/playwright-guide.md`（不存在就跳過）
- 同時讀全局坑 `~/projects/CLAUDE.md` 裡的 E2E-PITFALLS 段落
- 按指南裡的 pattern 寫測試，不要自己重新摸索

**執行中寫：**
每次遇到以下情況，**解決後立即**更新 `.claude/dev/playwright-guide.md`：
- Playwright 測試因非預期原因失敗 → 記下根因 + 解法
- 找到該專案有效的 selector 策略 → 記下 pattern（例：這個專案用 `data-testid` / 用 role / 用 text）
- 找到該專案的 auth/session 處理方式 → 記下 storageState 路徑和設定
- 找到避免 flaky 的有效手段 → 記下（例：等 network idle、waitForSelector 的特定用法）
- 找到該專案 CI vs local 的差異 → 記下

**指南格式：**

```markdown
# Playwright Guide — [專案名]

## Auth & Session
- storageState 路徑：...
- 登入流程：...

## Selector 策略
- 優先用：...
- 避免用：...

## 已知坑
### [日期] [問題描述]
- 症狀：...
- 根因：...
- 解法：...

## 有效 Pattern
### [Pattern 名]
- 用途：...
- 範例：...
```

**原則：**
- 每次 append 新段落，不刪舊內容（除非過時）
- 不存在就建，建了就持續維護
- 不問使用者「要不要記」——靜默維護

### 自主決策規則

在 /goal 執行中遇到需要判斷的點：
- UI 細節拿不準 → 做保守版 + 在 wave-{id}.md 標記 `[需確認: 我選了 A 方案因為...]`
- 需要新 dependency → 記到 wave-{id}.md feedback 區，這波不加
- Test flaky → 記到 wave-{id}.md，不花超過 10 分鐘 debug
- Requirements 有 ❓ → 用推薦方案 + 標記 `[自主決策]`（同既有 CLAUDE.md 規則）

### 收尾流程（所有項完成 + 閘門通過後）

> **CRITICAL: 完成宣告不可只看 goal condition。必須同時揭露延後決策債務。**

1. **收尾稽核 subagent（標「待人測」之前的強制步驟）**

   派一個 fresh-context 稽核 subagent（與 implementer/reviewer 都不同的新 agent），帶以下稽核合約：

   > 你是 Wave {id} 的收尾稽核員。在 worktree [路徑] 內執行，唯讀 + 跑測試，不改程式碼：
   > 1. **抓虛報**：重跑 `wave-{id}.md` 上每個 🤖 / 🤖👁️ 項的合約指令，比對實際輸出 vs dashboard 宣稱。輸出不符 = ❌
   > 2. **抓偷懶**：回掃 `docs/requirements/` 找有 🔴🟡❓ 但無對應工作項的漏項
   > 3. **抓縮水**：抽查每項合約的三角度場景（happy/edge/誤用）是否都有對應 test case
   > 4. **抓外部化偷懶**：核對 `wave-{id}-ledger.md`——流水帳涵蓋每個 commit（條目數 ≥ commit 數）、基線綠燈記錄存在、RESUME POINTER 與 git log 一致非過時。不新鮮 = ❌
   > 5. 回報逐項 ✅/❌ + 漏項清單 + 實際指令輸出

   稽核結果寫入 `wave-{id}.md`「🕵️ 稽核結果」區塊。**有 ❌ 或漏項 → 打回修復，修完重派稽核**，不得標「待人測」。
2. 逐條核對 wave-{id}.md「🎯 Goal Condition」區塊並打勾（(1)-(10) 全過才往下），把 `wave-{id}.md` 狀態標 ✅「待人測」
   - **核對 (10) 不可單勾**：必須先列出本波實際發生的所有停點（時點 + 原因），逐一對照「停點規則」合法清單。有任何一次停點不在合法清單 → (10) 不可勾，如實記錄違規
3. **延後決策揭露**（Phase 2.5 有觸發 grill/brainstorming 時）：
   - 讀取 wave-{id}.md 的「📋 延後決策」區塊
   - 在完成報告中**醒目列出**所有延後項，格式：
     ```
     ## ⚠️ 本波延後決策（grill/spec 共識未落地）
     
     | # | 決策 | 優先順序 | 延後原因 |
     |---|------|---------|---------|
     | 1 | 匯入他案嫌疑人需先核准 | 🔴 安全 | scope cut |
     | 2 | 合併四步 wizard | 🟡 完整性 | 只做了入口 |
     
     建議下波優先處理 🔴 項。
     ```
   - 延後項為零時明確寫：「✅ 本波涵蓋所有 grill/spec 決策，無延後項。」
   - **這段在 goal condition 判定之外**——即使 goal 全綠，延後項仍需揭露
4. 提示使用者「本波完成，可以 merge 回 main」+ 來人測

### 以下僅 mode = general

#### Checklist 執行規則

每個工作項完成時：
1. **逐項勾 checklist** — 產出物存在、結構完整、內容涵蓋
2. **更新 wave-{id}.md** — 勾完的打 ✅，未達的標 ❌ 附原因
3. **👁️ 項列出交人判斷的具體問題**（不是模糊的「請 review」，要寫具體問什麼）
4. **全勾才算完成**

#### 完成標準

不設固定品質閘門，但標「待人 review」前派一個輕量稽核 subagent：核對每項 checklist 的產出物**實際存在、結構完整、內容涵蓋要點**（不重跑指令），結果寫入 wave-{id}.md。有缺 → 打回補齊。Checklist 全勾 + 稽核通過 + 👁️ 項已列出具體問題 → 可標「待人 review」。

---

## 多波並行

> 支援多波同時在同專案內開發——各自獨立規劃、獨立 dashboard、獨立 session，互不干擾。

### 隔離策略

Worktree 建立的具體步驟見 **Phase 6 Step 1**。這裡說明設計理由和並行安全保證。

**為什麼不在 main 工作：** 使用者經常在多個 tmux session 同時對同專案開 wave。如果有「單波在 main」的路徑，兩個 session 同時啟動就會 race condition——都以為自己是第一個。一律 worktree 從設計上消除這個問題，不需要偵測、不需要旗標。單波也一樣——規則統一才不會有漏洞。

**並行安全保證：**
1. 所有波在獨立 worktree 工作，互不影響 working tree
2. 每個波只讀寫自己的 `wave-{id}.md`
3. `playwright-guide.md` 併發寫入處理：每個 worktree 維護自己的副本，merge 回 main 時自動合併（append-only 格式天然可合併）
4. `prisma/schema.prisma` 等共用檔案的衝突在 merge 階段處理（見合併協助段落）

### `/wave status` — 全局概覽

任何時候可呼叫，動態掃描所有波次狀態：

**資料來源：** `git worktree list` + 各 worktree / main 的 `.claude/dev/wave-*.md`。

```markdown
## 🌊 Wave 全局狀態

| ID | 簡述 | 狀態 | 進度 | Worktree | 建立 |
|---|------|------|------|---------|------|
| orders-api | 訂單 API CRUD | 🟡 執行中 | 3/5 ✅ | .claude/worktrees/wave-orders-api | 06-27 |
| report-ui | 報表頁面 | ✅ 待人測 | 4/4 ✅ | .claude/worktrees/wave-report-ui | 06-27 |

### ⚠️ 檔案交集
- prisma/schema.prisma → orders-api, report-ui

### 建議下一步
- report-ui 已完成，可 merge 回 main + 人測
- orders-api 還在跑，3/5 完成
```

找不到 dashboard 的波標「資訊不可用」。🗑️ 狀態的波不顯示。

### `/wave drop {id}` — 放棄一波

1. 把 `wave-{id}.md` 狀態標 🗑️
2. `/wave status` 不再顯示該波
3. 不自動刪 worktree 或檔案——使用者想清理就手動清

### 合併協助

每波在 worktree 完成後，merge 回 main：

1. `git merge wave-{id}-branch` 到 main
2. 無衝突 → 自動完成，跑測試確認沒 break
3. 加法衝突（兩波各加不同欄位到同檔案）→ 自動合併
4. 改法矛盾（同一行改成不同東西）→ 列出衝突 + 兩波原始意圖，使用者裁定
5. 合併後跑受影響檔案的測試確認沒 break
6. 清理 worktree：環境有 `ExitWorktree` 工具用 `ExitWorktree({ action: "remove" })`；`discard_changes` 屬破壞性選項，僅在親自確認 worktree 無未合併變更後使用

不自動 force merge——有矛盾必停，呈現衝突 + 推薦方案，使用者確認才執行。
