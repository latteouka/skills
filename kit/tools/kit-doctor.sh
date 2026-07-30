#!/usr/bin/env bash
# kit-doctor.sh — 消費者宣告健檢（consumer contract 檢查層；K5.5 GPT §1.1／§5.2）
#
# 母題：kit 引擎與消費者宣告之間沒有版本協商——中央 kit 一更新，所有消費者
# 行為立即改變，無法重現某次消費者 commit 當時的品質系統。本工具在消費者側
# 驗證宣告與 kit 的契約一致性（K6 前 dfaa Step A 之後首跑）。
#
# 檢查項（各自獨立報告行，fail-closed 匯總）：
#   1. contract_version 缺席或非引擎支援集合（目前 {1}）→ FAIL
#   2. kit_pin 非空且 ≠ kit HEAD（短/長 hash 皆可）→ 預設 WARN；--strict-pin
#      下 FAIL（K6 凍結期用）。空值/缺鍵＝不 pin（滾動），明示不攔。
#      宣告了 pin 但 kit root 非 git repo（驗不了）→ FAIL（不可驗證≠通過）
#   3. 恆綠 example gate：gates.d stub 內容與 kit/templates/gates.d/ 對應 tier
#      模板字面相同（未客製）→ FAIL 列名；模板目錄缺失無法比對 → FAIL
#   4. canary.d 不存在或 0 個 gate fixture 目錄 → FAIL
#   5. gates.d↔canary.d 對帳（重用 lib/canary-harness.sh 的
#      canary_reconcile_gates，邏輯與 engines/canary.sh 完全一致）→ FAIL
#   6. 必要欄位空降級：依 modules 宣告判定——ratchet 消費者的 baseline_file、
#      rtm 消費者的 matrix_dir。key 存在但空值（宣告降級）→ FAIL 指名；
#      缺鍵＝引擎預設 → 不攔（kit_decl_get 兩態語意）
#
# 輸入面安全（sharp-edges）：全程只讀——宣告檔內容經 grep/sed 取值、cmp 比對、
# 字串比較，絕不 eval、不當命令執行；kit_pin 宣告值不傳入 git rev-parse
# （防 revision 表達式注入），只對 rev-parse HEAD 的結果做字串前綴比對。
#
# 用法：bash tools/kit-doctor.sh [--decl-dir <path>] [--kit-root <path>] [--strict-pin]
#   --decl-dir  預設 <repo>/.claude/kit（測試 seam，比照 engines/canary.sh）
#   --kit-root  pin 驗證的 git 目標＋模板目錄來源；預設本腳本所在 kit
#               （lib 一律從本腳本位置載入，不受此參數影響）
#
# exit：0=全過（WARN 允許）；1=任一 FAIL；2=fail-closed（未知參數、inspected:0）
# 輸出尾行 inspected:N（N=實檢項數；SKIP 不計）——0 項與全綠必須可區分。

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SELF_KIT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
. "${SELF_KIT_ROOT}/lib/common.sh" 2>/dev/null || {
    echo "kit-doctor: 找不到 kit/lib/common.sh，fail-closed" >&2; exit 2; }
. "${SELF_KIT_ROOT}/lib/canary-harness.sh" 2>/dev/null || {
    echo "kit-doctor: 找不到 kit/lib/canary-harness.sh，fail-closed" >&2; exit 2; }

SUPPORTED_CONTRACTS="1"   # 引擎支援的 contract_version 集合（空白分隔）

DECL_DIR=""
KIT_ROOT_TARGET="${SELF_KIT_ROOT}"
STRICT_PIN=0
while [ $# -gt 0 ]; do
    case "${1}" in
        --decl-dir)   DECL_DIR="${2}"; shift 2 ;;
        --kit-root)   KIT_ROOT_TARGET="$(cd "${2}" && pwd -P)" || exit 2; shift 2 ;;
        --strict-pin) STRICT_PIN=1; shift ;;
        *) echo "kit-doctor: 未知參數 [${1}]" >&2; exit 2 ;;
    esac
done
if [ -z "${DECL_DIR}" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
        echo "kit-doctor: 不在 git repo 內且未給 --decl-dir" >&2; exit 2; }
    DECL_DIR="${PROJECT_ROOT}/.claude/kit"
fi

KY="${DECL_DIR}/kit.yaml"
GATES_D="${DECL_DIR}/gates.d"
CANARY_D="${DECL_DIR}/canary.d"
SENTINEL="__KIT_DOCTOR_UNSET__"

N_INSPECTED=0
N_FAIL=0
N_WARN=0

_fail() { echo "  ✗ ${1}"; N_FAIL=$((N_FAIL + 1)); }
_warn() { echo "  ⚠ ${1}"; N_WARN=$((N_WARN + 1)); }
_ok()   { echo "  ✓ ${1}"; }

echo "== kit-doctor 報告（decl: ${DECL_DIR}｜kit: ${KIT_ROOT_TARGET}）"

if [ ! -f "${KY}" ]; then
    _fail "kit.yaml 不存在 [${KY}]——主宣告檔缺失，後續 kit.yaml 檢查全數以缺席論"
fi

# --- 1. contract_version ------------------------------------------------------
N_INSPECTED=$((N_INSPECTED + 1))
CV="$(kit_decl_get "${KY}" contract_version "${SENTINEL}")"
if [ "${CV}" = "${SENTINEL}" ]; then
    _fail "contract_version 缺席——宣告檔未聲明格式版本（引擎支援集合 {${SUPPORTED_CONTRACTS}}）"
elif [ -z "${CV}" ]; then
    _fail "contract_version 空值——版本協商不可降級（引擎支援集合 {${SUPPORTED_CONTRACTS}}）"
else
    CV_OK=0
    for v in ${SUPPORTED_CONTRACTS}; do
        [ "${CV}" = "${v}" ] && CV_OK=1
    done
    if [ "${CV_OK}" -eq 1 ]; then
        _ok "contract_version: ${CV}（引擎支援集合 {${SUPPORTED_CONTRACTS}}）"
    else
        _fail "contract_version 不支援：宣告 [${CV}]，引擎支援集合 {${SUPPORTED_CONTRACTS}}"
    fi
fi

# --- 2. kit_pin ---------------------------------------------------------------
N_INSPECTED=$((N_INSPECTED + 1))
PIN="$(kit_decl_get "${KY}" kit_pin "")"   # 缺鍵與空值同義：不 pin（滾動）
if [ -z "${PIN}" ]; then
    _ok "kit_pin: 未 pin（滾動模式——消費者跟隨 kit HEAD）"
else
    KIT_HEAD="$(git -C "${KIT_ROOT_TARGET}" rev-parse HEAD 2>/dev/null)" || KIT_HEAD=""
    if [ -z "${KIT_HEAD}" ]; then
        _fail "kit_pin 已宣告 [${PIN}] 但 kit root 非 git repo，無法驗證——不可驗證不得當通過 [${KIT_ROOT_TARGET}]"
    else
        PIN_MATCH=0
        PIN_VALID=1
        case "${PIN}" in
            *[!0-9a-f]*|"") PIN_VALID=0 ;;   # 非 hex ≠ 任何 hash（且不進 git 解析）
            *) [ "${#PIN}" -ge 7 ] || PIN_VALID=0 ;;   # 前綴比對需最小長度，防 1 字元 pin 矇中
        esac
        if [ "${PIN_VALID}" -eq 1 ]; then
            case "${KIT_HEAD}" in "${PIN}"*) PIN_MATCH=1 ;; esac
        else
            _fail "kit_pin 無效：[${PIN}]——須為 ≥7 位小寫 hex（git abbrev 慣例）；無效 pin 視同宣告了但驗不了"
        fi
        if [ "${PIN_VALID}" -eq 0 ]; then
            :   # 已 FAIL，不再進 match 分流
        elif [ "${PIN_MATCH}" -eq 1 ]; then
            _ok "kit_pin: ${PIN}＝當前 kit HEAD（${KIT_HEAD}）"
        elif [ "${STRICT_PIN}" -eq 1 ]; then
            _fail "kit_pin 不符（--strict-pin）：宣告 [${PIN}]，當前 kit HEAD [${KIT_HEAD}]——凍結期不得漂移"
        else
            _warn "kit_pin 不符：宣告 [${PIN}]，當前 kit HEAD [${KIT_HEAD}]——品質系統與 pin 當時不同；凍結期請用 --strict-pin"
        fi
    fi
fi

# --- 3. 恆綠 example gate（stub 未客製）---------------------------------------
TPL_D="${KIT_ROOT_TARGET}/templates/gates.d"
if [ ! -d "${GATES_D}" ]; then
    echo "  SKIP(恆綠 example gate): gates.d 不存在 [${GATES_D}]——本專案未用 wave-gate 模組"
else
    for tier in tierA tierB; do
        tier_dir="${GATES_D}/${tier}.d"
        [ -d "${tier_dir}" ] || continue
        for stub in "${tier_dir}"/*.sh; do
            [ -f "${stub}" ] || continue
            N_INSPECTED=$((N_INSPECTED + 1))
            if [ ! -d "${TPL_D}/${tier}.d" ]; then
                _fail "恆綠 example gate 無法驗證：模板目錄缺失 [${TPL_D}/${tier}.d]（kit 安裝不完整）"
                continue
            fi
            stub_is_template=0
            n_tpl_compared=0
            for tpl in "${TPL_D}/${tier}.d"/*.sh; do
                [ -f "${tpl}" ] || continue
                n_tpl_compared=$((n_tpl_compared + 1))
                if cmp -s "${stub}" "${tpl}"; then
                    stub_is_template=1
                    break
                fi
            done
            # 零模板檔＝比對迴圈空轉，「已客製」無依據——視同模板目錄缺失（防靜默通過）
            if [ "${n_tpl_compared}" -eq 0 ] && [ "${stub_is_template}" -eq 0 ]; then
                _fail "恆綠 example gate 無法驗證：模板目錄零 *.sh [${TPL_D}/${tier}.d]（kit 安裝不完整）"
                continue
            fi
            if [ "${stub_is_template}" -eq 1 ]; then
                _fail "恆綠 example gate 未客製：${tier}.d/$(basename "${stub}") 與 kit 模板字面相同——範例 stub 恆綠，等於沒有 gate"
            else
                _ok "gate stub 已客製：${tier}.d/$(basename "${stub}")"
            fi
        done
    done
fi

# --- 4. canary.d 存在且非空 ----------------------------------------------------
N_INSPECTED=$((N_INSPECTED + 1))
if [ ! -d "${CANARY_D}" ]; then
    _fail "canary.d 不存在 [${CANARY_D}]——未宣告任何 gate fixture，gate 自測空轉"
else
    N_FIXTURES="$(find "${CANARY_D}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${N_FIXTURES}" -eq 0 ]; then
        _fail "canary.d 存在但 0 個 gate fixture 目錄 [${CANARY_D}]——「跑了但測 0 支 gate」與全綠必須可區分"
    else
        _ok "canary.d: ${N_FIXTURES} 個 gate fixture"
    fi
fi

# --- 5. gates.d↔canary.d 對帳（重用 canary-harness）---------------------------
if [ -d "${GATES_D}" ]; then
    N_INSPECTED=$((N_INSPECTED + 1))
    RECONCILE_OUT="$(canary_reconcile_gates "${DECL_DIR}")"
    RECONCILE_RC=$?
    [ -z "${RECONCILE_OUT}" ] || printf '%s\n' "${RECONCILE_OUT}"
    if [ "${RECONCILE_RC}" -ne 0 ]; then
        _fail "gates.d↔canary.d 對帳失敗——上列 gate 缺 canary.d fixture 且未豁免"
    else
        _ok "gates.d↔canary.d 對帳：全數有 fixture 或已豁免"
    fi
else
    echo "  SKIP(gates.d↔canary.d 對帳): gates.d 不存在——本專案未用 wave-gate 模組"
fi

# --- 6. 必要欄位空降級（依 modules 宣告判定）-----------------------------------
MODULES="$(kit_decl_get "${KY}" modules "")"
_check_required() { # <module> <key>
    local module="${1}" key="${2}" v
    N_INSPECTED=$((N_INSPECTED + 1))
    v="$(kit_decl_get "${KY}" "${key}" "${SENTINEL}")"
    if [ "${v}" = "${SENTINEL}" ]; then
        _ok "必要欄位 ${key}: 缺鍵＝引擎預設（${module} 模組）"
    elif [ -z "${v}" ]; then
        _fail "必要欄位空降級：${key} 宣告空值（${module} 模組必要欄位，留空＝引擎降級不可用）"
    else
        _ok "必要欄位 ${key}: [${v}]（${module} 模組）"
    fi
}
for m in ${MODULES}; do
    case "${m}" in
        ratchet) _check_required ratchet baseline_file ;;
        rtm)     _check_required rtm matrix_dir ;;
    esac
done

# --- 匯總 -----------------------------------------------------------------------
echo ""
echo "== 匯總：FAIL ${N_FAIL}／WARN ${N_WARN}"
echo "inspected:${N_INSPECTED}"

if [ "${N_INSPECTED}" -eq 0 ]; then
    echo "FAIL(closed): 實檢 0 項——doctor 空轉與全綠必須可區分" >&2
    exit 2
fi
[ "${N_FAIL}" -eq 0 ] || exit 1
exit 0
