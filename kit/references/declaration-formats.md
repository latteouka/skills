# Kit 宣告檔規格

專案側宣告全部住 `<project>/.claude/kit/`（進版控）。引擎住 kit、專案只放宣告——kit 更新全專案立即受益。可執行邏輯（counter）一律是版控內可 review 的 bash 檔，不從資料檔執行命令字串（沿用 ratchet 既有設計裁定）。

> 活引擎只剩 ratchet／rtm-check／hook-wiring-check／reqsync 系（wave-gate、canary、pathspec-liveness、kit-doctor、manifest 已隨 wave 退役移除，其宣告節同步刪除——考古走 git history）。

## kit.yaml

主宣告檔，flat-key YAML（與 intake.config.yaml 同慣例，`kit_decl_get` grep-based 解析，不引入 yq）。欄位留空 = 該功能降級（引擎輸出必須明示降級）。

```yaml
kit_root: "/Users/x/projects/skills/kit"   # 安裝時寫死絕對路徑

# --- ratchet
baseline_file: "quality-baseline.json"     # repo-root 相對；引擎以 BASELINE_FILE 原名提供給 counter【必要欄位】
slow_counters: ""                          # 空白分隔；compare 模式跳過（RATCHET_FULL=1 強制跑）

# --- rtm
matrix_dir: "docs/rtm/matrix"                             # 【必要欄位】
status_enum: "implemented partial divergent planned na"   # PASS 統計行欄序＝宣告序
impl_path_bases: ". apps/web apps/web/src"                # check7 suffix-match 基準
rtm_nonpath_tokens: "Next.js Node.js"                     # impl_details 非路徑 token 白名單（dfaa 遷移補 sigma.js 等）
rtm_notes_required: "divergent"                           # 哪些 status 必填 notes
rtm_detail_specs_required: "implemented partial divergent"
rtm_impl_details_required: "implemented partial"
reqsync_anchors: "apps/web/src/server apps/web/prisma/schema"
reqsync_excludes: "__tests__ migrations"                  # 路徑段名比對
```

與 `intake.config.yaml` 的關係：intake.config.yaml 維持原位原格式；kit.yaml 是跨模組宣告。兩檔長期不合併。

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

