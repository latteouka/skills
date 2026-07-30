# canary-harness.sh — harness 的 harness：用假 gate 驗三斷言邏輯本身（雙向）
#
# 四假 gate：①行為全對 → 引擎必 PASS（不該攔的必不攔）②放行 violation → 必抓
# ③inspected:0 → 必抓 ④誤攔 clean → 必抓。另驗 canary.d 缺失 exit 2、.fixture 還原、
# gates.d↔canary.d 對帳（K5.5 GPT §4.3）、clean fixture 假通過（inspected:0/缺）。

CANARY_ENGINE="$KIT_ROOT/engines/canary.sh"

CN_DECL="$(mktemp -d)"
mkdir -p "$CN_DECL/canary.d"

_cn_mkgate() { # name run_sh_body
    local g="$CN_DECL/canary.d/$1"
    mkdir -p "$g/violation" "$g/clean"
    echo "bad content" > "$g/violation/file.txt"
    echo "good content" > "$g/clean/file.txt"
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$g/run.sh"
}

_cn_mkgate_in() { # decl_dir name run_sh_body — 同 _cn_mkgate，但可指定任意宣告目錄
    local g="$1/canary.d/$2"
    mkdir -p "$g/violation" "$g/clean"
    echo "bad content" > "$g/violation/file.txt"
    echo "good content" > "$g/clean/file.txt"
    printf '#!/usr/bin/env bash\n%s\n' "$3" > "$g/run.sh"
}
_cn_ok_body='if grep -q bad file.txt 2>/dev/null; then echo "inspected:1"; exit 1; fi; echo "inspected:1"; exit 0'

# ① 行為全對：violation（含 bad）→ exit 1；clean → exit 0；inspected:1
_cn_mkgate good 'if grep -q bad file.txt 2>/dev/null; then echo "inspected:1"; exit 1; fi; echo "inspected:1"; exit 0'
# ② 放行 violation：恆 exit 0
_cn_mkgate lets-violation-through 'echo "inspected:1"; exit 0'
# ③ inspected:0：正確攔但報 0 檢查數
_cn_mkgate zero-inspected 'if grep -q bad file.txt 2>/dev/null; then echo "inspected:0"; exit 1; fi; echo "inspected:0"; exit 0'
# ④ 誤攔 clean：恆 exit 1
_cn_mkgate blocks-clean 'echo "inspected:1"; exit 1'

CN_OUT="$(bash "$CANARY_ENGINE" --decl-dir "$CN_DECL" 2>&1)"
CN_RC=$?

assert_eq "1" "$CN_RC" "四假 gate 引擎總結 exit 1（三支問題 gate 在場）"
assert_contains "$CN_OUT" "1/4 gate PASS" "只有行為全對的 gate PASS（正向對照）"
assert_contains "$CN_OUT" "lets-violation-through" "放行 violation 的 gate 被點名"
assert_contains "$CN_OUT" "zero-inspected" "inspected:0 的 gate 被點名"
assert_contains "$CN_OUT" "假 PASS 母題" "inspected:0 訊息含母題標記"
assert_contains "$CN_OUT" "blocks-clean" "誤攔 clean 的 gate 被點名"
assert_not_contains "$CN_OUT" "✗ good" "行為全對的 gate 零失敗訊息"

# --- 只留 good gate → 全綠 exit 0
rm -rf "$CN_DECL/canary.d/lets-violation-through" "$CN_DECL/canary.d/zero-inspected" "$CN_DECL/canary.d/blocks-clean"
CN_OUT2="$(bash "$CANARY_ENGINE" --decl-dir "$CN_DECL" 2>&1)"
assert_eq "0" "$(echo $?)" "全對 gate 單獨跑 exit 0"
assert_contains "$CN_OUT2" "1/1 gate PASS" "全綠總結"

# --- canary.d 缺失 → fail-closed exit 2
CN_EMPTY="$(mktemp -d)"
bash "$CANARY_ENGINE" --decl-dir "$CN_EMPTY" >/dev/null 2>&1
assert_eq "2" "$?" "canary.d 缺失 exit 2（fail-closed）"
# --- canary.d 存在但零 gate → exit 2
mkdir -p "$CN_EMPTY/canary.d"
bash "$CANARY_ENGINE" --decl-dir "$CN_EMPTY" >/dev/null 2>&1
assert_eq "2" "$?" "canary.d 零 gate exit 2（測了 0 支 ≠ 全綠）"

# --- .fixture 副檔名遮蔽還原
CN_FX="$CN_DECL/canary.d/fixture-restore"
mkdir -p "$CN_FX/violation" "$CN_FX/clean"
echo "bad content" > "$CN_FX/violation/sample.ts.fixture"
echo "good content" > "$CN_FX/clean/sample.ts.fixture"
printf '#!/usr/bin/env bash\nif [ -f sample.ts ] && grep -q bad sample.ts; then echo "inspected:1"; exit 1; elif [ -f sample.ts ]; then echo "inspected:1"; exit 0; else echo "inspected:0"; exit 1; fi\n' > "$CN_FX/run.sh"
CN_OUT3="$(bash "$CANARY_ENGINE" --decl-dir "$CN_DECL" 2>&1)"
assert_eq "0" "$(echo $?)" ".fixture 還原後 gate 收到真檔名（2/2 PASS）"
assert_contains "$CN_OUT3" "2/2 gate PASS" ".fixture gate 三斷言全過"

# --- git marker：scratch repo + origin/main 可解析
CN_GIT="$CN_DECL/canary.d/git-gate"
mkdir -p "$CN_GIT/violation" "$CN_GIT/clean"
echo "x" > "$CN_GIT/violation/f.txt"; echo "x" > "$CN_GIT/clean/f.txt"
touch "$CN_GIT/git"
printf '#!/usr/bin/env bash\ngit rev-parse --verify origin/main >/dev/null 2>&1 || { echo "inspected:0"; exit 1; }\nif [ -f f.txt ] && [ "$(basename "$PWD")" = "violation" ]; then echo "inspected:1"; exit 1; fi\necho "inspected:1"; exit 0\n' > "$CN_GIT/run.sh"
CN_OUT4="$(bash "$CANARY_ENGINE" --decl-dir "$CN_DECL" 2>&1)"
assert_eq "0" "$(echo $?)" "git marker gate：scratch repo 內 origin/main 可解析且三斷言過"

# --- gates.d↔canary.d 對帳（K5.5 GPT §4.3）：以 gates.d 的 stub 清單為準反查
# canary.d，防「一支沒有 fixture 的 gate 永久漏測」
CN_RC="$(mktemp -d)"
mkdir -p "$CN_RC/gates.d/tierA.d" "$CN_RC/gates.d/tierB.d" "$CN_RC/canary.d"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CN_RC/gates.d/tierA.d/10-foo.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CN_RC/gates.d/tierB.d/20-bar.sh"

# 紅：兩支 stub 皆缺對應 canary fixture（命名規則：tierX.d/NN-<name>.sh → tierX-<name>）
CN_RC_OUT="$(bash "$CANARY_ENGINE" --decl-dir "$CN_RC" 2>&1)"
CN_RC_RC=$?
assert_eq "1" "$CN_RC_RC" "對帳：gates.d 兩支 stub 皆缺 canary fixture → exit 1"
assert_contains "$CN_RC_OUT" "tierA-foo" "缺 fixture 訊息點名 tierA-foo（去 NN- 前綴＋tier 前綴）"
assert_contains "$CN_RC_OUT" "tierB-bar" "缺 fixture 訊息點名 tierB-bar"
assert_contains "$CN_RC_OUT" "對帳失敗" "對帳失敗彙總訊息"

# 補 tierA-foo 的 canary fixture；tierB-bar 用空理由 .skip（無效豁免——仍須 FAIL）
_cn_mkgate_in "$CN_RC" "tierA-foo" "$_cn_ok_body"
: > "$CN_RC/canary.d/tierB-bar.skip"
CN_RC_OUT2="$(bash "$CANARY_ENGINE" --decl-dir "$CN_RC" 2>&1)"
CN_RC_RC2=$?
assert_eq "1" "$CN_RC_RC2" "對帳：空理由 .skip 視同未豁免，照樣 exit 1"
assert_contains "$CN_RC_OUT2" "理由為空" "空理由 .skip 訊息點名無效豁免"
assert_not_contains "$CN_RC_OUT2" "tierA-foo 缺" "已補 fixture 的 tierA-foo 不再被點名缺 fixture"

# 補上有效理由 → 該 gate 視為已豁免，對帳整體通過，回到正常三斷言流程
echo "尚未上線，人工核可暫緩" > "$CN_RC/canary.d/tierB-bar.skip"
CN_RC_OUT3="$(bash "$CANARY_ENGINE" --decl-dir "$CN_RC" 2>&1)"
CN_RC_RC3=$?
assert_eq "0" "$CN_RC_RC3" "對帳：tierA-foo 有 fixture、tierB-bar 有效 .skip → 對帳通過"
assert_contains "$CN_RC_OUT3" "已豁免" "有效 .skip 印豁免訊息"
assert_contains "$CN_RC_OUT3" "1/1 gate PASS" "對帳通過後照常跑三斷言（僅 tierA-foo 有 fixture 需測）"
rm -rf "$CN_RC"

# 綠：gates.d 整體不存在（專案未裝 wave-gate 模組）→ 對帳 SKIP 明示，不誤殺
CN_SKIP="$(mktemp -d)"
mkdir -p "$CN_SKIP/canary.d"
CN_SKIP_OUT="$(bash "$CANARY_ENGINE" --decl-dir "$CN_SKIP" 2>&1)"
assert_contains "$CN_SKIP_OUT" "SKIP(gates.d↔canary.d 對帳)" "gates.d 不存在時對帳 SKIP 明示"
assert_not_contains "$CN_SKIP_OUT" "對帳失敗" "gates.d 不存在不誤殺為對帳失敗"
rm -rf "$CN_SKIP"

# --- clean fixture 假通過母題：inspected:0 與缺 inspected 皆須 FAIL（防「clean 跑了
# 0 個檢查」與「真通過」不可區分）
CN_CLEAN0="$(mktemp -d)"
mkdir -p "$CN_CLEAN0/canary.d"
_cn_mkgate_in "$CN_CLEAN0" "clean-zero" 'if grep -q bad file.txt 2>/dev/null; then echo "inspected:1"; exit 1; fi; echo "inspected:0"; exit 0'
CN_CLEAN0_OUT="$(bash "$CANARY_ENGINE" --decl-dir "$CN_CLEAN0" 2>&1)"
CN_CLEAN0_RC=$?
assert_eq "1" "$CN_CLEAN0_RC" "clean fixture 輸出 inspected:0 → 引擎總結 exit 1"
assert_contains "$CN_CLEAN0_OUT" "clean inspected:0" "clean inspected:0 訊息點名"
assert_contains "$CN_CLEAN0_OUT" "clean 假通過母題" "clean 假通過母題標記"
rm -rf "$CN_CLEAN0"

CN_CLEANNA="$(mktemp -d)"
mkdir -p "$CN_CLEANNA/canary.d"
_cn_mkgate_in "$CN_CLEANNA" "clean-noinspect" 'if grep -q bad file.txt 2>/dev/null; then echo "inspected:1"; exit 1; fi; exit 0'
CN_CLEANNA_OUT="$(bash "$CANARY_ENGINE" --decl-dir "$CN_CLEANNA" 2>&1)"
CN_CLEANNA_RC=$?
assert_eq "1" "$CN_CLEANNA_RC" "clean fixture 完全無 inspected 輸出 → exit 1"
assert_contains "$CN_CLEANNA_OUT" "clean inspected:UNAVAILABLE" "clean 缺 inspected 訊息點名"
rm -rf "$CN_CLEANNA"

rm -rf "$CN_DECL" "$CN_EMPTY"
