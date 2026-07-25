#!/usr/bin/env bash
# 純 bash 測試 harness — 無外部依賴，bash 3.2 相容。
# 用法：tests/run.sh [case 檔名]；不帶參數跑全部 tests/cases/*.sh

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_ROOT

TESTS_RUN=0
TESTS_FAILED=0

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
    echo "--- ${TESTS_RUN} assertions, ${TESTS_FAILED} failed ---"

    if [ "${FULL_SUITE:-0}" = "1" ]; then
        baseline=0
        if [ -f "$ASSERTION_BASELINE_FILE" ]; then
            baseline="$(cat "$ASSERTION_BASELINE_FILE" 2>/dev/null)"
        fi
        case "$baseline" in ''|*[!0-9]*) baseline=0 ;; esac

        if [ "$TESTS_RUN" -lt "$baseline" ]; then
            echo "FAIL: assertion 總數從 ${baseline} 掉到 ${TESTS_RUN}——可能有測試檔被截斷、跳過，或中途出錯提早結束。"
            echo "  若為刻意移除測試，執行：echo ${TESTS_RUN} > ${ASSERTION_BASELINE_FILE}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        elif [ "$TESTS_RUN" -gt "$baseline" ]; then
            printf '%s' "$TESTS_RUN" > "$ASSERTION_BASELINE_FILE"
        fi
    fi

    [ "$TESTS_FAILED" -eq 0 ] || exit 1
    exit 0
}

if [ $# -gt 0 ]; then
    FULL_SUITE=0
    . "$KIT_ROOT/tests/cases/$1"
else
    FULL_SUITE=1
    for c in "$KIT_ROOT"/tests/cases/*.sh; do
        [ -f "$c" ] || continue
        echo "== $(basename "$c")"
        . "$c"
    done
fi

kit_test_report
