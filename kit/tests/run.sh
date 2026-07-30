#!/usr/bin/env bash
# 純 bash 測試 harness — 無外部依賴，bash 3.2 相容。
# 用法：tests/run.sh [case 檔名]；不帶參數跑全部 tests/cases/*.sh

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_ROOT

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# 依賴／runtime 缺席時的明示跳過：印 SKIP(原因)，計入 skipped 計數，
# 不計入 assertion 數（不得用恆真 assertion 佔位假裝有驗）。
# baseline 守衛比對 TESTS_RUN + TESTS_SKIPPED，跨機器（有無 runtime）總數守恆。
kit_test_skip() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "SKIP(${1:-未註明原因})"
}

assert_eq() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$1" = "$2" ]; then return 0; fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: ${3:-assert_eq}"
    echo "  expected: [$1]"
    echo "  actual:   [$2]"
}

assert_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: ${3:-assert_contains}"
    echo "  haystack: [$1]"
    echo "  needle:   [$2]"
}

assert_not_contains() {
    TESTS_RUN=$((TESTS_RUN + 1))
    case "$1" in
        *"$2"*)
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "FAIL: ${3:-assert_not_contains}"
            echo "  haystack: [$1]"
            echo "  unwanted: [$2]"
            return 0
            ;;
    esac
}

# 建立臨時測試專案（含 git repo 與 .claude/dev/）
kit_test_sandbox() {
    local d
    d="$(mktemp -d)"
    mkdir -p "$d/.claude/dev"
    git -C "$d" init -q
    echo "$d"
}

# assertion 總數下限守衛（只在跑完整套 tests/cases/*.sh 時生效）。
# 2026-07-25 起加入：review 曾把 archive.sh 測試檔截斷一部分，結果變成
# 「90 assertions, 0 failed」，exit 0——測試檔被整個跳過與全數通過長得
# 一模一樣，沒有任何訊號能區分。
#
# 用 ratchet（只降不升）而非精確比對，避免變成每次加測試都要手動更新的
# 維護負擔：assertion 數成長時自動把下限往上調；只有「這次比上次記錄的
# 下限還低」才視為異常（測試檔被截斷／跳過／中途出錯提早結束）並 fail，
# 需要人工確認是刻意移除測試才手動改小 baseline 檔。
ASSERTION_BASELINE_FILE="$KIT_ROOT/tests/assertion-baseline.txt"

kit_test_report() {
    echo ""
    if [ "${TESTS_SKIPPED}" -gt 0 ]; then
        echo "--- ${TESTS_RUN} assertions, ${TESTS_FAILED} failed, ${TESTS_SKIPPED} skipped ---"
    else
        echo "--- ${TESTS_RUN} assertions, ${TESTS_FAILED} failed ---"
    fi

    if [ "${FULL_SUITE:-0}" = "1" ]; then
        baseline=0
        if [ -f "$ASSERTION_BASELINE_FILE" ]; then
            baseline="$(cat "$ASSERTION_BASELINE_FILE" 2>/dev/null)"
        fi
        case "$baseline" in ''|*[!0-9]*) baseline=0 ;; esac

        # 守衛用 assertions + skipped：SKIP 不算通過的驗證，但算「測試檔仍在、
        # 檢查點仍被走到」——防截斷守衛在缺 runtime 的機器上不因此假紅。
        kit_total=$((TESTS_RUN + TESTS_SKIPPED))

        if [ "$kit_total" -lt "$baseline" ]; then
            echo "FAIL: assertion 總數從 ${baseline} 掉到 ${kit_total}——可能有測試檔被截斷、跳過，或中途出錯提早結束。"
            echo "  若為刻意移除測試，執行：echo ${kit_total} > ${ASSERTION_BASELINE_FILE}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif [ "$kit_total" -gt "$baseline" ]; then
            # 預設唯讀：baseline 只在明示 UPDATE_BASELINE=1 時上調（防跑一次測試
            # 就靜默自改寫守衛門檻）；下修永遠走人工 echo。
            if [ "${UPDATE_BASELINE:-0}" = "1" ]; then
                printf '%s' "$kit_total" > "$ASSERTION_BASELINE_FILE"
                echo "baseline 已上調：${baseline} → ${kit_total}（UPDATE_BASELINE=1）"
            else
                echo "NOTE: assertion 總數 ${kit_total} > baseline ${baseline}——要上調 baseline 請以 UPDATE_BASELINE=1 重跑。"
            fi
        fi
    fi

    [ "$TESTS_FAILED" -eq 0 ] || exit 1
    exit 0
}

if [ $# -gt 0 ]; then
    # 單 case 模式：維持直接 source（行為不變，便於互動 debug）。
    FULL_SUITE=0
    . "$KIT_ROOT/tests/cases/$1"
else
    # 全套模式：每個 case 在子 shell 執行——export／函式／變數不跨 case 殘留
    # （跨 case 汙染曾讓 case 偷依賴前面 case 的環境而不自知）。
    # 子 shell 繼承 assert_* 函式與當前計數，跑完把累加後的計數落檔傳回父 shell。
    FULL_SUITE=1
    KIT_CASE_COUNTS="$(mktemp)"
    for c in "$KIT_ROOT"/tests/cases/*.sh; do
        [ -f "$c" ] || continue
        echo "== $(basename "$c")"
        : > "$KIT_CASE_COUNTS"
        (
            . "$c"
            printf '%s %s %s\n' "${TESTS_RUN}" "${TESTS_FAILED}" "${TESTS_SKIPPED}" > "$KIT_CASE_COUNTS"
        )
        kit_case_rc=$?
        kit_cr=""; kit_cf=""; kit_cs=""
        IFS=' ' read -r kit_cr kit_cf kit_cs < "$KIT_CASE_COUNTS" || true
        kit_counts_ok=1
        for v in "${kit_cr}" "${kit_cf}" "${kit_cs}"; do
            case "$v" in ''|*[!0-9]*) kit_counts_ok=0 ;; esac
        done
        if [ "$kit_counts_ok" = "1" ]; then
            TESTS_RUN="${kit_cr}"
            TESTS_FAILED="${kit_cf}"
            TESTS_SKIPPED="${kit_cs}"
        else
            # 計數未回傳＝case 子 shell 提早終止（exit／set -u 中斷／檔案截斷），
            # 該 case 的部分斷言不可信——記一筆 FAIL，不得靜默略過。
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "FAIL: $(basename "$c") 子 shell 提早終止（exit ${kit_case_rc}），計數未回傳——case 可能被截斷或中途 exit"
        fi
    done
    rm -f "$KIT_CASE_COUNTS"
fi

kit_test_report
