export KIT_INIT_ALLOW_WORKTREE=1  # 測試在 worktree 跑，豁免 H2 安裝守衛（守衛本身另有專測）
# installer-backlog.sh — modules/backlog.sh 冪等 + husky marker + triage-rules 斷鏈修驗證
MOD="$KIT_ROOT/installers/modules/backlog.sh"

IB="$(kit_test_sandbox)"
# 既有 pre-commit 內容必須保留
mkdir -p "$IB/.husky"
printf '#!/usr/bin/env sh\necho existing-hook\n' > "$IB/.husky/pre-commit"

ib_out1="$( (cd "$IB" && bash "$MOD") 2>&1 )"
ib_rc1=$?
assert_eq "0" "$ib_rc1" "backlog 模組首跑 exit 0"
assert_eq "1" "$([ -d "$IB/.claude/dev/backlog" ] && echo 1 || echo 0)" "建立 backlog/ 目錄"
assert_eq "1" "$([ -f "$IB/.claude/dev/backlog/INDEX.md" ] && echo 1 || echo 0)" "建立 backlog/INDEX.md"
PC="$(cat "$IB/.husky/pre-commit")"
assert_contains "$PC" "echo existing-hook" "既有 pre-commit 內容保留"
assert_contains "$PC" ">>> kit:backlog >>>" "pre-commit 插入 kit:backlog marker 段"
assert_contains "$PC" "backlog-lint.sh" "marker 段掛 backlog-lint"
assert_contains "$ib_out1" "新建" "首跑回報新建項"

# --- 冪等：跑兩次第二次全 skip、diff 零
sum1="$(cksum "$IB/.husky/pre-commit" "$IB/.claude/dev/backlog/INDEX.md")"
ib_out2="$( (cd "$IB" && bash "$MOD") 2>&1 )"
ib_rc2=$?
assert_eq "0" "$ib_rc2" "backlog 模組重跑 exit 0"
assert_contains "$ib_out2" "跳過" "重跑回報跳過"
assert_not_contains "$ib_out2" "新建" "重跑無任何新建（全 skip）"
sum2="$(cksum "$IB/.husky/pre-commit" "$IB/.claude/dev/backlog/INDEX.md")"
assert_eq "$sum1" "$sum2" "重跑 diff 零（cksum 前後一致）"

# --- husky marker 兩次不重複
assert_eq "1" "$(grep -c '>>> kit:backlog >>>' "$IB/.husky/pre-commit")" "marker 起始行只出現一次"
assert_eq "1" "$(grep -c '<<< kit:backlog <<<' "$IB/.husky/pre-commit")" "marker 結尾行只出現一次"
rm -rf "$IB"

# --- triage-rules 斷鏈修：引用 kit tools 路徑且目標實存
TR="$(cat "$KIT_ROOT/references/triage-rules.md")"
assert_contains "$TR" '~/projects/skills/kit/tools/next-id.sh' "triage-rules 引用 kit tools 取號器"
assert_not_contains "$TR" 'scripts/next-id.sh' "scripts/next-id.sh 斷鏈引用無殘留"
assert_eq "1" "$([ -f "$KIT_ROOT/tools/next-id.sh" ] && echo 1 || echo 0)" "引用目標 next-id.sh 實存（KIT_ROOT 等價路徑）"
assert_eq "1" "$([ -x "$KIT_ROOT/tools/next-id.sh" ] && echo 1 || echo 0)" "next-id.sh 可執行"
