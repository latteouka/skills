# manifest.sh — provenance manifest（closed ledger）對帳測試
#
# 對「真實 manifest × 真實檔案樹」跑三類檢查——這個 case 進全套迴歸的意義：
# K2-K7 每波改到已登帳檔案、或在受管目錄新增檔案而忘記記帳，這裡立即紅燈，
# 不必等下次手動 /kit-audit 才發現 manifest 腐爛。
#
# 受管範圍（與 tools/kit-audit.sh 的無帳掃描範圍同步——改一邊必改另一邊）：
#   engines/ gates/ tools/ hooks/ scripts/ lib/ installers/ 下的 *.sh 與 *.ts（遞迴）
# templates/ 與 references/ 混有非機制檔，帳可選、掃描不強制
# （理由見 references/declaration-formats.md「manifest」節）。
#
# anchor 契約（與 kit-audit.sh 一致，K5.5 統一）：kh=- 或 kit_path 帶 #anchor
# 的列跳過實算 hash——段落錨是檔級粒度的保留位，實算必不符，無條件算會逼人
# 造假 hash 或永遠紅燈。

MANIFEST="$KIT_ROOT/manifest/provenance.tsv"

# _manifest_hash_scan <manifest> <root>
# 全行 kit_sha256 實算比對（kh=- 與 #anchor 列跳過）。輸出全域：
#   MHS_MISMATCH  不符的 kit_path 清單（空=全符）
#   MHS_CHECKED   實際驗過的行數
_manifest_hash_scan() {
    local _m="$1" _root="$2" kp _up _uc _uh kh _rest kp_file expected actual
    MHS_MISMATCH=""
    MHS_CHECKED=0
    while IFS="$(printf '\t')" read -r kp _up _uc _uh kh _rest; do
        case "$kp" in '#'*|'') continue ;; esac
        kp_file="${kp%%#*}"
        # 跳過：kh=-（無帳側 hash）或段落錨（檔級粒度，實算必不符）
        if [ "$kh" = "-" ] || [ "$kp_file" != "$kp" ]; then continue; fi
        expected="${kh#sha256:}"
        actual="$(shasum -a 256 "$_root/$kp_file" 2>/dev/null | cut -d' ' -f1)"
        MHS_CHECKED=$((MHS_CHECKED + 1))
        if [ "$expected" != "$actual" ]; then
            MHS_MISMATCH="${MHS_MISMATCH}${kp} "
        fi
    done < "$_m"
}

# --- 存在性（manifest 本身缺失 = 直接紅，不做後續）
if [ ! -f "$MANIFEST" ]; then
    assert_eq "exists" "missing" "manifest/provenance.tsv 存在"
else

# --- 1. 欄數守恆：非註解非空行必須恰好 9 欄（空欄一律 `-` 佔位）
BAD_NF="$(awk -F'\t' '!/^#/ && !/^$/ && NF!=9 { print NR }' "$MANIFEST" | tr '\n' ' ')"
assert_eq "" "$BAD_NF" "manifest 欄數守恆（9 欄，違規行號：${BAD_NF:-無}）"

# --- 2. 集合對帳：受管目錄實際檔案 vs manifest kit_path 雙向差集 = 0
MANIFEST_SANDBOX="$(mktemp -d)"
# 實際檔案清單（受管目錄遞迴 *.sh ∪ *.ts；目錄不存在時靜默跳過）
(cd "$KIT_ROOT" && find engines gates tools hooks scripts lib installers \( -name '*.sh' -o -name '*.ts' \) -type f 2>/dev/null | sort) > "$MANIFEST_SANDBOX/actual.txt"
# manifest kit_path 欄（去 #anchor 段落錨、去重——同檔多錨算一檔）
awk -F'\t' '!/^#/ && !/^$/ { p=$1; sub(/#.*$/, "", p); print p }' "$MANIFEST" | sort -u > "$MANIFEST_SANDBOX/ledger.txt"
ONLY_ACTUAL="$(comm -23 "$MANIFEST_SANDBOX/actual.txt" "$MANIFEST_SANDBOX/ledger.txt" | tr '\n' ' ')"
ONLY_LEDGER="$(comm -13 "$MANIFEST_SANDBOX/actual.txt" "$MANIFEST_SANDBOX/ledger.txt" | tr '\n' ' ')"
assert_eq "" "$ONLY_ACTUAL" "受管目錄無無帳檔案（未登帳：${ONLY_ACTUAL:-無}）"
assert_eq "" "$ONLY_LEDGER" "manifest 無幽靈條目（登帳但檔不存在：${ONLY_LEDGER:-無}）"

# --- 3. 全行 hash 驗證：kit_sha256（剝 sha256: 前綴）與實算相符（全查非抽查；
#        kh=- 與 #anchor 列依契約跳過）
_manifest_hash_scan "$MANIFEST" "$KIT_ROOT"
assert_eq "" "$MHS_MISMATCH" "全行 kit_sha256 與實算相符（不符：${MHS_MISMATCH:-無}）"
# 防假 0：分母＝「應驗行數」（資料行扣掉 kh=- 與 anchor 列）——迴圈驗過的行數
# 必須恰等於應驗行數；manifest 只剩註解或迴圈提早斷線時必紅。
EXPECTED_CHECKED="$(awk -F'\t' '!/^#/ && !/^$/ && $5 != "-" && $1 !~ /#/ { n++ } END { print n+0 }' "$MANIFEST")"
assert_eq "$EXPECTED_CHECKED" "$MHS_CHECKED" "hash 迴圈驗行數 = 應驗行數（防假 0）"
# 真帳目前應驗行數 >0 的下限守衛（防「應驗行數自己也算成 0」的雙重假 0）
assert_eq "1" "$([ "$EXPECTED_CHECKED" -gt 0 ] && echo 1 || echo 0)" "真帳應驗行數 > 0"

# --- 4. anchor 綠 fixture：帶 #anchor 與 kh=- 的列跳過實算、正常列照驗
#        （fixture manifest，不動真帳——真帳目前無 anchor 列，這裡證明跳過邏輯活著）
MANIFEST_FIXTURE_ROOT="$(mktemp -d)"
mkdir -p "$MANIFEST_FIXTURE_ROOT/tools"
printf '#!/bin/sh\necho fixture\n' > "$MANIFEST_FIXTURE_ROOT/tools/fx.sh"
MFX_HASH="$(shasum -a 256 "$MANIFEST_FIXTURE_ROOT/tools/fx.sh" | cut -d' ' -f1)"
MFX_TAB="$(printf '\t')"
{
    printf 'tools/fx.sh%skit:original%s-%s-%ssha256:%s%s2026-07-30%sverbatim%s-%s-\n' \
        "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_HASH" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB"
    printf 'tools/fx.sh#some-anchor%sdfaa:(多源)%s-%s-%s-%s2026-07-30%sextracted-pattern%s-%s-\n' \
        "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB" "$MFX_TAB"
} > "$MANIFEST_FIXTURE_ROOT/provenance-fixture.tsv"
_manifest_hash_scan "$MANIFEST_FIXTURE_ROOT/provenance-fixture.tsv" "$MANIFEST_FIXTURE_ROOT"
assert_eq "" "$MHS_MISMATCH" "anchor fixture：無誤報（anchor+kh=- 列已跳過）"
assert_eq "1" "$MHS_CHECKED" "anchor fixture：只驗正常列 1 行（anchor 列不進分母）"

rm -rf "$MANIFEST_SANDBOX" "$MANIFEST_FIXTURE_ROOT"
fi
