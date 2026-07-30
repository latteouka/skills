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
assert_eq "1" "$([ -d "$SANDBOX/.claude/dev/backlog" ] && echo 1 || echo 0)" "建立 backlog/ 目錄"
assert_eq "1" "$([ -f "$SANDBOX/.claude/dev/backlog/INDEX.md" ] && echo 1 || echo 0)" "建立 backlog/INDEX.md"
assert_eq "1" "$([ -f "$SANDBOX/.claude/dev/intake.config.yaml" ] && echo 1 || echo 0)" "建立 config"

BACKLOG_CONTENT="$(cat "$SANDBOX/.claude/dev/backlog/INDEX.md")"
assert_contains "$BACKLOG_CONTENT" '`touches`' "backlog INDEX 含 touches 欄說明"
assert_contains "$BACKLOG_CONTENT" 'unknown:' "backlog INDEX 示範未知 touches 標記"

S="$(cat "$SANDBOX/.claude/settings.json")"
assert_contains "$S" "existing.sh" "既有 hook 保留"
assert_contains "$S" "capture.sh" "裝上 capture hook"
assert_contains "$S" "summary.sh" "裝上 summary hook"
assert_contains "$S" "archive.sh" "裝上 archive hook"
assert_contains "$S" "no-midwave-questions.sh" "裝上 no-midwave-questions hook"
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
# 補充驗證：壞 JSON 時不應建立 .claude/dev/ 下的檔案
assert_eq "0" "$([ -f "$BAD/.claude/dev/inbox.md" ] && echo 1 || echo 0)" "壞 JSON 時不建 inbox.md"
assert_eq "0" "$([ -d "$BAD/.claude/dev/backlog" ] && echo 1 || echo 0)" "壞 JSON 時不建 backlog/ 目錄"
assert_eq "0" "$([ -f "$BAD/.claude/dev/intake.config.yaml" ] && echo 1 || echo 0)" "壞 JSON 時不建 config"
rm -rf "$BAD"

# --- 改名目錄情境下的冪等性：路徑改變不導致重複追加
RENAMED="$(kit_test_sandbox)"
mkdir -p "$RENAMED/.claude"
# 複製 KIT_ROOT 到不同名稱的目錄
TOOLBOX="${RENAMED}/toolbox"
cp -r "$KIT_ROOT" "$TOOLBOX"
chmod +x "$TOOLBOX/installers/intake.sh"

# 第一次安裝
(cd "$RENAMED" && bash "$TOOLBOX/installers/intake.sh" --non-interactive) >/dev/null 2>&1
before="$(grep -c 'capture.sh' "$RENAMED/.claude/settings.json")"

# 第二次安裝（冪等檢查）
(cd "$RENAMED" && bash "$TOOLBOX/installers/intake.sh" --non-interactive) >/dev/null 2>&1
after="$(grep -c 'capture.sh' "$RENAMED/.claude/settings.json")"
assert_eq "$before" "$after" "改名目錄後重跑不重複追加 hook"

rm -rf "$RENAMED"

# --- [NEW] .gitignore：安裝時補上 kit 執行期檔案的忽略規則
GI="$(kit_test_sandbox)"
(cd "$GI" && bash "$INST" --non-interactive) >/dev/null 2>&1
GI_CONTENT="$(cat "$GI/.gitignore" 2>/dev/null)"
assert_contains "$GI_CONTENT" ".claude/dev/.inbox.lock/" "gitignore 含 .inbox.lock/"
assert_contains "$GI_CONTENT" ".claude/dev/.readme-snapshot" "gitignore 含 .readme-snapshot"
assert_contains "$GI_CONTENT" ".claude/dev/README.md" "gitignore 含衍生 README.md（不進版控）"

# --- 冪等：重跑不重複追加同一行
gi_lines_before="$(grep -c '^\.claude/dev/README\.md$' "$GI/.gitignore")"
(cd "$GI" && bash "$INST" --non-interactive) >/dev/null 2>&1
gi_lines_after="$(grep -c '^\.claude/dev/README\.md$' "$GI/.gitignore")"
assert_eq "1" "$gi_lines_before" "首次安裝只寫一行 README.md 忽略規則"
assert_eq "$gi_lines_before" "$gi_lines_after" "重跑不重複追加 gitignore 行"
rm -rf "$GI"

# --- 既有 .gitignore 內容：只補缺的行，不動既有內容、不重複已存在的行
GI2="$(kit_test_sandbox)"
printf '# 既有註解\nnode_modules/\n.claude/dev/.inbox.lock/\n' > "$GI2/.gitignore"
(cd "$GI2" && bash "$INST" --non-interactive) >/dev/null 2>&1
GI2_CONTENT="$(cat "$GI2/.gitignore")"
assert_contains "$GI2_CONTENT" "node_modules/" "既有 .gitignore 內容保留"
assert_eq "1" "$(grep -c '^\.claude/dev/\.inbox\.lock/$' "$GI2/.gitignore")" "既有已存在的行不重複追加"
assert_contains "$GI2_CONTENT" ".claude/dev/README.md" "缺的行仍會補上"
rm -rf "$GI2"

rm -rf "$SANDBOX"
