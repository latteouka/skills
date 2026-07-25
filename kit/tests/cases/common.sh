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

# --- kit_config_get：真實 template（templates/intake.config.yaml，每行帶行內註解）
# 不可自己造一份乾淨版本當 fixture——這正是 2026-07-25 那次 bug 漏測的根因：
# 舊 fixture 是乾淨版，測不出行內註解會把整串（含註解）讀進來的問題。
cp "$KIT_ROOT/templates/intake.config.yaml" "$SANDBOX/.claude/dev/intake.config.yaml"
assert_eq "20" "$(cd "$SANDBOX" && kit_config_get hot_zone_limit 999)" "真實 template：hot_zone_limit 去除行內註解"
assert_eq "8" "$(cd "$SANDBOX" && kit_config_get inbox_alert 999)" "真實 template：inbox_alert 去除行內註解"
assert_eq "60" "$(cd "$SANDBOX" && kit_config_get stale_days 999)" "真實 template：stale_days 去除行內註解"
assert_eq "7" "$(cd "$SANDBOX" && kit_config_get archive_after_days 999)" "真實 template：archive_after_days 去除行內註解"
assert_eq ".claude/dev/archive" "$(cd "$SANDBOX" && kit_config_get archive_root '.claude/dev/archive')" "真實 template：archive_root 無註解正常讀值"
assert_eq "X" "$(cd "$SANDBOX" && kit_config_get spec_layer 'X')" "真實 template：spec_layer 空引號值去引號後為空,回 default（不可殘留字面 \"\"）"
assert_eq "X" "$(cd "$SANDBOX" && kit_config_get spec_check 'X')" "真實 template：spec_check 空引號值去引號後為空,回 default（不可殘留字面 \"\"）"

# --- kit_config_get：引號值（installer 填入後的狀態）不可被行內註解截斷，
# 引號內含空白的值（如指令字串）也不可被誤截。
cat > "$SANDBOX/.claude/dev/intake.config.yaml" <<'EOF'
spec_layer: "docs/rtm/matrix/"
spec_check: "pnpm tsx scripts/rtm-check.ts"   # 用來對帳 spec
EOF
assert_eq "docs/rtm/matrix/" "$(cd "$SANDBOX" && kit_config_get spec_layer '')" "引號值去引號"
assert_eq "pnpm tsx scripts/rtm-check.ts" "$(cd "$SANDBOX" && kit_config_get spec_check '')" "引號值含空格＋行內註解不被截斷"

# --- kit_fm_get：frontmatter 值同樣要能去行內註解與引號（同一套邏輯共用）
cat > "$SANDBOX/w-comment.md" <<'EOF'
---
wave_id: map-v2   # 內部代號
status: done
closed: "2026-07-16"
---
# 內文
EOF
assert_eq "map-v2" "$(kit_fm_get "$SANDBOX/w-comment.md" wave_id)" "frontmatter 行內註解不污染值"
assert_eq "2026-07-16" "$(kit_fm_get "$SANDBOX/w-comment.md" closed)" "frontmatter 引號值去引號"

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

# --- [NEW] C3 根因修正：只認 ^## 標題行，內文引用既有編號不污染計數
# （2026-07-25 修正前：grep -o 全檔掃描，raw 裡出現的「INB-042」會把
# 下一號劫持到 INB-043，即使真正最大的條目只有 INB-001）
cat > "$SANDBOX/inbox2.md" <<'EOF'
## INB-001
- when: 2026-07-25 12:00
- from: 口述
- raw: 這跟 INB-042 是同一個問題
EOF
assert_eq "INB-002" "$(kit_next_id "$SANDBOX/inbox2.md" INB)" "非標題行內的編號引用不影響計數"

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
