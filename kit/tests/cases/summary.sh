SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/summary.sh"
DEV="$SANDBOX/.claude/dev"

cat > "$DEV/intake.config.yaml" <<'EOF'
inbox_alert: 3
hot_zone_limit: 5
stale_days: 60
EOF
: > "$DEV/inbox.md"
: > "$DEV/backlog.md"

run_summary() { printf '{"hook_event_name":"SessionStart"}' | (cd "$SANDBOX" && bash "$HOOK"); }

# --- 全部乾淨：靜默
assert_eq "" "$(run_summary)" "無積壓時靜默"

# --- inbox 未達門檻：仍靜默
printf '## INB-001\n## INB-002\n' > "$DEV/inbox.md"
assert_eq "" "$(run_summary)" "未達 inbox_alert 靜默"

# --- inbox 達門檻：印一行
printf '## INB-001\n## INB-002\n## INB-003\n' > "$DEV/inbox.md"
out="$(run_summary)"
assert_contains "$out" "3" "報出未整理筆數"
assert_contains "$out" "收件匣" "訊息含收件匣字樣"

# --- 熱區超標
: > "$DEV/inbox.md"
for i in 1 2 3 4 5 6; do printf '# w\n' > "$DEV/wave-$i.md"; done
out="$(run_summary)"
assert_contains "$out" "熱區" "熱區超標有提示"

# --- 輸出恆為單行（噪音紀律）
lines="$(run_summary | wc -l | tr -d ' ')"
assert_eq "1" "$lines" "輸出恆為一行"

# --- fail-open：config 壞掉不報錯
printf 'this is not: valid: yaml: [\n' > "$DEV/intake.config.yaml"
printf '{"x":1}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1
assert_eq "0" "$?" "config 壞掉仍 exit 0"

rm -rf "$SANDBOX"
