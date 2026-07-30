#!/usr/bin/env bash
# engines/canary.sh — 專案 gate 自測引擎（消費 .claude/kit/canary.d/）
#
# 逐 gate 執行三斷言（violation 必紅／clean 必綠／inspected:N>0），核心在
# lib/canary-harness.sh。gate 清單由 canary.d/ 目錄自動發現。
#
# canary.d/<gate>/ 契約（詳見 references/declaration-formats.md「canary.d」節）：
#   run.sh       必要——引擎把 fixture 樹複製進 scratch 後、以 scratch 為 cwd 執行；
#                exit code = gate 結果；stdout 須含 inspected:N（有 fixture 的 gate
#                必填——三斷言之 3）
#   violation/   必要——違規 fixture 樹（*.fixture 副檔名遮蔽自動還原）
#   clean/       必要——語意相近但合法的 fixture 樹
#   git          選配 marker 檔——存在＝該 gate 需要 scratch git repo（引擎先
#                git init + seed origin/main 再複製 fixture）
#   setup.sh     選配——git 拓撲建構（scratch repo 內、fixture 複製後、run.sh 前
#                執行；建 commit/merge/branch 等目錄 fixture 表達不了的狀態）
#
# 用法：bash engines/canary.sh [--decl-dir <path>]
#   --decl-dir 預設 <repo>/.claude/kit（測試 seam）
#
# exit：0=全部 gate 三斷言過；1=任一敗；2=fail-closed（canary.d 缺失或空——
#   「跑了但測了 0 支 gate」與全綠必須可區分）

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
. "${KIT_ROOT}/lib/canary-harness.sh"

DECL_DIR=""
while [ $# -gt 0 ]; do
    case "${1}" in
        --decl-dir) DECL_DIR="${2}"; shift 2 ;;
        *) echo "canary: 未知參數 [${1}]" >&2; exit 2 ;;
    esac
done
if [ -z "${DECL_DIR}" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "canary: 不在 git repo 內且未給 --decl-dir" >&2; exit 2; }
    DECL_DIR="${PROJECT_ROOT}/.claude/kit"
fi
CANARY_D="${DECL_DIR}/canary.d"

if [ ! -d "${CANARY_D}" ]; then
    echo "FAIL(closed): canary.d 不存在 [${CANARY_D}]——未宣告任何 gate fixture" >&2
    exit 2
fi

# --- gates.d↔canary.d 對帳（K5.5 GPT §4.3）：canary.d 只列舉自己有的目錄，
# 一支 gates.d stub 沒人補 fixture 就永遠測不到。逐 stub 反查 canary.d，
# 缺且未 .skip 豁免 → FAIL 列名 exit 1；gates.d 不存在 → SKIP 不誤殺。
RECONCILE_OUT="$(canary_reconcile_gates "${DECL_DIR}")"
RECONCILE_RC=$?
[ -z "${RECONCILE_OUT}" ] || echo "${RECONCILE_OUT}"
if [ "${RECONCILE_RC}" -ne 0 ]; then
    echo "" >&2
    echo "FAIL(closed): gates.d↔canary.d 對帳失敗——上列 gate 缺 canary.d fixture 且未豁免" >&2
    exit 1
fi

TMP_ROOT="$(canary_tmp_init kit-canary)" || exit 1
cleanup() { rm -rf "${TMP_ROOT}"; }
trap cleanup EXIT

N_TOTAL=0
N_PASS=0
FAILED_GATES=""

for gate_dir in "${CANARY_D}"/*/; do
    [ -d "${gate_dir}" ] || continue
    gate_name="$(basename "${gate_dir}")"
    N_TOTAL=$((N_TOTAL + 1))
    echo ""
    echo "=== [canary] ${gate_name} ==="

    gate_ok=0
    if [ ! -f "${gate_dir}run.sh" ]; then
        echo "  ✗ ${gate_name}: run.sh 缺失（canary.d 契約必要件）"
        gate_ok=1
    elif [ ! -d "${gate_dir}violation" ] || [ ! -d "${gate_dir}clean" ]; then
        echo "  ✗ ${gate_name}: violation/ 或 clean/ fixture 目錄缺失"
        gate_ok=1
    else
        for label in violation clean; do
            scratch="${TMP_ROOT}/${gate_name}/${label}"
            if [ -f "${gate_dir}git" ]; then
                canary_new_scratch_repo "${scratch}" || { gate_ok=1; continue; }
                canary_seed_origin_main "${scratch}" >/dev/null || { gate_ok=1; continue; }
            fi
            canary_copy_fixture_tree "${gate_dir}${label}" "${scratch}" || { gate_ok=1; continue; }
            if [ -f "${gate_dir}setup.sh" ]; then
                ( cd "${scratch}" && bash "${gate_dir}setup.sh" ) >/dev/null 2>&1 || {
                    echo "  ✗ ${gate_name}: setup.sh 失敗（${label}）"; gate_ok=1; continue; }
            fi
            out="$( (cd "${scratch}" && bash "${gate_dir}run.sh") 2>&1 )"
            rc=$?
            if [ "${label}" = "violation" ]; then
                if [ "${rc}" -eq 0 ]; then
                    echo "  ✗ ${gate_name}: violation fixture 未被攔（exit 0）"
                    gate_ok=1
                else
                    echo "  ✓ ${gate_name}: violation:caught (exit ${rc})"
                fi
                inspected="$(canary_extract_inspected "${out}")" || {
                    echo "  ✗ ${gate_name}: inspected:UNAVAILABLE(輸出無 inspected:N)"
                    gate_ok=1
                    inspected=""
                }
                if [ -n "${inspected}" ] && [ "${inspected}" -eq 0 ] 2>/dev/null; then
                    echo "  ✗ ${gate_name}: inspected:0——假 PASS 母題"
                    gate_ok=1
                fi
            else
                if [ "${rc}" -ne 0 ]; then
                    echo "  ✗ ${gate_name}: clean fixture 被誤攔（exit ${rc}）"
                    gate_ok=1
                else
                    echo "  ✓ ${gate_name}: clean:pass"
                fi
                inspected="$(canary_extract_inspected "${out}")" || {
                    echo "  ✗ ${gate_name}: clean inspected:UNAVAILABLE(輸出無 inspected:N)——clean 假通過母題（跑了 0 個檢查與真通過無法區分）"
                    gate_ok=1
                    inspected=""
                }
                if [ -n "${inspected}" ] && [ "${inspected}" -eq 0 ] 2>/dev/null; then
                    echo "  ✗ ${gate_name}: clean inspected:0——clean 假通過母題（跑了 0 個檢查與真通過無法區分）"
                    gate_ok=1
                fi
            fi
        done
    fi

    if [ "${gate_ok}" -eq 0 ]; then
        N_PASS=$((N_PASS + 1))
    else
        FAILED_GATES="${FAILED_GATES} ${gate_name}"
    fi
done

echo ""
if [ "${N_TOTAL}" -eq 0 ]; then
    echo "FAIL(closed): canary.d 存在但無任何 gate 目錄——測了 0 支 gate" >&2
    exit 2
fi
echo "== canary 總結：${N_PASS}/${N_TOTAL} gate PASS"
if [ "${N_PASS}" -ne "${N_TOTAL}" ]; then
    echo "   FAILED:${FAILED_GATES}"
    exit 1
fi
exit 0
