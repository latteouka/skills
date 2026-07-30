# 部署／現場作業 Memo（SSOT）

**Created**: <YYYY-MM-DD>
> **部署與現場作業的唯一追蹤檔**——所有 session 共享同一進度。
> 涵蓋：deploy 執行、現場／進場作業、環境狀態確認。
> **不進開發 backlog、不排波、不散落 inbox**；規則見專案 CLAUDE.md「部署／現場作業控管」節（若已設）。
> 接線：`intake.config.yaml` 的 `ops_memo` 指向本檔複製後的路徑，`ops_keywords` 命中時
> `hooks/capture.sh` 會提示分流到此檔而非 inbox（見 kit SKILL.md「ops」節）。

---

## 🖥️ 環境狀態板（改了就更新，帶日期）

| 項 | 現況 | 最後確認 |
|---|---|---|
| （範例）主環境 image | — | YYYY-MM-DD |

## 📦 Deploy Log（append-only：日期｜內容｜授權｜結果）

| 日期 | 內容 | 授權 | 結果 |
|---|---|---|---|
| YYYY-MM-DD | （部署內容摘要，含 commit／版本） | （使用者授權原話，不得代填） | （exit code／驗證結果，落檔為準） |

## ⚖️ 部署設定待裁

- [ ] （待使用者裁決的部署／現場相關決策）

## 回程後 / 事後追蹤

- （現場作業完成、資料回來才動的項目）
