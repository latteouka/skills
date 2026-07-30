# Kit 宣告檔規格

專案側宣告全部住 `<project>/.claude/kit/`（進版控）。引擎住 kit、專案只放宣告——kit 更新全專案立即受益。可執行邏輯（counter、gate stub）一律是版控內可 review 的 bash 檔，不從資料檔執行命令字串（沿用 ratchet 既有設計裁定）。唯一受信任例外：`kit.yaml` 的 `merge_prep_cmd`（wave-merge-prep.sh 以 `bash -c` 執行宣告字串）——宣告者＝repo 擁有者，kit.yaml 進版控可 review，與 hook 腳本同信任層級。

## kit.yaml

主宣告檔，flat-key YAML（與 intake.config.yaml 同慣例，`kit_decl_get` grep-based 解析，不引入 yq）。欄位留空 = 該功能降級（引擎輸出必須明示降級）。

```yaml
kit_root: "/Users/x/projects/skills/kit"   # 安裝時寫死絕對路徑
modules: "intake backlog rtm wave-gates ratchet"   # 已安裝模組（空白分隔）

# --- ratchet
baseline_file: "quality-baseline.json"     # repo-root 相對；引擎以 BASELINE_FILE 原名提供給 counter
slow_counters: ""                          # 空白分隔；compare 模式跳過（RATCHET_FULL=1 強制跑）。dfaa 遷移必填 "eslint-warnings"

# --- wave-gate
app_workspace: "apps/web"                  # Tier B 指令 cwd；無 monorepo 留空
merge_prep_cmd: "pnpm install --frozen-lockfile && pnpm prisma generate"
tool_readiness: "eslint tsc vitest"
base_branch: "main"                        # merge-train 六支+wave-gate 統一消費（K2 裁定，取代早稿 regate_branch）
# lock_docs_exempt: "*.md|.claude/dev/*"   # closure-lock-guard docs 豁免 glob（| 分隔）；缺鍵=引擎預設、宣告空值=關閉豁免——預設不寫入

# --- rtm
matrix_dir: "docs/rtm/matrix"
status_enum: "implemented partial divergent planned na"   # PASS 統計行欄序＝宣告序
impl_path_bases: ". apps/web apps/web/src"                # check7 suffix-match 基準
rtm_nonpath_tokens: "Next.js Node.js"                     # impl_details 非路徑 token 白名單（dfaa 遷移補 sigma.js 等）
rtm_notes_required: "divergent"                           # 哪些 status 必填 notes
rtm_detail_specs_required: "implemented partial divergent"
rtm_impl_details_required: "implemented partial"
reqsync_anchors: "apps/web/src/server apps/web/prisma/schema"
reqsync_excludes: "__tests__ migrations"                  # 路徑段名比對
```

與 `intake.config.yaml` 的關係：intake.config.yaml 維持原位原格式（intake 模組私有）；kit.yaml 是跨模組宣告。`--rtm` 安裝時把 `matrix_dir` 回填 intake.config.yaml 的 `spec_layer`、rtm-check 指令回填 `spec_check`，接通 /triage 對帳線。兩檔長期不合併。

## counters.d/

ratchet counter 宣告，每 counter 一檔 `<name>.counter.sh`，檔名即 counter 名（函式名 = `count_` + 名稱 `-`→`_`）、須與 baseline JSON 的 `counters.<name>` 鍵對應（引擎雙向核對：有鍵無檔或有檔無鍵皆 fail-closed）。

補充契約（K34 凍結）：
- **counter 檔只保證拿到 `PROJECT_ROOT` 與 `BASELINE_FILE`** 兩個環境變數；禁 `set -e`／禁 `exit`（sourced 進引擎）
- **共用 helper**：`NN-*.lib.sh` 先按字典序 source，不參與名稱推導與雙向核對
- **scope-conditioning 選配**：定義 `inputs_<name>()`（stdout 一行一 pathspec）→ compare 模式 push range 未碰輸入時沿用 baseline；未定義＝永不 skip
- `--count <name>` 單獨取值（`--count-<name>` 糖衣等價）

```bash
#!/usr/bin/env bash
# counter 契約：定義 count_<name>()，stdout 輸出單一非負整數；失敗 return 1（引擎 fail-closed）。
count_e2e_non_acceptance() {
  local n
  n="$(find "${PROJECT_ROOT}/apps/web/tests/e2e" -type f -name '*.spec.ts' ! -path '*/acceptance/*' | wc -l | tr -d ' ')" || return 1
  case "${n}" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "${n}"
}
```

## gates.d/

wave-gate 的 tier gate stub，`gates.d/tierA.d/NN-*.sh`（快篩）與 `gates.d/tierB.d/NN-*.sh`（重型）。

- `NN-` 前綴決定字典序執行順位（dfaa A1..A5/B1..B5 直譯 10-…50-）
- 每檔可執行，cwd＝repo 根；環境變數：`PROJECT_ROOT`、`APP_WORKSPACE`、`GATE_PHASE`（收尾|baseline）、`TIER_B_ALREADY_RED`（tier 內已有紅燈旗標）
- **exit code 唯一介面**；stdout 前綴 `inspected:N`——**有 canary.d fixture 的 gate 必填**（三斷言之 3），無 fixture 的 gate 選填
- 條件觸發（如僅 source 變更時跑）寫在 stub 內自行 `exit 0` ＋印 `SKIP(原因)`；紅燈早退、baseline 不早退、re-gate 戳記、鎖——全在引擎骨架，stub 無感

## canary.d/

gate 自測 fixture。`canary.d/<gate>/` 契約：

- `run.sh` 必要——引擎把 fixture 樹複製進 scratch 後以 scratch 為 cwd 執行；exit code = gate 結果；stdout 須含 `inspected:N`
- `violation/` 與 `clean/` 必要——違規／語意相近但合法的 fixture 樹（`*.fixture` 副檔名遮蔽自動還原——防 violation fixture 被它要測的 gate 在 commit 時攔下）
- `git` 選配 marker 檔——存在＝引擎先建 scratch git repo + seed 字面名 origin/main 分支再複製 fixture
- `setup.sh` 選配——git 拓撲建構（scratch 內、fixture 複製後、run.sh 前執行）

引擎（`engines/canary.sh`）逐 gate 三斷言：violation 必紅、clean 必綠、`inspected:N` N>0——缺一即 FAIL（防「gate 跑了 exit 0 但檢查 0 個檔」）；三斷言之 3 對 violation 與 clean 兩分支**都**驗（K5.5 修：clean 分支若無 `inspected:N` 或 `inspected:0`，同樣 FAIL——否則「clean 跑了 0 個檢查」與「clean 真通過」在輸出上無法區分）；canary.d 缺失或零 gate = exit 2 fail-closed。

### gates.d↔canary.d 對帳（K5.5 GPT §4.3）

canary.d 只列舉自己已有的目錄——一支 `gates.d` 有 stub 但沒人補 canary fixture 的 gate，永遠不會被三斷言測到，「漏測」與「測過全綠」在引擎輸出上長得一樣。`engines/canary.sh` 反過來，以 `gates.d/tierA.d/` 與 `gates.d/tierB.d/` 的 stub 清單為準逐一核對 canary.d 是否有對應 fixture（跑在 canary.d 存在性檢查之後、三斷言主迴圈之前）：

- **命名對應規則**：`gates.d/tierA.d/NN-<name>.sh` → `canary.d/tierA-<name>/`；`gates.d/tierB.d/NN-<name>.sh` → `canary.d/tierB-<name>/`（去字典序 `NN-` 前綴與 `.sh` 副檔名，前綴 tier 名避免 tierA／tierB 同名 stub 撞名）。推導邏輯見 `lib/canary-harness.sh` 的 `canary_stub_gate_name`。
- **缺 fixture 且未豁免 → FAIL**：對帳失敗時引擎逐一列出缺 fixture 的 gate 名並 `exit 1`（與 canary.d 整體缺失的 `exit 2` 區分——對帳失敗代表「知道要測什麼但沒測」，比「完全沒宣告」更明確可行動）。
- **豁免必須逐 gate 明示（fail-closed）**：無法立即補 fixture 的 gate，放 `canary.d/<gate>.skip` marker 檔（如 `canary.d/tierB-bar.skip`），**內容必須非空白**（一行理由）。理由留空＝無效豁免，視同未豁免照樣 FAIL——不許用空檔繞過對帳。
- **`gates.d` 整體不存在**（專案未裝 wave-gate 模組、只用 canary 跑其他自訂 gate）→ 對帳印 `SKIP(gates.d↔canary.d 對帳)` 明示並略過，不誤殺。
- 對帳邏輯抽成 `lib/canary-harness.sh` 的 `canary_reconcile_gates <decl_dir>`（可獨立呼叫，供未來 kit-doctor 等消費者重用）。

## health.d/

> **K7 未交付**——本節為規格預告，repo 內尚無對應引擎。

governance-health 數據源節，每節一檔 `NN-*.sh`，stdout 即該節報告內容。引擎提供 11 節骨架與「結論三行」硬性要求；單一數據源失敗降級 N/A 不中斷（刻意不 `set -e`）。

## pathspec-targets.conf

pathspec-liveness 掃描對象清單，每行一個 hook 檔路徑（repo-root 相對，如 `.husky/pre-push`）。引擎驗證檔內 git pathspec 至少命中 1 檔，恆 0 命中即紅（防 pathspec 寫錯靜默空轉）。

## manifest（kit 側，非專案宣告）

`kit/manifest/provenance.tsv`——closed ledger，9 欄 TSV：

```
kit_path  upstream  upstream_commit  upstream_sha256  kit_sha256  absorbed  mode  upstream_status  notes
```

- **空欄一律 `-` 佔位，永不留空**（防 NF≠9）；hash 格式 `sha256:<64hex>`，`-` = 跳過該側比對
- `upstream`：`<專案>:<路徑>`（如 `dfaa:scripts/hooks/ratchet.sh`）；kit 自創記 `kit:original`；多源抽取記 `<專案>:(多源)` 並以 `-` hash 跳過解析
- **來源驗證走歷史 blob（K5.5）**：`upstream_sha256` 對的是上游 repo 中 `git show <upstream_commit>:<path>` 的 blob hash——來源真偽與上游 live 狀態脫鉤，上游後續演化或換 shim（K6）不影響來源驗證；`upstream_commit=-` 跳過來源驗證
- `mode` 三值：`verbatim`（逐位元組或僅路徑定位改動）｜`parameterized`（邏輯同構、參數抽宣告）｜`extracted-pattern`（抽模式不抽內容——上游演化只提醒人工比對，不做 hash 判定）
- `upstream_status` enum：`active`（上游仍是活源——audit 額外比對 live 檔，差異報「live 前進」獨立分類）｜`retired`（上游已退役/換 shim——跳過 live 比對）｜`successor`（kit 版已是正宗，上游反向依賴）｜`-`（`kit:original` 行固定填 `-`）
- **欄位驗證 fail-closed**（`tools/kit-audit.sh` 前置，違規 exit 2）：mode／upstream_status 非法 enum、absorbed 非 `YYYY-MM-DD` 或晚於今日、hash 欄非 `sha256:<64hex>` 且非 `-`、kit_path 重複
- `kit_path` 可帶 `#anchor` 段落錨（K1 為檔級粒度保留位：存在性檢查剝 fragment、hash 比對跳過——`kit-audit.sh` 與 `tests/cases/manifest.sh` 同契約，anchor 列不進 hash 驗證分母）
- **無帳掃描範圍**：`engines/ gates/ tools/ hooks/ scripts/ lib/ installers/` 遞迴 `*.sh` 與 `*.ts`——目錄下存在但未列帳 = FAIL（與 `tests/cases/manifest.sh` 同步，改一邊必改另一邊）。templates/ 與 references/ 混有非機制檔，帳可選、掃描不強制
- 消費者：`tools/kit-audit.sh`（三態判定）＋ `tests/cases/manifest.sh`（迴歸對帳，K2-K7 改檔忘記帳立即紅燈）
