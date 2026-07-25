SANDBOX="$(kit_test_sandbox)"
INST="$KIT_ROOT/installers/intake.sh"

# 既有 settings.json 含其他 hook，安裝後必須保留
mkdir -p "$SANDBOX/.claude"
cat > "$SANDBOX/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "existing.sh" } ] }
    ]
  }
}
EOF

(cd "$SANDBOX" && bash "$INST" --non-interactive) >/dev/null 2>&1

assert_eq "1" "$([ -f "$SANDBOX/.claude/dev/inbox.md" ] && echo 1 || echo 0)" "建立 inbox.md"
assert_eq "1" "$([ -f "$SANDBOX/.claude/dev/backlog.md" ] && echo 1 || echo 0)" "建立 backlog.md"
assert_eq "1" "$([ -f "$SANDBOX/.claude/dev/intake.config.yaml" ] && echo 1 || echo 0)" "建立 config"

S="$(cat "$SANDBOX/.claude/settings.json")"
assert_contains "$S" "existing.sh" "既有 hook 保留"
assert_contains "$S" "capture.sh" "裝上 capture hook"
assert_contains "$S" "summary.sh" "裝上 summary hook"
assert_contains "$S" "archive.sh" "裝上 archive hook"
assert_contains "$S" "compact" "SessionStart matcher 含 compact"

# --- 備份存在
assert_eq "1" "$(ls "$SANDBOX/.claude"/settings.json.bak-* >/dev/null 2>&1 && echo 1 || echo 0)" "寫入前備份"

# --- 冪等：重跑不重複追加
before="$(grep -c 'capture.sh' "$SANDBOX/.claude/settings.json")"
printf 'existing content\n' > "$SANDBOX/.claude/dev/inbox.md"
(cd "$SANDBOX" && bash "$INST" --non-interactive) >/dev/null 2>&1
after="$(grep -c 'capture.sh' "$SANDBOX/.claude/settings.json")"
assert_eq "$before" "$after" "重跑不重複追加 hook"
assert_eq "existing content" "$(cat "$SANDBOX/.claude/dev/inbox.md")" "重跑不覆寫既有 inbox"

# --- 壞 JSON：中止且不寫入
BAD="$(kit_test_sandbox)"
mkdir -p "$BAD/.claude"
printf '{ this is not json' > "$BAD/.claude/settings.json"
(cd "$BAD" && bash "$INST" --non-interactive) >/dev/null 2>&1 && rc=0 || rc=1
assert_eq "1" "$rc" "壞 JSON 中止安裝"
assert_eq "{ this is not json" "$(cat "$BAD/.claude/settings.json")" "壞 JSON 未被改動"
rm -rf "$BAD"

rm -rf "$SANDBOX"
