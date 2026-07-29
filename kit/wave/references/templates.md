# Wave 深度材料 — 模板

本檔由 wave/SKILL.md 於對應動作點載入——不要直接執行本檔。

## Phase 4 工作範圍輸出範本

> **選項集合封閉。** 執行方式自動採用不問（Subagent-Driven 既定；Inline 須附一句理由，見 SKILL.md
> Phase 4「執行方式自動採用」）；UX 審計只有清單勾選。**不得增列其他選項**，
> 尤其禁止任何形式的減量方案（「先只做 N 項」「精簡版」「範圍縮小為…」「其餘留給下一波」）。
> 工作清單本體以文字**全列**，不分「完整版／精簡版」。縮減範圍的唯一合法路徑＝使用者自己提出。

```markdown
## 📋 Wave {id} 工作範圍

**來源掃描結果**：{四來源各掃到幾項}，收斂後 {N} 項全部排入本波。

### 工作項

**🤖-1 {功能名}**（預估 {規模}）
- 動到：{檔案/目錄}
- 驗證合約：
  - happy: `{指令}`
  - edge: `{指令}`
  - 誤用場景: `{指令}`

**🤖-2 ...**（同上格式逐項列完，不省略、不折疊）

### Checkpoint 分段
C1: 🤖-1〜3 / C2: 🤖-4〜6 / ...（每 3 項一段）

### ⚠️ 交集預警（有並行波時才出現）
| 檔案 | 本波 | 他波 | merge-tree 分級 |
|---|---|---|---|
| {path} | 🤖-2 | wave-{id} | 可自動合併／需裁定 |

### ❓ 需裁定項
（每項一個獨立 AskUserQuestion 問題；無則寫「無」）

### 🚀 執行方式（自動採用，不問）
Subagent-Driven（既定）／ Inline＋一句具體理由（記入 dashboard Metadata）
```

**AskUserQuestion 結構（環境有此工具時）：**

| 問題 | 型別 | 選項 |
|---|---|---|
| UX 審計清單 | multiSelect | ui-test ／ wcag ／ nielsen ／ ux-audit-rethink |
| 每個 ❓ 項 | 單選 | 各方案（推薦標 Recommended）／ 延後 |

「延後」選項僅出現在 ❓ 項問題內，且必須由使用者親自選中才生效。

## Dashboard 模板

```markdown
# Wave {id} — [日期] [簡述]

## Metadata
- **涉及檔案/目錄**: [目錄 glob 清單，用於交集分析]
- **Checkpoint 分段**: C1: [項] / C2: [項] / ...（每 3 項一段，re-grounding 錨點）
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-{id}-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑

## 狀態：🟢 規劃完成，待啟動

## 🎯 Goal Condition
（貼 Phase 5 輸出 3 全文 (1)-(7)；收尾時逐條打勾）

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

## 📋 漏項掃描
（收尾流程步驟 3 回掃 `docs/requirements/` 的結果：有 🔴🟡❓ 但無對應工作項者逐條列出，無則寫「無漏項」）

## 📋 未涵蓋決策
<!-- 有裝 intake kit 的專案：整區刪除。未涵蓋項 append 到 .claude/dev/inbox.md
     （from: grill:{題目}），由下次開波的 triage 一併處理，wave 不自維護此表。
     此區僅供未裝 kit 的專案使用。 -->
| # | 決策 | 來源 | 為何本波不做 |
|---|------|------|-------------|
| 1 | [決策內容] | [spec §N / grill Q#] | [scope cut / blocker / 依賴未就緒] |
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

## Goal Condition 模板

Phase 5 輸出 3 逐字填入（{id} 與約束代入本波實值）：
```
Wave {id} 全部完成。完成標準：
(1) 所有工作項合約指令全部跑過，輸出貼在 wave-{id}.md 對應合約結果欄
(2) 每項覆蓋 happy path + edge case + 誤用場景 + 適用的資料守恆/規模場景（合約內列的全部跑過）
(3) 品質閘門通過：🔒 安全 skill 0 high/critical；專案 gate script（scripts/hooks/wave-gate.sh 存在時）exit 0；🎨 UX 審計已執行並記錄，或依降級規則標「待 UX 補跑」封鎖閘門
(4) requirements 對應項狀態已更新
(5) wave-{id}.md「📋 延後決策」區已填寫（列出 grill 產出的所有未落地決策 + 優先順序；零延後明確寫零）
(6) wave-{id}.md 狀態更新為「✅ 完成」
(7) 全程遵守唯一停點制——除「停點規則」所列合法停點與例外（Align、範圍確認、Phase 2.5 訪談、破壞性操作確認、阻塞全部剩餘工作的需人裁定）外未曾停下等待輸入
約束：不動其他波正在處理的檔案（[列出其他波 ID: 涉及檔案]）。不碰其他 wave-*.md。
合約輸出必須是本輪實際跑出的，不可憑記憶填。
```

**收尾核對佐證**：收尾步驟 2 打勾時，每條旁邊填入佐證來源：

| 條目 | 佐證來源 |
|------|---------|
| (1) 合約跑過 | 各項 dashboard 合約結果欄的實際輸出 |
| (2) 覆蓋場景 | 各項合約覆蓋場景欄的 test case 對應 |
| (3) 品質閘門 | gate script exit code + 安全/UX 閘門記錄 |
| (4) requirements | commit SHA（更新 requirements 的 commit） |
| (5) 延後決策 | dashboard 📋 區內容 |
| (6) 狀態 | dashboard 頂部狀態行 |
| (7) 停點制 | 列出本波所有停點時點+原因，逐一對照合法清單 |

## 啟動宣告模板

```
✅ Wave {id} 規劃完成，直接開工。

🌿 Worktree: .claude/worktrees/wave-{id} (branch: wave/{id})
🚀 執行方式: [Phase 4 自動採用的方式]

📋 Goal Condition:
[貼出 goal condition 內容]
```

有其他並行的波時，額外顯示：
```
⚠️ 並行波：[列出其他波 ID + 狀態]
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
