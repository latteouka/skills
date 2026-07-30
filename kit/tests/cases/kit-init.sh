export KIT_INIT_ALLOW_WORKTREE=1  # 測試在 worktree 跑，豁免 H2 安裝守衛（守衛本身另有專測）
# kit-init.sh — dispatcher + modules/{rtm,wave-gates,ratchet} 測試（K5 🤖-4）
#
# runtime 政策（同 rtm-check.sh 合約）：無 node≥23.6/tsx → 「scaffold matrix
# 過 rtm-check」小節 SKIP 明示＋佔位斷言補到同數量——assertion-baseline 在
# 任何環境同值。
# js-yaml：fixture 用 kit 測試 stub（去 # 註解行後 JSON.parse）——scaffold
# matrix 刻意採「註解＋JSON 體」寫法（JSON 是 YAML 子集），真 js-yaml 解析
# 結果相同；parity 由 K5 🤖-C dfaa 雙跑合約看守。

KI_INIT="$KIT_ROOT/installers/kit-init.sh"
KI_RTM="$KIT_ROOT/installers/modules/rtm.sh"
KI_WG="$KIT_ROOT/installers/modules/wave-gates.sh"
KI_RAT="$KIT_ROOT/installers/modules/ratchet.sh"

# --- runtime 偵測（與 hooks/rtm-session-start.sh 同判準）---
KI_RUNTIME=""
KI_NODE_VER="$(node --version 2>/dev/null || true)"
if [ -n "$KI_NODE_VER" ]; then
    KI_MAJ="${KI_NODE_VER#v}"; KI_MAJ="${KI_MAJ%%.*}"
    KI_MIN="${KI_NODE_VER#v*.}"; KI_MIN="${KI_MIN%%.*}"
    case "$KI_MAJ" in ''|*[!0-9]*) KI_MAJ=0 ;; esac
    case "$KI_MIN" in ''|*[!0-9]*) KI_MIN=0 ;; esac
    if [ "$KI_MAJ" -gt 23 ] || { [ "$KI_MAJ" -eq 23 ] && [ "$KI_MIN" -ge 6 ]; }; then
        KI_RUNTIME="node"
    fi
fi
if [ -z "$KI_RUNTIME" ] && command -v tsx >/dev/null 2>&1; then
    KI_RUNTIME="tsx"
fi

# 在 sandbox 種 js-yaml 測試 stub＋package.json（rtm-check createRequire 解析用）
ki_seed_jsyaml() {
    mkdir -p "$1/node_modules/js-yaml"
    printf '{"name":"kit-init-fixture","private":true}\n' > "$1/package.json"
    printf '{"name":"js-yaml","version":"0.0.0-kitstub","main":"index.js"}\n' \
        > "$1/node_modules/js-yaml/package.json"
    printf 'module.exports = { load: function (s) { return JSON.parse(s.split("\\n").filter(function (l) { return !/^\\s*#/.test(l); }).join("\\n")); } };\n' \
        > "$1/node_modules/js-yaml/index.js"
}

# ══ ① dispatcher ═══════════════════════════════════════════════════

KI_S1="$(kit_test_sandbox)"

# 未知參數 exit 2
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT" --bogus) 2>&1 )"; ki_rc=$?
assert_eq "2" "$ki_rc" "① 未知參數 exit 2"

# 無參數＝用法錯誤 exit 2
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT") 2>&1 )"; ki_rc=$?
assert_eq "2" "$ki_rc" "① 無參數 exit 2（訪談歸 SKILL，installer 不猜）"

# --hygiene 單獨 → exit 1 含 K7
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT" --hygiene) 2>&1 )"; ki_rc=$?
assert_eq "1" "$ki_rc" "① --hygiene 單獨 exit 1"
assert_contains "$ki_out" "K7" "① --hygiene 訊息含 K7"

# --ratchet 缺 wave-gates → 報錯提示、不自動帶裝
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT" --ratchet) 2>&1 )"; ki_rc=$?
assert_eq "1" "$ki_rc" "① --ratchet 缺依賴 exit 1"
assert_contains "$ki_out" "wave-gates" "① --ratchet 缺依賴訊息提示 wave-gates"
assert_eq "0" "$([ -d "$KI_S1/.claude/kit/counters.d" ] && echo 1 || echo 0)" "① 依賴缺失不自動帶裝（counters.d 未建）"

# --all → exit 0、skipped(K7 交付)、五模組全裝
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT" --all --non-interactive) 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "① --all exit 0"
assert_contains "$ki_out" "skipped(K7 交付)" "① --all 列 skipped(K7 交付)"
assert_eq "1" "$([ -f "$KI_S1/.claude/dev/intake.config.yaml" ] && echo 1 || echo 0)" "① --all 裝 intake"
assert_eq "1" "$([ -f "$KI_S1/.claude/dev/backlog/INDEX.md" ] && echo 1 || echo 0)" "① --all 裝 backlog"
assert_eq "1" "$([ -f "$KI_S1/.claude/kit/gates.d/tierA.d/10-example.sh" ] && echo 1 || echo 0)" "① --all 裝 wave-gates（tierA 範例 stub）"
assert_eq "1" "$([ -f "$KI_S1/.claude/kit/gates.d/tierA.d/30-rtm-check.sh" ] && echo 1 || echo 0)" "① --all 裝 rtm（wave-gates 先行故 stub 有掛）"
assert_eq "1" "$([ -f "$KI_S1/docs/rtm/matrix/00-scaffold.yaml" ] && echo 1 || echo 0)" "① --all 裝 rtm（最小 matrix）"
assert_eq "1" "$([ -f "$KI_S1/.claude/kit/counters.d/00-example.counter.sh" ] && echo 1 || echo 0)" "① --all 裝 ratchet（範例 counter）"
assert_eq "1" "$([ -f "$KI_S1/.claude/kit/gates.d/tierA.d/50-ratchet.sh" ] && echo 1 || echo 0)" "① --all 裝 ratchet（gate stub）"

# --all 冪等重跑：exit 0、settings/kit.yaml/husky diff 零、marker 不重複
ki_sum1="$(cksum "$KI_S1/.claude/settings.json" "$KI_S1/.claude/kit/kit.yaml" "$KI_S1/.husky/pre-commit" "$KI_S1/.husky/pre-push" "$KI_S1/.gitignore")"
ki_out="$( (cd "$KI_S1" && bash "$KI_INIT" --all --non-interactive) 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "① --all 重跑 exit 0"
ki_sum2="$(cksum "$KI_S1/.claude/settings.json" "$KI_S1/.claude/kit/kit.yaml" "$KI_S1/.husky/pre-commit" "$KI_S1/.husky/pre-push" "$KI_S1/.gitignore")"
assert_eq "$ki_sum1" "$ki_sum2" "① --all 重跑 diff 零（cksum 前後一致）"
rm -rf "$KI_S1"

# ══ ② modules/rtm.sh ═══════════════════════════════════════════════

KI_S2="$(kit_test_sandbox)"
(cd "$KI_S2" && bash "$KIT_ROOT/installers/intake.sh" --non-interactive) >/dev/null 2>&1
printf '# 專案說明\n既有內容必須保留\n' > "$KI_S2/CLAUDE.md"

ki_out1="$( (cd "$KI_S2" && bash "$KI_RTM") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "② rtm 首跑 exit 0"
assert_eq "1" "$([ -f "$KI_S2/.claude/kit/kit.yaml" ] && echo 1 || echo 0)" "② 建 kit.yaml"
assert_contains "$(cat "$KI_S2/.claude/kit/kit.yaml")" 'modules: "rtm"' "② kit.yaml modules 登記 rtm"
assert_eq "1" "$([ -f "$KI_S2/docs/rtm/matrix/00-scaffold.yaml" ] && echo 1 || echo 0)" "② 建最小 matrix"
KI_CM="$(cat "$KI_S2/CLAUDE.md")"
assert_contains "$KI_CM" "既有內容必須保留" "② CLAUDE.md 既有內容保留（append 不覆寫）"
assert_contains "$KI_CM" "<!-- kit:rtm:begin -->" "② CLAUDE.md 插入 rtm marker 段"
assert_contains "$KI_CM" "docs/rtm/matrix/" "② {{MATRIX_DIR}} 已代換為 matrix_dir"
assert_not_contains "$KI_CM" "{{MATRIX_DIR}}" "② 佔位符無殘留"
KI_SET="$(cat "$KI_S2/.claude/settings.json")"
assert_contains "$KI_SET" "rtm-touch-reminder.sh" "② settings 掛 PostToolUse hook"
assert_contains "$KI_SET" "rtm-session-start.sh" "② settings 掛 SessionStart hook"
assert_contains "$KI_SET" "capture.sh" "② intake 既有 hook 保留"
assert_contains "$(cat "$KI_S2/.husky/pre-commit")" "require-requirements-sync.sh" "② pre-commit 掛 reqsync gate"
KI_PCM="$(cat "$KI_S2/.husky/prepare-commit-msg")"
assert_contains "$KI_PCM" "append-req-sync-skip-trailer.sh" "② prepare-commit-msg 掛 trailer"
assert_contains "$KI_PCM" '"$1"' "② trailer 掛載透傳訊息檔參數 \$1"
KI_CFG="$(cat "$KI_S2/.claude/dev/intake.config.yaml")"
assert_contains "$KI_CFG" 'spec_layer: "docs/rtm/matrix/"' "② 回填 spec_layer"
assert_contains "$KI_CFG" "rtm-check.ts" "② 回填 spec_check"
assert_contains "$ki_out1" "wave-gates" "② 無 gates.d 提示先裝 --wave-gates"
assert_eq "0" "$([ -f "$KI_S2/.claude/kit/gates.d/tierA.d/30-rtm-check.sh" ] && echo 1 || echo 0)" "② 無 gates.d 不掛 stub（不失敗）"

# 冪等：重跑全 skip、diff 零
ki_sum1="$(cksum "$KI_S2/.claude/settings.json" "$KI_S2/.claude/kit/kit.yaml" "$KI_S2/CLAUDE.md" "$KI_S2/docs/rtm/matrix/00-scaffold.yaml" "$KI_S2/.gitignore" "$KI_S2/.husky/pre-commit" "$KI_S2/.husky/prepare-commit-msg" "$KI_S2/.claude/dev/intake.config.yaml")"
ki_out2="$( (cd "$KI_S2" && bash "$KI_RTM") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "② rtm 重跑 exit 0"
assert_not_contains "$ki_out2" "新建" "② 重跑無任何新建（全 skip）"
ki_sum2="$(cksum "$KI_S2/.claude/settings.json" "$KI_S2/.claude/kit/kit.yaml" "$KI_S2/CLAUDE.md" "$KI_S2/docs/rtm/matrix/00-scaffold.yaml" "$KI_S2/.gitignore" "$KI_S2/.husky/pre-commit" "$KI_S2/.husky/prepare-commit-msg" "$KI_S2/.claude/dev/intake.config.yaml")"
assert_eq "$ki_sum1" "$ki_sum2" "② rtm 重跑 diff 零（cksum 前後一致）"

# gitignore 三條各恰一行（冪等）
assert_eq "1" "$(grep -c '^\.claude/kit/rtm-index\.tsv$' "$KI_S2/.gitignore")" "② gitignore rtm-index.tsv 恰一行"
assert_eq "1" "$(grep -c '^\.claude/kit/\.rtm-seen/$' "$KI_S2/.gitignore")" "② gitignore .rtm-seen/ 恰一行"
assert_eq "1" "$(grep -c '^\.claude/dev/\.rtm-reminder-log$' "$KI_S2/.gitignore")" "② gitignore .rtm-reminder-log 恰一行"

# scaffold 最小 matrix 過 rtm-check（runtime 分支；SKIP 分支佔位斷言數相同）
if [ -n "$KI_RUNTIME" ]; then
    ki_seed_jsyaml "$KI_S2"
    ki_out="$("$KI_RUNTIME" "$KIT_ROOT/engines/rtm-check.ts" --repo-root "$KI_S2" 2>&1)"; ki_rc=$?
    assert_eq "0" "$ki_rc" "② scaffold matrix 過 rtm-check（exit 0）"
    assert_contains "$ki_out" "rtm-check: PASS" "② rtm-check 輸出 PASS 統計行"
    assert_contains "$ki_out" "planned=1" "② 統計行 planned=1（scaffold 條目）"
else
    # 缺 runtime：逐檢查點明示 SKIP（計入 skipped、不計入 assertion 數），不用恆真斷言佔位。
    kit_test_skip "無 node≥23.6/tsx——② scaffold matrix 過 rtm-check（exit 0）未驗"
    kit_test_skip "無 node≥23.6/tsx——② rtm-check 輸出 PASS 統計行未驗"
    kit_test_skip "無 node≥23.6/tsx——② 統計行 planned=1（scaffold 條目）未驗"
fi
rm -rf "$KI_S2"

# 壞 settings.json → 零寫入中止
KI_S3="$(kit_test_sandbox)"
(cd "$KI_S3" && bash "$KIT_ROOT/installers/intake.sh" --non-interactive) >/dev/null 2>&1
printf '{ this is not json' > "$KI_S3/.claude/settings.json"
ki_out="$( (cd "$KI_S3" && bash "$KI_RTM") 2>&1 )"; ki_rc=$?
assert_eq "1" "$ki_rc" "② 壞 settings.json 中止安裝"
assert_eq "{ this is not json" "$(cat "$KI_S3/.claude/settings.json")" "② 壞 JSON 未被改動"
assert_eq "0" "$([ -f "$KI_S3/.claude/kit/kit.yaml" ] && echo 1 || echo 0)" "② 壞 JSON 零寫入（無 kit.yaml）"
assert_eq "0" "$([ -d "$KI_S3/docs/rtm/matrix" ] && echo 1 || echo 0)" "② 壞 JSON 零寫入（無 matrix 目錄）"
assert_eq "0" "$([ -f "$KI_S3/CLAUDE.md" ] && echo 1 || echo 0)" "② 壞 JSON 零寫入（無 CLAUDE.md）"
rm -rf "$KI_S3"

# ══ ③ modules/wave-gates.sh ＋ ④ modules/ratchet.sh ═══════════════

KI_S4="$(kit_test_sandbox)"
mkdir -p "$KI_S4/.husky"
printf '#!/usr/bin/env sh\necho existing-pre-push\n' > "$KI_S4/.husky/pre-push"

ki_out1="$( (cd "$KI_S4" && bash "$KI_WG") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "③ wave-gates 首跑 exit 0"
assert_eq "1" "$([ -f "$KI_S4/.claude/kit/gates.d/tierB.d/10-example.sh" ] && echo 1 || echo 0)" "③ tierB 範例 stub 落檔"
assert_eq "1" "$([ -d "$KI_S4/.claude/kit/canary.d" ] && echo 1 || echo 0)" "③ canary.d 目錄"
KI_PSC="$(cat "$KI_S4/.claude/kit/pathspec-targets.conf")"
assert_contains "$KI_PSC" ".husky/pre-push" "③ pathspec-targets.conf 預設列 .husky"
KI_PP="$(cat "$KI_S4/.husky/pre-push")"
assert_contains "$KI_PP" "existing-pre-push" "③ 既有 pre-push 內容保留"
assert_contains "$KI_PP" "wave-regate-guard.sh" "③ pre-push 掛 regate guard（check）"
assert_contains "$KI_PP" "wave-close-guard.sh" "③ pre-push 掛 close guard"
assert_contains "$KI_PP" "backlog-writeback-guard.sh" "③ pre-push 掛 backlog guard"
assert_contains "$(cat "$KI_S4/.husky/pre-commit")" "closure-lock-guard.sh" "③ pre-commit 掛 closure-lock guard"

# 冪等＋marker 兩次不重複
ki_sum1="$(cksum "$KI_S4/.claude/kit/kit.yaml" "$KI_S4/.husky/pre-commit" "$KI_S4/.husky/pre-push" "$KI_S4/.claude/kit/pathspec-targets.conf" "$KI_S4/.claude/kit/gates.d/tierA.d/10-example.sh")"
ki_out2="$( (cd "$KI_S4" && bash "$KI_WG") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "③ wave-gates 重跑 exit 0"
assert_not_contains "$ki_out2" "新建" "③ 重跑無任何新建（全 skip）"
ki_sum2="$(cksum "$KI_S4/.claude/kit/kit.yaml" "$KI_S4/.husky/pre-commit" "$KI_S4/.husky/pre-push" "$KI_S4/.claude/kit/pathspec-targets.conf" "$KI_S4/.claude/kit/gates.d/tierA.d/10-example.sh")"
assert_eq "$ki_sum1" "$ki_sum2" "③ 重跑 diff 零（cksum 前後一致）"
assert_eq "1" "$(grep -c '>>> kit:wave-gates >>>' "$KI_S4/.husky/pre-push")" "③ pre-push marker 起始行恰一次"
assert_eq "1" "$(grep -c '>>> kit:wave-gates >>>' "$KI_S4/.husky/pre-commit")" "③ pre-commit marker 起始行恰一次"

# ④ ratchet（gates.d 已由 ③ 備妥）
ki_out1="$( (cd "$KI_S4" && bash "$KI_RAT") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "④ ratchet 首跑 exit 0"
assert_eq "1" "$([ -f "$KI_S4/.claude/kit/counters.d/00-example.counter.sh" ] && echo 1 || echo 0)" "④ counters.d 範例落檔"
assert_eq "1" "$([ -f "$KI_S4/.claude/kit/gates.d/tierA.d/50-ratchet.sh" ] && echo 1 || echo 0)" "④ ratchet gate stub 落檔"
assert_contains "$ki_out1" "RATCHET_ALLOW_TIGHTEN=1" "④ 輸出 baseline 首跑說明"
assert_contains "$(cat "$KI_S4/.claude/kit/kit.yaml")" 'wave-gates ratchet' "④ kit.yaml modules 累積登記"
ki_sum1="$(cksum "$KI_S4/.claude/kit/kit.yaml" "$KI_S4/.claude/kit/counters.d/00-example.counter.sh" "$KI_S4/.claude/kit/gates.d/tierA.d/50-ratchet.sh")"
ki_out2="$( (cd "$KI_S4" && bash "$KI_RAT") 2>&1 )"; ki_rc=$?
assert_eq "0" "$ki_rc" "④ ratchet 重跑 exit 0"
assert_not_contains "$ki_out2" "新建" "④ 重跑無任何新建（全 skip）"
ki_sum2="$(cksum "$KI_S4/.claude/kit/kit.yaml" "$KI_S4/.claude/kit/counters.d/00-example.counter.sh" "$KI_S4/.claude/kit/gates.d/tierA.d/50-ratchet.sh")"
assert_eq "$ki_sum1" "$ki_sum2" "④ 重跑 diff 零（cksum 前後一致）"
rm -rf "$KI_S4"

# ══ ⑤ SKILL.md ═════════════════════════════════════════════════════

KI_SKILL_LINES="$(wc -l < "$KIT_ROOT/SKILL.md" | tr -d ' ')"
assert_eq "1" "$([ "$KI_SKILL_LINES" -le 110 ] && echo 1 || echo 0)" "⑤ SKILL.md 行數 ≤110（實際 ${KI_SKILL_LINES}）"
KI_SKILL="$(cat "$KIT_ROOT/SKILL.md")"
assert_contains "$KI_SKILL" "最小組" "⑤ SKILL.md 含三檔組合：最小組"
assert_contains "$KI_SKILL" "標準組" "⑤ SKILL.md 含三檔組合：標準組"
assert_contains "$KI_SKILL" "全套" "⑤ SKILL.md 含三檔組合：全套"
assert_contains "$KI_SKILL" "K7" "⑤ SKILL.md 標記 K7 未實裝"
assert_contains "$KI_SKILL" ".kit-init-progress.yaml" "⑤ SKILL.md 含 progress 檔說明"

# --- [K5-C 安全修] H2：worktree 安裝守衛（無豁免時必擋）
# 環境無關化：把 kit-init.sh 複製進「假 worktree 路徑」執行——KIT_ROOT 由腳本自身位置推導，
# 必含 .claude/worktrees/ 觸發守衛。直接跑 $KIT_ROOT 版在 main checkout 上守衛不觸發、
# 會真裝進 kit repo（K5 收尾實踩：suite 中斷後 main 留下 installer 殘留）。
H2_BASE="$(mktemp -d)"
H2_FAKE="$H2_BASE/repo/.claude/worktrees/wave-x/kit/installers"
mkdir -p "$H2_FAKE"
cp "$KIT_ROOT/installers/kit-init.sh" "$H2_FAKE/"
H2_TARGET="$(kit_test_sandbox)"
H2_OUT="$( cd "$H2_TARGET" && KIT_INIT_ALLOW_WORKTREE=0 bash "$H2_FAKE/kit-init.sh" --intake 2>&1 )"
H2_RC=$?
assert_eq "1" "$H2_RC" "H2: worktree 安裝無豁免 exit 1"
assert_contains "$H2_OUT" "worktree" "H2: 錯誤訊息指明 worktree"
rm -rf "$H2_BASE" "$H2_TARGET"

# --- [K5-C 安全修] H1：空檔 settings.json → merge 拒絕（非假成功）
H1_SANDBOX="$(kit_test_sandbox)"
mkdir -p "$H1_SANDBOX/.claude"
printf '' > "$H1_SANDBOX/.claude/settings.json"
H1_OUT="$( cd "$H1_SANDBOX" && bash "$KIT_ROOT/installers/kit-init.sh" --intake --non-interactive 2>&1 )"
H1_RC=$?
assert_eq "1" "$H1_RC" "H1: 空檔 settings.json exit 1（不再假成功）"
assert_contains "$H1_OUT" "object" "H1: 錯誤訊息指明非 JSON object"
assert_eq "0" "$(printf '%s' "$(cat "$H1_SANDBOX/.claude/settings.json" | wc -c | tr -d ' ')")" "H1: 空檔未被覆寫（零寫入）"
rm -rf "$H1_SANDBOX"
