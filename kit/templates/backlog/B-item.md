---
id: B-NNN
type: BUG            # BUG | NEW | CHORE | SPEC_CHANGE
pri: P2              # P0（本波製造的回歸）| P1 擋驗收 | P2 客戶會碰到 | P3 體驗 | P4 有空再說
flow: direct         # direct | spec
status: "ready"      # ready | done:<wave-id> | dropped:<理由> | ⚠️需客戶確認 | orphan-review | placeholder
matrix: "—"          # RTM 條目或 —
from: "INB-NNN（來源說明）"
touches:             # status=ready 必填；repo-root-relative exact path 或窄 glob，多值用；分隔
  - "`<repo-root-relative exact path 或窄 glob>`"
# closed: YYYY-MM-DD  ← done/dropped 時必填（retention 靠它算保留期）
created: YYYY-MM-DD
source: direct       # both | table-only | detail-only | direct | audit
---

# <一行摘要（60 字內，backlog-ls 只取前 60 字）>

## evidence

<為何判定此 type 的依據；BUG 附 repro>

<!-- ready 階段不得留 ## proof 區（backlog-lint 檢查 8 會擋：結項證據沒同步翻 status ＝ 派發矛盾單）。
     標 done/dropped 時才補：
## proof
commit hash／實測輸出／counter 變化／閘門結果。填不出 proof 就不能標 done -->

## notes

<其餘脈絡；unknown touches 填 `unknown:<具體原因>`，不得猜路徑>
