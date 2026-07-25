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

rm -rf "$SANDBOX"
