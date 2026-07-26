# 📋 Backlog

> triage 後的料倉。`/wave --from backlog` 只取 `status: ready` 的項。
> ⚠️需客戶確認 的項不會被自動取用，須人工改為 ready 或 dropped。
>
> **兩個入口**（見 `references/triage-rules.md` 步驟 0）：判斷完成（填得出 type/flow/matrix）
> 可直接寫此檔；填不出來就寫 `inbox.md` 等 triage。

| id | type | pri | flow | matrix | status | summary |
|---|---|---|---|---|---|---|

---

## 明細區（按 id 排序）

> 表格是索引（快速掃視），明細區是完整內容。兩者靠 `id` 對應。

### B-001

- **from**: INB-042（口述 2026-07-25）／INB-051（逐字稿:0724會議）
- **matrix**: 101-案件與證物管理.yaml #12
- **touches**: `<repo-root-relative exact path/glob>`；未知時改填 `unknown:<具體原因>`
- **evidence**: <為何判定此 type 的依據>
- **repro**: <重現步驟；BUG 才需要>
- **wave**: —
- **proof**: <完成後必填：commit hash／實測輸出／counter 變化>

---

## 欄位說明

### `status` 值域

| 值 | 意義 |
|---|---|
| `ready` | 可排波。`/wave --from backlog` 只取這個 |
| `⚠️需客戶確認` | 硬閘門，wave 取不到。須人工改 ready 或 dropped |
| `blocked:{原因}` | 有明確 blocker |
| `🔶止血:{wave-id}` | **已緩解但未根治**——症狀消失、根因仍在。不可視同完成 |
| `done:{wave-id}` | 完成。**必須同時填 `proof`**，否則視同未完成 |
| `dropped:{理由}` | 不做 |

### `pri` 值域

| 值 | 意義 |
|---|---|
| `P0` | **本波製造的回歸**——自己造的債優先於一切既有待辦 |
| `P1` | 擋驗收 |
| `P2` | 客戶會碰到 |
| `P3` | 體驗 |
| `P4` | 有空再說 |

### `touches` 欄（`ready` 必填）

填預計寫入的 repo-root-relative exact path 或窄 glob；多個值用 `；` 分隔。
規劃尚未收斂時填 `unknown:<具體原因>`，不得猜測。`/wave batch` 會對比候選項：
確定交集不得排進同一波或並行波；unknown 視為交集未明，收斂前不得並行。

### `proof` 欄（`done` 必填）

「已完成」必須可被查證，不是宣稱。至少一項：

- commit hash（`d40301f09`）
- 實測輸出（`sub-xs 785 → 92`）
- counter 變化（`gaps 117 → 64`）
- 閘門結果（`main 閘門 exit 0，9 段全過`）

**填不出 proof 就不能標 `done`**——那代表沒有實際驗證過。
