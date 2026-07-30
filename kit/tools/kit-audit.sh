#!/usr/bin/env bash
# kit-audit.sh — provenance manifest 稽核機械層（/kit-audit skill 的執行核心）
#
# 逐行比對 manifest 記載 vs kit 現檔 vs 上游（歷史 blob＋live 檔），分類報告：
#   同步          各側比對皆符（或依規則跳過）
#   來源驗證失敗  上游 repo 中 upstream_commit 的歷史 blob hash ≠ upstream_sha256
#                 ——帳錯（commit/hash 記錄不實）或 blob 不可得，與上游 live 狀態無關
#   live 前進     upstream_status=active 行的上游 live 檔 hash ≠ upstream_sha256
#                 ——上游又演化了，kit 沒跟上（吸收或擱置由人裁定）
#   kit 演化      kit 檔 hash ≠ kit_sha256——kit 有意改動但 manifest 沒記帳
# 各態非互斥：同一行可同時命中多類，並列報。
#
# 來源驗證與 live 狀態脫鉤（K5.5，GPT 總檢 §3 裁定）：
#   來源真偽走歷史 blob（git show <upstream_commit>:<path>），上游後續怎麼改、
#   甚至換成 shim（K6）都不影響來源驗證；live 比對只對 upstream_status=active
#   的行做，上游退役後改 retired/successor 即不再誤報。
#
# closed ledger 完整性（fail 類）：
#   檔案缺失  manifest 列的 kit 檔不存在
#   無帳機制  受管目錄（engines/ gates/ tools/ hooks/ scripts/ lib/ installers/
#             遞迴 *.sh ∪ *.ts）存在但 manifest 未列——受管範圍與
#             tests/cases/manifest.sh 同步，改一邊必改另一邊
#
# 跳過規則（判定矩陣，K1 凍結、K5.5 修訂）:
#   hash 欄 = `-`         → 跳過該側比對
#   upstream=kit:original  → 冒號切分前特判，跳過上游側（kit 自創機制）
#   upstream_sha256 = `-`  → 跳過上游側（來源＋live）且不解析路徑（extracted-pattern、(多源) 等）
#   upstream_commit = `-`  → 跳過來源驗證（無歷史錨點）；live 比對不受影響
#   upstream_status ≠ active → 跳過 live 比對（retired/successor 為 K6 預留；kit:original 行填 `-`）
#   kit_path 含 #anchor    → 存在性檢查剝 fragment；雙側 hash 比對跳過（段落錨，
#                            K1 檔級粒度；tests/cases/manifest.sh 同契約跳過）
#   上游 live 檔已刪       → 報「live 檔已移除，人工裁定」歸 live 前進，不 crash 不誤報同步
#
# exit code：
#   0  全同步（無來源失敗、無 live 前進、無 kit 演化、無缺失、無無帳）
#   1  有來源驗證失敗／live 前進／kit 演化／檔案缺失／無帳機制——人工裁定後更新 manifest
#   2  fail-closed：manifest 缺失、0 資料行、malformed 行（NF≠9）、欄位驗證未過
#      （mode／upstream_status enum、absorbed 日期、hash 格式、kit_path 重複）、inspected:0
#      （「跑了但檢查 0 個機制」與「全綠」必須可區分——防假 0）
#
# 用法：
#   bash tools/kit-audit.sh [--manifest <path>] [--kit-root <path>]
#   環境：KIT_AUDIT_UPSTREAM_BASE 上游專案根（預設 ~/projects；dfaa:x/y →
#         $BASE/dfaa 為上游 git repo、$BASE/dfaa/x/y 為 live 檔）——測試 seam，
#         fixture 全 scratch 隔離用
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
[ -n "${MANIFEST}" ] || MANIFEST="${KIT_ROOT}/manifest/provenance.tsv"

# --- fail-closed 前置
if [ ! -f "${MANIFEST}" ]; then
    echo "FAIL(closed): manifest 不存在: ${MANIFEST}" >&2
    exit 2
fi
MALFORMED="$(awk -F'\t' '!/^#/ && !/^$/ && NF!=9 { print NR }' "${MANIFEST}" | tr '\n' ' ')"
if [ -n "${MALFORMED}" ]; then
    echo "FAIL(closed): manifest malformed 行（NF≠9）: 行號 ${MALFORMED}" >&2
    exit 2
fi

# 欄位驗證（fail-closed：帳的格式錯 = 稽核結論不可信，不往下跑）
TODAY="$(date +%Y-%m-%d)"
FIELD_ERRORS="$(awk -F'\t' -v today="${TODAY}" '
    /^#/ || /^$/ { next }
    seen[$1]++ { print "行" NR ": kit_path 重複（" $1 "）" }
    $4 != "-" && $4 !~ /^sha256:[0-9a-f]{64}$/ { print "行" NR ": upstream_sha256 格式錯（非 sha256:<64hex> 亦非 -）" }
    $5 != "-" && $5 !~ /^sha256:[0-9a-f]{64}$/ { print "行" NR ": kit_sha256 格式錯（非 sha256:<64hex> 亦非 -）" }
    $6 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ { print "行" NR ": absorbed 非 YYYY-MM-DD（" $6 "）"; next }
    $6 > today { print "行" NR ": absorbed 晚於今日（" $6 " > " today "）" }
' "${MANIFEST}")"
MODE_ERRORS="$(awk -F'\t' '
    /^#/ || /^$/ { next }
    $7 != "verbatim" && $7 != "parameterized" && $7 != "extracted-pattern" { print "行" NR ": mode 非法（" $7 "）" }
    $8 != "active" && $8 != "retired" && $8 != "successor" && $8 != "-" { print "行" NR ": upstream_status 非法（" $8 "）" }
' "${MANIFEST}")"
if [ -n "${FIELD_ERRORS}${MODE_ERRORS}" ]; then
    echo "FAIL(closed): manifest 欄位驗證未過:" >&2
    [ -n "${FIELD_ERRORS}" ] && printf '%s\n' "${FIELD_ERRORS}" >&2
    [ -n "${MODE_ERRORS}" ] && printf '%s\n' "${MODE_ERRORS}" >&2
    exit 2
fi

TAB="$(printf '\t')"
N_INSPECTED=0
N_SYNC=0
UP_DRIFT=""    # 來源驗證失敗（換行分隔的報告行）
LIVE_FWD=""    # live 前進（upstream_status=active 限定）
KIT_EVOLVED=""
MISSING=""

while IFS="${TAB}" read -r kp up uc uh kh _abs _mode ustatus _notes; do
    case "${kp}" in '#'*|'') continue ;; esac
    N_INSPECTED=$((N_INSPECTED + 1))
    kp_file="${kp%%#*}"          # 剝 #anchor
    has_anchor=0
    [ "${kp_file}" != "${kp}" ] && has_anchor=1
    row_drift=0

    # 檔案缺失（closed ledger：列了就必須存在）
    if [ ! -f "${KIT_ROOT}/${kp_file}" ]; then
        MISSING="${MISSING}  - ${kp}（manifest 列帳但檔案不存在）
"
        continue
    fi

    # kit 側比對（hash=- 或 #anchor 行跳過）
    if [ "${kh}" != "-" ] && [ "${has_anchor}" -eq 0 ]; then
        kit_actual="$(shasum -a 256 "${KIT_ROOT}/${kp_file}" | cut -d' ' -f1)"
        if [ "sha256:${kit_actual}" != "${kh}" ]; then
            KIT_EVOLVED="${KIT_EVOLVED}  - ${kp}（更新 kit_sha256 + notes 記一句演化內容）
"
            row_drift=1
        fi
    fi

    # 上游側（kit:original 特判；uh=- 跳過且不解析路徑；#anchor 跳過 hash）
    if [ "${up}" != "kit:original" ] && [ "${uh}" != "-" ] && [ "${has_anchor}" -eq 0 ]; then
        up_proj="${up%%:*}"
        up_path="${up#*:}"
        up_repo="${UPSTREAM_BASE}/${up_proj}"

        # 來源驗證：歷史 blob hash 對 upstream_sha256（uc=- 跳過，無歷史錨點）
        if [ "${uc}" != "-" ]; then
            if git -C "${up_repo}" cat-file -e "${uc}:${up_path}" 2>/dev/null; then
                blob_actual="$(git -C "${up_repo}" show "${uc}:${up_path}" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
                if [ "sha256:${blob_actual}" != "${uh}" ]; then
                    UP_DRIFT="${UP_DRIFT}  - ${kp} ← ${up}@${uc}（歷史 blob hash ≠ upstream_sha256——帳錯，核對 commit 與 hash）
"
                    row_drift=1
                fi
            else
                UP_DRIFT="${UP_DRIFT}  - ${kp} ← ${up}@${uc}（上游 blob 不可得——repo/commit/path 缺，人工裁定）
"
                row_drift=1
            fi
        fi

        # live 比對：僅 upstream_status=active——與來源驗證分開報告
        if [ "${ustatus}" = "active" ]; then
            up_file="${UPSTREAM_BASE}/${up_proj}/${up_path}"
            if [ ! -f "${up_file}" ]; then
                LIVE_FWD="${LIVE_FWD}  - ${kp} ← ${up}（上游 live 檔已移除——改 upstream_status 或人工裁定）
"
                row_drift=1
            else
                live_actual="$(shasum -a 256 "${up_file}" | cut -d' ' -f1)"
                if [ "sha256:${live_actual}" != "${uh}" ]; then
                    LIVE_FWD="${LIVE_FWD}  - ${kp} ← ${up}（live 前進——上游又演化；diff \"${up_file}\" \"${KIT_ROOT}/${kp_file}\"）
"
                    row_drift=1
                fi
            fi
        fi
    fi

    [ "${row_drift}" -eq 0 ] && N_SYNC=$((N_SYNC + 1))
done < "${MANIFEST}"

# runtime self-canary：0 資料行 = manifest 路徑錯或整檔註解——與全綠必須可區分
if [ "${N_INSPECTED}" -eq 0 ]; then
    echo "FAIL(closed): manifest 0 資料行（inspected:0）——路徑錯或檔案空" >&2
    exit 2
fi

# --- 無帳掃描（受管目錄 vs ledger 集合差）
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
(cd "${KIT_ROOT}" && find engines gates tools hooks scripts lib installers \( -name '*.sh' -o -name '*.ts' \) -type f 2>/dev/null | sort) > "${SCRATCH}/actual.txt"
awk -F'\t' '!/^#/ && !/^$/ { p=$1; sub(/#.*$/, "", p); print p }' "${MANIFEST}" | sort -u > "${SCRATCH}/ledger.txt"
UNLEDGERED="$(comm -23 "${SCRATCH}/actual.txt" "${SCRATCH}/ledger.txt")"

# --- 報告
echo "== kit-audit 報告（manifest: ${MANIFEST}）"
echo "同步: ${N_SYNC}"
if [ -n "${UP_DRIFT}" ]; then
    printf '來源驗證失敗（帳錯——核對 upstream_commit/upstream_sha256，逐筆 notes 記校正）:\n%s' "${UP_DRIFT}"
fi
if [ -n "${LIVE_FWD}" ]; then
    printf 'live 前進（上游又演化——吸收→更新雙 hash+commit 欄／擱置→notes 記理由日期）:\n%s' "${LIVE_FWD}"
fi
if [ -n "${KIT_EVOLVED}" ]; then
    printf 'kit 演化（kit 改了沒記帳）:\n%s' "${KIT_EVOLVED}"
fi
if [ -n "${MISSING}" ]; then
    printf '檔案缺失:\n%s' "${MISSING}"
fi
if [ -n "${UNLEDGERED}" ]; then
    echo "無帳機制（受管目錄存在但 manifest 未列——closed ledger 不是 best-effort）:"
    printf '%s\n' "${UNLEDGERED}" | sed 's/^/  - /'
fi
echo "inspected:${N_INSPECTED}"

if [ -n "${UP_DRIFT}" ] || [ -n "${LIVE_FWD}" ] || [ -n "${KIT_EVOLVED}" ] || [ -n "${MISSING}" ] || [ -n "${UNLEDGERED}" ]; then
    exit 1
fi
exit 0
