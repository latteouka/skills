# kit-audit.sh — 三態判定 + closed ledger 完整性（全 scratch 隔離，不碰真 kit / 真 dfaa）
#
# seam：--manifest / --kit-root / KIT_AUDIT_UPSTREAM_BASE 三者皆指 scratch。
# 每個 fixture 斷言 exit code + 關鍵詞 + inspected:N 精確值（fixture 行數已知，
# 不用 >0——「只讀到一半」也要抓）。

AUDIT="$KIT_ROOT/tools/kit-audit.sh"
AU_TAB="$(printf '\t')"

# 建 scratch kit root：受管目錄 + 一個檔案
_au_mkroot() {
    local d
    d="$(mktemp -d)"
    mkdir -p "$d/tools" "$d/engines" "$d/manifest"
    printf '#!/bin/sh\necho v1\n' > "$d/tools/thing.sh"
    echo "$d"
}
_au_hash() { shasum -a 256 "$1" | cut -d' ' -f1; }
_au_row() { # kit_path upstream uh kh
    printf '%s\t%s\t-\t%s\t%s\t2026-07-30\tverbatim\t-\n' "$1" "$2" "$3" "$4"
}

# --- fixture 1：同步（kit:original 跳上游 + dfaa 上游雙側皆符）
AU1_ROOT="$(_au_mkroot)"
AU1_UP="$(mktemp -d)"
mkdir -p "$AU1_UP/dfaa/scripts"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_ROOT/engines/absorbed.sh"
{
    _au_row "tools/thing.sh" "kit:original" "-" "sha256:$(_au_hash "$AU1_ROOT/tools/thing.sh")"
    _au_row "engines/absorbed.sh" "dfaa:scripts/up.sh" "sha256:$(_au_hash "$AU1_UP/dfaa/scripts/up.sh")" "sha256:$(_au_hash "$AU1_ROOT/engines/absorbed.sh")"
} > "$AU1_ROOT/manifest/provenance.tsv"
AU1_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU1_RC=$?
assert_eq "0" "$AU1_RC" "同步 fixture exit 0"
assert_contains "$AU1_OUT" "同步: 2" "同步 fixture 兩行皆同步"
assert_contains "$AU1_OUT" "inspected:2" "同步 fixture inspected 精確值 2"

# --- fixture 2：上游漂移（上游檔內容變了）
printf '#!/bin/sh\necho upstream-v2-CHANGED\n' > "$AU1_UP/dfaa/scripts/up.sh"
AU2_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU2_RC=$?
assert_eq "1" "$AU2_RC" "上游漂移 fixture exit 1"
assert_contains "$AU2_OUT" "上游漂移" "上游漂移 fixture 關鍵詞"
assert_contains "$AU2_OUT" "diff " "上游漂移 fixture 附 diff 指令"
assert_contains "$AU2_OUT" "inspected:2" "上游漂移 fixture inspected 仍為 2"

# --- fixture 3：kit 演化（kit 檔改了、上游還原同步）
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
printf '#!/bin/sh\necho kit-evolved\n' > "$AU1_ROOT/engines/absorbed.sh"
AU3_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU3_RC=$?
assert_eq "1" "$AU3_RC" "kit 演化 fixture exit 1"
assert_contains "$AU3_OUT" "kit 演化" "kit 演化 fixture 關鍵詞"

# --- fixture 4：雙漂移同現（上游也變、kit 也變——非互斥並列報）
printf '#!/bin/sh\necho upstream-v3\n' > "$AU1_UP/dfaa/scripts/up.sh"
AU4_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU4_RC=$?
assert_eq "1" "$AU4_RC" "雙漂移 fixture exit 1"
assert_contains "$AU4_OUT" "上游漂移" "雙漂移 fixture 報上游漂移"
assert_contains "$AU4_OUT" "kit 演化" "雙漂移 fixture 同行並列報 kit 演化"

# --- fixture 5：無帳機制（受管目錄有檔、manifest 未列）
printf '#!/bin/sh\necho rogue\n' > "$AU1_ROOT/engines/rogue.sh"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_ROOT/engines/absorbed.sh"
AU5_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU5_RC=$?
assert_eq "1" "$AU5_RC" "無帳 fixture exit 1"
assert_contains "$AU5_OUT" "無帳機制" "無帳 fixture 關鍵詞"
assert_contains "$AU5_OUT" "engines/rogue.sh" "無帳 fixture 點名檔案"
rm -f "$AU1_ROOT/engines/rogue.sh"

# --- fixture 6：檔案缺失（manifest 列帳但 kit 檔不存在）
rm -f "$AU1_ROOT/engines/absorbed.sh"
AU6_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU6_RC=$?
assert_eq "1" "$AU6_RC" "檔案缺失 fixture exit 1"
assert_contains "$AU6_OUT" "檔案缺失" "檔案缺失 fixture 關鍵詞"

# --- fixture 7：跳過規則——#anchor 剝 fragment 驗存在、hash 跳過；uh=- 不解析路徑
AU7_ROOT="$(_au_mkroot)"
{
    _au_row "tools/thing.sh#escape-enum" "dfaa:(多源)" "-" "-"
} > "$AU7_ROOT/manifest/provenance.tsv"
AU7_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU7_ROOT" 2>&1)"
AU7_RC=$?
assert_eq "0" "$AU7_RC" "anchor+uh=- fixture exit 0（存在性過、雙側 hash 跳過、(多源) 不解析）"
assert_contains "$AU7_OUT" "inspected:1" "anchor fixture inspected 1"

# --- fail-closed 三態
AU8_OUT="$(bash "$AUDIT" --kit-root "$AU7_ROOT" --manifest "/no/such/manifest.tsv" 2>&1)"
assert_eq "2" "$?" "manifest 缺失 exit 2（fail-closed）"
printf '# only comments\n' > "$AU7_ROOT/manifest/provenance.tsv"
AU9_OUT="$(bash "$AUDIT" --kit-root "$AU7_ROOT" 2>&1)"
assert_eq "2" "$?" "manifest 0 資料行 exit 2（inspected:0 self-canary）"
printf 'bad-row-only-three\tfields\there\n' > "$AU7_ROOT/manifest/provenance.tsv"
AU10_OUT="$(bash "$AUDIT" --kit-root "$AU7_ROOT" 2>&1)"
assert_eq "2" "$?" "malformed 行（NF≠8）exit 2（fail-closed）"

rm -rf "$AU1_ROOT" "$AU1_UP" "$AU7_ROOT"
