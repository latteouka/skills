# rtm-hooks.sh — hooks/rtm-touch-reminder.sh + hooks/rtm-session-start.sh 測試（K5）
#
# touch-reminder 四態（命中／未命中／缺失或過期／同 session 去重）＋ fallback
# 尾綴比對＋非 rtm 專案靜默——全部純 bash，無 runtime 依賴（index 以 bash 側
# 同公式 hash 手工鑄造）。session-start：GC／新鮮靜默／無 runtime 明示／
# 重生（重生段 runtime-gated，SKIP 分支佔位斷言維持斷言數恆定）。

RH_TOUCH="$KIT_ROOT/hooks/rtm-touch-reminder.sh"
RH_START="$KIT_ROOT/hooks/rtm-session-start.sh"

# bash 側 matrix hash（與 hook／引擎同公式）
rh_bash_hash() {
    (cd "$1" && LC_ALL=C find . -maxdepth 1 -name '*.yaml' | LC_ALL=C sort \
        | while IFS= read -r f; do cat "$f"; done) | shasum -a 256 | awk '{print $1}'
}

# sandbox：git repo + kit.yaml + matrix（內容任意——touch-reminder 只 hash 不解析）
rh_make_repo() {
    local d
    d="$(mktemp -d)"
    git -C "$d" init -q
    mkdir -p "$d/.claude/kit" "$d/docs/rtm/matrix"
    printf 'matrix_dir: "docs/rtm/matrix"\n' > "$d/.claude/kit/kit.yaml"
    printf 'meta: fixture\n' > "$d/docs/rtm/matrix/010.yaml"
    echo "$d"
}

# 鑄造新鮮 index（header hash＝現算），映射 src/app/foo.ts → REQ-001
rh_write_index() {
    printf '# rtm-index v1 matrix_hash=sha256:%s\nsrc/app/foo.ts\tREQ-001\t010.yaml\n' \
        "$(rh_bash_hash "$1/docs/rtm/matrix")" > "$1/.claude/kit/rtm-index.tsv"
}

# rh_touch <repo> <session> <file_path> → stdout/stderr 合流進 RH_OUT、rc 進 RH_RC
rh_touch() {
    RH_OUT="$(printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$2" "$3" \
        | CLAUDE_PROJECT_DIR="$1" bash "$RH_TOUCH" 2>&1)"
    RH_RC=$?
}

RH_R1="$(rh_make_repo)"
rh_write_index "$RH_R1"
RH_LOG="$RH_R1/.claude/dev/.rtm-reminder-log"

# ═══ T1 命中：exit 2 傳訊＋log＋seen ═══
rh_touch "$RH_R1" "sess-A" "$RH_R1/src/app/foo.ts"
assert_eq "2" "$RH_RC" "T1 命中 → exit 2（傳訊不 block）"
assert_contains "$RH_OUT" "REQ-001" "T1 提醒點名條目"
assert_eq "1" "$(grep -c '	hit$' "$RH_LOG")" "T1 命中 log 一筆"
RH_SEEN_A="no"; [ -f "$RH_R1/.claude/kit/.rtm-seen/sess-A" ] && RH_SEEN_A="yes"
assert_eq "yes" "$RH_SEEN_A" "T1 seen 檔帶 session_id 後綴"

# ═══ T2 同 session 去重：靜默 0、log 不增 ═══
rh_touch "$RH_R1" "sess-A" "$RH_R1/src/app/foo.ts"
assert_eq "0" "$RH_RC" "T2 同 session 重複 → exit 0"
assert_eq "" "$RH_OUT" "T2 靜默無輸出"
assert_eq "1" "$(grep -c '	hit$' "$RH_LOG")" "T2 log 不增"

# ═══ T3 不同 session：再次提醒（session 粒度去重）═══
rh_touch "$RH_R1" "sess-B" "$RH_R1/src/app/foo.ts"
assert_eq "2" "$RH_RC" "T3 新 session → 再提醒 exit 2"

# ═══ T4 未命中：靜默 0 ═══
rh_touch "$RH_R1" "sess-B" "$RH_R1/src/unrelated/bar.ts"
assert_eq "0" "$RH_RC" "T4 未命中 → exit 0"
assert_eq "" "$RH_OUT" "T4 靜默無輸出"

# ═══ T5 index 過期（matrix 變動）：首次 exit 2 明示＋log kind=stale ═══
printf 'changed\n' >> "$RH_R1/docs/rtm/matrix/010.yaml"
rh_touch "$RH_R1" "sess-C" "$RH_R1/src/app/foo.ts"
assert_eq "2" "$RH_RC" "T5 過期首次 → exit 2"
assert_contains "$RH_OUT" "rtm-index 過期" "T5 過期明示"
assert_eq "1" "$(grep -c '	stale$' "$RH_LOG")" "T5 stale log 一筆"

# ═══ T6 過期同 session 二次：靜默 0 ═══
rh_touch "$RH_R1" "sess-C" "$RH_R1/src/app/foo.ts"
assert_eq "0" "$RH_RC" "T6 過期同 session 二次 → exit 0"

# ═══ T7 index 缺失：首次 exit 2 明示、二次靜默 ═══
rm -f "$RH_R1/.claude/kit/rtm-index.tsv"
rh_touch "$RH_R1" "sess-D" "$RH_R1/src/app/foo.ts"
assert_eq "2" "$RH_RC" "T7 缺失首次 → exit 2"
assert_contains "$RH_OUT" "rtm-index 缺失" "T7 缺失明示"
rh_touch "$RH_R1" "sess-D" "$RH_R1/src/app/foo.ts"
assert_eq "0" "$RH_RC" "T7 缺失同 session 二次 → exit 0"

# ═══ T8 前綴剝不動 → fallback 尾綴比對 ═══
rh_write_index "$RH_R1"
rh_touch "$RH_R1" "sess-E" "/some-other-prefix/checkout/src/app/foo.ts"
assert_eq "2" "$RH_RC" "T8 尾綴 fallback 命中 → exit 2"

# ═══ T9 非 rtm 專案（無 matrix 目錄）：靜默 0 ═══
RH_R9="$(mktemp -d)"
git -C "$RH_R9" init -q
rh_touch "$RH_R9" "sess-F" "$RH_R9/src/app/foo.ts"
assert_eq "0" "$RH_RC" "T9 非 rtm 專案 → exit 0"

# ═══ S1+S2 session-start：GC（>7 天清、現役留）＋index 新鮮靜默 ═══
RH_S1="$(rh_make_repo)"
rh_write_index "$RH_S1"
mkdir -p "$RH_S1/.claude/kit/.rtm-seen"
printf 'stale\n' > "$RH_S1/.claude/kit/.rtm-seen/sess-old"
touch -t 202001010000 "$RH_S1/.claude/kit/.rtm-seen/sess-old"
printf 'stale\n' > "$RH_S1/.claude/kit/.rtm-seen/sess-new"
RH_SOUT="$(CLAUDE_PROJECT_DIR="$RH_S1" bash "$RH_START" </dev/null 2>&1)"
RH_SRC=$?
assert_eq "0" "$RH_SRC" "S1 session-start → exit 0"
RH_OLD="kept"; [ -f "$RH_S1/.claude/kit/.rtm-seen/sess-old" ] || RH_OLD="gone"
assert_eq "gone" "$RH_OLD" "S1 GC：>7 天 seen 檔已清"
RH_NEW="gone"; [ -f "$RH_S1/.claude/kit/.rtm-seen/sess-new" ] && RH_NEW="kept"
assert_eq "kept" "$RH_NEW" "S1 GC：現役 seen 檔保留"
assert_eq "" "$RH_SOUT" "S2 index 新鮮 → 靜默"

# ═══ S3 stale＋無 runtime → 明示無法重生、不擋 ═══
RH_S3="$(rh_make_repo)"   # 無 index ＝缺失
RH_NORT="$(mktemp -d)"
for RH_BIN in bash sh cat find sed head awk shasum sort rm dirname printf grep ls mkdir tr date git jq; do
    RH_BINPATH="$(command -v "$RH_BIN" 2>/dev/null)" && ln -s "$RH_BINPATH" "$RH_NORT/$RH_BIN"
done
RH_S3OUT="$(CLAUDE_PROJECT_DIR="$RH_S3" PATH="$RH_NORT" bash "$RH_START" </dev/null 2>&1)"
RH_S3RC=$?
assert_eq "0" "$RH_S3RC" "S3 無 runtime → exit 0（fail-open）"
assert_contains "$RH_S3OUT" "無可用 runtime" "S3 無法重生明示"

# ═══ S4 重生（runtime-gated；SKIP 分支佔位維持斷言數）═══
RH_RT_EXPECTED=4
RH_RT_START=$TESTS_RUN
RH_RT_SKIP_START=$TESTS_SKIPPED

RH_RUNTIME=""
RH_NODE_VER="$(node --version 2>/dev/null || true)"
if [ -n "$RH_NODE_VER" ]; then
    RH_MAJ="${RH_NODE_VER#v}"; RH_MAJ="${RH_MAJ%%.*}"
    RH_MIN="${RH_NODE_VER#v*.}"; RH_MIN="${RH_MIN%%.*}"
    case "$RH_MAJ" in ''|*[!0-9]*) RH_MAJ=0 ;; esac
    case "$RH_MIN" in ''|*[!0-9]*) RH_MIN=0 ;; esac
    if [ "$RH_MAJ" -gt 23 ] || { [ "$RH_MAJ" -eq 23 ] && [ "$RH_MIN" -ge 6 ]; }; then
        RH_RUNTIME="node"
    fi
fi
[ -n "$RH_RUNTIME" ] || { command -v tsx >/dev/null 2>&1 && RH_RUNTIME="tsx"; }

if [ -n "$RH_RUNTIME" ]; then
    RH_S4="$(mktemp -d)"
    git -C "$RH_S4" init -q
    mkdir -p "$RH_S4/node_modules/js-yaml" "$RH_S4/.claude/kit" "$RH_S4/docs/rtm/matrix" "$RH_S4/src"
    printf '{"name":"rtm-fixture","private":true}\n' > "$RH_S4/package.json"
    printf '{"name":"js-yaml","version":"0.0.0-kitstub","main":"index.js"}\n' \
        > "$RH_S4/node_modules/js-yaml/package.json"
    printf 'module.exports = { load: function (s) { return JSON.parse(s); } };\n' \
        > "$RH_S4/node_modules/js-yaml/index.js"
    printf 'matrix_dir: "docs/rtm/matrix"\n' > "$RH_S4/.claude/kit/kit.yaml"
    printf 'export const x = 1;\n' > "$RH_S4/src/thing.ts"
    cat > "$RH_S4/docs/rtm/matrix/010.yaml" <<'EOF'
{ "meta": { "section": "R", "total_clauses": 1 },
  "entries": [ { "req_id": "R-1", "req_text": "t", "status": "implemented",
    "detail_specs": ["s"], "impl_details": ["src/thing.ts"] } ] }
EOF
    RH_S4OUT="$(CLAUDE_PROJECT_DIR="$RH_S4" bash "$RH_START" </dev/null 2>&1)"
    RH_S4RC=$?
    assert_eq "0" "$RH_S4RC" "S4 重生 → exit 0"
    assert_contains "$RH_S4OUT" "rtm-index 已重生" "S4 重生明示"
    RH_S4IDX="no"; [ -f "$RH_S4/.claude/kit/rtm-index.tsv" ] && RH_S4IDX="yes"
    assert_eq "yes" "$RH_S4IDX" "S4 index 已產生"
    RH_S4HDR="$(head -1 "$RH_S4/.claude/kit/rtm-index.tsv" | sed -n 's/.*matrix_hash=sha256:\([0-9a-f]*\).*/\1/p')"
    assert_eq "$(rh_bash_hash "$RH_S4/docs/rtm/matrix")" "$RH_S4HDR" "S4 重生後 header hash 新鮮"
    rm -rf "$RH_S4"
else
    # 缺 runtime：以明示 SKIP 補到與 runtime 分支同數（計入 skipped、不計入
    # assertion 數）——記 caveat：重生路徑未在本機驗證。
    while [ $(( (TESTS_RUN - RH_RT_START) + (TESTS_SKIPPED - RH_RT_SKIP_START) )) -lt "$RH_RT_EXPECTED" ]; do
        kit_test_skip "rtm-session-start 重生段需 node≥23.6 或 tsx，本機皆缺——未驗"
    done
fi

assert_eq "$RH_RT_EXPECTED" "$(( (TESTS_RUN - RH_RT_START) + (TESTS_SKIPPED - RH_RT_SKIP_START) ))" "session-start 重生段斷言＋SKIP 數恆定守衛"

rm -rf "$RH_R1" "$RH_R9" "$RH_S1" "$RH_S3" "$RH_NORT"
