SANDBOX="$(kit_test_sandbox)"
HOOK="$KIT_ROOT/hooks/archive.sh"
DEV="$SANDBOX/.claude/dev"

git -C "$SANDBOX" config user.email t@t.t
git -C "$SANDBOX" config user.name t
cat > "$DEV/intake.config.yaml" <<'EOF'
archive_after_days: 7
archive_root: .claude/dev/archive
EOF

OLD="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
NEW="$(date '+%Y-%m-%d')"

# done 且逾期 → 應被歸檔
cat > "$DEV/wave-old.md" <<EOF
---
wave_id: old
status: done
closed: $OLD
---
# 舊波
做了地圖改版，改用 MapLibre。
EOF

# done 但未逾期 → 不動
cat > "$DEV/wave-fresh.md" <<EOF
---
wave_id: fresh
status: done
closed: $NEW
---
# 新完成的波
EOF

# active → 不動
cat > "$DEV/wave-active.md" <<EOF
---
wave_id: active
status: active
opened: $NEW
---
# 進行中
EOF

# 無 frontmatter 的舊檔 → 絕不自動動
printf '# 沒有 frontmatter 的舊檔\n' > "$DEV/wave-legacy.md"

git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1

printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1

MONTH="$(printf '%s' "$OLD" | cut -c1-7)"
assert_eq "1" "$([ -f "$DEV/archive/$MONTH/wave-old.md" ] && echo 1 || echo 0)" "逾期 done 已歸檔"
assert_eq "0" "$([ -f "$DEV/wave-old.md" ] && echo 1 || echo 0)" "原位置已移除"
assert_eq "1" "$([ -f "$DEV/wave-fresh.md" ] && echo 1 || echo 0)" "未逾期不動"
assert_eq "1" "$([ -f "$DEV/wave-active.md" ] && echo 1 || echo 0)" "active 不動"
assert_eq "1" "$([ -f "$DEV/wave-legacy.md" ] && echo 1 || echo 0)" "無 frontmatter 舊檔不動"
assert_contains "$(cat "$DEV/wave-INDEX.md")" "old" "INDEX 有該波記錄"
assert_contains "$(cat "$DEV/wave-INDEX.md")" "$MONTH" "INDEX 指向歸檔月份"

# --- 冪等：再跑一次不應重複寫 INDEX
lines1="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
printf '{"x":1}' | (cd "$SANDBOX" && bash "$HOOK") >/dev/null 2>&1
lines2="$(grep -c '| old |' "$DEV/wave-INDEX.md" 2>/dev/null || echo 0)"
assert_eq "$lines1" "$lines2" "重跑不重複寫 INDEX"

# --- Critical 1：畸形 frontmatter（有開頭無結尾）+ 內文含舊日期 → 不搬移
SANDBOX2="$(kit_test_sandbox)"
DEV2="$SANDBOX2/.claude/dev"
git -C "$SANDBOX2" config user.email t@t.t
git -C "$SANDBOX2" config user.name t
cat > "$DEV2/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

# 畸形檔案：開頭 --- 但無結尾，內文含「status: done / closed: 舊日期」
cat > "$DEV2/wave-malformed.md" <<EOF
---
wave_id: malformed
status: active
# 內文段落（無結尾 ---）
status: done
closed: 1999-01-01
EOF

git -C "$SANDBOX2" add -A >/dev/null 2>&1
git -C "$SANDBOX2" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX2" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV2/wave-malformed.md" ] && echo 1 || echo 0)" "畸形 frontmatter 不被搬移"
rm -rf "$SANDBOX2"

# --- Critical 2：closed 為路徑跳脫 → 不搬移
SANDBOX3="$(kit_test_sandbox)"
DEV3="$SANDBOX3/.claude/dev"
git -C "$SANDBOX3" config user.email t@t.t
git -C "$SANDBOX3" config user.name t
cat > "$DEV3/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

cat > "$DEV3/wave-path-escape.md" <<EOF
---
wave_id: escaped
status: done
closed: ../../dangerous
---
# 內文
EOF

git -C "$SANDBOX3" add -A >/dev/null 2>&1
git -C "$SANDBOX3" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX3" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV3/wave-path-escape.md" ] && echo 1 || echo 0)" "路徑跳脫不被搬移"
rm -rf "$SANDBOX3"

# --- Critical 2：closed 為非日期格式 → 不搬移
SANDBOX4="$(kit_test_sandbox)"
DEV4="$SANDBOX4/.claude/dev"
git -C "$SANDBOX4" config user.email t@t.t
git -C "$SANDBOX4" config user.name t
cat > "$DEV4/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

cat > "$DEV4/wave-baddate.md" <<EOF
---
wave_id: baddate
status: done
closed: not-a-date
---
# 內文
EOF

git -C "$SANDBOX4" add -A >/dev/null 2>&1
git -C "$SANDBOX4" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX4" && bash "$HOOK") >/dev/null 2>&1

assert_eq "1" "$([ -f "$DEV4/wave-baddate.md" ] && echo 1 || echo 0)" "非日期格式不被搬移"
rm -rf "$SANDBOX4"

# --- Important 2：archive_root 非預設值時的正確位置
SANDBOX5="$(kit_test_sandbox)"
DEV5="$SANDBOX5/.claude/dev"
git -C "$SANDBOX5" config user.email t@t.t
git -C "$SANDBOX5" config user.name t
cat > "$DEV5/intake.config.yaml" <<'EOF'
archive_after_days: 7
archive_root: custom/archive
EOF

OLD5="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
cat > "$DEV5/wave-custom.md" <<EOF
---
wave_id: custom
status: done
closed: $OLD5
---
# 自訂歸檔路徑測試
EOF

git -C "$SANDBOX5" add -A >/dev/null 2>&1
git -C "$SANDBOX5" commit -qm init >/dev/null 2>&1
printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX5" && bash "$HOOK") >/dev/null 2>&1

MONTH5="$(printf '%s' "$OLD5" | cut -c1-7)"
assert_eq "1" "$([ -f "$SANDBOX5/custom/archive/$MONTH5/wave-custom.md" ] && echo 1 || echo 0)" "非預設 archive_root 路徑正確"
rm -rf "$SANDBOX5"

# --- Important 1：並發情境下 INDEX 無重複行
SANDBOX6="$(kit_test_sandbox)"
DEV6="$SANDBOX6/.claude/dev"
git -C "$SANDBOX6" config user.email t@t.t
git -C "$SANDBOX6" config user.name t
cat > "$DEV6/intake.config.yaml" <<'EOF'
archive_after_days: 7
EOF

OLD6="$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d')"
for i in 1 2 3; do
  cat > "$DEV6/wave-concurrent-$i.md" <<EOF
---
wave_id: concurrent-$i
status: done
closed: $OLD6
---
# 並發測試 $i
EOF
done

git -C "$SANDBOX6" add -A >/dev/null 2>&1
git -C "$SANDBOX6" commit -qm init >/dev/null 2>&1

# 並發呼叫 5 次（模擬多 session）
for j in 1 2 3 4 5; do
  printf '{"hook_event_name":"Stop"}' | (cd "$SANDBOX6" && bash "$HOOK") >/dev/null 2>&1 &
done
wait

# 檢查 INDEX 中 concurrent-1 的行數（應只有 1 行，不重複）
concurrent_1_lines="$(grep -c '| concurrent-1 |' "$DEV6/wave-INDEX.md" 2>/dev/null || echo 0)"
assert_eq "1" "$concurrent_1_lines" "並發下 INDEX 無重複行"

rm -rf "$SANDBOX6"

rm -rf "$SANDBOX"
