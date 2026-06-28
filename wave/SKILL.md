---
name: wave
description: 規劃並啟動一波工作。自動偵測開發/通用模式，讀 requirements → 偵測是否需要 align 新素材 → 分類自主/人判斷項 → 產出 living dashboard + session prompt + goal condition。支援多波並行（各波獨立 worktree + dashboard）。觸發詞：/wave、開新波、新一波、plan wave、啟動開發、啟動工作。子指令：/wave status（全局概覽）、/wave drop {id}（放棄一波）。旗標：--dev（強制開發模式）、--general（強制通用模式）。
argument-hint: "（選填）逐字稿路徑、會議檔案、或簡述這波方向"
---

# Wave — 開發波次規劃與啟動

一次呼叫完成：對齊新資訊 → 規劃工作項 → 產出可直接貼入的 session prompt + goal condition。

## Core Principles

- **Wave 是唯一入口。** 使用者不需要記「要不要先 align」、「要不要看 requirements」——Wave 自動判斷並串接。
- **一波帶走。** 所有掃出的未完成項都排進這一波，不建議延後。遇到真正的 blocker 在該項旁邊標註原因讓使用者決定，但不主動歸類為「建議延後」。
- **做好比做快重要。** 不趕進度、不跳過測試、不為了早點結束而降低覆蓋。一個功能做兩小時但零 bug，勝過六個功能做完三個要回頭修。Session 跑再久都沒關係，品質是唯一標準。

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

- **單波**（無其他 🟢/🟡 波）：跳過命名，自動用日期 ID（`wave-0627`）
- **多波**（已有其他波在跑）：Claude 從工作項方向自動生成 ID（如 `report-ui`），不問使用者。使用者不滿意才改

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

### Phase 2: 掃描工作項

自動執行（不問使用者）：

```bash
# 讀取所有 requirements 檔案
find docs/requirements/ -name "*.md" -exec grep -l "🔴\|🟡\|❓" {} \;

# 讀取最近 git log 了解已完成的工作
git log --oneline -20

# 讀取 .claude/dev/wave-*.md（如果存在，看上波殘留）
ls .claude/dev/wave-*.md 2>/dev/null
```

從 requirements 中收集所有未完成項（🔴 未實作 / 🟡 部分實作 / ❓ 未決）。

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
> **預估規模**：約 N 個 commit，預計 /goal 執行 M 小時
> 
> 要調整嗎？（移除某些項 / 改合約覆蓋範圍 / 改優先序）

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

使用者確認工作範圍 + UX 審計清單後進入 Phase 5。

**mode = general 時：** 不顯示 UX 審計推薦、不顯示檔案交集預警（非開發不需要）。直接確認工作範圍後進入 Phase 5。

### Phase 5: 產出三份輸出

#### 輸出 1: `.claude/dev/wave-{id}.md`（Living Dashboard）

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單，用於交集分析]

## 狀態：🟢 規劃完成，待啟動

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

## 📋 Feedback（人測後填寫區）
（使用者只需測上面「殘項」和「人看什麼」欄位列出的項目，其餘 Claude 已按合約驗過）
```

**mode = general 時 Dashboard 格式：**

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **Mode**: general

## 狀態：🟢 規劃完成，待啟動

## 🤖 自主項
| # | 工作項 | 狀態 | Checklist | 產出物 |
|---|--------|------|-----------|--------|
| 1 | ... | ⏳ 待做 | 0/4 ✅ | — |

## 👁️ 需人判斷
| # | 工作項 | 狀態 | Claude 已完成 | 交人判斷什麼 | 人 review |
|---|--------|------|--------------|-------------|----------|
| 1 | ... | ⏳ 待做 | — | — | ⏳ 待 review |

## 📋 Feedback
（人 review 後填寫區）
```

#### 輸出 2: Session Prompt（給使用者複製貼入新 session）

包含：
- 這波的完整脈絡和目標
- 工作項清單（含優先序）
- 自主決策規則
- 執行時的行為規範（更新 wave-{id}.md、requirements 回寫、Playwright 自驗）
- 相關檔案路徑

**多波時額外加入：**

```markdown
## 本波資訊
- **Wave ID**: {id}
- **Dashboard**: `.claude/dev/wave-{id}.md`
- **並行波**: [其他波 ID + 狀態]
- **Worktree**: [worktree 路徑]

## 並行規則
- 只讀寫 `wave-{id}.md`，不碰其他 wave-*.md
- 不動其他波正在處理的檔案：[列出其他波的涉及檔案]
- 其他檔案自由修改
```

單波時不加這些段落——完全向下相容。

#### 輸出 3: Goal Condition（給使用者貼在 /goal 後面）

遵循 goal condition 五原則：
- 可觀測、可驗證、有範圍、有約束、簡短
- 完成條件只包含自主項 + 人測項「已實作已標記」
- 不把人測通過當作完成條件

格式範例：
```
Wave {id} 全部完成。完成標準：
(1) 所有 🤖 項合約指令全部跑過，輸出貼在 wave-{id}.md 對應合約結果欄
(2) 所有 🤖👁️ 項 E2E 合約全過，輸出貼在 wave-{id}.md，殘項已列出
(3) 所有 👁️ 項已實作+commit + 自檢截圖，wave-{id}.md 填入需人看什麼
(4) 每項覆蓋 happy path + edge case + 誤用場景（合約內列的全部跑過）
(5) 品質閘門通過：🔒 安全 skill 0 high/critical，🎨 UX 審計已執行並記錄到 wave-{id}.md
(6) requirements 對應項狀態已更新
(7) wave-{id}.md 狀態更新為「待人測」
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
約束：[同現有多波約束]
```

### Phase 6: 指示使用者下一步

**單波時：**
```
✅ Wave 規劃完成！

你的下一步：
1. /clear
2. 貼入上面的 Session Prompt
3. /goal [貼入上面的 Goal Condition]
4. 離開做別的事，2-3 小時後回來看 .claude/dev/wave-{id}.md

（Session Prompt 和 Goal Condition 已輸出在上方，直接複製即可）
```

**多波時：**
```
✅ Wave {id} 規劃完成！

你的下一步：
1. 開新終端，用 /using-git-worktrees 建立 worktree
2. 在 worktree 裡 /clear
3. 貼入上面的 Session Prompt
4. /goal [貼入上面的 Goal Condition]
5. 離開做別的事，完成後 Claude 會提示你 merge 回 main

目前並行的波：[列出其他波 ID + 狀態]
隨時可用 /wave status 查看全局進度。
```

---

## 執行泵的行為規範（寫入 Session Prompt）

以下規則會被嵌入每個 wave 的 session prompt 中，確保 /goal 執行時 Claude 自動遵循：

> 以下規範依 mode 分區。「共用」段落 dev + general 都嵌入 session prompt；「mode = dev」段落只在 dev 模式嵌入。

### 品質優先——不趕不跳

> **CRITICAL: 做好比做快重要。寧可這波只完成 3 項全部零 bug，也不要 6 項完成但 3 項要回頭修。**

- 一個功能做完 → 跑完驗證合約全部場景 → 合約全過才 commit
- 合約沒過 = 功能沒做完，不是「先 commit 再修」
- 不為了趕進度跳過誤用場景測試
- Session 時間不是限制，品質才是

### 以下僅 mode = dev（現有規範不動）

### 驗證合約執行規則

> **CRITICAL: 每個工作項 commit 前，必須按合約跑完所有指令，把實際輸出貼到 wave-{id}.md。**

每個功能完成時：
1. **跑合約指令** — 逐條執行合約裡列的指令
2. **貼實際輸出** — 把終端輸出貼到 wave-{id}.md 的「合約結果」欄（不是寫「passed」，是貼實際輸出）
3. **比對預期** — 輸出 ≠ 預期 → 修到符合，不是改預期
4. **覆蓋場景檢查** — 合約列的 happy path / edge case / 誤用場景，測試裡必須都有對應的 test case，不可遺漏
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

- 安全 0 high/critical + UX 審計已跑完記錄 → 可標「待人測」
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

### 自主決策規則

在 /goal 執行中遇到需要判斷的點：
- UI 細節拿不準 → 做保守版 + 在 wave-{id}.md 標記 `[需確認: 我選了 A 方案因為...]`
- 需要新 dependency → 記到 wave-{id}.md feedback 區，這波不加
- Test flaky → 記到 wave-{id}.md，不花超過 10 分鐘 debug
- Requirements 有 ❓ → 用推薦方案 + 標記 `[自主決策]`（同既有 CLAUDE.md 規則）

### 收尾流程（所有項完成 + 閘門通過後）

1. 把 `wave-{id}.md` 狀態標 ✅「待人測」
2. **單波時**：提示使用者來人測
3. **多波時**：提示使用者「本波完成，可以 merge 回 main 或先等其他波」

### 以下僅 mode = general

#### Checklist 執行規則

每個工作項完成時：
1. **逐項勾 checklist** — 產出物存在、結構完整、內容涵蓋
2. **更新 wave-{id}.md** — 勾完的打 ✅，未達的標 ❌ 附原因
3. **👁️ 項列出交人判斷的具體問題**（不是模糊的「請 review」，要寫具體問什麼）
4. **全勾才算完成**

#### 完成標準

不設固定品質閘門。Checklist 全勾 + 👁️ 項已列出具體問題 → 可標「待人 review」。

---

## 多波並行

> 支援多波同時在同專案內開發——各自獨立規劃、獨立 dashboard、獨立 session，互不干擾。

### 隔離策略

- **單波**（無其他 🟢/🟡 波）→ 直接在 main 工作（原本行為），零摩擦
- **多波**（有其他波在跑）→ 一律開 worktree，各波獨立 branch

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

不自動 force merge——有矛盾必停，呈現衝突 + 推薦方案，使用者確認才執行。
