# Wave k55-harden Ledger（append-only，新條目往下加）

## 流水帳
- [開波] Phase 0-2：registry 乾淨（僅 wave-INDEX.md）；本 repo 無 intake kit（來源 1/3 無產出，來源 3 fallback 掃延後決策無命中）；kit/ 無真 TODO；兩輪掃描收斂
- [開波] 諮詢點 1 跳過：主 session 已是 Fable（fable-consultation.md 既定降級）
- [開波] Phase 4：使用者裁定 harness 隔離＋merge-train 參數化皆納入 → 9 項
- [開波] EnterWorktree 原生工具拒絕（session 錨定 dotfiles repo）→ 手動 worktree＋絕對路徑紀律（shell cwd 每指令重設，一律帶 cd 前綴）
- [開波] worktree 基底 bc6fd25 = main HEAD（無落後）

- [開工] 基線：FULL_SUITE run.sh → 732 assertions / 0 failed / EXIT=0（/tmp/k55-baseline.log）；kit-audit → 同步:40 inspected:40 EXIT=0
- [開工] Task 系統鏡像完成（#1-#9）
- [C1] 派工 task-1 implementer（繼承 session 模型）、task-2 implementer（繼承；brief 落檔 .superpowers/sdd/task-2-brief.md）、task-3 implementer（sonnet）——並行背景；ScheduleWakeup 1800s fallback 已排
- [C1] [自主決策] task-2 屬大項（schema 變更），諮詢點 3 因主 session 已是 Fable 跳過；設計方向（9 欄 upstream_status＋歷史 blob）已在 Phase 4 合約呈現並經使用者核可，視同 design review 過，不另設停點。被否決替代案：live 狀態塞 mode/notes 欄（混語意，GPT 明示反對）。可逆性：schema 遷移單 commit 可 revert

- [C1] task-3 commit f95d17e，controller 親跑 review：31/0 EXIT=0，diff 4 檔範圍內——✅。對帳函式 canary_reconcile_gates 已抽 lib（task-6 重用）。命名規則裁定：tierA/NN-name.sh → canary.d/tierA-name/

- [C1] task-1 commit 7b38079，controller 親跑 review：58/0 EXIT=0，kit_decl_get 兩態實作正確——✅。升級殘留：installer seed lock_docs_exempt "" 在新語意下=關閉豁免（變嚴）
- [C1] [浮動修] lock_docs_exempt 判定無第二種合理選擇（存量消費者=0，出廠意圖=吃引擎預設）→ controller inline 修：installer 不 seed＋template 註解化＋declaration-formats 措辭；installer.sh 29/0、merge-train.sh 30/0 迴歸綠（e3dae74）
- [C1] task-2 commit 8fe11c2，controller 親跑 review：kit-audit.sh 41/0＋manifest.sh 8/0、真帳 EXIT=0 inspected:40、07-31 殘留 0——✅。歷史 blob 20/20 相符（upstream_sha256 無帳錯）；kit_sha256 校正 5 行留痕
- [C1] kit-audit 抓到浮動修沒記帳（機制自證有效）→ controller 統一記帳 wave-gates.sh 新 hash（6e7fdf9）
- [C1] 對帳注意：task-1 commit 7b38079 掃進了 task-2 的 declaration-formats.md manifest 節編輯（task-1 pathspec 含該檔、未排除他人 staged hunk）——內容正確已入 history，歸屬混淆記錄備查
- [C2] 派工 task-4 implementer（sonnet）、task-5 implementer（sonnet）、task-6 implementer（繼承；brief .superpowers/sdd/task-6-brief.md）——並行背景

- [C3備料] task-7 大項三件套：design＋brief 已落 .superpowers/sdd/。[自主決策] 諮詢點 3 跳過（主 session 已是 Fable）；design 不另設使用者停點——核心做法（隔離雙 clone+五面向）已在 Phase 4 合約經使用者核可，design 只是細化。被否決替代案記 design doc 內。可逆性：純新增工具檔，revert 單 commit

- [C2] task-4 commit 3f6ea31，controller 親跑 review：24/0 EXIT=0，diff 2 檔範圍內——✅。修法含兜底不變量（grand_total=0→exit 1 獨立於目標層判定）

- [C2] task-5 commit 4dc828f，controller 親跑 review：44/0 EXIT=0，收口 || true 全移除——✅。加了 WAVE_GATE_{REGATE,LOCK}_SH_OVERRIDE 測試 seam（真 regate script 對寫入失敗也不回非 0，該檔在 task-5 停止範圍外未動——K6 checklist 留意）

- [C2] [浮動修] regate-guard stamp/preauth 裸重導向 fail-closed（TWINS of task-5，ae0d060）；selftest 0＋merge-train 30/0＋wave-gate 44/0 迴歸綠；manifest 同 commit 記帳
- [C2] manifest 記帳 task-4/5 引擎演化（8393cf6）
- [C2] task-6 commit 6fcf96f，controller 親跑 review：33/0 EXIT=0；🔒 sharp-edges 實跑（四階段）：2 findings 0 high/critical，當場修（pin 最小長度 7＋零模板 FAIL，1df19ea，case 擴 37/0）；kit-doctor 入帳（08852ed）audit 回綠 41/41
- [C3] 派工 task-7 implementer（繼承；brief+design .superpowers/sdd/）、task-9 implementer（sonnet）——並行背景。task-8 動 tests/run.sh＋掃全 case 檔，與 7/9 產出衝突 → 排 7/9 收工後單獨跑（守恆對帳也需要 case 終態）

- [C3] task-9 commit d99b2c6，controller 親跑 review：40/0 EXIT=0，6 檔範圍內——✅。實作裁定合理：三支消費者各留歷史預設（統一預設會改 closure-lock-guard 現行為）
- [C3] [浮動修] TWINS 補掃第三處：regate-guard 自動補戳裸重導向（ae0d060 的 grep pattern 漏抓 `> "$(stamp_path)"` 形式）——寫入失敗會銷毀 preauth 又謊報補戳；修＋全庫終掃 0 殘留＋manifest 記帳 task-9 三支（bf95ae8）
- [C3] audit 現殘留無帳=tools/{parity-run,shim-probe}.sh（task-7 in flight 產物，收工後記帳）

- [C3] task-7 commit 2829490，controller 親跑 review：42/0 EXIT=0，4 檔全新增——✅。設計內微調合理（state-glob 加 .git/wave-*、diff --cached、126/127→exit 2）。manifest 記帳兩支新工具（a2f4959）audit 綠 43/43
- [C3] 🔒 sharp-edges 審 parity 工具：1 finding medium——--env 缺 = 被 env 當指令、雙邊對稱跑錯＝假 EQUIV（K6 閘門最糟失效向）；當場修強制 KEY=VAL（b6fdf5a）case 45/0
- [C3] K6 checklist 追加：.ts shim 退役前須在有 tsx 環境補跑 shim-probe（本機 tsx 缺席 SKIP 明示）
- [C3] 派工 task-8 implementer（繼承）——單獨跑（動 tests/run.sh＋掃全 case 終態）

- [收尾] task-8 commit e30b118，controller 親跑 review：FULL_SUITE 891/0 EXIT=0（標記 K55-GATE-112828）、baseline 唯讀 diff 實證、守恆對帳差 0——✅
- [收尾] 品質閘門：FULL_SUITE 891/0＋kit-audit 43/43 皆綠；🔒 兩輪 sharp-edges 0 high/critical；UX 不適用
- [收尾] ERRATA 升級判定：①zsh path 覆寫——AGENTS.md 鐵則 5 已載，屬已升級規則的執行失誤，Q1 不過（本波內未再犯）→ 丟掉；②TWINS pattern 太窄——Q1 過（同型漏抓 1/3 實發）Q2 難機器化 Q3 過（改變掃描行為）→ 升級候選記 dashboard 未涵蓋決策 #3，使用者裁定落點
- [收尾] goal condition (1)-(7) 全勾（佐證見 dashboard 🎯 區）；開始合併協助

## ERRATA（controller 自我教訓，永久有效）
- 教訓：TWINS 掃描的 grep pattern 要涵蓋變體形式（`> "${var}"` 與 `> "$(fn)"`）——第一輪只掃到 2/3 處，字面 pattern 太窄
- 教訓：zsh `while read path` 覆寫 PATH（AGENTS.md 鐵則 5 實踩）——迴圈變數一律用 wt_dir 等任務名

## 暫停意圖
（使用者下節流/暫停指令時寫入；「可以繼續」時清除。有內容時不派新工作）

## RESUME POINTER（隨進度更新，下個 session 照抄接手）
1. cd /Users/chunn/projects/skills/.claude/worktrees/wave-k55-harden
2. git log --oneline -10 + git status 核實真實狀態
3. 讀 wave-k55-harden.md 比對，不一致以 git 修正文件
4. 下一步：跑基線 FULL_SUITE=1 bash kit/tests/run.sh，然後派 C1（🤖-1〜3）
