# manifest.sh — provenance manifest（closed ledger）對帳測試
#
# 對「真實 manifest × 真實檔案樹」跑三類檢查——這個 case 進全套迴歸的意義：
# K2-K7 每波改到已登帳檔案、或在受管目錄新增檔案而忘記記帳，這裡立即紅燈，
# 不必等下次手動 /kit-audit 才發現 manifest 腐爛。
#
# 受管範圍（與 tools/kit-audit.sh 的無帳掃描範圍同步——改一邊必改另一邊）：
#   engines/ gates/ tools/ hooks/ scripts/ lib/ installers/ 下的 *.sh（遞迴）
# templates/ 與 references/ 混有非機制檔，帳可選、掃描不強制
# （理由見 references/declaration-formats.md「manifest」節）。

MANIFEST="$KIT_ROOT/manifest/provenance.tsv"

# --- 存在性（manifest 本身缺失 = 直接紅，不做後續）
if [ ! -f "$MANIFEST" ]; then
    assert_eq "exists" "missing" "manifest/provenance.tsv 存在"
else

# --- 1. 欄數守恆：非註解非空行必須恰好 8 欄（空欄一律 `-` 佔位）
BAD_NF="$(awk -F'\t' '!/^#/ && !/^$/ && NF!=8 { print NR }' "$MANIFEST" | tr '\n' ' ')"
assert_eq "" "$BAD_NF" "manifest 欄數守恆（8 欄，違規行號：${BAD_NF:-無}）"

# --- 2. 集合對帳：受管目錄實際檔案 vs manifest kit_path 雙向差集 = 0
MANIFEST_SANDBOX="$(mktemp -d)"
# 實際檔案清單（受管目錄遞迴 *.sh；目錄不存在時靜默跳過）
(cd "$KIT_ROOT" && find engines gates tools hooks scripts lib installers \( -name '*.sh' -o -name '*.ts' \) -type f 2>/dev/null | sort) > "$MANIFEST_SANDBOX/actual.txt"
# manifest kit_path 欄（去 #anchor 段落錨、去重——同檔多錨算一檔）
awk -F'\t' '!/^#/ && !/^$/ { p=$1; sub(/#.*$/, "", p); print p }' "$MANIFEST" | sort -u > "$MANIFEST_SANDBOX/ledger.txt"
ONLY_ACTUAL="$(comm -23 "$MANIFEST_SANDBOX/actual.txt" "$MANIFEST_SANDBOX/ledger.txt" | tr '\n' ' ')"
ONLY_LEDGER="$(comm -13 "$MANIFEST_SANDBOX/actual.txt" "$MANIFEST_SANDBOX/ledger.txt" | tr '\n' ' ')"
assert_eq "" "$ONLY_ACTUAL" "受管目錄無無帳檔案（未登帳：${ONLY_ACTUAL:-無}）"
assert_eq "" "$ONLY_LEDGER" "manifest 無幽靈條目（登帳但檔不存在：${ONLY_LEDGER:-無}）"

# --- 3. 全行 hash 驗證：每行 kit_sha256（剝 sha256: 前綴）與實算相符（全查非抽查）
HASH_MISMATCH=""
HASH_CHECKED=0
while IFS="$(printf '\t')" read -r kp _up _uc _uh kh _rest; do
    case "$kp" in '#'*|'') continue ;; esac
    kp_file="${kp%%#*}"
    expected="${kh#sha256:}"
    actual="$(shasum -a 256 "$KIT_ROOT/$kp_file" 2>/dev/null | cut -d' ' -f1)"
    HASH_CHECKED=$((HASH_CHECKED + 1))
    if [ "$expected" != "$actual" ]; then
        HASH_MISMATCH="${HASH_MISMATCH}${kp} "
    fi
done < "$MANIFEST"
assert_eq "" "$HASH_MISMATCH" "全行 kit_sha256 與實算相符（不符：${HASH_MISMATCH:-無}）"
# 防假 0：確認迴圈真的讀到資料行（manifest 只剩註解時 HASH_CHECKED=0 必須紅）
MANIFEST_ROWS="$(awk -F'\t' '!/^#/ && !/^$/ { n++ } END { print n+0 }' "$MANIFEST")"
assert_eq "$MANIFEST_ROWS" "$HASH_CHECKED" "hash 迴圈讀行數 = manifest 資料行數（防假 0）"

rm -rf "$MANIFEST_SANDBOX"
fi
