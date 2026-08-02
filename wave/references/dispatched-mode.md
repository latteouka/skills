# Dispatched 模式細則（portfolio supervisor 無人派發）

> SKILL.md「Dispatched 模式」節的展開。判定條件:env `PORTFOLIO_DISPATCHED=1`(supervisor 的 dispatch_cmd 設定;同時提供 `PORTFOLIO_WAVE_ID`)。人工互動 wave 完全不受本檔影響。

## 為什麼需要這個模式

Wave skill 原生為「人在場的互動波」設計:停點問人、收尾自跑 merge-train、PENDING 留給使用者。被 supervisor 無人派發時,這些行為全部失效或有害(live 實證,2026-08-02 調測日誌):

| 實證 | 行為 | 後果 |
|---|---|---|
| B-284 | 不建 worktree 直接改主 checkout | sandbox 邊界失義、run 永卡 MERGED |
| B-279/280 | 自跑 merge-train 進 main | 繞過 supervisor diff 敏感面分流(合約 §18) |
| B-284/283 | 收尾留「需你在終端跑 X」PENDING | 使用者不在場,訊息躺在 pane 無人讀 |
| 四波 | interactive session 完工後閒置 | supervisor 要 session 死才接手 merge,永不發生(v0.6 起 executor 用 `claude -p` headless,完工自動退出,根治此類) |

## 與 supervisor 的分工(v0.6)

| 事項 | executor(你) | supervisor |
|---|---|---|
| worktree | 沿用預建(cwd 即是) | 派發前 `git worktree add`(基底=trusted ref) |
| session 型態 | `claude -p` headless,完工自動退出 | dispatch_cmd 啟動;WIP:DISPATCHED cap=3(一次最多派 3 個新 session) |
| 開發自驗 | typecheck/tests/`wave-gate.sh baseline` | — |
| merge 前檢查 | 不跑 | 只跑 typecheck(~90 秒,同步) |
| merge | **禁止**(hook 會擋主 checkout commit/merge) | typecheck 綠→diff 分流→auto-merge;diff HOLD 不降級——碰敏感面照 merge,通知裡提示使用者看 diff |
| dirty worktree | 收尾前把變更 commit 乾淨 | 偵測到未 commit 變更→自動 commit 繼續流程(不凍結等人) |
| 完整品質閘門 | 不跑 | merge 後 deep lane:每 3 個 merge 跑完整 `wave-gate.sh baseline`,紅燈自動寫 inbox 開單→triage→dispatch 修復 |
| worktree 清理 | 不清 | merge 後 remove+branch -D |
| 待人事項 | append `.claude/dev/inbox.md` | triage→材料化→TG |

## 各階段覆寫明細

- **停點**:全部跳過。Align=派發 prompt 就是素材;Phase 2.5 訪談降級為 `[自主決策]` 記 dashboard;Phase 4 清單照產但不問,❓ 項採推薦方案+一行進 inbox;合併協助的裁定停點不適用(不合併)。
- **命名**:wave id=`$PORTFOLIO_WAVE_ID`(如 `wave-B-282-0d6f6f`)。dashboard/ledger 檔名照常以此 id 組成。
- **Phase 6 Step 1**:跳過建立;守衛檢查(`git rev-parse --show-toplevel` 含 `worktrees/wave-`)照做——supervisor 命名天然通過。
- **基線 gate 與品質閘門**:一律 `bash scripts/hooks/wave-gate.sh baseline`(開工基線+開發自驗)。v0.6 起 gate script 只剩 baseline 用途——merge 前 supervisor 只跑 typecheck,完整品質閘門在 merge 後的 deep lane 背景跑(每 3 個 merge 一次,紅燈寫 inbox 開單),executor 不跑也不等它。
- **UX 閘門降級**:「merge 後補跑」不存在(你不 merge)——改寫一行進 inbox。
- **長跑規範第 1 條**:push 自己的 branch 視為已授權(派發即授權);merge/deploy/對外發送仍禁。
- **收尾**:①backlog status→`done:{id}` ②dashboard 待人事項搬 inbox ③dashboard+ledger `git rm` ④以上併入最後 commit ⑤`git push -u origin <branch>` ⑥輸出總結(含 commit 清單+自驗結果)即結束。**不寫 wave-INDEX**(supervisor merge 後處理)。
- **ERRATA 判定**照常做(結果進 inbox,不進報告等人)。

## Codex 執行面注意

`references/codex-adaptation.md` 的 EnterWorktree 對應(建 worktree 後重開 session)在 dispatched 模式**不適用**——worktree 已存在且 cwd 正確,直接開工。
