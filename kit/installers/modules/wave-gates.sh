#!/usr/bin/env bash
# modules/wave-gates.sh — wave 收尾閘門機制安裝模組（K5）。
# 冪等：已存在的檔案／目錄／marker 段一律 skip 不覆寫，重跑 diff 零。
#
# 安裝內容：
#   1. .claude/kit/kit.yaml scaffold（缺檔才建；wave 段 key 缺哪補哪）＋modules 登記
#   2. gates.d/tierA.d ＋ tierB.d scaffold（copy templates 範例 stub——
#      使用者換成專案自己的檢查；tierA 零 stub 時 wave-gate fail-closed）
#   3. canary.d/ 目錄 scaffold（gate 自測 fixture；契約見 declaration-formats.md）
#   4. pathspec-targets.conf scaffold（預設列 .husky 兩支 hook——防 git diff
#      pathspec 寫錯靜默空轉）
#   5. merge-train 掛 .husky（marker 冪等）：
#        pre-commit：closure-lock-guard（收尾鎖守門＋merge 旁路執法）
#        pre-push：wave-regate-guard check ＋ wave-close-guard check ＋
#                  backlog-writeback-guard check（三擋門）
#      另兩支（wave-merge-prep／wave-closure-lock）由 engines/wave-gate.sh
#      自動呼叫，不掛 husky。
#
# 依賴：backlog（backlog-writeback-guard 消費）——由 kit-init.sh dispatcher
# 把關；單獨執行不驗（guard 自身對缺 backlog 的專案 fail-open）。
# bash 3.2 相容；一律 ${var} 形式。

set -u

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }
. "${MODULE_DIR}/_shared.sh"  2>/dev/null || { echo "找不到 modules/_shared.sh"; exit 1; }

root="$(kit_repo_root)"
if [ -z "${root}" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

kit_module_begin

# --- 1. kit.yaml scaffold ＋ wave 段 ＋ modules 登記
kit_module_ensure_kit_yaml "${root}" "${KIT_ROOT}"
kit_module_decl_key "${root}" base_branch "main"
kit_module_decl_key "${root}" app_workspace ""
kit_module_decl_key "${root}" merge_prep_cmd ""
kit_module_decl_key "${root}" tool_readiness ""
# lock_docs_exempt 不 seed：引擎預設非空（*.md|.claude/dev/*），兩態語意下
# seed 空值＝關閉豁免（變嚴），缺鍵才吃引擎預設——要覆寫的專案自行加 key
kit_module_register "${root}" wave-gates

decl="${root}/.claude/kit"

# --- 2. gates.d scaffold（copy templates 範例 stub）
kit_scaffold_dir "${decl}/gates.d/tierA.d" "gates.d/tierA.d/"
kit_scaffold_dir "${decl}/gates.d/tierB.d" "gates.d/tierB.d/"
kit_scaffold_file "${KIT_ROOT}/templates/gates.d/tierA.d/10-example.sh" \
    "${decl}/gates.d/tierA.d/10-example.sh" "tierA.d/10-example.sh"
chmod +x "${decl}/gates.d/tierA.d/10-example.sh" 2>/dev/null || true
kit_scaffold_file "${KIT_ROOT}/templates/gates.d/tierB.d/10-example.sh" \
    "${decl}/gates.d/tierB.d/10-example.sh" "tierB.d/10-example.sh"
chmod +x "${decl}/gates.d/tierB.d/10-example.sh" 2>/dev/null || true

# --- 3. canary.d 目錄 scaffold
kit_scaffold_dir "${decl}/canary.d" "canary.d/"

# --- 4. pathspec-targets.conf scaffold
pathspec_conf='# pathspec-liveness 掃描對象（每行一個 repo-root 相對路徑；格式見
# kit/references/declaration-formats.md「pathspec-targets.conf」節）。
# 預設掃 .husky 兩支 hook——防 hook 內 git diff pathspec 寫錯後靜默空轉。
.husky/pre-commit
.husky/pre-push'
kit_scaffold_content "${decl}/pathspec-targets.conf" "pathspec-targets.conf" "${pathspec_conf}"

# --- 5. merge-train 掛 .husky（marker 冪等）
kit_module_husky_marker "${root}" "pre-commit" "wave-gates" \
    "# wave 收尾鎖守門（鎖存在時凍結非 docs commit＋merge 旁路執法）
bash \"${KIT_ROOT}/gates/merge-train/closure-lock-guard.sh\" || exit 1"

kit_module_husky_marker "${root}" "pre-push" "wave-gates" \
    "# merge-train 三擋門（re-gate 唯一入口／wave-close 執行／backlog 回寫）
bash \"${KIT_ROOT}/gates/merge-train/wave-regate-guard.sh\" check || exit 1
bash \"${KIT_ROOT}/gates/merge-train/wave-close-guard.sh\" check || exit 1
bash \"${KIT_ROOT}/gates/merge-train/backlog-writeback-guard.sh\" check || exit 1"

kit_module_report "wave-gates"
echo "  收尾閘門入口：bash ${KIT_ROOT}/engines/wave-gate.sh 收尾｜baseline（收尾鎖／merge-prep 自癒由引擎自動呼叫）。"
echo "  範例 stub 恆綠——換成專案自己的檢查後才有把關語意；canary fixture 見 declaration-formats.md。"
exit 0
