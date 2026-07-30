# reqsync.sh — gates/require-requirements-sync.sh + append-req-sync-skip-trailer.sh 測試（K5）
#
# 純 bash/git，無 runtime 依賴。合約場景：anchors 擋／excludes 放／SKIP 逃生口
# ＋trailer／amend 不重複／裸 1 擋／merge commit 跳過／中文 matrix 檔名 fixture
# （core.quotepath 上游實踩）／anchors 未宣告降級明示。

RS_GATE="$KIT_ROOT/gates/require-requirements-sync.sh"
RS_TRAILER="$KIT_ROOT/gates/append-req-sync-skip-trailer.sh"

# sandbox：git repo + kit.yaml 宣告（anchors 兩組、excludes 兩段）
rs_make_repo() {
    local d
    d="$(mktemp -d)"
    git -C "$d" init -q
    mkdir -p "$d/.claude/kit"
    {
        printf 'matrix_dir: "docs/rtm/matrix"\n'
        printf 'reqsync_anchors: "src/server prisma/schema"\n'
        printf 'reqsync_excludes: "__tests__ migrations"\n'
    } > "$d/.claude/kit/kit.yaml"
    echo "$d"
}

rs_stage() { # rs_stage <repo> <相對路徑>...
    local d="$1" f
    shift
    for f in "$@"; do
        mkdir -p "$d/$(dirname "$f")"
        printf 'x\n' > "$d/$f"
        git -C "$d" add "$f"
    done
}

# ═══ ① anchor 命中、matrix 未動 → 擋 ═══
RS_R1="$(rs_make_repo)"
rs_stage "$RS_R1" "src/server/foo.ts"
RS_OUT1="$( (cd "$RS_R1" && bash "$RS_GATE") 2>&1 )"
RS_RC1=$?
assert_eq "1" "$RS_RC1" "①anchor 命中未同步 → exit 1"
assert_contains "$RS_OUT1" "rtm-sync: 行為 diff 未同步 docs/rtm/matrix/" "①訊息帶宣告的 matrix_dir"
assert_contains "$RS_OUT1" "src/server/foo.ts" "①命中檔被點名"

# ═══ ② excludes：__tests__ 段放行 ═══
RS_R2="$(rs_make_repo)"
rs_stage "$RS_R2" "src/server/__tests__/foo.test.ts"
RS_OUT2="$( (cd "$RS_R2" && bash "$RS_GATE") 2>&1 )"
RS_RC2=$?
assert_eq "0" "$RS_RC2" "②__tests__ 排除 → exit 0"

# ═══ ③ excludes：migrations 段放行 ═══
RS_R3="$(rs_make_repo)"
rs_stage "$RS_R3" "prisma/schema/migrations/0001_init.sql"
RS_RC3=0
(cd "$RS_R3" && bash "$RS_GATE") >/dev/null 2>&1 || RS_RC3=$?
assert_eq "0" "$RS_RC3" "③migrations 排除 → exit 0"

# ═══ ④ anchor 命中＋中文檔名 matrix 同步 → 放行（core.quotepath fixture）═══
RS_R4="$(rs_make_repo)"
rs_stage "$RS_R4" "src/server/foo.ts" "docs/rtm/matrix/101-案件與證物管理.yaml"
RS_RC4=0
(cd "$RS_R4" && bash "$RS_GATE") >/dev/null 2>&1 || RS_RC4=$?
assert_eq "0" "$RS_RC4" "④中文 matrix 檔名同步 → exit 0（quotepath 不誤判）"

# ═══ ⑤ REQ_SYNC_SKIP="具體理由" 逃生口 ═══
RS_R5="$(rs_make_repo)"
rs_stage "$RS_R5" "src/server/foo.ts"
RS_OUT5="$( (cd "$RS_R5" && REQ_SYNC_SKIP="純重構，未改變行為" bash "$RS_GATE") 2>&1 )"
RS_RC5=$?
assert_eq "0" "$RS_RC5" "⑤具體理由 SKIP → exit 0"
assert_contains "$RS_OUT5" "已跳過" "⑤SKIP 明示（理由將寫入 trailer）"

# ═══ ⑥ 裸 REQ_SYNC_SKIP=1 → 照擋＋裸值訊息 ═══
RS_OUT6="$( (cd "$RS_R5" && REQ_SYNC_SKIP=1 bash "$RS_GATE") 2>&1 )"
RS_RC6=$?
assert_eq "1" "$RS_RC6" "⑥裸 1 → exit 1"
assert_contains "$RS_OUT6" "裸值）已停用" "⑥裸值停用訊息"

# ═══ ⑦ merge commit（MERGE_HEAD 存在）→ 跳過 ═══
RS_R7="$(rs_make_repo)"
rs_stage "$RS_R7" "src/server/foo.ts"
touch "$RS_R7/.git/MERGE_HEAD"
RS_RC7=0
(cd "$RS_R7" && bash "$RS_GATE") >/dev/null 2>&1 || RS_RC7=$?
assert_eq "0" "$RS_RC7" "⑦merge commit → exit 0"

# ═══ ⑧ anchors 未宣告 → 降級 SKIP 明示 ═══
RS_R8="$(mktemp -d)"
git -C "$RS_R8" init -q
rs_stage "$RS_R8" "src/server/foo.ts"
RS_OUT8="$( (cd "$RS_R8" && bash "$RS_GATE") 2>&1 )"
RS_RC8=$?
assert_eq "0" "$RS_RC8" "⑧無宣告 → exit 0"
assert_contains "$RS_OUT8" "SKIP(reqsync_anchors 未宣告" "⑧降級明示"

# ═══ ⑨ 非錨點檔 → 放行 ═══
RS_R9="$(rs_make_repo)"
rs_stage "$RS_R9" "README.md" "src/client/page.tsx"
RS_RC9=0
(cd "$RS_R9" && bash "$RS_GATE") >/dev/null 2>&1 || RS_RC9=$?
assert_eq "0" "$RS_RC9" "⑨非錨點檔 → exit 0"

# ═══ ⑩ 命中 >5 檔 → 計數行 ═══
RS_R10="$(rs_make_repo)"
rs_stage "$RS_R10" "src/server/a.ts" "src/server/b.ts" "src/server/c.ts" \
    "src/server/d.ts" "src/server/e.ts" "src/server/f.ts"
RS_OUT10="$( (cd "$RS_R10" && bash "$RS_GATE") 2>&1 )"
RS_RC10=$?
assert_eq "1" "$RS_RC10" "⑩多檔命中 → exit 1"
assert_contains "$RS_OUT10" "共 6 檔" "⑩計數行"

# ═══ trailer：寫入／amend 不重複／裸 1 不寫／未設不寫／無結尾換行 ═══
RS_MSG="$(mktemp)"
printf 'feat: 某功能\n\n內文' > "$RS_MSG"   # 刻意無結尾換行
REQ_SYNC_SKIP="純重構，未改變行為" bash "$RS_TRAILER" "$RS_MSG"
RS_TCOUNT="$(grep -c '^Req-Sync-Skip: 純重構，未改變行為$' "$RS_MSG")"
assert_eq "1" "$RS_TCOUNT" "trailer 寫入且自成一行（無結尾換行檔亦正確）"

REQ_SYNC_SKIP="純重構，未改變行為" bash "$RS_TRAILER" "$RS_MSG"
RS_TCOUNT2="$(grep -c '^Req-Sync-Skip:' "$RS_MSG")"
assert_eq "1" "$RS_TCOUNT2" "trailer amend/重跑不重複"

RS_MSG2="$(mktemp)"
printf 'fix: x\n' > "$RS_MSG2"
REQ_SYNC_SKIP=1 bash "$RS_TRAILER" "$RS_MSG2"
RS_TCOUNT3="$(grep -c '^Req-Sync-Skip:' "$RS_MSG2" || true)"
assert_eq "0" "$RS_TCOUNT3" "裸 1 不寫 trailer"

bash "$RS_TRAILER" "$RS_MSG2"
RS_TCOUNT4="$(grep -c '^Req-Sync-Skip:' "$RS_MSG2" || true)"
assert_eq "0" "$RS_TCOUNT4" "未設 REQ_SYNC_SKIP 不寫 trailer"

rm -rf "$RS_R1" "$RS_R2" "$RS_R3" "$RS_R4" "$RS_R5" "$RS_R7" "$RS_R8" "$RS_R9" "$RS_R10" "$RS_MSG" "$RS_MSG2"
