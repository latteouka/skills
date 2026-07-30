# rtm-check.sh — engines/rtm-check.ts 引擎測試（K5）
#
# runtime 政策（合約凍結）：無 node≥23.6/tsx → SKIP 明示且「斷言數不掉」——
# SKIP 分支以佔位斷言補到與 runtime 分支相同數量（RC_EXPECTED），兩分支
# 各自最後再加一個 delta 守衛斷言，保證 assertion-baseline 在任何環境同值
# （防 baseline 假紅；floor＝無 runtime 環境值＝有 runtime 環境值）。
#
# js-yaml 策略：fixture 的 node_modules/js-yaml 是 kit 測試 stub
# （load=JSON.parse）——matrix fixture 以 JSON 語法撰寫（JSON 是 YAML 子集，
# 真 js-yaml 解析結果相同），createRequire「從目標專案解析」的 seam 被真實
# 走過；與真 js-yaml 的 parity 由 K5 🤖-C 的 dfaa 雙跑合約看守。

RC_ENGINE="$KIT_ROOT/engines/rtm-check.ts"
RC_EXPECTED=25

# --- runtime 偵測（與 hooks/rtm-session-start.sh 同判準）---
RC_RUNTIME=""
RC_MISSING="node≥23.6 或 tsx"
RC_NODE_VER="$(node --version 2>/dev/null || true)"
if [ -n "$RC_NODE_VER" ]; then
    RC_MAJ="${RC_NODE_VER#v}"; RC_MAJ="${RC_MAJ%%.*}"
    RC_MIN="${RC_NODE_VER#v*.}"; RC_MIN="${RC_MIN%%.*}"
    case "$RC_MAJ" in ''|*[!0-9]*) RC_MAJ=0 ;; esac
    case "$RC_MIN" in ''|*[!0-9]*) RC_MIN=0 ;; esac
    if [ "$RC_MAJ" -gt 23 ] || { [ "$RC_MAJ" -eq 23 ] && [ "$RC_MIN" -ge 6 ]; }; then
        RC_RUNTIME="node"
    else
        RC_MISSING="node 過舊（${RC_NODE_VER}，需 ≥23.6）且無 tsx"
    fi
else
    RC_MISSING="node 未裝且無 tsx"
fi
if [ -z "$RC_RUNTIME" ] && command -v tsx >/dev/null 2>&1; then
    RC_RUNTIME="tsx"
fi

rc_run() { "$RC_RUNTIME" "$RC_ENGINE" "$@"; }

# fixture 專案：git repo + package.json + js-yaml stub + kit.yaml + matrix 目錄
rc_make_project() {
    local d
    d="$(mktemp -d)"
    git -C "$d" init -q
    mkdir -p "$d/node_modules/js-yaml" "$d/.claude/kit" "$d/docs/rtm/matrix"
    printf '{"name":"rtm-fixture","private":true}\n' > "$d/package.json"
    printf '{"name":"js-yaml","version":"0.0.0-kitstub","main":"index.js"}\n' \
        > "$d/node_modules/js-yaml/package.json"
    printf 'module.exports = { load: function (s) { return JSON.parse(s); } };\n' \
        > "$d/node_modules/js-yaml/index.js"
    {
        printf 'matrix_dir: "docs/rtm/matrix"\n'
        printf 'status_enum: "implemented partial divergent planned na"\n'
        printf 'impl_path_bases: "."\n'
        printf 'rtm_nonpath_tokens: "Next.js Node.js"\n'
    } > "$d/.claude/kit/kit.yaml"
    echo "$d"
}

# bash 側 matrix hash（與引擎/hook 同公式——「hash 兩側同值」的 bash 側）
rc_bash_hash() {
    (cd "$1" && LC_ALL=C find . -maxdepth 1 -name '*.yaml' | LC_ALL=C sort \
        | while IFS= read -r f; do cat "$f"; done) | shasum -a 256 | awk '{print $1}'
}

RC_START=$TESTS_RUN
RC_SKIP_START=$TESTS_SKIPPED

if [ -n "$RC_RUNTIME" ]; then

    # ═══ A. 相容性混用 fixture（rfp_id 舊欄位 × req_id 新欄位）→ PASS ═══
    RC_P1="$(rc_make_project)"
    cat > "$RC_P1/docs/rtm/matrix/010-core.yaml" <<'EOF'
{ "meta": { "section": "REQ-A", "total_clauses": 2 },
  "entries": [
    { "rfp_id": "REQ-A-1", "rfp_text": "舊欄位名條目（向下相容）", "status": "implemented",
      "detail_specs": ["規格一"], "impl_details": ["定位: src/app/core/logic.ts"],
      "impl_routes": ["/a"], "verify": "passthrough 額外欄不驗不擋" },
    { "req_id": "REQ-A-2", "req_text": "新欄位名條目", "status": "planned" } ] }
EOF
    cat > "$RC_P1/docs/rtm/matrix/020-other.yaml" <<'EOF'
{ "meta": { "section": "REQ-B", "total_clauses": 1 },
  "entries": [
    { "req_id": "REQ-B-1", "req_text": "差異條目", "status": "divergent",
      "notes": "差異說明", "detail_specs": ["規格"] } ] }
EOF
    mkdir -p "$RC_P1/src/app/core"
    printf 'export const x = 1;\n' > "$RC_P1/src/app/core/logic.ts"
    git -C "$RC_P1" add -A

    RC_OUT_A="$( (cd "$RC_P1" && rc_run --repo-root "$RC_P1") 2>&1 )"
    RC_RC_A=$?
    assert_eq "0" "$RC_RC_A" "A 混用 fixture → exit 0"
    assert_contains "$RC_OUT_A" "rtm-check: PASS — 2 檔 3 條" "A PASS 統計行檔/條數"
    assert_contains "$RC_OUT_A" "implemented=1 partial=0 divergent=1 planned=1 na=0" "A 統計欄序＝宣告序"
    assert_contains "$RC_OUT_A" "impl_details 路徑 1 個（存在 1／缺失 0）" "A 路徑統計"

    # ═══ B. --emit-index：檔案存在、header hash、映射列、hash 兩側同值 ═══
    RC_OUT_B="$( (cd "$RC_P1" && rc_run --repo-root "$RC_P1" --emit-index) 2>&1 )"
    RC_RC_B=$?
    RC_IDX="$RC_P1/.claude/kit/rtm-index.tsv"
    assert_eq "0" "$RC_RC_B" "B --emit-index → exit 0"
    RC_IDX_EXISTS="no"; [ -f "$RC_IDX" ] && RC_IDX_EXISTS="yes"
    assert_eq "yes" "$RC_IDX_EXISTS" "B index 檔已產生"
    RC_HDR="$(head -1 "$RC_IDX")"
    assert_contains "$RC_HDR" "matrix_hash=sha256:" "B header 帶 matrix hash"
    assert_contains "$(cat "$RC_IDX")" "src/app/core/logic.ts	REQ-A-1	010-core.yaml" "B 映射列（解析後 repo-root 相對路徑）"
    RC_TS_HASH="$(printf '%s' "$RC_HDR" | sed -n 's/.*matrix_hash=sha256:\([0-9a-f]*\).*/\1/p')"
    assert_eq "$(rc_bash_hash "$RC_P1/docs/rtm/matrix")" "$RC_TS_HASH" "B hash 兩側同值（TS vs bash 公式）"

    # ═══ C. suffix 一對多 → 全 emit ═══
    mkdir -p "$RC_P1/src/lib/dup" "$RC_P1/src/other/dup"
    printf 'export const a = 1;\n' > "$RC_P1/src/lib/dup/util.ts"
    printf 'export const b = 2;\n' > "$RC_P1/src/other/dup/util.ts"
    cat > "$RC_P1/docs/rtm/matrix/030-dup.yaml" <<'EOF'
{ "meta": { "section": "REQ-C", "total_clauses": 1 },
  "entries": [
    { "req_id": "REQ-C-1", "req_text": "一對多 suffix", "status": "implemented",
      "detail_specs": ["規格"], "impl_details": ["共用: dup/util.ts"] } ] }
EOF
    git -C "$RC_P1" add -A
    RC_OUT_C="$( (cd "$RC_P1" && rc_run --repo-root "$RC_P1" --emit-index) 2>&1 )"
    RC_RC_C=$?
    assert_eq "0" "$RC_RC_C" "C 一對多 → exit 0"
    assert_contains "$(cat "$RC_IDX")" "src/lib/dup/util.ts	REQ-C-1	030-dup.yaml" "C 一對多命中①全 emit"
    assert_contains "$(cat "$RC_IDX")" "src/other/dup/util.ts	REQ-C-1	030-dup.yaml" "C 一對多命中②全 emit"

    # ═══ D. 七類違規逐一命中（訊息格式保留上游）═══
    RC_P2="$(rc_make_project)"
    cat > "$RC_P2/docs/rtm/matrix/010-v.yaml" <<'EOF'
{ "meta": { "section": "REQ-V", "total_clauses": 6 },
  "entries": [
    { "req_id": "REQ-V-1", "req_text": "非法狀態", "status": "bogus" },
    { "req_id": "REQ-V-2", "req_text": "缺 notes", "status": "divergent", "detail_specs": ["s"] },
    { "req_id": "XX-9", "req_text": "前綴不符", "status": "planned" },
    { "req_id": "REQ-V-3", "req_text": "路徑失準", "status": "implemented",
      "detail_specs": ["s"], "impl_details": ["ghost/missing-file.ts"] },
    { "req_id": "REQ-V-4", "req_text": "缺 impl_details", "status": "implemented", "detail_specs": ["s"] } ] }
EOF
    cat > "$RC_P2/docs/rtm/matrix/020-v.yaml" <<'EOF'
{ "meta": { "section": "REQ-V", "total_clauses": 1 },
  "entries": [
    { "req_id": "REQ-V-1", "req_text": "跨檔重複", "status": "planned" } ] }
EOF
    printf '{invalid json/yaml\n' > "$RC_P2/docs/rtm/matrix/030-bad.yaml"
    RC_OUT_D="$( (cd "$RC_P2" && rc_run --repo-root "$RC_P2") 2>&1 )"
    RC_RC_D=$?
    assert_eq "1" "$RC_RC_D" "D 違規 → exit 1"
    assert_contains "$RC_OUT_D" "條文守恆失敗 meta.total_clauses=6 ≠ entries 5" "D 條文守恆"
    assert_contains "$RC_OUT_D" "非法 status「bogus」" "D 非法 status"
    assert_contains "$RC_OUT_D" "divergent 但 notes 空" "D divergent 缺 notes"
    assert_contains "$RC_OUT_D" "XX-9 前綴與 meta.section「REQ-V」不符" "D 前綴不符"
    assert_contains "$RC_OUT_D" "impl_details 路徑失準——「ghost/missing-file.ts」" "D 路徑失準"
    assert_contains "$RC_OUT_D" "REQ-V-4: status=implemented 但 impl_details 空" "D 缺 impl_details"
    assert_contains "$RC_OUT_D" "REQ-V-1: 跨檔重複（010-v.yaml 與 020-v.yaml）" "D 跨檔重複"
    assert_contains "$RC_OUT_D" "YAML 解析失敗" "D 解析失敗"

    # ═══ E. js-yaml 缺失 → exit 1，訊息指明缺 js-yaml ═══
    RC_P3="$(rc_make_project)"
    rm -rf "$RC_P3/node_modules"
    cat > "$RC_P3/docs/rtm/matrix/010.yaml" <<'EOF'
{ "meta": { "section": "R", "total_clauses": 1 },
  "entries": [ { "req_id": "R-1", "req_text": "t", "status": "planned" } ] }
EOF
    RC_OUT_E="$( (cd "$RC_P3" && rc_run --repo-root "$RC_P3") 2>&1 )"
    RC_RC_E=$?
    assert_eq "1" "$RC_RC_E" "E 缺 js-yaml → exit 1"
    assert_contains "$RC_OUT_E" "js-yaml" "E 訊息指明缺 js-yaml"

    # ═══ F. status_enum 宣告序決定統計行欄序 ═══
    RC_P4="$(rc_make_project)"
    {
        printf 'matrix_dir: "docs/rtm/matrix"\n'
        printf 'status_enum: "na planned implemented partial divergent"\n'
        printf 'impl_path_bases: "."\n'
    } > "$RC_P4/.claude/kit/kit.yaml"
    cat > "$RC_P4/docs/rtm/matrix/010.yaml" <<'EOF'
{ "meta": { "section": "R", "total_clauses": 1 },
  "entries": [ { "req_id": "R-1", "req_text": "t", "status": "planned" } ] }
EOF
    RC_OUT_F="$( (cd "$RC_P4" && rc_run --repo-root "$RC_P4") 2>&1 )"
    RC_RC_F=$?
    assert_eq "0" "$RC_RC_F" "F 重排宣告 → exit 0"
    assert_contains "$RC_OUT_F" "na=0 planned=1 implemented=0 partial=0 divergent=0" "F 欄序＝宣告序"

    rm -rf "$RC_P1" "$RC_P2" "$RC_P3" "$RC_P4"

else
    echo "SKIP: rtm-check 引擎測試需可用 runtime——本機缺 ${RC_MISSING}（記 caveat：引擎行為未在本機驗證）"
    assert_contains "$RC_MISSING" "node" "SKIP 訊息指明缺什麼 runtime"
    # 缺 runtime：以明示 SKIP 補到與 runtime 分支同數（計入 skipped、不計入
    # assertion 數）——baseline 守衛比對 assertions+skipped，總數跨機器守恆。
    while [ $(( (TESTS_RUN - RC_START) + (TESTS_SKIPPED - RC_SKIP_START) )) -lt "$RC_EXPECTED" ]; do
        kit_test_skip "rtm-check 引擎測試需 runtime，本機缺 ${RC_MISSING}——未驗"
    done
fi

# 兩分支共同的 delta 守衛：斷言＋SKIP 數必須恰為 RC_EXPECTED（新增測試須同步改常數）
assert_eq "$RC_EXPECTED" "$(( (TESTS_RUN - RC_START) + (TESTS_SKIPPED - RC_SKIP_START) ))" "rtm-check 斷言數恆定守衛（改測試須同步 RC_EXPECTED）"
