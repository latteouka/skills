# Wave: kit-k2

> **狀態**: ✅ 完成
> **建立**: 2026-07-30

## Metadata

- **背景**: kit 品管通用化 7 波第二波——防假 0 族 + merge-train 六支 + wave-gate 骨架。上游 dfaa main `53a242db6`（~2,600 行吸收參數化）。總計畫 `~/.claude/plans/witty-hugging-sphinx.md`；合約細節（Fable 修正版）`scratchpad/wave-kit-k2-draft.md`（凍結）
- **涉及檔案/目錄**: `kit/lib/canary-harness.sh kit/engines/ kit/gates/ kit/gates/merge-train/ kit/templates/gates.d/ kit/manifest/provenance.tsv kit/tests/cases/ kit/references/declaration-formats.md`
- **並行波**: 無
- **執行方式**: Subagent-Driven——🤖-1 controller 自做 → {2,3,4} 三 implementer 並行 → 🤖-5 → 🤖-6 controller。Brief 附五道吸收紀律防線
- **使用者裁定**: selftest 路線核准（🤖-4 偏離雙 fixture 字面）
- **恢復指引**: 讀本檔 + ledger RESUME POINTER，git 為準

## 🎯 Goal Condition

Wave kit-k2 全部完成。完成標準：
- [x] (1) 六項合約全跑過——各列合約結果欄有本輪實跑輸出（controller 每項親跑不採信報告）
- [x] (2) 全場景覆蓋——14+19+15+30+35+1 斷言；殘留路徑掃描各項逐命中歸類全合法；bash-compat 全庫 0 命中；base_branch key 守恆（declaration-formats 已收斂）
- [x] (3) 安全/UX N/A；全套 441 assertions 0 failed（新增 6 case：canary-harness/pathspec/wiring/merge-train/wave-gate/bash-compat）
- [x] (4) kit-audit 同步 23、inspected:23、AUDIT-EXIT=0（收尾實跑）
- [x] (5) 未涵蓋決策 3 項已填（見下）
- [x] (6) 已標 ✅ 完成
- [x] (7) 停點清單：①Phase 4 範圍確認（合法停點 2；Align 因帶參數跳過）②使用者中途插入 K8 討論（使用者主動發話非 wave 停等）——此外全程未停

約束：不動 dfaa repo（只讀上游）。不動 dotfiles。上游邏輯逐位元組保留（參數化白名單制）。合約輸出本輪實跑。

## 🤖 工作項

| # | 項目 | 狀態 | commit | 合約結果 |
|---|------|------|--------|---------|
| 🤖-1 | canary-harness + engines/canary.sh | ✅ | 1a8ed95 | run.sh canary-harness.sh → 14 assertions 0 failed（四假 gate 雙向+fail-closed 兩態+.fixture 還原+git marker）|
| 🤖-2 | engines/pathspec-liveness.sh | ✅ | 3b14fa0 | 19 assertions 0 failed（五場景含 cd 母題+`:(top)` 反向對照）；controller 親跑 review、hash 符、四函式與上游 IDENTICAL diff 實證 |
| 🤖-3 | gates/hook-wiring-check.sh | ✅ | f911ce8 | 15 assertions 0 failed（四場景+jq 缺席+預設定根）；dfaa parity 實測 inspected:39 兩邊一致 |
| 🤖-4 | merge-train 六支（selftest 路線） | ✅ | 5e01a7d | 30 assertions 0 failed；53/53 selftest 全✓（含無宣告預設態=dfaa 現行為證明）；controller 親跑、7 hash 全符 |
| 🤖-5 | engines/wave-gate.sh 骨架 + templates/gates.d | ✅ | e1d4c84 | 35 assertions 0 failed（八場景：早退+鎖保持/baseline/stamp vs preauth 分態/STALE/零改動/鎖逾時/tierA 空 fail-closed/env+字典序）|
| 🤖-6 | 收尾對帳（manifest/掃描/迴歸） | ✅ | bf89f90 | manifest 23 行對帳綠；bash-compat 掃描 0 命中；全套 441 assertions 0 failed；kit-audit 同步 23 inspected:23 exit 0 |

合約細節（凍結）：`/private/tmp/claude-501/-Users-chunn-projects-dotfiles/c77ee1a4-2c30-4320-a673-82086ebfff87/scratchpad/wave-kit-k2-draft.md`

## 🔒 安全審計結果

N/A（純 bash，無 API/auth/dependency/TS）

## 🎨 UX 審計結果

N/A（無前端）

## 📋 未涵蓋決策

1. **pathspec whitelist 宣告化**（灰色清單①）：`whitelist_reason()` 白名單仍硬編碼引擎內——專案要加白名單得改引擎。候選：`pathspec-whitelist.conf` 宣告化。本波不能做＝白名單制未列、需 declaration-formats 擴充設計。建議 K6 遷移時一併裁定
2. **hook-wiring `${ref#../../}` 固定剝兩層**（灰色清單）：與 dfaa cd apps/web 寫法耦合，逐位元組保留——遇一層/三層 repo 需改迴圈剝除。K6 驗證時留意
3. **templates/gates.d 未入 manifest**（templates/ 帳可選範圍）——K5 kit-init 消費時若升格為機制檔再議

✅ 本波涵蓋 K2 計畫範圍全部項目。
