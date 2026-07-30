# 📋 Backlog（一筆一檔）

> triage 後的料倉。一筆工作項＝一個 `B-NNN.md`（格式見 `kit/templates/backlog/B-item.md`），
> ID 由 `~/projects/skills/kit/tools/next-id.sh --touch B` 原子取號。
> `/wave --from backlog` 只取 `status: ready` 的項；查詢用 `backlog-ls.sh`（如
> `--status ready --count`）。⚠️需客戶確認 的項不會被自動取用，須人工改為 ready 或 dropped。
> schema 由 pre-commit 的 `backlog-lint.sh` 把關；過期清理用 `backlog-retention.sh --dry-run`。

## 欄位說明

### `status` 值域

| 值 | 意義 |
|---|---|
| `ready` | 可排波。`/wave --from backlog` 只取這個 |
| `⚠️需客戶確認` | 硬閘門，wave 取不到。須人工改 ready 或 dropped |
| `blocked:{原因}` | 有明確 blocker |
| `🔶止血:{wave-id}` | **已緩解但未根治**——症狀消失、根因仍在。不可視同完成 |
| `done:{wave-id}` | 完成。**必須同時填 `proof` 與 `closed` 日期**，否則視同未完成 |
| `dropped:{理由}` | 不做 |
| `orphan-review` | 遷移時無對應表列，待 triage 裁決 |
| `placeholder` | `next-id.sh --touch` 的佔位檔，取號後應立即填寫 |

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
