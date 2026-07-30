# GPT-5 K1-K5 架構總檢（2026-07-31，K6 前跨廠牌審查）

結論：`kit/` 已具備扎實骨架，但目前是 **K6 有條件 No-Go**；直接進 shim 切換會遇到三個結構性問題：狀態型腳本無法安全雙跑、消費者沒有版本契約、K6 會讓 provenance 的 live-upstream 稽核失去語意。

## 1. 架構層

整體切分方向正確，但實際上不是單純「引擎／宣告」，而是：

```text
kit framework + project executable plugins + project config
```

主要弱點：

1. **沒有 engine／declaration 版本協商。**  
   `kit_root` 只是資訊欄，沒有 `contract_version`、最低相容版本或 kit commit pin；中央 kit 一更新，所有消費者行為立即改變，無法重現某次 dfaa commit 當時使用的品質系統。[kit.yaml](/Users/chunn/projects/skills/kit/templates/kit.yaml:11)

2. **「空值＝降級」不成立。**  
   文件宣告空值會降級，但 `kit_decl_get` 把空值與缺 key 都轉成 default；例如空的 `matrix_dir` 仍會變成 `docs/rtm/matrix`，空的 `baseline_file` 仍是預設檔。[declaration-formats.md](/Users/chunn/projects/skills/kit/references/declaration-formats.md:7) [common.sh](/Users/chunn/projects/skills/kit/lib/common.sh:110)

3. **「不從資料檔執行命令字串」與實作矛盾。**  
   `merge_prep_cmd` 正是從 YAML 讀出後交給 `bash -c`。應把它明列為唯一受信任例外，或改成 executable prep stub。[declaration-formats.md](/Users/chunn/projects/skills/kit/references/declaration-formats.md:3) [wave-merge-prep.sh](/Users/chunn/projects/skills/kit/gates/merge-train/wave-merge-prep.sh:36)

4. **仍有 dfaa 工作流假設。**  
   Merge train 只認 `worktree-*`／`wave/` merge subject；第二個專案若用 `feature/*`、squash merge 或不同訊息格式，可能直接不被視為 wave merge。[wave-regate-guard.sh](/Users/chunn/projects/skills/kit/gates/merge-train/wave-regate-guard.sh:21)

5. **文件包含尚不存在的契約。**  
   `health.d` 被描述成已有 11 節引擎骨架，但 repo 裡沒有相應 engine、template 或 installer。第二個消費者照文件操作會直接落空。[declaration-formats.md](/Users/chunn/projects/skills/kit/references/declaration-formats.md:79)

## 2. K6 遷移風險

Claude 系最容易共同盲視的是把「雙跑」當成純函式比對，但這批腳本大量帶狀態：

- `wave-gate`／merge-train 共用 closure lock、stamp、preauth。
- `preauth check` 會消耗 preauth、寫 stamp、釋放鎖。
- `merge_prep` 會改依賴與 generated files。
- `ratchet --tighten` 會改 baseline。
- 舊版先跑可能替新版修好環境，造成新版假等價。

因此不能在同一 worktree 依序跑舊／新後比較。必須在相同 commit 的兩個隔離 clone/worktree，各自從相同 git-common state 開始，對帳：

- exit code；
- 正規化後 stdout/stderr；
- working tree／baseline／generated files；
- lock、stamp、preauth；
- 實際 Husky `sh -e` 與 Claude session restart 後的 hook 行為。

另外兩個切換洞：

- `wave-gate` 即使 stamp／preauth 寫入失敗仍用 `|| true` 報整體 PASS，K6 路徑或權限問題可能直到 push 才曝光。[wave-gate.sh](/Users/chunn/projects/skills/kit/engines/wave-gate.sh:296)
- 保持 `.husky/*`／`.claude/settings.json` 路徑不動是合理策略，但 static wiring check 只能證明檔案存在，不能證明三行 shim 保留 `$@`、cwd、環境、signal 與 exit code；Claude settings 的新接線也必須重開 session 才算驗到。

## 3. Manifest／audit

目前狀態是乾淨的：我唯讀重算了 40/40 筆 kit hash、20/20 筆可比對 upstream hash，皆相符；所有 shell 亦通過 `bash -n`。

但長期模型會腐爛：

1. **K6 會讓 upstream 漂移成常態。**  
   Audit 比對的是 dfaa 工作樹現檔；K6 將原腳本換成 shim 後，相關列必然報 drift。雖然 ledger 有 `upstream_commit`，程式卻讀成 `_uc` 後完全不用。[kit-audit.sh](/Users/chunn/projects/skills/kit/tools/kit-audit.sh:67)

2. **三種 mode 只是註解。**  
   `mode`、commit、日期、hash 格式、upstream 格式、重複 `kit_path` 都未驗證；任何八欄字串都可進帳。

3. **Anchor 契約與測試衝突。**  
   Audit 規定 `#anchor` 跳過 hash，但 manifest regression test 對所有資料列無條件實算 hash；真正加入 `kh=-` 的 anchor 列會被測試打紅。[kit-audit.sh](/Users/chunn/projects/skills/kit/tools/kit-audit.sh:82) [manifest.sh](/Users/chunn/projects/skills/kit/tests/cases/manifest.sh:34)

4. **已經有資料品質警訊。**  
   目前 28 筆 `absorbed` 日期是 `2026-07-31`，晚於本輪日期 `2026-07-30`，現有 validator 完全不會發現。[provenance.tsv](/Users/chunn/projects/skills/kit/manifest/provenance.tsv:15)

正確方向是：provenance hash 應驗 `git show <upstream_commit>:<path>` 的歷史來源；live upstream 另設 `active/retired/successor` 狀態，不要混成同一個 hash。

## 4. 測試品質

優點是負向 fixture、selftest、fail-closed 與精確 `inspected:N` 已有一致思維；但 732 assertions 不能等同整合覆蓋。

系統性盲區：

1. **沒有持續存在的 dfaa parity／K6 cutover case。**  
   測試只在註解提到 K5 parity，沒有可重跑的舊版對新版契約。

2. **沒有完整消費者 E2E。**  
   缺少「kit-init → 正式宣告 → 真 Husky → wave gate → merge → pre-push」整條路徑。

3. **Canary 不保證每支 gate 都有 fixture。**  
   引擎只列舉 `canary.d`，不對帳 `gates.d`；一支無 fixture 的 gate 可永久漏測。Clean fixture 也沒有驗自己的 `inspected:N>0`。[canary.sh](/Users/chunn/projects/skills/kit/engines/canary.sh:84)

4. **Pathspec 仍有假 0。**  
   宣告目標存在但解析出零條 pathspec 時，會印 `inspected:0` 後 exit 0；測試沒有此 mutation case。[pathspec-liveness.sh](/Users/chunn/projects/skills/kit/engines/pathspec-liveness.sh:475)

5. **Harness 數字可產生 false confidence。**  
   所有 case 被 source 到同一 shell，export／函式／變數可跨 case 污染；缺 runtime 時又用永真 assertion 補數。總數 baseline 只能抓總量下降，不能抓「某 case 少 20 個、另一 case 新增 20 個」。此外完整 suite 會自行改寫 baseline。[run.sh](/Users/chunn/projects/skills/kit/tests/run.sh:55)

本輪因環境唯讀、suite 需要建立暫存檔且可能改 assertion baseline，未實跑完整 732 assertions。

## 5. K6 前三大必修

1. **建立 K6 隔離 parity harness，禁止同 worktree 串行雙跑狀態型腳本。**  
   納入真 Husky、session restart、lock/stamp/preauth、檔案副作用，以及 `inspected:0`／缺 canary mutation。約 1–2 天。

2. **新增 consumer contract gate。**  
   `kit.yaml` 加 `contract_version` 與 kit commit/version pin；`kit doctor` 應拒絕未知版本、恆綠 example gate、空 canary、gate/fixture 不對帳及必要欄位降級。K6 期間凍結 kit revision。約 1 天。

3. **在替換 dfaa upstream 前重做 provenance 語意。**  
   以 `upstream_commit` 的歷史 blob 驗來源，另外記 live successor／retired；同時驗 mode、hash、日期、重複 key，統一 anchor 規則。約半天至 1 天。

確切模型：GPT-5（Codex）
