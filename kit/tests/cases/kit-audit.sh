# kit-audit.sh — 分類判定 + closed ledger 完整性（全 scratch 隔離，不碰真 kit / 真 dfaa）
#
# seam：--manifest / --kit-root / KIT_AUDIT_UPSTREAM_BASE 三者皆指 scratch。
# 上游 fixture 是 scratch git repo（歷史 blob 驗證需要 commit 歷史，不能只是檔案樹）：
# commit 舊版取得 blob 錨點，再改工作樹即構造「歷史 blob 相符但 live 已改」態。
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
_au_row() { # kit_path upstream upstream_commit uh kh upstream_status
    printf '%s\t%s\t%s\t%s\t%s\t2026-07-30\tverbatim\t%s\t-\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

# --- 上游 scratch git repo：commit v1 當歷史錨點
AU1_ROOT="$(_au_mkroot)"
AU1_UP="$(mktemp -d)"
mkdir -p "$AU1_UP/dfaa/scripts"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
git -C "$AU1_UP/dfaa" init -q
git -C "$AU1_UP/dfaa" -c user.email=t@t -c user.name=t add scripts/up.sh
git -C "$AU1_UP/dfaa" -c user.email=t@t -c user.name=t commit -qm v1
AU_UC="$(git -C "$AU1_UP/dfaa" rev-parse --short HEAD)"
AU_UH="sha256:$(_au_hash "$AU1_UP/dfaa/scripts/up.sh")"   # v1 blob hash（=commit 當下工作樹）
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_ROOT/engines/absorbed.sh"
_au_mkmanifest() { # ustatus [uh]
    {
        _au_row "tools/thing.sh" "kit:original" "-" "-" "sha256:$(_au_hash "$AU1_ROOT/tools/thing.sh")" "-"
        _au_row "engines/absorbed.sh" "dfaa:scripts/up.sh" "$AU_UC" "${2:-$AU_UH}" "sha256:$(_au_hash "$AU1_ROOT/engines/absorbed.sh")" "$1"
    } > "$AU1_ROOT/manifest/provenance.tsv"
}

# --- fixture 1：同步（kit:original 跳上游 + dfaa 行歷史 blob 符＋live 符）
_au_mkmanifest "active"
AU1_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU1_RC=$?
assert_eq "0" "$AU1_RC" "同步 fixture exit 0"
assert_contains "$AU1_OUT" "同步: 2" "同步 fixture 兩行皆同步"
assert_contains "$AU1_OUT" "inspected:2" "同步 fixture inspected 精確值 2"

# --- fixture 2：歷史 blob 相符但 live 已改（active）→ 不報來源失敗，live 前進獨立分類
printf '#!/bin/sh\necho upstream-v2-CHANGED\n' > "$AU1_UP/dfaa/scripts/up.sh"
AU2_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU2_RC=$?
assert_eq "1" "$AU2_RC" "live 前進 fixture exit 1"
assert_contains "$AU2_OUT" "live 前進" "live 前進 fixture 獨立分類關鍵詞"
assert_not_contains "$AU2_OUT" "來源驗證失敗" "live 前進 fixture 不誤報來源失敗（歷史 blob 仍相符）"
assert_contains "$AU2_OUT" "diff " "live 前進 fixture 附 diff 指令"
assert_contains "$AU2_OUT" "inspected:2" "live 前進 fixture inspected 仍為 2"

# --- fixture 3：同態但 upstream_status=retired → live 跳過，回全綠（K6 shim 情境）
_au_mkmanifest "retired"
AU3_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU3_RC=$?
assert_eq "0" "$AU3_RC" "retired fixture exit 0（live 已改但不比 live）"
assert_contains "$AU3_OUT" "同步: 2" "retired fixture 來源驗證仍過、計同步"

# --- fixture 4：來源 hash 不符（帳錯——uh 記錯值，與 live 狀態無關）
_au_mkmanifest "active" "sha256:0000000000000000000000000000000000000000000000000000000000000000"
AU4_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU4_RC=$?
assert_eq "1" "$AU4_RC" "來源帳錯 fixture exit 1"
assert_contains "$AU4_OUT" "來源驗證失敗" "來源帳錯 fixture 分類關鍵詞"
assert_contains "$AU4_OUT" "帳錯" "來源帳錯 fixture 點名帳錯"

# --- fixture 5：上游 blob 不可得（commit 不存在）
_au_mkmanifest "active"
sed "s/${AU_TAB}${AU_UC}${AU_TAB}/${AU_TAB}deadbee${AU_TAB}/" "$AU1_ROOT/manifest/provenance.tsv" > "$AU1_ROOT/manifest/provenance.tsv.tmp"
mv "$AU1_ROOT/manifest/provenance.tsv.tmp" "$AU1_ROOT/manifest/provenance.tsv"
AU5_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU5_RC=$?
assert_eq "1" "$AU5_RC" "blob 不可得 fixture exit 1"
assert_contains "$AU5_OUT" "blob 不可得" "blob 不可得 fixture 關鍵詞"

# --- fixture 6：kit 演化（kit 檔改了、上游還原同步）
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
printf '#!/bin/sh\necho kit-evolved\n' > "$AU1_ROOT/engines/absorbed.sh"
_au_mkmanifest "active"
printf '#!/bin/sh\necho kit-evolved-again\n' > "$AU1_ROOT/engines/absorbed.sh"
AU6_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU6_RC=$?
assert_eq "1" "$AU6_RC" "kit 演化 fixture exit 1"
assert_contains "$AU6_OUT" "kit 演化" "kit 演化 fixture 關鍵詞"

# --- fixture 7：三態同現（來源帳錯 + live 前進 + kit 演化——非互斥並列報）
printf '#!/bin/sh\necho upstream-v3\n' > "$AU1_UP/dfaa/scripts/up.sh"
_au_mkmanifest "active" "sha256:1111111111111111111111111111111111111111111111111111111111111111"
printf '#!/bin/sh\necho kit-evolved-more\n' > "$AU1_ROOT/engines/absorbed.sh"
AU7_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU7_RC=$?
assert_eq "1" "$AU7_RC" "三態同現 fixture exit 1"
assert_contains "$AU7_OUT" "來源驗證失敗" "三態同現 fixture 報來源失敗"
assert_contains "$AU7_OUT" "live 前進" "三態同現 fixture 報 live 前進"
assert_contains "$AU7_OUT" "kit 演化" "三態同現 fixture 同行並列報 kit 演化"

# --- fixture 8：無帳機制（受管目錄有檔、manifest 未列）
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_UP/dfaa/scripts/up.sh"
printf '#!/bin/sh\necho upstream-v1\n' > "$AU1_ROOT/engines/absorbed.sh"
_au_mkmanifest "active"
printf '#!/bin/sh\necho rogue\n' > "$AU1_ROOT/engines/rogue.sh"
AU8_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU8_RC=$?
assert_eq "1" "$AU8_RC" "無帳 fixture exit 1"
assert_contains "$AU8_OUT" "無帳機制" "無帳 fixture 關鍵詞"
assert_contains "$AU8_OUT" "engines/rogue.sh" "無帳 fixture 點名檔案"
rm -f "$AU1_ROOT/engines/rogue.sh"

# --- fixture 9：檔案缺失（manifest 列帳但 kit 檔不存在）
rm -f "$AU1_ROOT/engines/absorbed.sh"
AU9_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU1_ROOT" 2>&1)"
AU9_RC=$?
assert_eq "1" "$AU9_RC" "檔案缺失 fixture exit 1"
assert_contains "$AU9_OUT" "檔案缺失" "檔案缺失 fixture 關鍵詞"

# --- fixture 10：跳過規則——#anchor 剝 fragment 驗存在、hash 跳過；uh=- 不解析路徑；uc=- 跳來源
AU10_ROOT="$(_au_mkroot)"
{
    _au_row "tools/thing.sh#escape-enum" "dfaa:(多源)" "-" "-" "-" "-"
} > "$AU10_ROOT/manifest/provenance.tsv"
AU10_OUT="$(KIT_AUDIT_UPSTREAM_BASE="$AU1_UP" bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU10_RC=$?
assert_eq "0" "$AU10_RC" "anchor+uh=- fixture exit 0（存在性過、雙側 hash 跳過、(多源) 不解析）"
assert_contains "$AU10_OUT" "inspected:1" "anchor fixture inspected 1"

# --- fail-closed：結構三態
AU11_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" --manifest "/no/such/manifest.tsv" 2>&1)"
assert_eq "2" "$?" "manifest 缺失 exit 2（fail-closed）"
printf '# only comments\n' > "$AU10_ROOT/manifest/provenance.tsv"
AU12_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
assert_eq "2" "$?" "manifest 0 資料行 exit 2（inspected:0 self-canary）"
printf 'bad-row-only-three\tfields\there\n' > "$AU10_ROOT/manifest/provenance.tsv"
AU13_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
assert_eq "2" "$?" "malformed 行（NF≠9）exit 2（fail-closed）"

# --- fail-closed：欄位驗證紅 fixture 各一（mode／absorbed 未來日期／hash 格式／kit_path 重複）
_au_badrow() { # 整行自組（可注入非法值）
    printf '%s\n' "$1" > "$AU10_ROOT/manifest/provenance.tsv"
}
AU_KH="sha256:$(_au_hash "$AU10_ROOT/tools/thing.sh")"
_au_badrow "tools/thing.sh${AU_TAB}kit:original${AU_TAB}-${AU_TAB}-${AU_TAB}${AU_KH}${AU_TAB}2026-07-30${AU_TAB}freestyle${AU_TAB}-${AU_TAB}-"
AU14_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU14_RC=$?
assert_eq "2" "$AU14_RC" "mode 非法 exit 2"
assert_contains "$AU14_OUT" "mode 非法" "mode 非法 點名欄位"

_au_badrow "tools/thing.sh${AU_TAB}kit:original${AU_TAB}-${AU_TAB}-${AU_TAB}${AU_KH}${AU_TAB}2999-01-01${AU_TAB}verbatim${AU_TAB}-${AU_TAB}-"
AU15_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU15_RC=$?
assert_eq "2" "$AU15_RC" "absorbed 未來日期 exit 2"
assert_contains "$AU15_OUT" "晚於今日" "absorbed 未來日期 點名"

_au_badrow "tools/thing.sh${AU_TAB}kit:original${AU_TAB}-${AU_TAB}-${AU_TAB}sha256:zzzz${AU_TAB}2026-07-30${AU_TAB}verbatim${AU_TAB}-${AU_TAB}-"
AU16_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU16_RC=$?
assert_eq "2" "$AU16_RC" "hash 格式錯 exit 2"
assert_contains "$AU16_OUT" "格式錯" "hash 格式錯 點名"

{
    printf 'tools/thing.sh%skit:original%s-%s-%s%s%s2026-07-30%sverbatim%s-%s-\n' "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_KH" "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_TAB"
    printf 'tools/thing.sh%skit:original%s-%s-%s%s%s2026-07-30%sverbatim%s-%s-\n' "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_KH" "$AU_TAB" "$AU_TAB" "$AU_TAB" "$AU_TAB"
} > "$AU10_ROOT/manifest/provenance.tsv"
AU17_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU17_RC=$?
assert_eq "2" "$AU17_RC" "kit_path 重複 exit 2"
assert_contains "$AU17_OUT" "kit_path 重複" "kit_path 重複 點名"

# upstream_status 非法（新欄 enum 守衛）
_au_badrow "tools/thing.sh${AU_TAB}kit:original${AU_TAB}-${AU_TAB}-${AU_TAB}${AU_KH}${AU_TAB}2026-07-30${AU_TAB}verbatim${AU_TAB}zombie${AU_TAB}-"
AU18_OUT="$(bash "$AUDIT" --kit-root "$AU10_ROOT" 2>&1)"
AU18_RC=$?
assert_eq "2" "$AU18_RC" "upstream_status 非法 exit 2"
assert_contains "$AU18_OUT" "upstream_status 非法" "upstream_status 非法 點名欄位"

rm -rf "$AU1_ROOT" "$AU1_UP" "$AU10_ROOT"
