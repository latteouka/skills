# Claude Code Skills

可分享的 Claude Code skills 合集。核心是 `/wave`——開發波次規劃與啟動框架，支援軟體開發和通用工作場景。

## 安裝

```bash
git clone <repo-url> ~/projects/skills
cd ~/projects/skills
./install.sh
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

## 依賴

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Wave 的 dev 模式依賴 [superpowers](https://github.com/anthropics/claude-code-plugins) 的 `brainstorming` 和 `using-git-worktrees` skills（Claude Code 內建）
