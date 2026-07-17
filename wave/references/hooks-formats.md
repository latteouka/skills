# Wave 深度材料 — 鉤子檔格式範本

本檔由 wave/SKILL.md 於對應動作點載入——不要直接執行本檔。

## quality-gates.md 格式範本

```markdown
# Quality Gates — [專案名]

## Gate 指令
| 觸發條件 | 指令 | 預期 | 時機 |
|---------|------|------|------|
| 動到 parser / 資料管線 | pnpm quality:affected --run | 受影響 checks 全 PASS | 每項 commit 前 |
| 收尾 | pnpm quality-check | 0 FAIL | 品質閘門 + 基線 |

## 大規模資料 smoke 清單
- [情境] → [URL / 指令 + 資料規模說明]（例：22 萬則訊息的對話頁）

## 資料守恆錨點
- [來源 vs 落庫對帳指令或 SQL]（收尾稽核「抓資料失真」用）

## Worktree dev server 啟動方式
- [指令 + port]（UX 閘門降級規則第一步查這裡）
```

## playwright-guide.md 格式範本

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
