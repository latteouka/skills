# Wave k55-harden — 2026-07-30 K5.5 kit 硬化波（GPT 總檢三必修＋附修＋掃描補挖）

## Metadata
- **涉及檔案/目錄**: kit/lib/common.sh, kit/tools/*, kit/engines/*, kit/manifest/provenance.tsv, kit/templates/*, kit/references/declaration-formats.md, kit/tests/**, kit/gates/merge-train/*
- **Checkpoint 分段**: C1: 🤖-1〜3 / C2: 🤖-4〜6 / C3: 🤖-7〜9
- **恢復指引**: 新 session 接手 → 讀 `.claude/dev/wave-k55-harden-ledger.md` 末尾 RESUME POINTER，按「中斷恢復協議」以 git 為準續跑
- **並行波**: 無
- **執行方式**: Subagent-Driven
- **依據**: `.claude/dev/2026-07-31_gpt-review-k1k5.md`（GPT-5 總檢）；交班書 `.claude/dev/2026-07-31_handoff-k6.md`
- **本 repo 無 intake kit**：未涵蓋決策記本檔「📋 未涵蓋決策」區；收波 gate＝`bash kit/tests/run.sh` 全套＋`bash kit/tools/kit-audit.sh` exit 0（無 scripts/hooks/wave-gate.sh）
- **cwd 紀律**: session 錨定 dotfiles repo，shell cwd 每次重設——所有指令一律帶絕對路徑前綴 `cd /Users/chunn/projects/skills/.claude/worktrees/wave-k55-harden && ...`

## 狀態：✅ 完成

## 🎯 Goal Condition

Wave k55-harden 全部完成。完成標準：
- [x] (1) 所有工作項合約指令全部跑過，輸出貼在 wave-k55-harden.md 對應合約結果欄——佐證：工作項表 9/9 合約結果欄皆為 controller 本輪親跑輸出（各 commit hash 並列）
- [x] (2) 每項覆蓋 happy path + edge case + 誤用場景（合約內列的全部跑過）——佐證：各項合約逐條有紅/綠 fixture 實跑（見合約結果欄與 ledger review 條目）；本波無資料管線項，守恆場景=task-8 assertion 守恆對帳（878+13=891 差 0）
- [x] (3) 品質閘門通過——佐證：🔒 sharp-edges 2 輪（task-6/7）0 high/critical、findings 當場修；收波 gate FULL_SUITE=891/0 EXIT=0（標記 K55-GATE-112828）＋ kit-audit 43/43 EXIT=0；🎨 UX 不適用（無前端項）
- [x] (4) 總計畫 witty-hugging-sphinx.md K5.5 行標記完成——佐證：收尾 docs commit（merge 後更新）
- [x] (5) 「📋 未涵蓋決策」區已填寫——佐證：下方 3 筆（M2/M3 既定 K7、tsx 環境補跑、TWINS pattern 教訓升級候選）
- [x] (6) 狀態已更新「✅ 完成」——佐證：本檔頂部狀態行
- [x] (7) 唯一停點制——本波實際停點清單：①Phase 0 Align 問題（合法停點 1）②Phase 4 範圍確認＋harness/merge-train 納入裁定（合法停點 2，AskUserQuestion 一次問完）。此外全程未停下等待輸入；Phase 2.5 訪談未觸發、無破壞性操作停點。逐一對照合法清單：2/2 合法，0 違規
約束：無其他並行波。合約輸出必須是本輪實際跑出的，不可憑記憶填。——遵守：所有數字皆本輪 tool 輸出。

## 🤖 工作項

| # | 功能 | 狀態 | 合約指令 | 合約結果 | commit |
|---|------|------|---------|---------|--------|
| 1 | 宣告契約語意修（空值≠缺 key＋merge_prep_cmd 例外＋health.d 標註） | ✅ | `bash kit/tests/run.sh common.sh` | controller 親跑：58/0 EXIT=0；call site 22 處清點 A組9 B組13 無需改傳法；merge-prep 空值迴歸 SKIP exit 0；浮動修 lock_docs_exempt seed（e3dae74，見 ledger） | 7b38079 |
| 2 | provenance 語意重做（歷史 blob＋upstream_status＋欄位驗證＋anchor 統一＋日期修正） | ✅ | `bash kit/tests/run.sh kit-audit.sh` + `manifest.sh` | controller 親跑：41/0＋8/0 EXIT=0；真帳 audit EXIT=0 inspected:40；07-31 殘留=0；歷史 blob 20/20 相符無帳錯 | 8fe11c2 |
| 3 | canary↔gates.d 對帳＋clean inspected | ✅ | `bash kit/tests/run.sh canary-harness.sh` | controller 親跑：31 assertions, 0 failed, EXIT=0；紅 fixture 四態（缺fixture/空.skip/clean inspected:0/gates.d缺席SKIP）implementer log 逐條有 | f95d17e |
| 4 | pathspec 解析零條假 0 | ✅ | `bash kit/tests/run.sh pathspec-liveness.sh` | controller 親跑：24/0 EXIT=0；紅 case 訊息含來源檔＋零條指示；兜底不變量 inspected:0→exit 1 獨立實證 | 3f6ea31 |
| 5 | wave-gate stamp/preauth 失敗不遮蔽 | ✅ | `bash kit/tests/run.sh wave-gate.sh` | controller 親跑：44/0 EXIT=0；收口三處 || true 移除實證（grep 僅剩說明註解）；stamp/preauth 紅 case 訊息可區分於 gate 紅 | 4dc828f |
| 6 | consumer contract（contract_version＋pin＋kit-doctor） | ✅ | `bash kit/tests/run.sh kit-doctor.sh` | controller 親跑：33/0→sharp-edges 修後 37/0 EXIT=0；六檢查項紅 fixture 各一實證；pin 三態＋最小長度；audit 回綠 41/41 | 6fcf96f＋1df19ea |
| 7 | 隔離 parity harness（必修①，最大項） | ✅ | `bash kit/tests/run.sh parity-harness.sh` | controller 親跑：42/0→sharp-edges 修後 45/0 EXIT=0；核心紅（同樹假等價→隔離必 DIFF）實證；五面向各有直接命中；shim-probe 四項 round-trip；真 Husky hooksPath 攔截 | 2829490＋b6fdf5a |
| 8 | 測試 harness 隔離（per-case 子 shell＋去永真補數＋baseline 改寫需明示旗標） | ✅ | `FULL_SUITE=1 bash kit/tests/run.sh` | controller 親跑（標記 K55-GATE-112828）：891/0 EXIT=0；baseline 唯讀 diff 實證 UNCHANGED；守恆對帳 30/31 case 前後全同、3 筆差異逐筆解釋（878+13=891 差 0）；永真 5 處→SKIP 明示 | e30b118 |
| 9 | merge-train subject pattern 參數化（去 dfaa 寫死假設） | ✅ | `bash kit/tests/run.sh merge-train.sh` | controller 親跑：40/0 EXIT=0（30 舊＋10 新）；三支消費者各留歷史預設（closure-lock-guard 原只認 worktree-*，不統一——零迴歸）；四支 selftest 全綠 | d99b2c6＋bf95ae8 |

### 🤖-1 驗證合約（宣告契約語意修）
1. `cd <WT> && bash kit/tests/run.sh common.sh` → passed，新增 case：
   - key 存在但空值（`key: ""`）→ `kit_decl_get` 回空字串（降級語意）
   - key 完全缺席 → 回 default
   - 兩態輸出可區分（紅→綠各一 assertion）
2. 全 call site 清點：`grep -rn "kit_decl_get" kit/ --include="*.sh" --include="*.ts"` 逐一核對語意遷移（哪些依賴舊行為需改 default 傳法），清點表貼本檔
3. declaration-formats.md：merge_prep_cmd 明列為唯一 `bash -c` 受信任例外（`grep -n "受信任例外\|唯一例外" kit/references/declaration-formats.md` 命中）
4. declaration-formats.md：health.d 段標註 K7 未交付（grep 命中）
5. 誤用：空 merge_prep_cmd 宣告餵 wave-merge-prep → 輸出含 `SKIP(無 merge_prep_cmd 宣告)`、exit 0（行為不變迴歸）

### 🤖-2 驗證合約（provenance 語意重做）
1. schema：provenance.tsv 加第 9 欄 `upstream_status`（active/retired/successor；kit:original 行填 `-`），40 行全遷移；NF 檢查 8→9 同步改（kit-audit.sh＋tests/cases/manifest.sh 兩處）
2. upstream 驗證改歷史 blob：`git -C <上游repo> show <upstream_commit>:<path>` hash 比對；fixture case：歷史 blob 相符但 live 檔已改 → 不報漂移（這正是 K6 shim 後的常態）；`upstream_status=active` 才附帶 live 比對（分開報告，不混 hash）
3. 欄位驗證紅 fixture 各一：mode ∉ {verbatim,parameterized,extracted-pattern}／absorbed 晚於今日／hash 欄非 `sha256:[0-9a-f]{64}` 且非 `-`／kit_path 重複 → exit 2
4. anchor 統一：manifest.sh 對 `kh=-` 的 anchor 列跳過實算；新增 anchor 列 fixture 綠 case（audit 與 test 契約一致）
5. 日期守恆：`awk -F'\t' '!/^#/ && $6=="2026-07-31"' kit/manifest/provenance.tsv | wc -l` → 0（28 筆修正為 2026-07-30）
6. 真帳實跑：`bash kit/tools/kit-audit.sh` → exit 0、`inspected:40`
7. `bash kit/tests/run.sh kit-audit.sh` ＋ `bash kit/tests/run.sh manifest.sh` → 0 failed

### 🤖-3 驗證合約（canary↔gates.d 對帳）
1. 對帳：gates.d/tier{A,B}.d 有 stub 但 canary.d 無同名 fixture → FAIL 列出 gate 名（紅 fixture case）；全對帳 → 綠
2. 豁免機制 fail-closed：豁免需逐 gate 明示宣告（實作自決：marker 檔或 kit.yaml key），未宣告缺 fixture 一律紅
3. clean fixture 驗 `inspected:N>0`：clean 輸出 inspected:0 → 紅（新 case）
4. `bash kit/tests/run.sh canary-harness.sh` → 0 failed；既有 canary 綠 case 不變

### 🤖-4 驗證合約（pathspec 假 0）
1. mutation 紅 case：宣告目標存在但解析出 0 條 pathspec → exit 1、訊息指明來源檔
2. 既有綠 case 全數不變
3. 不變量：輸出 `inspected:0` 時 exit 必 ≠0（assertion 直接驗這條）
4. `bash kit/tests/run.sh pathspec-liveness.sh` → 0 failed

### 🤖-5 驗證合約（wave-gate stamp/preauth）
1. 紅 case：stamp／preauth 寫入失敗（唯讀目錄或假 regate script 模擬）→ 輸出明示 FAIL、exit ≠0（現行 `|| true` 移除）
2. 綠 case：寫入正常 → PASS 行為與現行一致（stamp＋conditional-release／preauth＋鎖保持訊息）
3. `bash kit/tests/run.sh wave-gate.sh` → 0 failed

### 🤖-6 驗證合約（consumer contract）
1. templates/kit.yaml 加 `contract_version`＋`kit_pin`（commit hash）；declaration-formats.md 寫版本協商與 K6 凍結語意（grep 斷言）
2. 新 kit/tools/kit-doctor.sh 紅 case 各一：未知 contract_version／恆綠 example gate（stub 與模板字面相同）／空 canary.d／gate↔fixture 不對帳（重用 🤖-3 邏輯）／必要欄位空降級 → exit ≠0
3. 綠 case：完整宣告 → exit 0＋`inspected:N>0`（防假 0 同族）
4. 🔒 `/sharp-edges` 掃 kit-doctor.sh（解析專案宣告檔的輸入面）→ 0 high/critical
5. `bash kit/tests/run.sh kit-doctor.sh` → 0 failed

### 🤖-7 驗證合約（隔離 parity harness）
1. 核心紅 case（selftest）：構造狀態型腳本對（寫 lock/stamp/改 baseline），同樹串行雙跑產生假等價；隔離雙 clone 從相同 git state 起跑 → harness 必報 DIFF
2. 對帳五面向各有 assertion：exit code／正規化 stdout+stderr（路徑、時間戳正規化）／working tree 副作用 diff／baseline+generated files／lock+stamp+preauth 狀態
3. shim 三行傳遞 probe：`$@`（含帶空白與引號參數）／cwd／env／exit code 四項 round-trip 全等 case
4. 真 Husky：scratch repo 實裝 `.husky/`，由真 git hook 觸發跑一輪（非直接呼叫腳本）
5. session restart／settings.json 接線不可腳本化 → 報告模板列 UNVERIFIABLE 手動 checklist（grep 斷言模板存在該區）
6. 常駐性：case 進 tests/cases/parity-harness.sh 常駐可重跑（GPT §4.1）
7. `bash kit/tests/run.sh parity-harness.sh` → 0 failed

### 🤖-8 驗證合約（測試 harness 隔離）
1. per-case 隔離：每個 case 在子 shell 執行，case A export 的變數/函式在 case B 不可見（污染偵測 case：故意在 A 設變數、B 斷言不存在）
2. 去永真補數：全庫掃描恆真 assertion（`assert_eq "x" "x"` 型與無條件通過型），逐一改為真斷言或刪除，清點表貼本檔
3. baseline 改寫需明示：`FULL_SUITE=1` 跑完不再自動改寫 assertion-baseline.txt；改寫需 `UPDATE_BASELINE=1` 明示旗標（紅 case：無旗標時檔案內容不變）
4. 守恆對帳：改造前後 assertion 總數逐 case 對照表（差異逐筆解釋——防「隔離後某 case 靜默少跑」）
5. `FULL_SUITE=1 bash kit/tests/run.sh > /tmp/k55-suite.log 2>&1; echo EXIT=$?` → EXIT=0，總數 ≥ 改造前基線

### 🤖-9 驗證合約（merge-train subject pattern 參數化）
1. kit.yaml 加宣告 key（如 `wave_branch_patterns`／`wave_merge_subject_patterns`），預設值＝現行為（worktree-*/wave/），dfaa 零影響
2. 紅→綠 case：宣告 `feature/*` pattern 後，feature branch merge subject 被辨識為 wave merge；未宣告時照舊
3. 迴歸：merge-train 既有六支 case 全綠
4. `bash kit/tests/run.sh merge-train.sh` → 0 failed

## 🔒 安全審計結果
| 工作項 | Skill | Findings | High/Critical | 狀態 |
|--------|-------|----------|--------------|------|
| 🤖-6 | sharp-edges | 2（1 medium：pin 無最小長度；1 low：零模板靜默過） | 0 | ✅（兩 findings 當場修 1df19ea） |
| 🤖-7 | sharp-edges | 1（medium：--env 缺 = 假 EQUIV） | 0 | ✅（當場修 b6fdf5a） |

## 🎨 UX 審計結果
不適用（無前端工作項）。

## 📋 漏項掃描
本 repo 無 docs/requirements/。回掃 GPT 總檢全文（本波 requirements 等價物）：三必修①②③全交付（task-7/6/2）；附修六項全交付（task-3/4/1×2/2/1）；§1.4 merge-train（task-9）與 §4.5 harness（task-8）經使用者 Phase 4 裁定納入並交付。GPT 文中未排波項：§4.2「完整消費者 E2E（kit-init→宣告→真 Husky→wave gate→merge→pre-push 整條）」——K6 dfaa 遷移本身即此路徑的真實執行（雙跑+shim 驗證），列 K6 checklist 不另開工作項。無漏項。

## 📋 未涵蓋決策
| # | 決策 | 來源 | 為何本波不做 |
|---|------|------|-------------|
| 1 | 安全 advisory M2（matrix_dir 白名單驗證）、M3（marker 缺尾拒寫） | K5 安全審計 | 交班書既定：使用者已裁定排 K7 |
| 2 | .ts shim 退役前須在有 tsx 的環境補跑 shim-probe（本機 tsx 缺席，ts 子測 SKIP 明示未驗） | task-7 交付註記 | 外部依賴不可得（本機無 tsx）；K6 Step C 前置檢查項 |
| 3 | ERRATA 升級候選：「TWINS 掃描 grep pattern 須涵蓋字面變體（`> "${var}"` 與 `> "$(fn)"`）」——一般化為 CLAUDE.md 稽核邏輯 TWINS 條款補一句 | 本波 ERRATA Q3 判定 | 屬 CLAUDE.md 修訂，跨波常駐規則，使用者裁定落點 |
