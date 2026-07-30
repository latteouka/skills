#!/usr/bin/env bash
# installers/kit-init.sh — /kit-init 模組化 dispatcher（K5）。
#
# 用法：kit-init.sh [--intake] [--backlog] [--rtm] [--wave-gates] [--ratchet]
#                   [--hygiene|--ui|--ops] [--all] [--non-interactive]
#
# 行為：
#   - 依賴序執行：intake → backlog → wave-gates → rtm → ratchet
#     （rtm 與 wave-gates 同層；wave-gates 先跑，讓 rtm 的 tierA stub 有
#      gates.d 可掛——反序不會錯，只是 stub 延到下次 --rtm 重跑才補掛）
#   - 依賴缺失（未安裝、且本次未同時指定）→ 報錯提示、exit 1，不自動帶裝：
#       backlog←intake、rtm←intake、wave-gates←backlog、ratchet←wave-gates
#   - --hygiene/--ui/--ops 未實裝（K7 交付）：單獨指定 → 報錯 exit 1；
#     --all → 列 skipped(K7 交付)、整體 exit 0
#   - --non-interactive 透傳給 intake.sh（其餘模組本就無互動）
#   - 未知參數 exit 2；無任何模組參數＝用法錯誤 exit 2（onboarding 訪談的
#     判斷樹在 kit/SKILL.md，由 LLM 執行——installer 只管寫入）
#   - 各模組自行輸出新建/跳過明細（_shared.sh 報告格式）；結尾彙總已執行
#     與略過清單；任一模組失敗 → fail-fast 中止後續、exit 非 0
#
# 冪等：各模組全冪等（已存在一律 skip），dispatcher 重跑安全。
# bash 3.2 相容；一律 ${var} 形式。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    echo "用法: kit-init.sh [--intake] [--backlog] [--rtm] [--wave-gates] [--ratchet] [--all] [--non-interactive]" >&2
    echo "     （--hygiene/--ui/--ops 為 K7 交付，尚未實裝；onboarding 訪談見 kit/SKILL.md）" >&2
}

sel_intake=false
sel_backlog=false
sel_rtm=false
sel_wave_gates=false
sel_ratchet=false
sel_all=false
noni=""
unimpl_requested=""

if [ $# -eq 0 ]; then usage; exit 2; fi

for a in "$@"; do
    case "${a}" in
        --intake)          sel_intake=true ;;
        --backlog)         sel_backlog=true ;;
        --rtm)             sel_rtm=true ;;
        --wave-gates)      sel_wave_gates=true ;;
        --ratchet)         sel_ratchet=true ;;
        --hygiene|--ui|--ops) unimpl_requested="${unimpl_requested} ${a#--}" ;;
        --all)             sel_all=true ;;
        --non-interactive) noni="--non-interactive" ;;
        *)
            echo "錯誤：未知參數 ${a}" >&2
            usage
            exit 2
            ;;
    esac
done

if [ "${sel_all}" = "true" ]; then
    sel_intake=true; sel_backlog=true; sel_rtm=true
    sel_wave_gates=true; sel_ratchet=true
fi

# --hygiene/--ui/--ops：未實裝。單獨指定＝硬錯；--all＝列 skipped 不擋。
if [ -n "${unimpl_requested}" ] && [ "${sel_all}" != "true" ]; then
    echo "錯誤：${unimpl_requested# } 模組尚未實裝（K7 交付）——先用 --intake/--backlog/--rtm/--wave-gates/--ratchet 或 --all。" >&2
    exit 1
fi

if [ "${sel_intake}" != "true" ] && [ "${sel_backlog}" != "true" ] \
    && [ "${sel_rtm}" != "true" ] && [ "${sel_wave_gates}" != "true" ] \
    && [ "${sel_ratchet}" != "true" ]; then
    usage
    exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "${root}" ]; then
    echo "錯誤：不在 git repo 內，無法安裝。" >&2
    exit 1
fi

# --- 依賴檢查（安裝前一次驗完；「本次同時指定」視為將被滿足）----------------

installed_intake()     { [ -f "${root}/.claude/dev/intake.config.yaml" ]; }
installed_backlog()    { [ -f "${root}/.claude/dev/backlog/INDEX.md" ]; }
installed_wave_gates() { [ -d "${root}/.claude/kit/gates.d/tierA.d" ]; }

dep_errors=""
add_dep_error() { dep_errors="${dep_errors}${1}"$'\n'; }

if [ "${sel_backlog}" = "true" ] && [ "${sel_intake}" != "true" ] && ! installed_intake; then
    add_dep_error "錯誤：--backlog 依賴 intake 模組（未偵測到 intake.config.yaml）——先跑 kit-init --intake（依賴不自動帶裝）。"
fi
if [ "${sel_rtm}" = "true" ] && [ "${sel_intake}" != "true" ] && ! installed_intake; then
    add_dep_error "錯誤：--rtm 依賴 intake 模組（spec_layer/spec_check 回填線）——先跑 kit-init --intake（依賴不自動帶裝）。"
fi
if [ "${sel_wave_gates}" = "true" ] && [ "${sel_backlog}" != "true" ] && ! installed_backlog; then
    add_dep_error "錯誤：--wave-gates 依賴 backlog 模組（backlog-writeback-guard 消費）——先跑 kit-init --backlog（依賴不自動帶裝）。"
fi
if [ "${sel_ratchet}" = "true" ] && [ "${sel_wave_gates}" != "true" ] && ! installed_wave_gates; then
    add_dep_error "錯誤：--ratchet 依賴 wave-gates 模組（gates.d 掛 ratchet stub、kit.yaml wave 段）——先跑 kit-init --wave-gates（依賴不自動帶裝）。"
fi

if [ -n "${dep_errors}" ]; then
    printf '%s' "${dep_errors}" >&2
    exit 1
fi

# --- 依賴序執行（fail-fast）--------------------------------------------------

executed=""

run_module() {
    local name="$1" rc
    shift
    echo ""
    echo "── ${name} ──"
    "$@"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "錯誤：${name} 模組安裝失敗（exit ${rc}）——中止後續模組。" >&2
        exit "${rc}"
    fi
    executed="${executed} ${name}"
}

if [ "${sel_intake}" = "true" ]; then
    run_module intake bash "${KIT_ROOT}/installers/intake.sh" ${noni}
fi
if [ "${sel_backlog}" = "true" ]; then
    run_module backlog bash "${KIT_ROOT}/installers/modules/backlog.sh"
fi
if [ "${sel_wave_gates}" = "true" ]; then
    run_module wave-gates bash "${KIT_ROOT}/installers/modules/wave-gates.sh"
fi
if [ "${sel_rtm}" = "true" ]; then
    run_module rtm bash "${KIT_ROOT}/installers/modules/rtm.sh"
fi
if [ "${sel_ratchet}" = "true" ]; then
    run_module ratchet bash "${KIT_ROOT}/installers/modules/ratchet.sh"
fi

echo ""
echo "== kit-init 彙總 =="
echo "  已執行：${executed# }（各模組新建/跳過明細如上）"
if [ "${sel_all}" = "true" ]; then
    echo "  skipped(K7 交付)：hygiene ui ops"
fi
exit 0
