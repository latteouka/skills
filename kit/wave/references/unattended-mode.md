# 無人值守模式細則

> SKILL.md「無人值守模式」節的展開。判定條件：env `WAVE_UNATTENDED=1`（呼叫端設定；通常同時提供 `WAVE_ID`）。人在場的互動波完全不受本檔影響。

## 本模式只解決一個問題：沒有人可問

Wave 的流程原生假設「人在終端前」——停點問人、❓ 項等裁定、PENDING 留給使用者處理。這個假設在無人值守時全部失效：問了沒人答，留了沒人讀。

本模式**不改變收尾行為**。所有波都是 push branch 即收工（SKILL.md Core Principles「收工＝push branch」），這條與人在不在場無關。

## 三條實證教訓

| 錯誤行為 | 後果 |
|---|---|
| 不建 worktree 直接改主 checkout | 隔離邊界失義，改動與其他並行工作互相污染 |
| 收尾留「需你在終端跑 X」PENDING | 沒有人在場，訊息躺在終端無人讀 |
| 完工後 session 不退出、閒置等待 | 呼叫端要 session 結束才能接手，永遠等不到 |

## 各階段覆寫明細

- **停點**：全部跳過。Align ＝啟動 prompt 就是素材；Phase 2.5 訪談降級為 `[自主決策]` 記 dashboard；Phase 4 清單照產但不問，❓ 項採推薦方案＋開一則 issue 留痕。禁用 `AskUserQuestion`。
- **命名**：wave id ＝ `$WAVE_ID`（有值時）。dashboard／ledger 檔名照常以此 id 組成。
- **Phase 6 Step 1**：cwd 已在 worktree 內時跳過建立；守衛檢查（`git rev-parse --show-toplevel` 含 `worktrees/wave-`）照做。
- **UX 閘門降級**：dev server 起不來時標「✅ 完成（UX 未跑：dev server 不可用）」＋開一則 `[ux]` issue（與互動波同規則）。
- **待人事項**：先過「問題出口」節的可解性檢查，真不能做才 `gh issue create`（body 註明 `wave-{id}（無人值守）`），報告只留摘要。收尾流程步驟 3「待裁決事項在收尾報告直接請使用者裁決」不適用——直接開 issue 附推薦方案。
- **ERRATA 判定**照常做（結果開 issue，不進報告等人）。
- **退場**：輸出總結後立即結束 session，不閒置等待。

## Codex 執行面注意

`references/codex-adaptation.md` 的 EnterWorktree 對應（建 worktree 後重開 session）在 cwd 已於 worktree 內時**不適用**——直接開工。
