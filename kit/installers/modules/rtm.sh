#!/usr/bin/env bash
# modules/rtm.sh — RTM（需求追溯矩陣）機制安裝模組（K5）。
# 冪等：已存在的檔案／marker／settings 條目／gitignore 行一律 skip 不覆寫，
# 重跑 diff 零。
#
# 安裝內容：
#   1. .claude/kit/kit.yaml scaffold（缺檔才建；rtm 段 key 缺哪補哪）＋modules 登記
#   2. <matrix_dir>/ scaffold ＋最小 matrix（1 條 planned，天然過 rtm-check；
#      目錄已有任何 *.yaml 則不放——不污染既有真 matrix）
#   3. rtm-check tierA stub 掛 gates.d/tierA.d/（有 gates.d 才掛；無則提示
#      先裝 --wave-gates，不失敗）
#   4. require-requirements-sync 掛 .husky/pre-commit（kit:rtm marker）
#   5. append-req-sync-skip-trailer 掛 .husky/prepare-commit-msg（kit:rtm marker）
#   6. rtm-touch-reminder（PostToolUse Write|Edit）＋rtm-session-start
#      （SessionStart）merge 進 .claude/settings.json——壞 JSON 前置驗證，
#      驗不過＝零寫入中止
#   7. CLAUDE.md 行為定位協議段（templates/rtm/claude-md-rtm-section.md，
#      marker 冪等、{{MATRIX_DIR}} 代換；CLAUDE.md 不存在則建，存在則
#      append 不覆寫既有內容）
#   8. 回填 intake.config.yaml 的 spec_layer/spec_check（僅原值為空時——
#      接通 /triage 對帳線）
#   9. .gitignore 三條（rtm-index.tsv／.rtm-seen/／.rtm-reminder-log——
#      全為執行期衍生物，不進版控）
#
# 依賴：intake（回填線）——由 kit-init.sh dispatcher 把關；單獨執行時缺
# intake 只跳過回填並提示，不失敗。
# 另：rtm-check 執行需專案自備 js-yaml 與 node≥23.6/tsx（宣告見 kit.yaml 註解）。
# bash 3.2 相容；一律 ${var} 形式。

set -u

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }
. "${MODULE_DIR}/_shared.sh"  2>/dev/null || { echo "找不到 modules/_shared.sh"; exit 1; }

root="$(kit_repo_root)"
if [ -z "${root}" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

# --- 前置驗證（任何寫入之前）：jq ＋ settings.json 合法性——壞 JSON 零寫入
command -v jq >/dev/null 2>&1 || { echo "錯誤：rtm 模組需要 jq（settings.json merge）。" >&2; exit 1; }
settings="${root}/.claude/settings.json"
if [ -f "${settings}" ] && ! jq empty "${settings}" >/dev/null 2>&1; then
    echo "錯誤：${settings} 不是合法 JSON，中止安裝（未做任何寫入）。" >&2
    exit 1
fi

kit_module_begin

# --- 1. kit.yaml scaffold ＋ rtm 段 ＋ modules 登記
kit_module_ensure_kit_yaml "${root}" "${KIT_ROOT}"
kit_yaml="${root}/.claude/kit/kit.yaml"
kit_module_decl_key "${root}" matrix_dir "docs/rtm/matrix"
kit_module_decl_key "${root}" status_enum "implemented partial divergent planned na"
kit_module_decl_key "${root}" impl_path_bases "."
kit_module_decl_key "${root}" reqsync_anchors ""
kit_module_decl_key "${root}" reqsync_excludes ""
kit_module_decl_key "${root}" rtm_nonpath_tokens "Next.js Node.js"
kit_module_register "${root}" rtm

matrix_dir="$(kit_decl_get "${kit_yaml}" matrix_dir docs/rtm/matrix)"
matrix_dir="${matrix_dir%/}"

# --- 2. matrix scaffold（最小 matrix：1 條 planned——rtm-check 天然綠）
# 語法採 JSON（JSON 是 YAML 子集，js-yaml 可解析）：scaffold 是機器可測的
# 佔位條目，真條目由 onboarding 訪談（references/rtm-authoring.md）產出後刪除。
kit_scaffold_dir "${root}/${matrix_dir}" "${matrix_dir}/"
if ls "${root}/${matrix_dir}"/*.yaml >/dev/null 2>&1; then
    KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} 最小matrix(目錄已有yaml)"
else
    scaffold_matrix='# RTM scaffold（kit --rtm 安裝產生）——照 kit/references/rtm-authoring.md 建真條目後刪除本檔。
# 語法採 JSON（JSON 是 YAML 子集）；改寫成一般 YAML 亦可，完整欄位範例見
# kit/templates/rtm/matrix-example.yaml。增刪條目必須同步 meta.total_clauses。
{
  "meta": { "section": "scaffold/待建檔", "total_clauses": 1 },
  "entries": [
    { "req_id": "scaffold/待建檔/1",
      "req_text": "以 rtm-authoring.md 訪談流程建立本專案的 RTM 條目（本條為安裝佔位）。",
      "status": "planned",
      "detail_specs": ["尚未建檔——安裝 scaffold 佔位條目；正式條目落檔後刪除本檔並同步 meta。"] }
  ]
}'
    kit_scaffold_content "${root}/${matrix_dir}/00-scaffold.yaml" \
        "${matrix_dir}/00-scaffold.yaml" "${scaffold_matrix}"
fi

# --- 3. rtm-check tierA stub（有 gates.d 才掛；runtime 偵測與
#        hooks/rtm-session-start.sh 同判準，皆無＝紅 fail-closed）
tierA_dir="${root}/.claude/kit/gates.d/tierA.d"
if [ -d "${tierA_dir}" ]; then
    rtm_stub='#!/usr/bin/env bash
# 30-rtm-check.sh — RTM 一致性 gate stub（kit --rtm 安裝產生）
# runtime：node ≥23.6（type stripping）或 tsx；皆無＝紅（fail-closed——
# rtm 專案的驗證工具缺席不可與全綠混同）。
set -u -o pipefail
engine="'"${KIT_ROOT}"'/engines/rtm-check.ts"
root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel)}"
runtime=""
node_ver="$(node --version 2>/dev/null || true)"
if [ -n "${node_ver}" ]; then
  maj="${node_ver#v}"; maj="${maj%%.*}"
  min="${node_ver#v*.}"; min="${min%%.*}"
  case "${maj}" in ""|*[!0-9]*) maj=0 ;; esac
  case "${min}" in ""|*[!0-9]*) min=0 ;; esac
  if [ "${maj}" -gt 23 ] || { [ "${maj}" -eq 23 ] && [ "${min}" -ge 6 ]; }; then
    runtime="node"
  fi
fi
if [ -z "${runtime}" ]; then
  if command -v tsx >/dev/null 2>&1; then
    runtime="tsx"
  elif [ -x "${root}/node_modules/.bin/tsx" ]; then
    runtime="${root}/node_modules/.bin/tsx"
  fi
fi
if [ -z "${runtime}" ]; then
  echo "rtm-check: FAIL——無可用 runtime（node ≥23.6 或 tsx），RTM 無法驗證（fail-closed）" >&2
  exit 1
fi
"${runtime}" "${engine}" --repo-root "${root}"'
    kit_scaffold_content "${tierA_dir}/30-rtm-check.sh" \
        "gates.d/tierA.d/30-rtm-check.sh" "${rtm_stub}"
    chmod +x "${tierA_dir}/30-rtm-check.sh" 2>/dev/null || true
else
    echo "提示：尚無 gates.d/tierA.d——rtm-check gate stub 未掛；先跑 kit-init --wave-gates 再重跑 --rtm 即補掛（本次不失敗）。"
    KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} tierA-stub(無gates.d)"
fi

# --- 4/5. husky markers（pre-commit：reqsync gate；prepare-commit-msg：trailer）
kit_module_husky_marker "${root}" "pre-commit" "rtm" \
    "# RTM 同步 gate：行為 diff 未動 matrix → 擋（逃生口 REQ_SYNC_SKIP=\"具體理由\"）
bash \"${KIT_ROOT}/gates/require-requirements-sync.sh\" || exit 1"
kit_module_husky_marker "${root}" "prepare-commit-msg" "rtm" \
    "# REQ_SYNC_SKIP 理由寫入 commit trailer（收波稽核可掃）；trailer 失敗不擋 commit
bash \"${KIT_ROOT}/gates/append-req-sync-skip-trailer.sh\" \"\$1\" || true"

# --- 6. settings.json merge（讀側雙 hook）
mkdir -p "${root}/.claude"
kit_module_settings_merge "${settings}" "${KIT_ROOT}/hooks/rtm-touch-reminder.sh" '
  .hooks //= {}
  | .hooks.PostToolUse //= []
  | .hooks.SessionStart //= []
  | .hooks.PostToolUse += [{
      matcher: "Write|Edit",
      hooks: [{ type: "command", command: "'"${KIT_ROOT}"'/hooks/rtm-touch-reminder.sh", timeout: 5 }]
    }]
  | .hooks.SessionStart += [{
      matcher: "startup|resume|clear|compact",
      hooks: [{ type: "command", command: "'"${KIT_ROOT}"'/hooks/rtm-session-start.sh", timeout: 30 }]
    }]
' || exit 1

# --- 7. CLAUDE.md 行為定位協議段（marker 冪等；append 不覆寫既有內容）
claude_md="${root}/CLAUDE.md"
if [ -f "${claude_md}" ] && grep -qF '<!-- kit:rtm:begin -->' "${claude_md}" 2>/dev/null; then
    KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} CLAUDE.md(rtm段已存在)"
else
    {
        if [ -f "${claude_md}" ] && [ -s "${claude_md}" ]; then printf '\n'; fi
        sed "s|{{MATRIX_DIR}}|${matrix_dir}/|g" \
            "${KIT_ROOT}/templates/rtm/claude-md-rtm-section.md"
    } >> "${claude_md}"
    KIT_MODULE_CREATED="${KIT_MODULE_CREATED} CLAUDE.md(rtm段)"
fi

# --- 8. 回填 intake.config.yaml（僅原值為空時；接通 /triage 對帳線）
cfg="${root}/.claude/dev/intake.config.yaml"
if [ ! -f "${cfg}" ]; then
    echo "提示：未偵測到 intake.config.yaml（intake 未裝？）——spec_layer/spec_check 回填跳過。"
    KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} intake回填(無config)"
else
    cur_layer="$(kit_decl_get "${cfg}" spec_layer '')"
    if [ -z "${cur_layer}" ]; then
        tmp="${cfg}.kit-rtm.$$"
        sed "s|^spec_layer: \"\"|spec_layer: \"${matrix_dir}/\"|" "${cfg}" > "${tmp}" && mv "${tmp}" "${cfg}"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} intake.config(spec_layer)"
    else
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} intake.config(spec_layer已設)"
    fi
    cur_check="$(kit_decl_get "${cfg}" spec_check '')"
    if [ -z "${cur_check}" ]; then
        tmp="${cfg}.kit-rtm.$$"
        sed "s|^spec_check: \"\"|spec_check: \"node ${KIT_ROOT}/engines/rtm-check.ts\"|" "${cfg}" > "${tmp}" && mv "${tmp}" "${cfg}"
        KIT_MODULE_CREATED="${KIT_MODULE_CREATED} intake.config(spec_check)"
    else
        KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} intake.config(spec_check已設)"
    fi
fi

# --- 9. .gitignore 三條（rtm 執行期衍生物）
kit_module_gitignore "${root}" "kit rtm 執行期檔案（自動產生，非版控內容）" \
    ".claude/kit/rtm-index.tsv" \
    ".claude/kit/.rtm-seen/" \
    ".claude/dev/.rtm-reminder-log"

kit_module_report "rtm"
echo "  下一步：照 kit/references/rtm-authoring.md 建真 matrix；kit.yaml 的 reqsync_anchors 宣告後 reqsync gate 才生效。"
exit 0
