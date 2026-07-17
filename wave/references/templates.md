# Wave 深度材料 — 模板

本檔由 wave/SKILL.md 於對應動作點載入——不要直接執行本檔。

## Dashboard 模板（dev 模式）

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單，用於交集分析]
- **Checkpoint 分段**: C1: [項] / C2: [項] / ...（每 3 項一段，re-grounding 錨點）
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-{id}-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑

## 狀態：🟢 規劃完成，待啟動

## 🎯 Goal Condition
（貼 Phase 5 輸出 3 全文 (1)-(8)；收尾時逐條打勾）

## 🤖 工作項
| # | 功能 | 狀態 | 合約指令 | 合約結果 | commit |
|---|------|------|---------|---------|--------|
| 1 | ... | ⏳ 待做 | `pnpm vitest run ...` | （貼輸出） | — |

### 🤖-1 驗證合約
（從 Phase 3 複製完整合約，含 happy/edge/誤用場景）

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
```

## Dashboard 模板（general 模式）

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **Mode**: general
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-{id}-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑

## 狀態：🟢 規劃完成，待啟動

## 🎯 Goal Condition
（貼 Phase 5 輸出 3 全文 (1)-(4)；收尾時逐條打勾）

## 🤖 工作項
| # | 工作項 | 狀態 | Checklist | 產出物 |
|---|--------|------|-----------|--------|
| 1 | ... | ⏳ 待做 | 0/3 ✅ | — |

## 🕵️ 稽核結果（輕量稽核 subagent 填寫）
（核對各項產出物存在/結構/內容的結果，有缺列出）
```

## Phase 4 工作範圍輸出範本

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
> ---
> **預估規模**：約 N 個 commit（規模以完整覆蓋為準，不以 session 長度為準）
> **Checkpoint 分段**：每 3 項一段（C1: 🤖-1~3 / C2: 🤖-4~6 / ...），執行期 re-grounding 以段為錨點
>
> **執行方式**（本次確認一併選定，Phase 6 不再另問）：
> 1. **Subagent-Driven**（推薦）— 每個工作項派獨立 subagent，中間 checkpoint review
> 2. **Inline Execution** — 在此 session 直接逐項執行，每項完成後 checkpoint review
> 
> 要調整嗎？（移除某些項 / 改合約覆蓋範圍 / 改優先序 / 換執行方式）

## UX 審計推薦範本

> ## 🎨 UX 品質閘門（完成所有項後批次執行）
> 
> 根據這波工作項性質，推薦以下審計：
> - ✅ `/ui-test` — 本波含新頁面/整頁改版，跑探索性對抗測試（用大案規模資料）
> - ✅ `/wcag-accessibility-audit` — 新增表單元件，檢查無障礙
> - ⬚ `/nielsen-heuristics-audit` — 無新頁面，不推薦
> - ⬚ `/ux-audit-rethink` — 非大改版，不推薦
> 
> 要調整嗎？（打勾/取消任一項）

## 延後決策揭露範例

```
## ⚠️ 本波延後決策（grill/spec 共識未落地）

| # | 決策 | 優先順序 | 延後原因 |
|---|------|---------|---------|
| 1 | 匯入他案嫌疑人需先核准 | 🔴 安全 | scope cut |
| 2 | 合併四步 wizard | 🟡 完整性 | 只做了入口 |

建議下波優先處理 🔴 項。
```

## Ledger 格式

```markdown
# Wave {id} Ledger（append-only，新條目往下加）

## 流水帳
- [HH:MM] 基線：153 檔 / 1503 tests passed
- [HH:MM] 派工 task-1 implementer（sonnet）
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

## 心跳 Wakeup Prompt 模板

```
Wave {id} SDD 執行泵 fallback。已完成：[task 清單+commit]。進行中：[task+agent]。
後續序列：[N→N+1→...]。封鎖閘門：[如「安全 HIGH 未解不得標完成」，無則寫無]。
ERRATA：[ledger ERRATA 全部條目]。
喚醒後：先核 git 真實狀態與 ledger，暫停意圖區有內容則只記錄不派工。
```

## `/wave status` 輸出範例

```markdown
## 🌊 Wave 全局狀態

| ID | 簡述 | 狀態 | 進度 | Worktree | 建立 |
|---|------|------|------|---------|------|
| orders-api | 訂單 API CRUD | 🟡 執行中 | 3/5 ✅ | .claude/worktrees/wave-orders-api | 06-27 |
| report-ui | 報表頁面 | ✅ 完成 | 4/4 ✅ | .claude/worktrees/wave-report-ui | 06-27 |

### ⚠️ 檔案交集
- prisma/schema.prisma → orders-api, report-ui

### 建議下一步
- report-ui 已完成，可 merge 回 main
- orders-api 還在跑，3/5 完成
```
