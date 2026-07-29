# Kit 宣告檔規格

專案側宣告全部住 `<project>/.claude/kit/`（進版控）。引擎住 kit、專案只放宣告——kit 更新全專案立即受益。可執行邏輯（counter、gate stub）一律是版控內可 review 的 bash 檔，不從資料檔執行命令字串（沿用 ratchet 既有設計裁定）。

## kit.yaml

主宣告檔，flat-key YAML（與 intake.config.yaml 同慣例，`kit_decl_get` grep-based 解析，不引入 yq）。欄位留空 = 該功能降級（引擎輸出必須明示降級）。

```yaml
kit_root: "/Users/x/projects/skills/kit"   # 安裝時寫死絕對路徑
modules: "intake backlog rtm wave-gates ratchet"   # 已安裝模組（空白分隔）

# --- ratchet
baseline_file: "quality-baseline.json"     # repo-root 相對
tighten_branch: "main"

# --- wave-gate
app_workspace: "apps/web"                  # Tier B 指令 cwd；無 monorepo 留空
merge_prep_cmd: "pnpm install --frozen-lockfile && pnpm prisma generate"
tool_readiness: "eslint tsc vitest"
regate_branch: "main"

# --- rtm
matrix_dir: "docs/rtm/matrix"
status_enum: "implemented partial divergent planned na"
impl_path_bases: ". apps/web apps/web/src"
reqsync_anchors: "apps/web/src/server apps/web/prisma/schema"
reqsync_excludes: "__tests__ migrations"
```

與 `intake.config.yaml` 的關係：intake.config.yaml 維持原位原格式（intake 模組私有）；kit.yaml 是跨模組宣告。`--rtm` 安裝時把 `matrix_dir` 回填 intake.config.yaml 的 `spec_layer`、rtm-check 指令回填 `spec_check`，接通 /triage 對帳線。兩檔長期不合併。

## counters.d/

ratchet counter 宣告，每 counter 一檔 `<name>.counter.sh`，檔名即 counter 名、須與 baseline JSON 的 `counters.<name>` 鍵對應（引擎雙向核對：有鍵無檔或有檔無鍵皆 fail-closed）。

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
- **exit code 唯一介面**；stdout 前綴 `inspected:N` 選填（canary 消費）
- 條件觸發（如僅 source 變更時跑）寫在 stub 內自行 `exit 0` ＋印 `SKIP(原因)`；紅燈早退、baseline 不早退、re-gate 戳記、鎖——全在引擎骨架，stub 無感

## canary.d/

gate 自測 fixture，`canary.d/<gate>/violation/` 與 `canary.d/<gate>/clean/` 雙目錄。canary 引擎對每支 gate 餵雙 fixture：violation 必紅、clean 必綠、`inspected:N` N>0——三斷言缺一即 canary FAIL（防「gate 跑了 exit 0 但檢查 0 個檔」）。

## health.d/

governance-health 數據源節，每節一檔 `NN-*.sh`，stdout 即該節報告內容。引擎提供 11 節骨架與「結論三行」硬性要求；單一數據源失敗降級 N/A 不中斷（刻意不 `set -e`）。

## pathspec-targets.conf

pathspec-liveness 掃描對象清單，每行一個 hook 檔路徑（repo-root 相對，如 `.husky/pre-push`）。引擎驗證檔內 git pathspec 至少命中 1 檔，恆 0 命中即紅（防 pathspec 寫錯靜默空轉）。

## manifest（kit 側，非專案宣告）

`kit/manifest/provenance.tsv`——closed ledger，8 欄 TSV：

```
kit_path  upstream  upstream_commit  upstream_sha256  kit_sha256  absorbed  mode  notes
```

- **空欄一律 `-` 佔位，永不留空**（防 NF≠8）；hash 格式 `sha256:<hex>`，`-` = 跳過該側比對
- `upstream`：`<專案>:<路徑>`（如 `dfaa:scripts/hooks/ratchet.sh`）；kit 自創記 `kit:original`；多源抽取記 `<專案>:(多源)` 並以 `-` hash 跳過解析
- `mode` 三值：`verbatim`（逐位元組或僅路徑定位改動）｜`parameterized`（邏輯同構、參數抽宣告）｜`extracted-pattern`（抽模式不抽內容——上游漂移只提醒人工比對，不做 hash 判定）
- `kit_path` 可帶 `#anchor` 段落錨（K1 為檔級粒度保留位：存在性檢查剝 fragment、hash 比對跳過）
- **無帳掃描範圍**：`engines/ gates/ tools/ hooks/ scripts/ lib/ installers/` 遞迴 `*.sh`——目錄下存在但未列帳 = FAIL（與 `tests/cases/manifest.sh` 同步，改一邊必改另一邊）。templates/ 與 references/ 混有非機制檔，帳可選、掃描不強制
- 消費者：`tools/kit-audit.sh`（三態判定）＋ `tests/cases/manifest.sh`（迴歸對帳，K2-K7 改檔忘記帳立即紅燈）
