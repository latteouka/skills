# hook-wiring-check.sh — gate 四場景驗證（吸收自 dfaa，K2）
#
# ①settings.json 引用不存在的 script → 紅＋點名 ②引用存在但無執行位 → 紅
# ③全部正常 → 綠＋inspected:N 精確值 ④零引用 → inspected:0 自身紅
# 另驗：jq 缺席明確報「jq 未裝」（不誤報成非法 JSON）、--repo-root 預設 git rev-parse。

HW_GATE="$KIT_ROOT/gates/hook-wiring-check.sh"

# --- ① settings.json 引用不存在的 script → 紅，點名 ---
HW_R1="$(mktemp -d)"
mkdir -p "$HW_R1/.claude"
printf '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/scripts/ghost.sh"}]}]}}\n' > "$HW_R1/.claude/settings.json"
HW_OUT1="$(bash "$HW_GATE" --repo-root "$HW_R1" 2>&1)"
HW_RC1=$?
assert_eq "1" "$HW_RC1" "①引用不存在 → exit 1"
assert_contains "$HW_OUT1" "ghost.sh" "①失聯 script 被點名"
assert_contains "$HW_OUT1" "檔案不存在" "①原因＝檔案不存在"

# --- ② 引用存在但無執行位 → 紅 ---
HW_R2="$(mktemp -d)"
mkdir -p "$HW_R2/.claude" "$HW_R2/scripts"
printf '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/scripts/noexec.sh"}]}]}}\n' > "$HW_R2/.claude/settings.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HW_R2/scripts/noexec.sh"
chmod -x "$HW_R2/scripts/noexec.sh"
HW_OUT2="$(bash "$HW_GATE" --repo-root "$HW_R2" 2>&1)"
HW_RC2=$?
assert_eq "1" "$HW_RC2" "②無執行位 → exit 1"
assert_contains "$HW_OUT2" "noexec.sh" "②無執行位 script 被點名"
assert_contains "$HW_OUT2" "存在但不可執行" "②原因＝存在但不可執行"

# --- ③ 全部正常 → 綠 + inspected:N 精確值 ---
# 引用面：settings 1 條 + .husky/pre-push 2 條（repo 根相對 ../../ 寫法、
# cd 基準寫法各一——驗 cd 目標自動發現取代上游 apps/web 硬編碼）→ inspected:3
HW_R3="$(mktemp -d)"
mkdir -p "$HW_R3/.claude" "$HW_R3/scripts" "$HW_R3/apps/web/scripts" "$HW_R3/.husky"
printf '{"hooks":{"PostToolUse":[{"matcher":"","hooks":[{"type":"command","command":"${CLAUDE_PROJECT_DIR}/scripts/a.sh"}]}]}}\n' > "$HW_R3/.claude/settings.json"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HW_R3/scripts/a.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HW_R3/scripts/b.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$HW_R3/apps/web/scripts/wb.sh"
chmod +x "$HW_R3/scripts/a.sh" "$HW_R3/scripts/b.sh" "$HW_R3/apps/web/scripts/wb.sh"
{
  printf '#!/bin/sh\n'
  printf 'cd apps/web\n'
  printf 'bash ../../scripts/b.sh\n'
  printf 'bash scripts/wb.sh\n'
} > "$HW_R3/.husky/pre-push"
HW_OUT3="$(bash "$HW_GATE" --repo-root "$HW_R3" 2>&1)"
HW_RC3=$?
assert_eq "0" "$HW_RC3" "③全部正常 → exit 0"
assert_contains "$HW_OUT3" "PASS inspected:3" "③inspected 精確＝3（settings 1 + husky 2）"

# ③b --repo-root 預設 seam：git repo 內不帶參數，git rev-parse 應得同結果
git -C "$HW_R3" init -q
HW_OUT3B="$( (cd "$HW_R3" && bash "$HW_GATE" 2>&1) )"
HW_RC3B=$?
assert_eq "0" "$HW_RC3B" "③b 預設 git rev-parse 定根 → exit 0"
assert_contains "$HW_OUT3B" "PASS inspected:3" "③b 預設定根 inspected 同值"

# --- ④ 零引用（空 settings.json + 無 .husky）→ inspected:0 自身紅 ---
HW_R4="$(mktemp -d)"
mkdir -p "$HW_R4/.claude"
printf '{}\n' > "$HW_R4/.claude/settings.json"
HW_OUT4="$(bash "$HW_GATE" --repo-root "$HW_R4" 2>&1)"
HW_RC4=$?
assert_eq "1" "$HW_RC4" "④零引用 → exit 1（自身紅）"
assert_contains "$HW_OUT4" "inspected:0" "④明確報 inspected:0"

# --- ⑤ jq 缺席 → 明確報「jq 未裝」，不誤報成非法 JSON ---
HW_NOJQ="$(mktemp -d)"
for HW_BIN in bash sh grep sed sort basename printf env; do
  HW_BINPATH="$(command -v "$HW_BIN" 2>/dev/null)" && ln -s "$HW_BINPATH" "$HW_NOJQ/$HW_BIN"
done
HW_OUT5="$(PATH="$HW_NOJQ" bash "$HW_GATE" --repo-root "$HW_R3" 2>&1)"
HW_RC5=$?
assert_eq "1" "$HW_RC5" "⑤jq 缺席 → exit 1"
assert_contains "$HW_OUT5" "jq 未裝" "⑤明確報 jq 未裝"
assert_not_contains "$HW_OUT5" "不是合法 JSON" "⑤不得誤報成非法 JSON"

rm -rf "$HW_R1" "$HW_R2" "$HW_R3" "$HW_R4" "$HW_NOJQ"
