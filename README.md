# Skills

可跨平台分享的 AI coding agent skills 合集。支援 Claude Code、Codex、Copilot CLI、Gemini CLI。

大部分是從上游開源 repo vendored 進來、集中管理與升級；少數原創的規劃／訪談 skill 放在 `kit/`。

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

install.sh 只掃 repo 根目錄下帶 `SKILL.md` 的資料夾。`kit/` 底下的 skill 不在自動安裝範圍，需要自行 symlink。

## 包含的 Skills

| Skill | 用途 | 來源 |
|-------|------|------|
| insecure-defaults | 安全審計：不安全預設值 | vendored |
| sharp-edges | 安全審計：API 銳角 | vendored |
| static-analysis | 靜態分析（semgrep／codeql／sarif） | vendored |
| ui-test | 對抗性 UI 測試 | vendored |
| wcag-accessibility-audit | WCAG 無障礙審計 | vendored |
| nielsen-heuristics-audit | Nielsen 啟發式評估 | vendored |
| ux-audit-rethink | UX 全面重新檢視 | vendored |
| writing-for-agents | 撰寫 agent 讀的文件 | vendored |
| wizard | 產出互動式 bash 引導精靈 | vendored |
| prototype | 用拋棄式原型回答設計問題 | vendored |
| grilling | 壓力測試訪談引擎（frontier 批次問答） | vendored |
| grill-me | 壓力測試計畫（轉呼 /grilling） | vendored |
| grill-with-docs | 壓力測試 + 同步更新文件（轉呼 /grilling + /domain-modeling） | vendored |
| domain-modeling | 領域模型與 ADR／CONTEXT 維護 | vendored |
| debug | 系統化除錯流程（superpowers systematic-debugging） | vendored |
| kit/brainstorm | 需求模糊時先訪談再動手 | 原創（改編自 superpowers 後深度客製） |

**原創** = 本 repo 自行設計維護。**vendored** = 取自上游開源 repo，見 `vendors.conf`。

`kit/` 另含被 dfaa hooks 與 pctl deep-lane 呼叫的引擎：`engines/`（ratchet、rtm-check）、`gates/`（hook-wiring-check、reqsync 系）、`hooks/`（rtm 系）——kit 的角色是引擎 bin，品管由呼叫端的 hook 機制承擔，不靠文件。

## 升級 vendored skills

外來 skill 的上游來源記在 `vendors.conf`，用 sync 腳本追蹤上游更新：

```bash
scripts/sync-vendors.sh check    # dry-run：列出上游有什麼更新、本地是否被改過
scripts/sync-vendors.sh apply    # 實際覆蓋成上游版本，之後 git diff 審查再 commit
scripts/sync-vendors.sh apply --only ui-test   # 只升級單一個
```

`vendors.lock` 記錄每個 skill 上次同步的上游 SHA 與本地內容 hash——apply 前若偵測到本地被手動改過會跳過並警告（要強蓋加 `--force`）。**`kit/` 底下的原創 skill 不在 `vendors.conf` 內，永遠不受同步影響。**

授權：`trailofbits/*` 為 CC-BY-SA-4.0（需保留署名），`mastepanoski/*` 為 MIT。

## 依賴

不依賴 superpowers plugin。`kit/debug` 早期改編自 [superpowers](https://github.com/obra/superpowers)（MIT，見 `kit/LICENSE-superpowers`），已客製化為本工作流的副本，與上游不再同步。

## wave 已退役

本 repo 曾以 `/wave`（工作波次規劃與啟動框架）為核心。它已退役並自 repo 移除，理由：

- 路由層早已不再指向它，派工改由 GitHub issue ＋ 外部排程器承接，狀態 SSOT 在 GitHub 而非本地 dashboard 檔
- 它規定要跑的 `wave-close.sh`、`wave-registry.sh` 從未落地，導致收尾清理長期是空指令，dashboard 只增不減

歷史內容留在 git history，需要時 `git log --all -- wave/` 取回。批次工作改為拆多張 issue 成依賴鏈推進。

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
