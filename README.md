# Skills

可跨平台分享的 AI coding agent skills 合集。支援 Claude Code、Codex、Copilot CLI、Gemini CLI。

核心是 `/wave`——工作波次規劃與啟動框架，支援軟體開發和通用工作場景。

## 安裝

```bash
git clone https://github.com/latteouka/skills.git ~/projects/skills
cd ~/projects/skills
./install.sh
```

install.sh 會自動偵測你的 runtime（Claude Code / Codex），安裝到對應的 skills 目錄。

也可以手動指定：

```bash
./install.sh --claude   # ~/.claude/skills/
./install.sh --codex    # ~/.codex/skills/
./install.sh --agents   # ~/.agents/skills/ (跨平台通用)
./install.sh --force    # 覆蓋已存在的 skill
```

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

- **dev 模式**：偵測到 `package.json`、`Makefile` 等開發檔案 → 完整驗證合約 + 安全/UX 閘門
- **general 模式**：非開發環境 → 輕量 checklist review

手動覆寫：`/wave --dev` 或 `/wave --general`

## 解除安裝

```bash
./uninstall.sh
```

## 支援的 Runtime

| Runtime | Skills 目錄 | 旗標 |
|---------|------------|------|
| Claude Code | `~/.claude/skills/` | `--claude`（預設） |
| Codex | `~/.codex/skills/` | `--codex` |
| Copilot CLI / Gemini CLI | `~/.agents/skills/` | `--agents` |

## 依賴

- Wave 的 dev 模式依賴 [superpowers](https://github.com/anthropics/claude-code-plugins) 的 `brainstorming` 和 `using-git-worktrees` skills（Claude Code 內建；Codex 需另裝）
