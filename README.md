# Skills

可跨平台分享的 AI coding agent skills 合集。支援 Claude Code、Codex、Copilot CLI、Gemini CLI。

核心是 `/wave`——工作波次規劃與啟動框架：一次呼叫完成「對齊需求 → 掃出所有未完成項 → 寫驗證合約 → 隔離開工 → 自主長跑 → 稽核收尾」，支援軟體開發和通用工作場景。

## 安裝

```bash
git clone https://github.com/latteouka/skills.git
cd skills
./install.sh
```

install.sh 會自動偵測你的 runtime（Claude Code / Codex），以 symlink 安裝到對應的 skills 目錄。**同名 skill 已存在時會跳過不覆蓋**（你既有的優先），要覆蓋請明確加 `--force`。

```bash
./install.sh --claude   # ~/.claude/skills/
./install.sh --codex    # ~/.codex/skills/
./install.sh --agents   # ~/.agents/skills/ (跨平台通用)
./install.sh --force    # 覆蓋已存在的 skill
```

## 快速開始

裝完後，在你的專案目錄開啟 Claude Code，兩種入口：

**有新需求要做** → `/wave` + 需求（素材先對齊落檔，全程只確認一次範圍）：

```
/wave 幫我做訂單匯出功能：CSV 格式、支援日期區間篩選、匯出上限 1 萬筆
```

**清既有工作債** → 直接 `/wave`（它會問你有沒有新素材，答「沒有」就開始四來源掃描）：

```
/wave
> 這波有新素材要帶入嗎？
沒有，從現有 requirements 繼續
```

## 使用範例

```bash
# 1. 帶檔案素材——會議紀錄、逐字稿、客戶回饋
/wave ~/Downloads/0703-會議紀錄.md
# → 摘出行為承諾/需求變更 → 與 docs/requirements/ 比對 → 衝突讓你裁定 → 落檔後規劃

# 2. 帶文字需求——新功能從零開始
/wave 加一個成員權限管理頁：管理員可停用帳號、操作要留稽核紀錄
# → 偵測到新功能設計未定 → 自動先跑 brainstorming 對齊方向再寫合約

# 3. 空手掃債——把散落各處的未完成項一波帶走
/wave
# → 掃 docs/requirements/ 的 🔴🟡❓、程式內 TODO/FIXME、上波延後決策、git log 半成品
# → 連續兩輪掃不出新項才停（loop-until-dry），不會「掃到夠交差就停」

# 4. 非開發場景——文件、簡報、報告（自動切 general 模式）
cd ~/Documents/quarterly-report && claude
/wave 整理 Q2 季度報告：業績摘要、三個客戶案例、下季目標
# → 沒有 package.json 等開發特徵 → 輕量 checklist 流程，不跑測試合約

# 5. 多波並行——兩個 terminal 各開一波互不干擾（各自獨立 worktree）
/wave status     # 全局概覽：各波進度、檔案交集預警
/wave drop {id}  # 放棄一波

# 6. 中斷接手——session 斷了直接開新的說「接手 wave」
# → 新 session 讀 ledger 的 RESUME POINTER + 核對 git 真實狀態，從斷點續跑
```

## 工作流程

Wave 的設計目標：**你只需要在兩個時點出現**（開頭答有無新素材、規劃完確認範圍），其餘全程自主。

```
/wave
  │
  ├─ Phase 0-1  Align ── 有新素材？→ 消化、與 requirements 比對、衝突請你裁定、落檔
  │                                                        ◄── 停點 1（唯一兩停之一）
  ├─ Phase 2    掃描 ── 四來源 loop-until-dry：requirements 標記 / TODO·FIXME /
  │                     上波延後決策 / git log 半成品。連續兩輪無新項才停
  ├─ Phase 2.5  （自動判斷）新功能 → brainstorming；大波/高風險 → grill-me 壓力測試
  ├─ Phase 3    每項寫「驗證合約」── 可執行指令 + 預期輸出 +
  │                     happy path / edge case / 誤用場景三角度
  ├─ Phase 4    範圍確認 ── 工作清單 + 合約 + 執行方式一次確認
  │                                                        ◄── 停點 2（此後不再問你）
  ├─ Phase 5-6  隔離開工 ── 建獨立 worktree（絕不動 main）、goal condition
  │                     (1)-(10) 寫入 dashboard、跑基線測試記錄
  │
  ├─ 執行期（自主長跑）
  │     每項：TDD → 跑完合約全場景 → 全過才 commit → dashboard 即時更新
  │     ledger 流水帳逐 commit 記錄（中斷可無縫接手）
  │     需要你裁定的事不停等——先推其他項，自然節點批次呈報附推薦方案
  │
  └─ 收尾
        品質閘門（dev：安全 skill blocking + UX 審計 advisory）
        → 派 fresh-context 稽核 subagent：重跑全部合約抓虛報、回掃 requirements
          抓漏項、抽查場景抓縮水、核對 ledger 抓外部化偷懶
        → 稽核不過 = 打回修復重稽核
        → goal condition 逐條打勾 → 標「待人測」→ 協助 merge 回 main
```

**核心理念**：

- **一波帶走**——掃出的未完成項全部排進本波，不建議延後；真 blocker 標註原因交你裁定
- **做好比做快**——不趕進度、不跳過誤用場景測試；session 跑多久都沒關係
- **唯一停點制**——全程只在兩個點等你，不會做到一半問「要繼續嗎？」
- **證據式進度**——宣稱「完成/測試綠」必附本輪實際跑出的輸出；收尾稽核會重跑驗證，虛報過不了關
- **狀態外部化**——進度記在 dashboard + ledger 檔案而非對話記憶，session 斷了換一個接著跑

**產出物**（都在 worktree 內）：

| 檔案 | 用途 |
|------|------|
| `.claude/dev/wave-{id}.md` | Living dashboard：工作項狀態、合約結果、goal condition、稽核結果 |
| `.claude/dev/wave-{id}-ledger.md` | Append-only 流水帳 + RESUME POINTER（中斷接手指引） |
| `.claude/worktrees/wave-{id}/` | 本波的隔離工作區（git worktree） |

## 包含的 Skills

| Skill | 用途 | Wave 依賴 |
|-------|------|-----------|
| **wave** | 波次規劃與啟動（核心） | — |
| grill-me | 逐題壓力測試計畫 | Phase 2.5 |
| grill-with-docs | 壓力測試 + 同步更新文件 | Phase 2.5 |
| insecure-defaults | 安全審計：不安全預設值 | dev-mode 閘門 |
| sharp-edges | 安全審計：API 銳角 | dev-mode 閘門 |
| static-analysis | 靜態分析 | dev-mode 閘門 |
| ui-test | 對抗性 UI 測試 | dev-mode 閘門 |
| wcag-accessibility-audit | WCAG 無障礙審計 | dev-mode 閘門 |
| nielsen-heuristics-audit | Nielsen 啟發式評估 | dev-mode 閘門 |
| ux-audit-rethink | UX 全面重新檢視 | dev-mode 閘門 |

## Wave 雙模式

Wave 會自動偵測工作模式：

- **dev 模式**：偵測到 `package.json`、`Makefile` 等開發檔案 → 完整驗證合約 + 安全/UX 閘門 + 收尾稽核
- **general 模式**：非開發環境 → 輕量 checklist + 輕量稽核（核對產出物存在/結構/內容）

手動覆寫：`/wave --dev` 或 `/wave --general`

## 依賴

**Claude Code 使用者注意**：wave 的部分流程依賴 superpowers plugin（`claude-plugins-official` 市集）——**這是 plugin，不是內建**，需要先安裝：

```
claude 內執行：/plugin → Discover → 找 superpowers → 安裝並啟用
```

Wave 用到其中的：`brainstorming`（Phase 2.5 需求探索）、`using-git-worktrees`（隔離開發）、`subagent-driven-development`（Subagent-Driven 執行方式）、`writing-plans`。沒裝的話 Phase 2.5 與 Subagent-Driven 執行方式會觸發失敗——Inline 執行方式仍可用，但建議裝齊。

Codex / Copilot / Gemini CLI：無 plugin 生態，wave 會以 inline 方式執行，brainstorming/grill 段落改為對話式進行。

## 解除安裝

```bash
./uninstall.sh
```

只會移除指向本 repo 的 symlink（會驗證 symlink 指向），不會動到你同名的自有 skills。

## 支援的 Runtime

| Runtime | Skills 目錄 | 旗標 |
|---------|------------|------|
| Claude Code | `~/.claude/skills/` | `--claude`（預設） |
| Codex | `~/.codex/skills/` | `--codex` |
| Copilot CLI / Gemini CLI | `~/.agents/skills/` | `--agents` |
