# Wave: kit-k1

> **狀態**: ✅ 完成
> **建立**: 2026-07-30

## Metadata

- **背景**: dfaa 品管通用化 7 波計畫（K1-K7）第一波——骨架 + provenance 帳 + audit skill。總計畫 `~/.claude/plans/witty-hugging-sphinx.md`；詳細設計 `~/.claude/plans/witty-hugging-sphinx-agent-ace953f2ac0b47679.md`
- **涉及檔案/目錄**: `kit/engines/ kit/gates/ kit/tools/ kit/manifest/ kit/kit-audit/ kit/lib/common.sh kit/tests/cases/ kit/references/ kit/SKILL.md .gitignore`
- **並行波**: 無（skills repo 首波）
- **執行方式**: Inline（強依賴鏈 1→2→3→4→5，Subagent 無並行收益）
- **Fable 諮詢點 1**: 已審（5 必修已回寫：audit 自帳/掃描範圍對稱/集合對帳/指令副檔名/判定矩陣凍結）
- **恢復指引**: 讀本檔 + ledger RESUME POINTER，以 git log 為準核實進度

## 🎯 Goal Condition

Wave kit-k1 全部完成。完成標準：
- [x] (1) 所有工作項合約指令全部跑過——五項合約結果欄皆有本輪實跑輸出（9382b3e/d87c13e/1306c3d/38ddb7a + K1-5 commit）
- [x] (2) 全場景覆蓋——kit-audit 七 fixture+fail-closed 三態（22 斷言）、manifest 集合對帳+全行 hash+防假 0（5 斷言）、marker 首插/冪等/雙模組/特殊字元/多行（27 斷言）
- [x] (3) 品質閘門——安全/UX N/A（純 bash+markdown）；全套迴歸 327 assertions 0 failed（收尾實跑）；註：K1-5 合約「六專節計數」實測 7（六種宣告+manifest 節），符合合約意圖
- [x] (4) 真 kit 實跑 kit-audit → 同步 12、inspected:12、AUDIT-EXIT=0（收尾實跑）
- [x] (5) 「未涵蓋決策」區已填寫（1 項 ERRATA 升級候選，見下）
- [x] (6) 本檔狀態已標「✅ 完成」
- [x] (7) 停點清單：①Phase 4 範圍確認（合法停點 2）——此外全程未停。Phase 0 Align 因 /wave 帶參數跳過（合法）。共 1 停點

約束：不動 dfaa repo。不動 dotfiles repo（鏡像收尾後另行處理）。合約輸出必須是本輪實際跑出的，不可憑記憶填。

## 🤖 工作項

| # | 項目 | 狀態 | commit | 合約結果 |
|---|------|------|--------|---------|
| 🤖-1 | 目錄樹 + lib/common.sh 三函式 | ✅ | 9382b3e | `bash -n` exit 0（SYNTAX-OK-K1-073038）；`run.sh common.sh` → 57 assertions, 0 failed（新增 27 條：decl_get 取值/default/缺檔、manifest_lookup 命中/未命中/exact-match、marker_block 首插/冪等/更新/雙模組/特殊字元/多行） |
| 🤖-2 | manifest/provenance.tsv 12 行 + 格式定案 + tests/cases/manifest.sh | ✅ | d87c13e | `run.sh manifest.sh` → 5 assertions 0 failed（欄數守恆/集合雙向差集空/全行 hash/防假 0 行數對帳）；全套 305 綠 |
| 🤖-3 | tools/kit-audit.sh（判定矩陣+seam+六 fixture） | ✅ | 1306c3d | `run.sh kit-audit.sh` → 22 assertions 0 failed（七 fixture+fail-closed 三態）；E2E smoke 真 kit：同步 12 inspected:12 exit 0；全套 327 綠。修 B-210 同族全形標點 bug（ledger ERRATA） |
| 🤖-4 | kit-audit/SKILL.md + symlink + kit SKILL.md 入口 | ✅ | 38ddb7a | frontmatter OK/觸發詞 OK/35 行 ≤80/symlink 指 main checkout（merge 後生效）/七個子skill 反向 grep=0/引用路徑三項全存（declaration-formats 於 🤖-5 落地後補驗 OK） |
| 🤖-5 | references/declaration-formats.md | ✅ | (收尾commit) | 7 節（六種宣告+manifest）/mode 三值命中/`-` 佔位+掃描範圍關鍵詞 OK/counter 範例 bash -n OK |

合約詳細定義見 scratch 草稿（已凍結）：`/private/tmp/claude-501/-Users-chunn-projects-dotfiles/c77ee1a4-2c30-4320-a673-82086ebfff87/scratchpad/wave-kit-k1-draft.md`——關鍵合約條文複製如下備查。

### 🤖-1 合約
- `bash -n kit/lib/common.sh` exit 0
- `bash kit/tests/run.sh common.sh` 全綠；新斷言：kit_decl_get（取值/default/缺檔 fail-open）、kit_manifest_lookup（命中/未命中）、kit_marker_block（首插/更新冪等/雙模組共存/特殊字元不變形）

### 🤖-2 合約（tests/cases/manifest.sh 自動化，進全套迴歸）
- 欄數守恆 `!/^#/ && !/^$/ && NF!=8` exit 0
- 集合對帳雙向差集=0（受管目錄 vs manifest kit_path）
- 全行 kit_sha256 實算相符（剝 sha256: 前綴）
- 登帳 12 行（hooks/6+scripts/3+lib/common.sh+installers/intake.sh+tools/kit-audit.sh）

### 🤖-3 合約
- 六 fixture scratch 隔離（--manifest/--kit-root/KIT_AUDIT_UPSTREAM_BASE seam）：同步 exit 0／上游漂移／kit 演化／無帳／檔不存在 FAIL／雙漂移並列報
- 每 fixture 斷言 inspected:N 精確值；manifest 缺失/0 行/malformed → exit 2
- `bash kit/tests/run.sh kit-audit.sh` 綠 + 全套迴歸綠
- 端到端 smoke：對真 kit 實跑 → 0 漂移 0 無帳 exit 0

### 🤖-4 合約
- disable-model-invocation: true；description 含 /kit-audit 觸發詞；≤80 行
- symlink 正確；SKILL.md 引用路徑逐一 test -f；kit/SKILL.md 無「七個子 skill」殘留

### 🤖-5 合約
- 六專節標題計數=6；mode 三值 grep 皆命中；manifest 節含「`-` 佔位」「掃描範圍」；counter 範例 bash -n 可過

## 🔒 安全審計結果

N/A（純 bash+markdown，無 API/auth/dependency/TS 變更）

## 🎨 UX 審計結果

N/A（無前端工作項）

## 📋 未涵蓋決策

- **ERRATA 升級候選（Q1 過 Q2 過）**：bash 裸 `$var` 緊接全形標點 → `set -u` unbound variable（B-210 同族第 ≥4 次實踩，本波在 kit-audit.sh 報告行再犯）。判定：機器擋得住——`shell-fullwidth-punct.sh` gate 已排 K7 吸收，落地時應同時掛 kit 自身 repo（不只給消費專案）。無 intake kit 故記於此，K7 規劃時帶入。

✅ 本波涵蓋計畫 K1 範圍全部項目，執行中無其他新增未處理事項。
