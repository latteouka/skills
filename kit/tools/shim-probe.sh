#!/usr/bin/env bash
# shim-probe.sh — 3 行 shim（exec bash <target> "$@"）資訊保真 probe（K5.5 必修①配套）
#
# 驗 K6「舊腳本退役為 3 行 shim 指向 kit 引擎」的傳遞層不丟資訊：
# 生成一個記錄器 target（把 $#、逐一 "$@"、pwd、指定 env、預定 exit code 寫到
# 落檔），再生成標準 3 行 shim 指向它，透過 shim 呼叫，對帳四項 round-trip：
#   1. argv 逐位（含空白參數 `a b` 與引號參數 `x"y`）
#   2. cwd（shim 不得改工作目錄）
#   3. env 白名單（環境變數穿透）
#   4. exit code（exec 直通，非 0 不得被吃掉）
# .ts 版（exec tsx <target.ts>）同構；tsx 不在 PATH → SKIP 明示（未驗≠通過）。
#
# 用法：bash tools/shim-probe.sh（無參數）
# exit：0 全過；1 任一 round-trip 失敗；2 fail-closed（mktemp 失敗／未知參數／
#       生成的 shim 非 3 行——probe 自身完整性）
set -u
set -o pipefail

[ $# -eq 0 ] || { echo "FAIL(closed): 未知參數: $*" >&2; exit 2; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/shim-probe.XXXXXXXX")" \
    || { echo "FAIL(closed): mktemp -d 失敗" >&2; exit 2; }
trap 'rm -rf "${SCRATCH}"' EXIT

N=0; FAILED=0
_ok()  { echo "  ✓ ${1}"; N=$((N + 1)); }
_bad() { echo "  ✗ ${1}"; N=$((N + 1)); FAILED=1; }

EXPECT_EXIT=37
TOKEN="tok-shim-probe-$$"
PROBE_CWD="${SCRATCH}/probe-cwd"
mkdir -p "${PROBE_CWD}"
EXPECT_CWD="$(cd "${PROBE_CWD}" && pwd -P)"

# 期望的 argv 記錄（3 參數：含空白、含雙引號、素樸）
WANT_ARGV='argc=3
argv[1]=a b
argv[2]=x"y
argv[3]=plain'

verify_record() { # <kind> <rc> <record_file>
    local kind="${1}" rc="${2}" rec="${3}" got
    if [ ! -f "${rec}" ]; then
        _bad "${kind}-shim: 記錄檔缺失（target 未被執行？）——四項全數視為失敗"
        _bad "${kind}-shim: cwd round-trip（記錄檔缺失）"
        _bad "${kind}-shim: env round-trip（記錄檔缺失）"
        _bad "${kind}-shim: exit-code round-trip（記錄檔缺失）"
        return 0
    fi
    got="$(sed -n '1,4p' "${rec}")"
    if [ "${got}" = "${WANT_ARGV}" ]; then
        _ok "${kind}-shim: argv round-trip（含空白與引號參數）"
    else
        _bad "${kind}-shim: argv round-trip 失敗（記錄: $(printf '%s' "${got}" | tr '\n' '|')）"
    fi
    got="$(sed -n 's/^cwd=//p' "${rec}")"
    if [ "${got}" = "${EXPECT_CWD}" ]; then
        _ok "${kind}-shim: cwd round-trip"
    else
        _bad "${kind}-shim: cwd round-trip 失敗（期望 ${EXPECT_CWD}，記錄 ${got}）"
    fi
    got="$(sed -n 's/^env\.SHIM_PROBE_TOKEN=//p' "${rec}")"
    if [ "${got}" = "${TOKEN}" ]; then
        _ok "${kind}-shim: env round-trip"
    else
        _bad "${kind}-shim: env round-trip 失敗（期望 ${TOKEN}，記錄 ${got}）"
    fi
    if [ "${rc}" -eq "${EXPECT_EXIT}" ]; then
        _ok "${kind}-shim: exit-code round-trip（${EXPECT_EXIT}）"
    else
        _bad "${kind}-shim: exit-code round-trip 失敗（期望 ${EXPECT_EXIT}，實得 ${rc}）"
    fi
}

require_3_lines() { # <shim_path>
    local n
    n="$(wc -l < "${1}" | tr -d ' ')"
    [ "${n}" = "3" ] || { echo "FAIL(closed): 生成的 shim 非 3 行（${n} 行）——probe 沒在測它宣稱要測的東西" >&2; exit 2; }
}

echo "== shim-probe（標準 3 行 shim 傳遞保真）"

# --- bash 版 -----------------------------------------------------------------
cat > "${SCRATCH}/target.sh" <<'EOF'
#!/usr/bin/env bash
set -u
{
    echo "argc=$#"
    i=1
    for a in "$@"; do
        printf 'argv[%s]=%s\n' "${i}" "${a}"
        i=$((i + 1))
    done
    echo "cwd=$(pwd -P)"
    echo "env.SHIM_PROBE_TOKEN=${SHIM_PROBE_TOKEN:-<unset>}"
} > "${SHIM_PROBE_OUT}"
exit 37
EOF
{
    echo '#!/usr/bin/env bash'
    echo '# shim-probe 標準 3 行 shim（與 K6 退役殼同構）'
    printf 'exec bash "%s" "$@"\n' "${SCRATCH}/target.sh"
} > "${SCRATCH}/shim.sh"
chmod +x "${SCRATCH}/shim.sh" "${SCRATCH}/target.sh"
require_3_lines "${SCRATCH}/shim.sh"

BASH_RC=0
( cd "${PROBE_CWD}" \
    && SHIM_PROBE_OUT="${SCRATCH}/record-bash.txt" SHIM_PROBE_TOKEN="${TOKEN}" \
       bash "${SCRATCH}/shim.sh" 'a b' 'x"y' plain ) || BASH_RC=$?
verify_record bash "${BASH_RC}" "${SCRATCH}/record-bash.txt"

# --- .ts 版（exec tsx）同構；tsx 缺席 → SKIP 明示 ------------------------------
if command -v tsx >/dev/null 2>&1; then
    cat > "${SCRATCH}/target.ts" <<'EOF'
const fs = require('fs');
const args = process.argv.slice(2);
const lines: string[] = [];
lines.push(`argc=${args.length}`);
args.forEach((a: string, i: number) => { lines.push(`argv[${i + 1}]=${a}`); });
lines.push(`cwd=${process.cwd()}`);
lines.push(`env.SHIM_PROBE_TOKEN=${process.env.SHIM_PROBE_TOKEN || '<unset>'}`);
fs.writeFileSync(process.env.SHIM_PROBE_OUT, lines.join('\n') + '\n');
process.exit(37);
EOF
    {
        echo '#!/usr/bin/env bash'
        echo '# shim-probe 標準 3 行 shim（.ts 版，exec tsx）'
        printf 'exec tsx "%s" "$@"\n' "${SCRATCH}/target.ts"
    } > "${SCRATCH}/shim-ts.sh"
    chmod +x "${SCRATCH}/shim-ts.sh"
    require_3_lines "${SCRATCH}/shim-ts.sh"

    TS_RC=0
    ( cd "${PROBE_CWD}" \
        && SHIM_PROBE_OUT="${SCRATCH}/record-ts.txt" SHIM_PROBE_TOKEN="${TOKEN}" \
           bash "${SCRATCH}/shim-ts.sh" 'a b' 'x"y' plain ) || TS_RC=$?
    verify_record ts "${TS_RC}" "${SCRATCH}/record-ts.txt"
else
    echo "  SKIP(ts-shim): tsx 不在 PATH——.ts 版 shim 四項 round-trip 跳過（未驗，非通過）"
fi

echo "inspected:${N}"
if [ "${FAILED}" -ne 0 ]; then
    echo "SHIM-PROBE:FAIL"
    exit 1
fi
echo "SHIM-PROBE:PASS"
exit 0
