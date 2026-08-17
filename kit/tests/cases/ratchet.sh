# ratchet.sh — engines/ratchet.sh 引擎合約十一場景（scratch git repo + 假 counter 宣告）
#
# ①compare：現值>baseline 紅／≤ 綠
# ②--tighten 三態：<收緊、=不動、>不動且仍 exit 0（tighten 不是 gate）
#   ＋baseline 非 counter 鍵（allowlist 陣列）改寫後守恆＋非 base_branch 擋／豁免
# ③--report 含失敗 counter → 該行 ERROR 且仍 exit 0
# ④compare 模式 counter return 1 → 記錄並續跑其餘 counter，彙總後 exit 1
# ⑤雙向核對兩態各紅（有鍵無檔／有檔無鍵）＋0 個 counter 檔 fail-closed
# ⑥baseline 0 硬擋
# ⑦slow counter 五態（compare 跳過／RATCHET_FULL=1、--all 跑／tighten、report 不受影響）
# ⑧lib 檔（NN-*.lib.sh）不觸發核對＋有檔無函式紅
# ⑨inputs_ 定義但 origin 不可達 → 保守全跑（＋origin 可達時 skip／相關變更時跑）
# ⑩--count <name> 與 --count-<name> 糖衣等價
# ⑪無宣告預設態（無 kit.yaml：baseline 預設 quality-baseline.json、
#   base_branch=main、slow 空）＋--decl-dir/--repo-root seam＋base_branch 宣告生效

RT_ENGINE="$KIT_ROOT/engines/ratchet.sh"

rt_new_repo() {
    local d
    d="$(mktemp -d)"
    d="$(cd "$d" && pwd -P)"
    git -C "$d" init -q -b main
    git -C "$d" config user.email t@local
    git -C "$d" config user.name t
    git -C "$d" commit --allow-empty -qm init
    mkdir -p "$d/.claude/kit/counters.d"
    echo "$d"
}

# rt_counter <repo> <name> — 生成標準假 counter：跑到必留 ran-<name>.marker，
# 值讀 <repo>/<name>.value（檔缺＝return 1 模擬 counter 失敗）
rt_counter() {
    local repo="$1" name="$2" fn
    fn="count_$(printf '%s' "$name" | tr '-' '_')"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s() {\n' "$fn"
        printf '  touch "${PROJECT_ROOT}/ran-%s.marker"\n' "$name"
        printf '  cat "${PROJECT_ROOT}/%s.value" 2>/dev/null || return 1\n' "$name"
        printf '}\n'
    } > "$repo/.claude/kit/counters.d/$name.counter.sh"
}

# rt_baseline <repo> <counters-json> — 寫單行 baseline（單行故意：jq 改寫必換格式，
# 內容比對＝「檔案沒被重寫」的可靠證據）
rt_baseline() {
    printf '{ "counters": %s }\n' "$2" > "$1/quality-baseline.json"
}

# rt_run <repo> [engine args...] — RT_ENV 可注入環境變數（跑完歸零）
RT_ENV=""
rt_run() {
    local repo="$1"; shift
    # shellcheck disable=SC2086
    RT_OUT="$(cd "$repo" && env ${RT_ENV} bash "$RT_ENGINE" "$@" 2>&1)"
    RT_RC=$?
    RT_ENV=""
}

# ── ① compare：現值>baseline 紅／≤ 綠 ─────────────────────────────
RT_R1="$(rt_new_repo)"
rt_counter "$RT_R1" debt
rt_baseline "$RT_R1" '{"debt": 3}'
echo 5 > "$RT_R1/debt.value"
rt_run "$RT_R1"
assert_eq "1" "$RT_RC" "①現值 5 > baseline 3 → exit 1"
assert_contains "$RT_OUT" "debt 現值 5 > baseline 3" "①紅燈訊息含現值與 baseline"
echo 3 > "$RT_R1/debt.value"
rt_run "$RT_R1"
assert_eq "0" "$RT_RC" "①現值 = baseline → exit 0"
assert_contains "$RT_OUT" "ratchet: PASS" "①綠燈輸出 PASS 摘要"
assert_contains "$RT_OUT" "debt=3(<=3)" "①摘要含逐 counter 現值"
echo 2 > "$RT_R1/debt.value"
rt_run "$RT_R1"
assert_eq "0" "$RT_RC" "①現值 < baseline → exit 0（compare 永不寫檔）"
assert_eq "3" "$(jq -r '.counters.debt' "$RT_R1/quality-baseline.json")" "①compare 不動 baseline"

# ── ② --tighten 三態＋非 counter 鍵守恆＋branch 限定 ──────────────
RT_R2="$(rt_new_repo)"
rt_counter "$RT_R2" debt
printf '{ "counters": {"debt": 5}, "large-files-allowlist": [{"path": "src/x.ts", "reason": "r"}] }\n' \
    > "$RT_R2/quality-baseline.json"
echo 3 > "$RT_R2/debt.value"
rt_run "$RT_R2" --tighten
assert_eq "0" "$RT_RC" "②a 現值<baseline → tighten exit 0"
assert_contains "$RT_OUT" "收緊：規則 debt baseline 5 -> 3" "②a 收緊訊息"
assert_eq "3" "$(jq -r '.counters.debt' "$RT_R2/quality-baseline.json")" "②a baseline 改寫為現值"
assert_eq "src/x.ts" "$(jq -r '."large-files-allowlist"[0].path' "$RT_R2/quality-baseline.json")" \
    "②a 非 counter 鍵（allowlist 陣列）改寫後守恆"
RT_BL_BEFORE="$(cat "$RT_R2/quality-baseline.json")"
rt_run "$RT_R2" --tighten
assert_eq "0" "$RT_RC" "②b 現值=baseline → exit 0"
assert_contains "$RT_OUT" "無 counter 需要收緊" "②b 不動檔訊息"
assert_eq "$RT_BL_BEFORE" "$(cat "$RT_R2/quality-baseline.json")" "②b 檔案內容逐位元不變"
echo 9 > "$RT_R2/debt.value"
rt_run "$RT_R2" --tighten
assert_eq "0" "$RT_RC" "②c 現值>baseline → 不動且仍 exit 0（tighten 不是 gate）"
assert_eq "$RT_BL_BEFORE" "$(cat "$RT_R2/quality-baseline.json")" "②c baseline 不被放寬"
git -C "$RT_R2" checkout -q -b side
rt_run "$RT_R2" --tighten
assert_eq "1" "$RT_RC" "②d 非 base_branch tighten → exit 1"
assert_contains "$RT_OUT" "僅限 main branch" "②d 訊息含限定 branch"
RT_ENV="RATCHET_ALLOW_TIGHTEN=1"
rt_run "$RT_R2" --tighten
assert_eq "0" "$RT_RC" "②e RATCHET_ALLOW_TIGHTEN=1 豁免可跑"

# ②f tighten 遇壞 counter：字母序在後的仍收緊得到，壞的彙總報告後 exit 1
# （dfaa #2916 實測：舊語意下第 9 支壞掉 → 前 8 支已寫檔、後面全沒跑，
#   輸出只看得到那一支，得逐次修才知道還有幾支）
RT_R2F="$(rt_new_repo)"
rt_counter "$RT_R2F" aa-broken
rt_counter "$RT_R2F" zz-shrinks
rt_baseline "$RT_R2F" '{"aa-broken": 1, "zz-shrinks": 9}'
echo 2 > "$RT_R2F/zz-shrinks.value"
# aa-broken.value 不存在 → 字典序第一支就壞
RT_ENV=""
rt_run "$RT_R2F" --tighten
assert_eq "1" "$RT_RC" "②f tighten 有壞 counter → exit 1"
assert_contains "$RT_OUT" "counter [aa-broken] 執行失敗" "②f 指名壞掉的 counter"
assert_contains "$RT_OUT" "未參與本次收緊" "②f 明說壞的那支沒收緊"
assert_eq "2" "$(jq -r '.counters."zz-shrinks"' "$RT_R2F/quality-baseline.json")" \
    "②f 字母序在壞 counter 之後的仍正常收緊（不被遮蔽）"

# ── ③ --report 含失敗 counter → ERROR 行且仍 exit 0 ───────────────
RT_R3="$(rt_new_repo)"
rt_counter "$RT_R3" good
rt_counter "$RT_R3" bad
rt_baseline "$RT_R3" '{"good": 5, "bad": 7}'
echo 2 > "$RT_R3/good.value"
# bad.value 不存在 → counter return 1
rt_run "$RT_R3" --report
assert_eq "0" "$RT_RC" "③report 含失敗 counter 仍 exit 0（不是 gate）"
assert_contains "$RT_OUT" "bad=ERROR（counter 執行失敗，baseline=7）" "③失敗 counter 印 ERROR 行"
assert_contains "$RT_OUT" "good=2(baseline=5)" "③正常 counter 印 現值(baseline=X)"

# ── ④ compare counter 失敗 → 續跑其餘 counter，彙總後 exit 1 ────
# 契約於 2026-08-17 由「立即退出」改為「記錄並續跑」：立即退出會讓字母序在後的
# counter 完全沒被量到，而 dfaa #2916 的四次同族事故都是「一支壞 counter 遮蔽
# 之後約 50 支」——紅燈只露一個，每次都潛伏數十天到數月才被發現。
RT_R4="$(rt_new_repo)"
rt_counter "$RT_R4" aa-fail
rt_counter "$RT_R4" mm-alsofail
rt_counter "$RT_R4" zz-later
rt_baseline "$RT_R4" '{"aa-fail": 1, "mm-alsofail": 1, "zz-later": 1}'
echo 0 > "$RT_R4/zz-later.value"
# aa-fail.value 與 mm-alsofail.value 皆不存在 → 兩支都失敗
rt_run "$RT_R4"
assert_eq "1" "$RT_RC" "④counter 失敗 → exit 1（仍 fail-closed）"
assert_contains "$RT_OUT" "counter [aa-fail] 執行失敗" "④明確指名失敗的 counter"
assert_contains "$RT_OUT" "counter [mm-alsofail] 執行失敗" "④第二支失敗的 counter 也被指名（不被第一支遮蔽）"
assert_contains "$RT_OUT" "aa-fail mm-alsofail" "④彙總列出所有壞掉的 counter"
if [ -f "$RT_R4/ran-zz-later.marker" ]; then
    assert_eq "yes" "yes" "④續跑：字母序在失敗 counter 之後的仍被執行"
else
    assert_eq "後續 counter 已執行" "marker 不存在（zz-later 被遮蔽了）" "④續跑：字母序在失敗 counter 之後的仍被執行"
fi
assert_contains "$RT_OUT" "已比對 -- zz-later=0" "④紅燈時仍印出已量到的值（好的 counter 不被遮蔽）"

# ── ⑤ 雙向核對兩態各紅＋0 counter 檔 fail-closed ──────────────────
RT_R5="$(rt_new_repo)"
rt_counter "$RT_R5" debt
echo 1 > "$RT_R5/debt.value"
rt_baseline "$RT_R5" '{"debt": 1, "ghost": 2}'
rt_run "$RT_R5"
assert_eq "1" "$RT_RC" "⑤a baseline 有鍵無 counter 檔 → exit 1"
assert_contains "$RT_OUT" "有鍵 [ghost] 但 counters.d 無對應 counter 檔" "⑤a 指名多餘鍵"
rt_baseline "$RT_R5" '{"debt": 1}'
rt_counter "$RT_R5" extra
echo 0 > "$RT_R5/extra.value"
rt_run "$RT_R5"
assert_eq "1" "$RT_RC" "⑤b 有 counter 檔無 baseline 鍵 → exit 1"
assert_contains "$RT_OUT" "baseline 缺少或非數字的 counter [extra]" "⑤b 指名缺鍵 counter"
RT_R5C="$(rt_new_repo)"
rt_baseline "$RT_R5C" '{}'
rt_run "$RT_R5C"
assert_eq "1" "$RT_RC" "⑤c 0 個 counter 檔 → exit 1"
assert_contains "$RT_OUT" "0 個 *.counter.sh" "⑤c 明確報錯（跑了 0 個 counter ≠ 無債）"

# ── ⑥ baseline 0 硬擋 ─────────────────────────────────────────────
RT_R6="$(rt_new_repo)"
rt_counter "$RT_R6" zero-debt
rt_baseline "$RT_R6" '{"zero-debt": 0}'
echo 1 > "$RT_R6/zero-debt.value"
rt_run "$RT_R6"
assert_eq "1" "$RT_RC" "⑥baseline 0 時現值 1 → 硬擋"
echo 0 > "$RT_R6/zero-debt.value"
rt_run "$RT_R6"
assert_eq "0" "$RT_RC" "⑥baseline 0 現值 0 → 綠"

# ── ⑦ slow counter 四態 ───────────────────────────────────────────
RT_R7="$(rt_new_repo)"
printf 'slow_counters: "slowc"\n' > "$RT_R7/.claude/kit/kit.yaml"
rt_counter "$RT_R7" slowc
rt_counter "$RT_R7" fast
rt_baseline "$RT_R7" '{"slowc": 1, "fast": 0}'
echo 1 > "$RT_R7/slowc.value"
echo 0 > "$RT_R7/fast.value"
rt_run "$RT_R7"
assert_eq "0" "$RT_RC" "⑦a compare 跳過 slow counter → exit 0"
assert_contains "$RT_OUT" "slowc=skip(慢 counter" "⑦a 摘要明示 slow skip"
if [ -f "$RT_R7/ran-slowc.marker" ]; then
    assert_eq "slow counter 未執行" "marker 存在" "⑦a slow counter 真的沒跑"
else
    assert_eq "yes" "yes" "⑦a slow counter 真的沒跑"
fi
if [ -f "$RT_R7/ran-fast.marker" ]; then
    assert_eq "yes" "yes" "⑦a 非 slow counter 照跑"
else
    assert_eq "fast marker 存在" "不存在" "⑦a 非 slow counter 照跑"
fi
rm -f "$RT_R7/ran-slowc.marker" "$RT_R7/ran-fast.marker"
RT_ENV="RATCHET_FULL=1"
rt_run "$RT_R7"
assert_eq "0" "$RT_RC" "⑦b RATCHET_FULL=1 compare exit 0"
assert_contains "$RT_OUT" "slowc=1(<=1)" "⑦b RATCHET_FULL=1 時 slow counter 實跑入摘要"
if [ -f "$RT_R7/ran-slowc.marker" ]; then
    assert_eq "yes" "yes" "⑦b RATCHET_FULL=1 時 slow counter 真的跑了"
else
    assert_eq "slowc marker 存在" "不存在" "⑦b RATCHET_FULL=1 時 slow counter 真的跑了"
fi
rm -f "$RT_R7/ran-slowc.marker"
echo 2 > "$RT_R7/slowc.value"
rt_run "$RT_R7" --all
assert_eq "1" "$RT_RC" "⑦c --all 會執行 slow counter 並攔退步"
assert_contains "$RT_OUT" "slowc 現值 2 > baseline 1" "⑦c --all 不產生 slow skip"
if [ -f "$RT_R7/ran-slowc.marker" ]; then
    assert_eq "yes" "yes" "⑦c --all 真的跑了 slow counter"
else
    assert_eq "slowc marker 存在" "不存在" "⑦c --all 真的跑了 slow counter"
fi
rm -f "$RT_R7/ran-slowc.marker"
echo 1 > "$RT_R7/slowc.value"
rt_run "$RT_R7" --tighten
assert_eq "0" "$RT_RC" "⑦d tighten exit 0"
if [ -f "$RT_R7/ran-slowc.marker" ]; then
    assert_eq "yes" "yes" "⑦d tighten 不受 slow 影響（全跑）"
else
    assert_eq "slowc marker 存在" "不存在" "⑦d tighten 不受 slow 影響（全跑）"
fi
rm -f "$RT_R7/ran-slowc.marker"
rt_run "$RT_R7" --report
assert_eq "0" "$RT_RC" "⑦e report exit 0"
assert_contains "$RT_OUT" "slowc=1(baseline=1)" "⑦e report 不受 slow 影響（實值入列）"
if [ -f "$RT_R7/ran-slowc.marker" ]; then
    assert_eq "yes" "yes" "⑦e report 真的跑了 slow counter"
else
    assert_eq "slowc marker 存在" "不存在" "⑦e report 真的跑了 slow counter"
fi

# ── ⑧ lib 檔不觸發核對＋有檔無函式紅 ──────────────────────────────
RT_R8="$(rt_new_repo)"
cat > "$RT_R8/.claude/kit/counters.d/00-util.lib.sh" <<'EOF'
rt8_helper_value() {
  cat "${PROJECT_ROOT}/helper.value" 2>/dev/null || return 1
}
EOF
cat > "$RT_R8/.claude/kit/counters.d/uses-lib.counter.sh" <<'EOF'
count_uses_lib() {
  rt8_helper_value
}
EOF
echo 4 > "$RT_R8/helper.value"
rt_baseline "$RT_R8" '{"uses-lib": 4}'
rt_run "$RT_R8"
assert_eq "0" "$RT_RC" "⑧a lib 檔被載入供 counter 用、且不參與名稱核對"
assert_contains "$RT_OUT" "uses-lib=4(<=4)" "⑧a helper 取值正確入摘要"
cat > "$RT_R8/.claude/kit/counters.d/nofunc.counter.sh" <<'EOF'
count_wrong_name() { printf '0\n'; }
EOF
rt_baseline "$RT_R8" '{"uses-lib": 4, "nofunc": 0}'
rt_run "$RT_R8"
assert_eq "1" "$RT_RC" "⑧b counter 檔未定義對應函式 → exit 1"
assert_contains "$RT_OUT" "未定義函式 count_nofunc()" "⑧b 指名缺的函式"

# ── ⑨ inputs_：origin 不可達保守全跑／可達無變更 skip／相關變更跑 ──
RT_R9="$(rt_new_repo)"
rt_counter "$RT_R9" scoped
cat >> "$RT_R9/.claude/kit/counters.d/scoped.counter.sh" <<'EOF'
inputs_scoped() {
  printf '%s\n' '*.md'
}
EOF
rt_baseline "$RT_R9" '{"scoped": 1}'
echo 1 > "$RT_R9/scoped.value"
rt_run "$RT_R9"
assert_eq "0" "$RT_RC" "⑨a origin 不可達 exit 0"
assert_contains "$RT_OUT" "scoped=1(<=1)" "⑨a origin 不可達 → 保守實跑（不 skip）"
if [ -f "$RT_R9/ran-scoped.marker" ]; then
    assert_eq "yes" "yes" "⑨a 保守全跑證據：counter 真的執行"
else
    assert_eq "scoped marker 存在" "不存在" "⑨a 保守全跑證據：counter 真的執行"
fi
rm -f "$RT_R9/ran-scoped.marker"
git -C "$RT_R9" remote add origin "$RT_R9"
git -C "$RT_R9" fetch -q origin
rt_run "$RT_R9"
assert_eq "0" "$RT_RC" "⑨b origin/main=HEAD exit 0"
assert_contains "$RT_OUT" "scoped=skip(無相關變更，沿用 baseline 1)" "⑨b 無變更 → skip"
if [ -f "$RT_R9/ran-scoped.marker" ]; then
    assert_eq "skip 時 counter 不執行" "marker 存在" "⑨b skip 證據：counter 未執行"
else
    assert_eq "yes" "yes" "⑨b skip 證據：counter 未執行"
fi
echo 2 > "$RT_R9/scoped.value"
rt_run "$RT_R9" --all
assert_eq "1" "$RT_RC" "⑨c --all 在 origin/main=HEAD 時仍執行 scoped counter 並攔退步"
assert_contains "$RT_OUT" "scoped 現值 2 > baseline 1" "⑨c --all 輸出真實現值，不沿用 baseline"
if [ -f "$RT_R9/ran-scoped.marker" ]; then
    assert_eq "yes" "yes" "⑨c --all 證據：scoped counter 真的執行"
else
    assert_eq "scoped marker 存在" "不存在" "⑨c --all 證據：scoped counter 真的執行"
fi
rm -f "$RT_R9/ran-scoped.marker"
echo 1 > "$RT_R9/scoped.value"
echo x > "$RT_R9/plain.txt"
git -C "$RT_R9" add plain.txt
git -C "$RT_R9" commit -qm "irrelevant change"
rt_run "$RT_R9"
assert_contains "$RT_OUT" "scoped=skip(無相關變更" "⑨d 非宣告 pathspec 的變更 → 仍 skip"
echo x > "$RT_R9/note.md"
git -C "$RT_R9" add note.md
git -C "$RT_R9" commit -qm "relevant change"
rt_run "$RT_R9"
assert_contains "$RT_OUT" "scoped=1(<=1)" "⑨e 宣告 pathspec 有變更 → 實跑"
if [ -f "$RT_R9/ran-scoped.marker" ]; then
    assert_eq "yes" "yes" "⑨e 實跑證據：counter 執行"
else
    assert_eq "scoped marker 存在" "不存在" "⑨e 實跑證據：counter 執行"
fi

# ── ⑩ --count <name> 與 --count-<name> 糖衣等價 ───────────────────
RT_R10="$(rt_new_repo)"
rt_counter "$RT_R10" large-files
rt_baseline "$RT_R10" '{"large-files": 4}'
echo 4 > "$RT_R10/large-files.value"
rt_run "$RT_R10" --count large-files
RT_COUNT_A_OUT="$RT_OUT"; RT_COUNT_A_RC="$RT_RC"
rt_run "$RT_R10" --count-large-files
assert_eq "0" "$RT_COUNT_A_RC" "⑩--count large-files exit 0"
assert_eq "4" "$RT_COUNT_A_OUT" "⑩--count 輸出即 counter 現值"
assert_eq "$RT_COUNT_A_RC" "$RT_RC" "⑩糖衣 exit code 等價"
assert_eq "$RT_COUNT_A_OUT" "$RT_OUT" "⑩糖衣輸出等價"
rt_run "$RT_R10" --count no-such
assert_eq "1" "$RT_RC" "⑩未知 counter 名 → exit 1"
assert_contains "$RT_OUT" "unknown counter [no-such]" "⑩未知 counter 明確報錯"

# ── ⑪ 無宣告預設態＋seam＋base_branch 宣告生效 ────────────────────
RT_R11="$(rt_new_repo)"
# 無 kit.yaml：baseline 預設 quality-baseline.json、base_branch=main、slow 空
rt_counter "$RT_R11" debt
rt_baseline "$RT_R11" '{"debt": 2}'
echo 2 > "$RT_R11/debt.value"
rt_run "$RT_R11"
assert_eq "0" "$RT_RC" "⑪a 無 kit.yaml：預設 quality-baseline.json 生效（compare 綠）"
assert_not_contains "$RT_OUT" "慢 counter" "⑪a slow 預設空：無任何慢 counter skip"
git -C "$RT_R11" checkout -q -b side
rt_run "$RT_R11" --tighten
assert_eq "1" "$RT_RC" "⑪b 無宣告 base_branch 預設 main：非 main tighten 紅"
assert_contains "$RT_OUT" "僅限 main branch" "⑪b 訊息含預設 main"
# --decl-dir / --repo-root seam：宣告放非預設目錄、cwd 在 repo 外
RT_R11B="$(rt_new_repo)"
mkdir -p "$RT_R11B/customdecl/counters.d"
printf '#!/usr/bin/env bash\ncount_seam() { printf %s "1"; printf "\\n"; }\n' \
    > "$RT_R11B/customdecl/counters.d/seam.counter.sh"
rt_baseline "$RT_R11B" '{"seam": 1}'
RT_OUTSIDE="$(mktemp -d)"
RT_OUT="$(cd "$RT_OUTSIDE" && bash "$RT_ENGINE" --repo-root "$RT_R11B" --decl-dir "$RT_R11B/customdecl" 2>&1)"
RT_RC=$?
assert_eq "0" "$RT_RC" "⑪c --repo-root/--decl-dir seam：cwd 在 repo 外照常運作"
assert_contains "$RT_OUT" "seam=1(<=1)" "⑪c seam 下 counter 正常取值"
# base_branch 宣告生效：kit.yaml base_branch=develop → main 上 tighten 紅、develop 上綠
RT_R11C="$(rt_new_repo)"
printf 'base_branch: "develop"\n' > "$RT_R11C/.claude/kit/kit.yaml"
rt_counter "$RT_R11C" debt
rt_baseline "$RT_R11C" '{"debt": 0}'
echo 0 > "$RT_R11C/debt.value"
rt_run "$RT_R11C" --tighten
assert_eq "1" "$RT_RC" "⑪d base_branch 宣告 develop：main 上 tighten 紅"
assert_contains "$RT_OUT" "僅限 develop branch" "⑪d 訊息含宣告的 base_branch"
git -C "$RT_R11C" checkout -q -b develop
rt_run "$RT_R11C" --tighten
assert_eq "0" "$RT_RC" "⑪e base_branch 宣告 develop：develop 上 tighten 可跑"

rm -rf "$RT_R1" "$RT_R2" "$RT_R3" "$RT_R4" "$RT_R5" "$RT_R5C" "$RT_R6" "$RT_R7" \
    "$RT_R8" "$RT_R9" "$RT_R10" "$RT_R11" "$RT_R11B" "$RT_R11C" "$RT_OUTSIDE"
