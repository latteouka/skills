#!/usr/bin/env bash
# modules/ratchet.sh — 品質債 ratchet 機制安裝模組（K5）。
# 冪等：已存在的檔案／目錄一律 skip 不覆寫，重跑 diff 零。
#
# 安裝內容：
#   1. .claude/kit/kit.yaml scaffold（缺檔才建；ratchet 段 key 缺哪補哪）＋modules 登記
#   2. counters.d/ scaffold（copy 00-example.counter.sh——counter 契約範例，
#      使用者照契約寫專案自己的 counter）
#   3. ratchet tierA stub 掛 gates.d/tierA.d/（有 gates.d 才掛；無則提示
#      先裝 --wave-gates，不失敗——與 rtm 模組同條件邏輯）
#   4. 輸出 baseline 初始化說明（首跑 --tighten 產 baseline；baseline 未
#      初始化前 ratchet 引擎 fail-closed 紅，是刻意的——沒有基線的 gate
#      不可與全綠混同）
#
# 依賴：wave-gates（gates.d／kit.yaml wave 段）——由 kit-init.sh dispatcher
# 把關；單獨執行時缺 gates.d 只跳過 stub 掛載並提示，不失敗。
# bash 3.2 相容；一律 ${var} 形式。

set -u

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }
. "${MODULE_DIR}/_shared.sh"  2>/dev/null || { echo "找不到 modules/_shared.sh"; exit 1; }

root="$(kit_repo_root)"
if [ -z "${root}" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

kit_module_begin

# --- 1. kit.yaml scaffold ＋ ratchet 段 ＋ modules 登記
kit_module_ensure_kit_yaml "${root}" "${KIT_ROOT}"
kit_module_decl_key "${root}" baseline_file "quality-baseline.json"
kit_module_decl_key "${root}" slow_counters ""
kit_module_register "${root}" ratchet

decl="${root}/.claude/kit"

# --- 2. counters.d scaffold（範例 counter）
kit_scaffold_dir "${decl}/counters.d" "counters.d/"
kit_scaffold_file "${KIT_ROOT}/templates/counters.d/00-example.counter.sh" \
    "${decl}/counters.d/00-example.counter.sh" "counters.d/00-example.counter.sh"

# --- 3. ratchet tierA stub（有 gates.d 才掛——與 rtm 模組同條件邏輯）
tierA_dir="${decl}/gates.d/tierA.d"
if [ -d "${tierA_dir}" ]; then
    ratchet_stub='#!/usr/bin/env bash
# 50-ratchet.sh — 品質債 ratchet gate stub（kit --ratchet 安裝產生）
# baseline 未初始化時引擎 fail-closed 紅——首跑 tighten 產 baseline 後轉綠：
#   RATCHET_ALLOW_TIGHTEN=1 bash <kit>/engines/ratchet.sh --tighten
set -u -o pipefail
bash "'"${KIT_ROOT}"'/engines/ratchet.sh"'
    kit_scaffold_content "${tierA_dir}/50-ratchet.sh" \
        "gates.d/tierA.d/50-ratchet.sh" "${ratchet_stub}"
    chmod +x "${tierA_dir}/50-ratchet.sh" 2>/dev/null || true
else
    echo "提示：尚無 gates.d/tierA.d——ratchet gate stub 未掛；先跑 kit-init --wave-gates 再重跑 --ratchet 即補掛（本次不失敗）。"
    KIT_MODULE_SKIPPED="${KIT_MODULE_SKIPPED} tierA-stub(無gates.d)"
fi

kit_module_report "ratchet"
echo "  首跑 baseline：於 base_branch 上執行 RATCHET_ALLOW_TIGHTEN=1 bash ${KIT_ROOT}/engines/ratchet.sh --tighten 產生 baseline 檔後 commit。"
echo "  範例 counter（00-example）僅示範契約——換成專案自己的品質債計數器後才有 ratchet 語意。"
exit 0
