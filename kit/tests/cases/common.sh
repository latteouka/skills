. "$KIT_ROOT/lib/common.sh"

SANDBOX="$(kit_test_sandbox)"

# --- kit_config_get：檔案不存在時回 default
assert_eq "20" "$(cd "$SANDBOX" && kit_config_get hot_zone_limit 20)" "config 缺檔回 default"

# --- kit_config_get：讀得到值
cat > "$SANDBOX/.claude/dev/intake.config.yaml" <<'EOF'
spec_layer: docs/rtm/matrix/
hot_zone_limit: 15
inbox_alert: 8
EOF
assert_eq "15" "$(cd "$SANDBOX" && kit_config_get hot_zone_limit 20)" "config 讀值"
assert_eq "docs/rtm/matrix/" "$(cd "$SANDBOX" && kit_config_get spec_layer '')" "config 讀路徑值"
assert_eq "" "$(cd "$SANDBOX" && kit_config_get not_there '')" "config 缺 key 回 default"

# --- kit_fm_get：解析 frontmatter
cat > "$SANDBOX/w.md" <<'EOF'
---
wave_id: map-v2
status: done
closed: 2026-07-16
---
# 內文
status: 這行在內文，不該被讀到
EOF
assert_eq "done" "$(kit_fm_get "$SANDBOX/w.md" status)" "frontmatter 讀 status"
assert_eq "map-v2" "$(kit_fm_get "$SANDBOX/w.md" wave_id)" "frontmatter 讀 wave_id"
assert_eq "" "$(kit_fm_get "$SANDBOX/w.md" nope)" "frontmatter 缺 key 回空"

# --- kit_fm_get：無 frontmatter 的檔案回空（不可誤讀內文）
printf '# 只有內文\nstatus: done\n' > "$SANDBOX/plain.md"
assert_eq "" "$(kit_fm_get "$SANDBOX/plain.md" status)" "無 frontmatter 不誤讀內文"

# --- kit_fm_get：有開頭 --- 但無結尾 --- 的畸形檔案回空（不可誤讀內文）
cat > "$SANDBOX/malformed.md" <<'EOF'
---
wave_id: test
status: active
# 內文開始（無結尾 ---）
status: done
closed: 2026-01-01
EOF
assert_eq "" "$(kit_fm_get "$SANDBOX/malformed.md" status)" "畸形 frontmatter（無結尾）不誤讀內文"
assert_eq "" "$(kit_fm_get "$SANDBOX/malformed.md" closed)" "畸形 frontmatter（無結尾）不誤讀 closed"

# --- kit_next_id：空檔從 001 起
: > "$SANDBOX/inbox.md"
assert_eq "INB-001" "$(kit_next_id "$SANDBOX/inbox.md" INB)" "空檔起始編號"

# --- kit_next_id：取最大值 +1（非行數，非最後一筆）
cat > "$SANDBOX/inbox.md" <<'EOF'
## INB-001
## INB-042
## INB-007
EOF
assert_eq "INB-043" "$(kit_next_id "$SANDBOX/inbox.md" INB)" "取最大編號 +1"

# --- kit_lock：取得後再取應失敗
LOCK="$SANDBOX/.t.lock"
kit_lock_acquire "$LOCK" 2 && r1=0 || r1=1
assert_eq "0" "$r1" "首次取鎖成功"
kit_lock_acquire "$LOCK" 2 && r2=0 || r2=1
assert_eq "1" "$r2" "重複取鎖逾時失敗"
kit_lock_release "$LOCK"
kit_lock_acquire "$LOCK" 2 && r3=0 || r3=1
assert_eq "0" "$r3" "釋放後可再取"
kit_lock_release "$LOCK"

rm -rf "$SANDBOX"
