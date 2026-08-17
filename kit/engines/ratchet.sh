#!/usr/bin/env bash
# engines/ratchet.sh — 品質債 ratchet 引擎（薄計數器骨架，宣告驅動）
#
# 吸收自 dfaa scripts/hooks/ratchet.sh（K3/K4 拆分）：四模式（比對／--tighten／
# --report／--count）、fail-closed 契約、baseline 0=硬擋、SLOW_COUNTERS 降載、
# no_relevant_changes 的 B-098 雙 pass skip 判定——流程與語意逐段保留；counter
# 函式全數外移為專案宣告 <decl-dir>/counters.d/。本檔只剩骨架＝載入協定＋
# 模式流程＋比對/收緊語意＋fail-closed 防假 0。
#
# 用法：
#   bash engines/ratchet.sh                    # 比對模式（branch 用，pre-push 呼叫）
#   bash engines/ratchet.sh --all              # 全量比對（deep lane 用，不套 slow/scope skip）
#   bash engines/ratchet.sh --tighten          # 收緊模式（僅限 base_branch 手動執行）
#   RATCHET_ALLOW_TIGHTEN=1 ... --tighten      # 測試豁免，非 base_branch 也可跑
#   bash engines/ratchet.sh --report           # 唯讀現值報告（恆 exit 0）
#   bash engines/ratchet.sh --count <name>     # 單獨驗證/輸出指定 counter 的現值
#   bash engines/ratchet.sh --count-<name>     # 同上的糖衣 pass-through（消費端沿用
#                                              #   原字面 flag，如 dfaa canary 的
#                                              #   --count-large-files）
#   共通選項（測試 seam）：
#     --decl-dir <path>   宣告目錄，預設 <repo>/.claude/kit
#     --repo-root <path>  受檢 repo root，預設 git rev-parse --show-toplevel
#
# 設計裁定（上游 quality-governance-roadmap §4 Phase 0-2、§6-2、§7，保留）：
#   - branch 上只比對、不寫檔；base_branch 才收緊——避免平行 worktree baseline 衝突
#   - counter 邏輯住在版控內可 review 的 bash 宣告檔（counters.d/*.counter.sh）；
#     baseline JSON 只存數字，不從 JSON 執行命令字串（避免把可執行內容藏進資料檔）
#
# 協定（上游語意逐段保留）：
#   - 預設模式（比對）：逐 counter 現值 vs baseline。任一「現值 > baseline」→
#     報告後 exit 1；全部「現值 ≤ baseline」→ 輸出 PASS 摘要、exit 0。此模式
#     永不寫檔。baseline 0 ＝硬擋（現值 1 即紅）。
#     counter 執行失敗（或輸出非單一非負整數）→ 記錄該支、**續跑其餘 counter**，
#     迴圈結束後彙總列出所有壞掉的 counter 並 exit 1（仍 fail-closed）。
#     為何不再「立即退出」（2026-08-17 改契約，dfaa #2916 四次同族事故實證）：
#     counter 依字母序跑，立即退出會讓字母序在後的所有 counter 在那一輪
#     **完全沒被量到**，而輸出只看得到第一個壞掉的那支——四次事故（baseline
#     有鍵無檔／殘留死鎖／allowlist 殭屍條目／detector 同名重複鍵）都是同一個
#     失效模式：一支壞 counter 遮蔽它之後的約 50 支，且每次都潛伏數十天到數月。
#     fail-fast 省下的那幾秒，遠不及「紅燈只露一個」造成的診斷成本。
#   - --tighten 模式：僅限 base_branch（RATCHET_ALLOW_TIGHTEN=1 可豁免，供測試用）。
#     「現值 < baseline」→ 用 jq 把 baseline 改寫為現值；「現值 ≥ baseline」→
#     不動檔案且仍 exit 0（tighten 不是 gate）。jq 逐鍵改寫，baseline 檔內
#     非 counter 鍵（如 allowlist 陣列）守恆。
#   - --report 模式（唯讀）：逐 counter 印「現值(baseline=X)」，counter 失敗印
#     ERROR 行；不寫檔、不比較門檻、恆 exit 0——單純把數字印出來給彙整腳本讀，
#     不是新的 gate。全 counter 都跑（不套用 skip——健檢要的是「此刻真實現值」）。
#   - fail-closed：baseline 檔不存在／JSON 壞掉／counter 宣告缺失／counter 執行
#     失敗 → 明確錯誤、exit 1。ratchet 是閘門、不是回饋層。
#
# counters.d 載入協定（凍結契約；宣告端規格見 kit/references/declaration-formats.md
# 與 kit/templates/counters.d/00-example.counter.sh）：
#   ① 先按字典序 source <decl-dir>/counters.d/NN-*.lib.sh（共用 helper，
#      不參與名稱推導與雙向核對）
#   ② 再按字典序 source <decl-dir>/counters.d/*.counter.sh；counter 名＝檔名去
#      .counter.sh；函式名＝counter 名 tr '-' '_' 前綴 count_；source 後
#      declare -F 驗函式存在，缺＝fail-closed
#   ③ 0 個 counter 檔＝fail-closed 明確報錯（跑了 0 個 counter ≠ 無債）
#   ④ 雙向核對：baseline .counters「有鍵無 counter 檔」與「有檔無鍵／值非
#      非負整數」皆 fail-closed（差異 D2，見下）
#   counter 檔只保證拿到 PROJECT_ROOT、BASELINE_FILE 兩個環境變數（原變數名——
#   上游 counter 如 count_hardcoded_colors 直接讀 BASELINE_FILE）；其餘引擎
#   內部變數一律 ratchet_ 前綴防撞名。
#
# scope-conditioning（compare 模式的 skip 判定）：
#   counter 檔可選定義 inputs_<name>()（stdout 一行一 git pathspec，repo-root
#   相對）；compare 模式對其跑 no_relevant_changes（B-098 雙 pass），無相關變更
#   即 skip 沿用 baseline。未定義 inputs_ ＝永不 skip（＝上游 counter_skippable
#   default return 1 的保守語意）；origin/<base_branch> 不可達＝保守全跑。
#   --tighten／--report 一律全跑不看 skip。
#
# kit.yaml 宣告（<decl-dir>/kit.yaml，flat-key，kit_decl_get 解析；全部選配）：
#   baseline_file   repo-root 相對；無宣告預設 quality-baseline.json
#   base_branch     tighten 限定 branch 兼 skip 判定的 origin/<base>；預設 main
#   slow_counters   空白分隔 counter 名；compare 模式預設跳過、RATCHET_FULL=1
#                   全跑（wave-gate A5 承擔）；--tighten/--report 不受影響。
#                   無宣告＝空＝不跳過任何 counter。
#                   ⚠ K6 遷移 checklist：dfaa 遷移時必須宣告 slow_counters:
#                   "eslint-warnings"，否則全庫 eslint 進 pre-push、push 變分鐘級。
#
# 與上游 dfaa scripts/hooks/ratchet.sh 的差異清單（K6 對帳用；除此之外語意全等）：
#   D1 counter 函式（44 個）外移 counters.d（K6 抽到 dfaa 專案宣告）；名稱→函式
#      對照（counter_value case／COUNTER_NAMES 清單）由檔名推導取代
#   D2 雙向核對＝新行為：上游 baseline 多餘鍵靜默忽略、缺鍵的 exit 在 command
#      substitution 內被吞；本引擎載入期即雙向 fail-closed，並驗每個 .counters
#      值為非負整數
#   D3 counter 輸出於引擎端驗「單一非負整數」：上游由各 counter 函式自驗；
#      宣告驅動後引擎不信任宣告端自律——非數字輸出＝counter 失敗（fail-closed），
#      堵「-gt 對非數字比較噴錯後靜默落入 PASS 分支」的 fail-open 洞
#   D4 counter skip 判定：上游 counter_skippable 硬編碼 case 表 → 宣告端選配
#      inputs_<name>()；未定義＝永不 skip（上游 default return 1）
#   D5 PROJECT_ROOT 改 git rev-parse --show-toplevel（上游用腳本自身位置 ../..
#      定位；等價前提＝在 repo 內呼叫；跨 repo／測試用 --repo-root seam）
#   D6 origin/main → origin/${base_branch}（kit_decl_get，預設 main，預設態語意不變）
#   D7 --count-large-files 泛化為 --count <name>＋--count-<name> 糖衣
#   D8 未知參數 fail-closed exit 1（上游未知參數靜默落入比對模式）
#   D9 上游 UI_SHELL_CENSUS_CACHE 類快取假象不修：counter 在 $(...) subshell
#      執行，快取變數不跨 counter 持續——與上游同樣失效；行為外效能改動不做
#
# 已知坑（bash 3.2 / macOS 內建版，上游原文保留）：set -u 下，裸 $var（不加
# 大括號）若緊接著全形標點等多位元組字元，會被誤判成識別字延伸，觸發假的
# 「unbound variable」並直接中止整支 script（非僅該行失敗）。本檔一律用
# ${var} 形式，避免此雷。

set -u
set -o pipefail

# ---------- 參數（模式＋測試 seam） ----------

ratchet_mode="compare"
ratchet_force_all=0
ratchet_count_name=""
ratchet_decl_dir=""
ratchet_repo_root_arg=""
while [ $# -gt 0 ]; do
  case "${1}" in
    --all)
      ratchet_mode="compare"; ratchet_force_all=1; shift ;;
    --tighten)
      ratchet_mode="tighten"; shift ;;
    --report)
      ratchet_mode="report"; shift ;;
    --count)
      [ $# -ge 2 ] || { echo "ratchet: --count 缺 counter 名稱" >&2; exit 1; }
      ratchet_mode="count"; ratchet_count_name="${2}"; shift 2 ;;
    --count-?*)
      # 糖衣 pass-through：--count-<name> ≡ --count <name>（dfaa canary 用原字面 flag）
      ratchet_mode="count"; ratchet_count_name="${1#--count-}"; shift ;;
    --decl-dir)
      [ $# -ge 2 ] || { echo "ratchet: --decl-dir 缺參數值" >&2; exit 1; }
      ratchet_decl_dir="${2}"; shift 2 ;;
    --repo-root)
      [ $# -ge 2 ] || { echo "ratchet: --repo-root 缺參數值" >&2; exit 1; }
      ratchet_repo_root_arg="${2}"; shift 2 ;;
    *)
      echo "ratchet: 未知參數 [${1}]，fail-closed，拒絕通過" >&2
      exit 1 ;;
  esac
done

ratchet_engine_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! . "${ratchet_engine_dir}/../lib/common.sh" 2>/dev/null; then
  echo "ratchet: 找不到 kit/lib/common.sh，fail-closed，拒絕通過" >&2
  exit 1
fi

# ---------- 前置：定位 repo root（worktree 相容，不假設 cwd） ----------

if [ -n "${ratchet_repo_root_arg}" ]; then
  PROJECT_ROOT="$(cd "${ratchet_repo_root_arg}" 2>/dev/null && pwd -P)"
  if [ -z "${PROJECT_ROOT}" ]; then
    echo "ratchet: --repo-root 目錄不存在 [${ratchet_repo_root_arg}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "${PROJECT_ROOT}" ]; then
    echo "ratchet: 不在 git 工作目錄內（或改用 --repo-root 指定），fail-closed，拒絕通過" >&2
    exit 1
  fi
fi

[ -n "${ratchet_decl_dir}" ] || ratchet_decl_dir="${PROJECT_ROOT}/.claude/kit"
ratchet_kit_yaml="${ratchet_decl_dir}/kit.yaml"
ratchet_base_branch="$(kit_decl_get "${ratchet_kit_yaml}" base_branch main)"
ratchet_baseline_rel="$(kit_decl_get "${ratchet_kit_yaml}" baseline_file quality-baseline.json)"
ratchet_slow_counters="$(kit_decl_get "${ratchet_kit_yaml}" slow_counters '')"

BASELINE_FILE="${PROJECT_ROOT}/${ratchet_baseline_rel}"
export PROJECT_ROOT BASELINE_FILE

# ---------- 載入 counters.d 宣告（凍結契約，見檔頭） ----------

ratchet_counters_dir="${ratchet_decl_dir}/counters.d"
if [ ! -d "${ratchet_counters_dir}" ]; then
  echo "ratchet: 找不到 counter 宣告目錄 [${ratchet_counters_dir}]，fail-closed，拒絕通過" >&2
  exit 1
fi

# ① 共用 helper（NN-*.lib.sh，字典序；不參與名稱推導與雙向核對）
for ratchet_f in "${ratchet_counters_dir}"/[0-9][0-9]-*.lib.sh; do
  [ -f "${ratchet_f}" ] || continue   # nullglob guard（bash 3.2 無 nullglob 預設）
  if ! . "${ratchet_f}"; then
    echo "ratchet: 載入共用 helper 失敗 [${ratchet_f}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
done

# ② counter 檔（*.counter.sh，字典序）：source → 檔名推導名稱 → declare -F 驗函式
ratchet_counter_names=""
for ratchet_f in "${ratchet_counters_dir}"/*.counter.sh; do
  [ -f "${ratchet_f}" ] || continue   # nullglob guard
  if ! . "${ratchet_f}"; then
    echo "ratchet: 載入 counter 檔失敗 [${ratchet_f}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
  ratchet_name="$(basename "${ratchet_f}" .counter.sh)"
  ratchet_fn="count_$(printf '%s' "${ratchet_name}" | tr '-' '_')"
  if ! declare -F "${ratchet_fn}" >/dev/null 2>&1; then
    echo "ratchet: counter 檔 [${ratchet_f}] 未定義函式 ${ratchet_fn}()，fail-closed，拒絕通過" >&2
    exit 1
  fi
  ratchet_counter_names="${ratchet_counter_names}${ratchet_name} "
done

# ③ 0 個 counter 檔＝fail-closed（跑了 0 個 counter ≠ 無債——防假 0 母題）
if [ -z "${ratchet_counter_names}" ]; then
  echo "ratchet: [${ratchet_counters_dir}] 內 0 個 *.counter.sh，fail-closed，拒絕通過（跑了 0 個 counter ≠ 無債）" >&2
  exit 1
fi

# ---------- baseline 讀寫（fail-closed，上游語意保留） ----------

ratchet_require_baseline() {
  if [ ! -f "${BASELINE_FILE}" ]; then
    echo "ratchet: 找不到 baseline 檔 [${BASELINE_FILE}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
  if ! jq -e '.counters' "${BASELINE_FILE}" >/dev/null 2>&1; then
    echo "ratchet: baseline 檔 JSON 格式壞掉或缺 .counters [${BASELINE_FILE}]，fail-closed，拒絕通過" >&2
    exit 1
  fi
}

ratchet_baseline_value() {
  local name="${1}"
  local v
  v="$(jq -r --arg k "${name}" '.counters[$k] // empty' "${BASELINE_FILE}" 2>/dev/null)"
  case "${v}" in
    ''|*[!0-9]*)
      echo "ratchet: baseline 缺少或非數字的 counter [${name}]，fail-closed，拒絕通過" >&2
      exit 1
      ;;
  esac
  printf '%s\n' "${v}"
}

ratchet_require_baseline

# ④ 雙向核對（差異 D2；於任何模式的執行前做，載入期即擋）
#    a) baseline .counters 有鍵、counters.d 無對應檔 → fail-closed
#    b) 有檔、baseline 無鍵或值非「非負整數」 → fail-closed
ratchet_baseline_keys="$(jq -r '.counters | keys[]' "${BASELINE_FILE}" 2>/dev/null)"
while IFS= read -r ratchet_k || [ -n "${ratchet_k}" ]; do
  [ -n "${ratchet_k}" ] || continue
  case " ${ratchet_counter_names}" in
    *" ${ratchet_k} "*) ;;
    *)
      echo "ratchet: baseline counters 有鍵 [${ratchet_k}] 但 counters.d 無對應 counter 檔，fail-closed，拒絕通過" >&2
      exit 1
      ;;
  esac
done <<< "${ratchet_baseline_keys}"
for ratchet_name in ${ratchet_counter_names}; do
  ratchet_v="$(jq -r --arg k "${ratchet_name}" '.counters[$k] // empty' "${BASELINE_FILE}" 2>/dev/null)"
  case "${ratchet_v}" in
    ''|*[!0-9]*)
      echo "ratchet: baseline 缺少或非數字的 counter [${ratchet_name}]，fail-closed，拒絕通過" >&2
      exit 1
      ;;
  esac
done

# ---------- counter 執行與 skip 判定 ----------

# 呼叫端一律以 $(...) 取值：counter 的快取變數只活在 subshell 內（差異 D9，
# 與上游同樣的快取假象——刻意不修，行為外效能改動不做）。
ratchet_counter_value() {
  "count_$(printf '%s' "${1}" | tr '-' '_')"
}

# no_relevant_changes pathspec...
#   Returns 0 if there are NO relevant changes (safe to skip this counter).
#   Returns 1 if there ARE changes or origin/<base_branch> is unreachable
#   (conservative: must run).
#
# Uses two passes（上游 B-098 雙 pass，:784-793 逐字保留；僅 origin/main →
# origin/${ratchet_base_branch}）:
#   1. `git diff --name-only origin/<base>...HEAD` — net diff (fast, covers most cases)
#   2. `git log --name-only --format= origin/<base>..HEAD` — per-commit check, catches
#      add+delete pairs that cancel out in the three-dot net diff (B-098: when local
#      main is ahead of origin/main and the branch only deletes files that were added
#      after origin/main, the net diff from origin/main is zero → false skip).
ratchet_no_relevant_changes() {
  ( cd "${PROJECT_ROOT}" && git rev-parse --verify "origin/${ratchet_base_branch}" >/dev/null 2>&1 ) || return 1
  local changed
  changed="$(cd "${PROJECT_ROOT}" && git diff --name-only "origin/${ratchet_base_branch}...HEAD" -- "$@" 2>/dev/null)"
  if [ -z "${changed}" ]; then
    changed="$(cd "${PROJECT_ROOT}" && git log --name-only --format= "origin/${ratchet_base_branch}..HEAD" -- "$@" 2>/dev/null | head -1)"
  fi
  [ -z "${changed}" ] && return 0
  return 1
}

# ratchet_counter_skippable <name>：compare 模式下可否沿用 baseline 免跑（回 0=可跳過）。
# 判斷依據＝宣告端選配的 inputs_<name>()（差異 D4）；未定義／執行失敗＝保守不跳過。
# --tighten／--report 一律全跑不看此函式。
ratchet_counter_skippable() {
  local name="${1}" fn inputs
  fn="inputs_$(printf '%s' "${name}" | tr '-' '_')"
  declare -F "${fn}" >/dev/null 2>&1 || return 1
  inputs="$("${fn}" 2>/dev/null)" || return 1
  # pathspec 按空白/換行展開成多個參數（repo 內 pathspec 無空白——沿用上游
  # scan_target 同款假設）
  # shellcheck disable=SC2086
  set -- ${inputs}
  ratchet_no_relevant_changes "$@"
}

ratchet_is_slow_counter() {
  case " ${ratchet_slow_counters} " in
    *" ${1} "*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- --count 模式（--count-large-files 的泛化，差異 D7） ----------

if [ "${ratchet_mode}" = "count" ]; then
  case " ${ratchet_counter_names}" in
    *" ${ratchet_count_name} "*) ;;
    *)
      echo "ratchet: unknown counter [${ratchet_count_name}]" >&2
      exit 1
      ;;
  esac
  ratchet_counter_value "${ratchet_count_name}"
  exit $?
fi

# ---------- --report 模式（唯讀，恆 exit 0） ----------

if [ "${ratchet_mode}" = "report" ]; then
  for ratchet_name in ${ratchet_counter_names}; do
    ratchet_current="$(ratchet_counter_value "${ratchet_name}")"
    ratchet_rc=$?
    ratchet_baseline="$(ratchet_baseline_value "${ratchet_name}")"
    case "${ratchet_current}" in
      ''|*[!0-9]*) ratchet_rc=1 ;;   # 差異 D3：非數字輸出視同 counter 失敗
    esac
    if [ "${ratchet_rc}" -ne 0 ]; then
      echo "${ratchet_name}=ERROR（counter 執行失敗，baseline=${ratchet_baseline}）"
      continue
    fi
    echo "${ratchet_name}=${ratchet_current}(baseline=${ratchet_baseline})"
  done
  exit 0
fi

# ---------- --tighten 模式（僅限 base_branch；現值 ≥ baseline 不動檔且 exit 0） ----------

if [ "${ratchet_mode}" = "tighten" ]; then
  ratchet_current_branch="$(cd "${PROJECT_ROOT}" && git branch --show-current 2>/dev/null)"
  if [ "${ratchet_current_branch}" != "${ratchet_base_branch}" ] && [ "${RATCHET_ALLOW_TIGHTEN:-}" != "1" ]; then
    echo "ratchet: --tighten 僅限 ${ratchet_base_branch} branch 執行，目前在 [${ratchet_current_branch}]。" >&2
    echo "ratchet: 如需在測試環境豁免，設定 RATCHET_ALLOW_TIGHTEN=1。" >&2
    exit 1
  fi

  ratchet_any_change=0
  ratchet_broken=""
  for ratchet_name in ${ratchet_counter_names}; do
    ratchet_current="$(ratchet_counter_value "${ratchet_name}")"
    if [ $? -ne 0 ]; then
      echo "ratchet: counter [${ratchet_name}] 執行失敗" >&2
      ratchet_broken="${ratchet_broken}${ratchet_name} "
      continue
    fi
    case "${ratchet_current}" in
      ''|*[!0-9]*)
        echo "ratchet: counter [${ratchet_name}] 輸出非「單一非負整數」（[${ratchet_current}]），fail-closed，拒絕通過" >&2
        ratchet_broken="${ratchet_broken}${ratchet_name} "
        continue
        ;;
    esac
    ratchet_baseline="$(ratchet_baseline_value "${ratchet_name}")"

    if [ "${ratchet_current}" -lt "${ratchet_baseline}" ]; then
      ratchet_tmp="$(mktemp)"
      jq --arg k "${ratchet_name}" --argjson n "${ratchet_current}" '.counters[$k] = $n' "${BASELINE_FILE}" > "${ratchet_tmp}" \
        && chmod 644 "${ratchet_tmp}" \
        && mv "${ratchet_tmp}" "${BASELINE_FILE}"
      echo "收緊：規則 ${ratchet_name} baseline ${ratchet_baseline} -> ${ratchet_current}"
      ratchet_any_change=1
    fi
  done

  if [ "${ratchet_any_change}" -eq 0 ]; then
    echo "ratchet: 無 counter 需要收緊（現值均 >= baseline，檔案不動）"
  fi
  if [ -n "${ratchet_broken}" ]; then
    echo "ratchet: 以下 counter 執行失敗、未參與本次收緊：${ratchet_broken}" >&2
    exit 1
  fi
  exit 0
fi

# ---------- 比對模式（預設，永不寫檔） ----------

# 慢 counter 降載（上游 2026-07-27 裁定保留）：分鐘級 counter 超出 pre-push
# 秒級預算——compare 模式預設跳過、由 wave-gate A5 帶 RATCHET_FULL=1 全跑承擔
# （merge train 必經，增量在 merge 前仍被攔）；--tighten / --report 不受影響
# （本來就全跑）。清單由 kit.yaml slow_counters 宣告（無宣告＝空＝不跳過）。

ratchet_fail=0
ratchet_summary=""
ratchet_broken=""
for ratchet_name in ${ratchet_counter_names}; do
  ratchet_baseline="$(ratchet_baseline_value "${ratchet_name}")"

  if [ "${ratchet_force_all}" != "1" ] && [ "${RATCHET_FULL:-}" != "1" ] && ratchet_is_slow_counter "${ratchet_name}"; then
    ratchet_summary="${ratchet_summary}${ratchet_name}=skip(慢 counter，由 wave-gate RATCHET_FULL=1 承擔) "
    continue
  fi

  if [ "${ratchet_force_all}" != "1" ] && ratchet_counter_skippable "${ratchet_name}"; then
    ratchet_summary="${ratchet_summary}${ratchet_name}=skip(無相關變更，沿用 baseline ${ratchet_baseline}) "
    continue
  fi

  ratchet_current="$(ratchet_counter_value "${ratchet_name}")"
  if [ $? -ne 0 ]; then
    echo "ratchet: counter [${ratchet_name}] 執行失敗" >&2
    ratchet_broken="${ratchet_broken}${ratchet_name} "
    ratchet_fail=1
    continue
  fi
  case "${ratchet_current}" in
    ''|*[!0-9]*)
      echo "ratchet: counter [${ratchet_name}] 輸出非「單一非負整數」（[${ratchet_current}]），fail-closed，拒絕通過" >&2
      ratchet_broken="${ratchet_broken}${ratchet_name} "
      ratchet_fail=1
      continue
      ;;
  esac

  if [ "${ratchet_current}" -gt "${ratchet_baseline}" ]; then
    echo "ratchet: ${ratchet_name} 現值 ${ratchet_current} > baseline ${ratchet_baseline}，新增的債必須在本 branch 內消掉" >&2
    ratchet_fail=1
  else
    ratchet_summary="${ratchet_summary}${ratchet_name}=${ratchet_current}(<=${ratchet_baseline}) "
  fi
done

if [ "${ratchet_fail}" -eq 1 ]; then
  if [ -n "${ratchet_broken}" ]; then
    echo "ratchet: 以下 counter 執行失敗（其餘 counter 已照常比對，未被遮蔽）：${ratchet_broken}" >&2
  fi
  # 紅燈時也把已量到的值全印出來——否則「哪些 counter 其實是好的」同樣被遮蔽，
  # 診斷時得再跑一輪才知道。刻意不用 PASS 前綴（有消費端在 parse 它）。
  [ -n "${ratchet_summary}" ] && echo "ratchet: 已比對 -- ${ratchet_summary}"
  exit 1
fi

echo "ratchet: PASS -- ${ratchet_summary}"
exit 0
