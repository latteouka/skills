# canary-harness.sh — harness 的 harness：用假 gate 驗三斷言邏輯本身（雙向）
#
# 四假 gate：①行為全對 → 引擎必 PASS（不該攔的必不攔）②放行 violation → 必抓
# ③inspected:0 → 必抓 ④誤攔 clean → 必抓。另驗 canary.d 缺失 exit 2、.fixture 還原。

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

rm -rf "$CN_DECL" "$CN_EMPTY"
