#!/usr/bin/env bash
# kit-audit.sh — provenance manifest 三態稽核機械層（/kit-audit skill 的執行核心）
#
# 逐行比對 manifest 記載 vs kit 現檔 vs 上游現檔，報告三態：
#   同步      雙側 hash 皆符（或依規則跳過）
#   上游漂移  上游檔 hash ≠ upstream_sha256——上游又演化了，kit 沒跟上
#   kit 演化  kit 檔 hash ≠ kit_sha256——kit 有意改動但 manifest 沒記帳
# 兩態非互斥：同一行可同時上游漂移＋kit 演化，並列報。
#
# closed ledger 完整性（fail 類）：
#   檔案缺失  manifest 列的 kit 檔不存在
#   無帳機制  受管目錄（engines/ gates/ tools/ hooks/ scripts/ lib/ installers/
#             遞迴 *.sh）存在但 manifest 未列——受管範圍與 tests/cases/manifest.sh
#             同步，改一邊必改另一邊
#
# 跳過規則（判定矩陣，凍結於 wave kit-k1）：
#   hash 欄 = `-`        → 跳過該側比對
#   upstream=kit:original → 冒號切分前特判，跳過上游側（kit 自創機制）
#   upstream_sha256 = `-` → 跳過上游比對且不解析路徑（extracted-pattern、(多源) 等）
#   kit_path 含 #anchor   → 存在性檢查剝 fragment；hash 比對跳過（段落錨，K1 檔級粒度）
#   上游檔已刪            → 報「上游檔已移除，人工裁定」歸漂移，不 crash 不誤報同步
#
# exit code：
#   0  全同步（無漂移、無缺失、無無帳）
#   1  有漂移／檔案缺失／無帳機制——人工裁定後更新 manifest
#   2  fail-closed：manifest 缺失、0 資料行、malformed 行、inspected:0
#      （「跑了但檢查 0 個機制」與「全綠」必須可區分——防假 0）
#
# 用法：
#   bash tools/kit-audit.sh [--manifest <path>] [--kit-root <path>]
#   環境：KIT_AUDIT_UPSTREAM_BASE 上游專案根（預設 ~/projects；dfaa:x/y →
#         $BASE/dfaa/x/y）——測試 seam，fixture 全 scratch 隔離用
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
MANIFEST=""
UPSTREAM_BASE="${KIT_AUDIT_UPSTREAM_BASE:-$HOME/projects}"

while [ $# -gt 0 ]; do
    case "$1" in
        --manifest) MANIFEST="$2"; shift 2 ;;
        --kit-root) KIT_ROOT="$(cd "$2" && pwd -P)"; shift 2 ;;
        *) echo "未知參數: $1" >&2; exit 2 ;;
    esac
done
[ -n "$MANIFEST" ] || MANIFEST="$KIT_ROOT/manifest/provenance.tsv"

# --- fail-closed 前置
if [ ! -f "$MANIFEST" ]; then
    echo "FAIL(closed): manifest 不存在: $MANIFEST" >&2
    exit 2
fi
MALFORMED="$(awk -F'\t' '!/^#/ && !/^$/ && NF!=8 { print NR }' "$MANIFEST" | tr '\n' ' ')"
if [ -n "$MALFORMED" ]; then
    echo "FAIL(closed): manifest malformed 行（NF≠8）: 行號 $MALFORMED" >&2
    exit 2
fi

TAB="$(printf '\t')"
N_INSPECTED=0
N_SYNC=0
UP_DRIFT=""    # 換行分隔的報告行
KIT_EVOLVED=""
MISSING=""

while IFS="$TAB" read -r kp up _uc uh kh _abs _mode _notes; do
    case "$kp" in '#'*|'') continue ;; esac
    N_INSPECTED=$((N_INSPECTED + 1))
    kp_file="${kp%%#*}"          # 剝 #anchor
    has_anchor=0
    [ "$kp_file" != "$kp" ] && has_anchor=1
    row_drift=0

    # 檔案缺失（closed ledger：列了就必須存在）
    if [ ! -f "$KIT_ROOT/$kp_file" ]; then
        MISSING="${MISSING}  - ${kp}（manifest 列帳但檔案不存在）
"
        continue
    fi

    # kit 側比對（hash=- 或 #anchor 行跳過）
    if [ "$kh" != "-" ] && [ "$has_anchor" -eq 0 ]; then
        kit_actual="$(shasum -a 256 "$KIT_ROOT/$kp_file" | cut -d' ' -f1)"
        if [ "sha256:$kit_actual" != "$kh" ]; then
            KIT_EVOLVED="${KIT_EVOLVED}  - ${kp}（更新 kit_sha256 + notes 記一句演化內容）
"
            row_drift=1
        fi
    fi

    # 上游側比對（kit:original 特判；uh=- 跳過且不解析路徑；#anchor 跳過 hash）
    if [ "$up" != "kit:original" ] && [ "$uh" != "-" ] && [ "$has_anchor" -eq 0 ]; then
        up_proj="${up%%:*}"
        up_path="${up#*:}"
        up_file="$UPSTREAM_BASE/$up_proj/$up_path"
        if [ ! -f "$up_file" ]; then
            UP_DRIFT="${UP_DRIFT}  - ${kp} ← ${up}（上游檔已移除，人工裁定）
"
            row_drift=1
        else
            up_actual="$(shasum -a 256 "$up_file" | cut -d' ' -f1)"
            if [ "sha256:$up_actual" != "$uh" ]; then
                UP_DRIFT="${UP_DRIFT}  - ${kp} ← ${up}（diff: diff \"$up_file\" \"$KIT_ROOT/$kp_file\"）
"
                row_drift=1
            fi
        fi
    fi

    [ "$row_drift" -eq 0 ] && N_SYNC=$((N_SYNC + 1))
done < "$MANIFEST"

# runtime self-canary：0 資料行 = manifest 路徑錯或整檔註解——與全綠必須可區分
if [ "$N_INSPECTED" -eq 0 ]; then
    echo "FAIL(closed): manifest 0 資料行（inspected:0）——路徑錯或檔案空" >&2
    exit 2
fi

# --- 無帳掃描（受管目錄 vs ledger 集合差）
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
(cd "$KIT_ROOT" && find engines gates tools hooks scripts lib installers -name '*.sh' -type f 2>/dev/null | sort) > "$SCRATCH/actual.txt"
awk -F'\t' '!/^#/ && !/^$/ { p=$1; sub(/#.*$/, "", p); print p }' "$MANIFEST" | sort -u > "$SCRATCH/ledger.txt"
UNLEDGERED="$(comm -23 "$SCRATCH/actual.txt" "$SCRATCH/ledger.txt")"

# --- 報告
echo "== kit-audit 報告（manifest: ${MANIFEST}）"
echo "同步: $N_SYNC"
if [ -n "$UP_DRIFT" ]; then
    printf '上游漂移（吸收→更新雙 hash+commit 欄／擱置→notes 記理由日期）:\n%s' "$UP_DRIFT"
fi
if [ -n "$KIT_EVOLVED" ]; then
    printf 'kit 演化（kit 改了沒記帳）:\n%s' "$KIT_EVOLVED"
fi
if [ -n "$MISSING" ]; then
    printf '檔案缺失:\n%s' "$MISSING"
fi
if [ -n "$UNLEDGERED" ]; then
    echo "無帳機制（受管目錄存在但 manifest 未列——closed ledger 不是 best-effort）:"
    printf '%s\n' "$UNLEDGERED" | sed 's/^/  - /'
fi
echo "inspected:$N_INSPECTED"

if [ -n "$UP_DRIFT" ] || [ -n "$KIT_EVOLVED" ] || [ -n "$MISSING" ] || [ -n "$UNLEDGERED" ]; then
    exit 1
fi
exit 0
