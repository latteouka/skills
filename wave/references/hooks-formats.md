# Wave 深度材料 — 鉤子檔格式範本

本檔由 wave/SKILL.md 於對應動作點載入——不要直接執行本檔。

## quality-gates.md 格式範本

（表內指令皆為範例，建檔時替換為專案自有指令）

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

## feature-map.md 格式範本

```markdown
# Feature Map — [專案名]

> 口語素材 grounding 資產。維護規則：①別名只增不刪 ②route/檔案改動時同步更新對應行 ③命中前先驗證檔案存在，驗證失敗當場修行 ④累積靜默進行，不問使用者 ⑤檔案路徑寫完整（相對 [app 根目錄]），禁止縮寫。

## 功能對照表

| 功能 | Route | 主要檔案 | 口語別名（累積） |
|---|---|---|---|
| [正式功能名] | [/route/path 或（無 UI）] | [page／router／service 路徑，頓號分隔] | [口語講法，頓號分隔] |

## STT 勘誤表（素材為逐字稿檔時查）

| STT 常見輸出 | 正字 |
|---|---|
| [轉錯詞] | [正確詞] |
```

## feature-map grounding 程序

Phase 1 Ground 步驟的完整程序（素材為口語化描述且專案有 `.claude/dev/feature-map.md` 時執行）：

1. **逐項 resolve** — 把 Digest 產出的每個需求，用功能對照表對應成 route＋主要檔案
2. **✅ 命中** — 對照表命中且 **ls/grep 驗證檔案存在**才算命中；驗證失敗（route 改名、檔案搬家）→ 當場更新 feature-map 該行、ledger 記一行，改走 fallback
3. **未命中** — fallback 即時探索（Grep/Explore）；探索成功視同命中，並把口語講法 append 到該功能的別名欄
4. **❓ 對不到** — 收集起來**不現場問**，帶到 Phase 4 停點一次問完（附最似位置推測選項）
5. **靜默累積** — 命中但口語講法不在別名欄 → 立即 append；發現新的 STT 固定轉錯 → 立即 append 勘誤表。不問使用者、不報告（與 playwright-guide 同 pattern）
