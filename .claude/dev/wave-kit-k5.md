# Wave: kit-k5

> **狀態**: ✅ 完成
> **建立**: 2026-07-31

## Metadata

- **背景**: 7 波最後拼圖——RTM 模組（雙側執法三方向）+ kit-init dispatcher + onboarding。上游 dfaa main `53a242db6`。RTM=核心真理層（使用者裁定），讀側執法補缺口
- **涉及檔案/目錄**: `kit/engines/rtm-check.ts kit/gates/require-requirements-sync.sh kit/gates/append-req-sync-skip-trailer.sh kit/hooks/rtm-touch-reminder.sh kit/templates/rtm/ kit/templates/kit.yaml kit/references/rtm-authoring.md kit/installers/kit-init.sh kit/installers/modules/ kit/SKILL.md kit/wave/references/templates.md kit/manifest/ kit/tests/cases/`
- **並行波**: 無
- **執行方式**: Subagent-Driven（切法待 Fable 裁）
- **恢復指引**: 讀本檔 + ledger，git 為準

## 🎯 Goal Condition

Wave kit-k5 全部完成。完成標準：
- [x] (1) 全跑過（controller 逐項親跑）
- [x] (2) 26+20+30+78→83 斷言＋Fable 修正逐條落實
- [x] (3) 安全審計實跑（insecure-defaults+sharp-edges 框架）：HIGH×2 已修至 0、M×4/L×4 記錄於下；全套 732 assertions 0 failed
- [x] (4) audit 同步 40 exit 0（掃描已含 *.ts）
- [x] (5) 已填
- [x] (6) ✅
- [x] (7) 停點 0 次（Align 帶參跳過；Phase 4 依 K34 慣例使用者連續授權脈絡，開工前草稿經 Fable 修正）；使用者插話（askgpt 排程/onboarding 提問/ISMS 提問）非停等
- [x] (8) dry-run 重定義後達成：modules/rtm.sh scaffold 最小 matrix 過 rtm-check（測試+stub 雙驗；as-built 品質歸 K6 人工驗）

約束：不動 dfaa；不動 dotfiles；rfp_id 向下相容（dfaa matrix 零改動）；合約本輪實跑。

## 🤖 工作項

| # | 項目 | 狀態 | commit | 合約結果 |
|---|------|------|--------|---------|
| 🤖-1 | rtm-check.ts 參數化 + --emit-index | ✅ | 4b11150 | rtm-check.sh 26 斷言（runtime 實跑非 SKIP）；smoke PASS 1檔1條 |
| 🤖-2 | reqsync 兩支 + rtm-touch-reminder/session-start hooks | ✅ | 4b11150 | reqsync 20+rtm-hooks 30 斷言（中文檔名/amend/merge 跳過/四態/去重/GC 全入測）|
| 🤖-3 | templates/rtm + rtm-authoring + wave 合約層 | ✅ | 9b1597c | yaml 解析綠、守恆 3=3、wave SKILL 恰 +1 行、task-brief 零改動裁定記錄 |
| 🤖-4 | kit-init dispatcher + modules×3 + onboarding + SKILL 擴充 | ✅ | bcc23a7 | kit-init.sh 78 斷言（--all skipped 語意/冪等/壞 JSON 零寫入/最小 matrix 過 rtm-check）；SKILL 86 行 |
| 🤖-C | 收尾+安全修 | ✅ | 9063e65+(本commit) | manifest 40 行；掃描擴 *.ts 三處；--decl-dir seam；**dfaa parity PARITY-IDENTICAL**（315 條/972 路徑逐位相同）；安全 HIGH×2 修復+斷言；全套 732 綠（落檔量測）；audit 同步 40 exit 0 |

合約細節：scratchpad/wave-kit-k5-draft.md（Fable 修正後凍結）

## 🔒 安全審計結果

HIGH×2（已修至 0，blocking 解除）：H1 merge 假成功 fail-open、H2 worktree 安裝路徑炸彈。
Medium×4（advisory 記錄）：M1 jq filter 拼接不一致、M2 sed/路徑未跳脫未驗證（matrix_dir 注入面）、M3 marker 缺尾標記吞檔、M4 路徑 sentinel 疊加/誤判。
Low×4：寫入無錯誤檢查、備份秒級時戳、mktemp 跨 fs、chmod 靜默。
Note：絕對路徑信任鏈（已知接受設計，建議 kit.yaml 記 HEAD hash——K6 裁定）。

## 🎨 UX 審計結果

N/A

## 📋 未涵蓋決策

1. **安全 M1-M4/L1-L4**（advisory）——M2（matrix_dir 白名單驗證）與 M3（marker 缺尾拒寫）建議 K7 hygiene 波消化；M1/M4/L 級擇機
2. **rtm 灰色清單**：matrix_hash 公式三處內聯（K6 整併 lib）；reqsync excludes 寬鬆點（K6 checklist）；test case chmod 慣例統一（K6）
3. **K6 宣告 checklist 實證新增**：rtm_nonpath_tokens 5 項+impl_path_bases 4 基準（parity 實測得出）
4. **信任鏈緩解**：kit.yaml 記安裝時 kit HEAD hash——K6 裁定

✅ 本波涵蓋 K5 計畫範圍全部項目。
