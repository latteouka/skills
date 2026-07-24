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

kit_test_report() {
    echo ""
    echo "--- ${TESTS_RUN} assertions, ${TESTS_FAILED} failed ---"
    [ "$TESTS_FAILED" -eq 0 ] || exit 1
    exit 0
}

if [ $# -gt 0 ]; then
    . "$KIT_ROOT/tests/cases/$1"
else
    for c in "$KIT_ROOT"/tests/cases/*.sh; do
        [ -f "$c" ] || continue
        echo "== $(basename "$c")"
        . "$c"
    done
fi

kit_test_report
