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

# --- [NEW] kit_main_repo_root：非 worktree 路徑原樣回傳
assert_eq "/Users/x/projects/dfaa" "$(kit_main_repo_root "/Users/x/projects/dfaa")" \
    "非 worktree 路徑不截斷"

# --- [NEW] kit_main_repo_root：worktree 路徑截斷回主 checkout（用真實存在的
# 目錄當 main，確保「主 checkout 存在且是 git repo」的驗證會通過）
MAINROOT_SANDBOX="$(kit_test_sandbox)"
mkdir -p "$MAINROOT_SANDBOX/.claude/worktrees/wt-a"
assert_eq "$MAINROOT_SANDBOX" \
    "$(kit_main_repo_root "$MAINROOT_SANDBOX/.claude/worktrees/wt-a")" \
    "worktree 路徑截斷回主 checkout"

# --- [NEW] kit_main_repo_root：巢狀 worktree（路徑含兩層 .claude/worktrees/）
# 一律截到第一個（最外層）出現的位置，回真正的主 checkout
assert_eq "$MAINROOT_SANDBOX" \
    "$(kit_main_repo_root "$MAINROOT_SANDBOX/.claude/worktrees/wt-a/.claude/worktrees/wt-nested")" \
    "巢狀 worktree 截到第一個 .claude/worktrees/，回最外層主 checkout"

# --- [NEW] kit_main_repo_root：fail-open——算出的主 checkout 路徑不存在時，
# 回原路徑（目前所在的 worktree），不可回空字串
assert_eq "/no/such/main/.claude/worktrees/wt-a" \
    "$(kit_main_repo_root "/no/such/main/.claude/worktrees/wt-a")" \
    "主 checkout 不存在時 fail-open 回原路徑"

# --- [NEW] kit_main_repo_root：fail-open——算出的路徑存在但不是 git repo 時，
# 同樣回原路徑
NOTGIT_SANDBOX="$(mktemp -d)"
mkdir -p "$NOTGIT_SANDBOX/.claude/worktrees/wt-a"
assert_eq "$NOTGIT_SANDBOX/.claude/worktrees/wt-a" \
    "$(kit_main_repo_root "$NOTGIT_SANDBOX/.claude/worktrees/wt-a")" \
    "主 checkout 存在但非 git repo 時 fail-open 回原路徑"
rm -rf "$NOTGIT_SANDBOX"

rm -rf "$MAINROOT_SANDBOX"

# --- [K1] kit_decl_get：flat-key 宣告檔讀取（檔案路徑參數化版 kit_config_get）
DECL_SANDBOX="$(mktemp -d)"
cat > "$DECL_SANDBOX/kit.yaml" <<'EOF'
kit_root: "/Users/x/projects/skills/kit"
modules: "intake backlog rtm"   # 已安裝模組
baseline_file: quality-baseline.json
empty_field: ""
bare_empty:
EOF
assert_eq "/Users/x/projects/skills/kit" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" kit_root '')" "decl 引號值去引號"
assert_eq "intake backlog rtm" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" modules '')" "decl 引號值含空格＋行內註解不截斷"
assert_eq "quality-baseline.json" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" baseline_file '')" "decl 裸值"
assert_eq "DEF" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" not_there 'DEF')" "decl 缺 key 回 default"
assert_eq "" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" empty_field 'DEF')" "decl key 存在但空引號值→回空字串（欄位留空＝降級，不吃 default）"
assert_eq "" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" bare_empty 'DEF')" "decl key 存在但無值（key: 後空白）→回空字串（降級）"
assert_eq "DEF" "$(kit_decl_get "$DECL_SANDBOX/no-such-file.yaml" kit_root 'DEF')" "decl 缺檔 fail-open 回 default"

# --- [K1] kit_manifest_lookup：8 欄 TSV 欄 1 exact match
printf '# comment line\nengines/ratchet.sh\tdfaa:scripts/hooks/ratchet.sh\tc1260c839\tsha256:aa\tsha256:bb\t2026-07-30\tparameterized\tnote here\nlib/common.sh\tkit:original\t-\t-\tsha256:cc\t2026-07-30\tverbatim\t-\n' > "$DECL_SANDBOX/prov.tsv"
LOOKUP_HIT="$(kit_manifest_lookup "$DECL_SANDBOX/prov.tsv" "lib/common.sh")"
assert_eq "lib/common.sh" "$(printf '%s' "$LOOKUP_HIT" | cut -f1)" "manifest 命中取整行（驗欄1）"
assert_eq "kit:original" "$(printf '%s' "$LOOKUP_HIT" | cut -f2)" "manifest 命中取整行（驗欄2）"
assert_eq "" "$(kit_manifest_lookup "$DECL_SANDBOX/prov.tsv" "no/such/path.sh")" "manifest 未命中回空"
assert_eq "" "$(kit_manifest_lookup "$DECL_SANDBOX/absent.tsv" "lib/common.sh")" "manifest 缺檔 fail-open 回空"
# 欄 1 前綴相同的不可誤中（exact match，非 prefix match）
printf 'a/b.sh\tkit:original\t-\t-\tsha256:dd\t2026-07-30\tverbatim\t-\na/b.sh.bak\tkit:original\t-\t-\tsha256:ee\t2026-07-30\tverbatim\t-\n' > "$DECL_SANDBOX/prov2.tsv"
assert_eq "sha256:ee" "$(kit_manifest_lookup "$DECL_SANDBOX/prov2.tsv" "a/b.sh.bak" | cut -f5)" "manifest exact match 不受前綴相似行干擾"

# --- [K1] kit_marker_block：首插 → append 到檔尾
MB_FILE="$DECL_SANDBOX/pre-commit"
printf '#!/bin/sh\necho project-own-line\n' > "$MB_FILE"
kit_marker_block "$MB_FILE" "backlog" "bash /kit/gates/backlog-lint.sh"
assert_eq "1" "$(grep -c '^# >>> kit:backlog >>>$' "$MB_FILE")" "marker 首插：start 標記存在"
assert_eq "1" "$(grep -c 'backlog-lint.sh' "$MB_FILE")" "marker 首插：內容存在"
assert_eq "1" "$(grep -c 'project-own-line' "$MB_FILE")" "marker 首插：專案原有內容保留"

# --- [K1] kit_marker_block：更新冪等——同內容跑兩次，檔案不變
SNAP1="$(cat "$MB_FILE")"
kit_marker_block "$MB_FILE" "backlog" "bash /kit/gates/backlog-lint.sh"
assert_eq "$SNAP1" "$(cat "$MB_FILE")" "marker 同內容重跑冪等（檔案逐位元組相同）"

# --- [K1] kit_marker_block：更新換內容——區塊只有一份、內容是新的
kit_marker_block "$MB_FILE" "backlog" "bash /kit/gates/backlog-lint.sh --strict"
assert_eq "1" "$(grep -c '^# >>> kit:backlog >>>$' "$MB_FILE")" "marker 更新：區塊不重複"
assert_eq "1" "$(grep -c 'backlog-lint.sh --strict' "$MB_FILE")" "marker 更新：新內容生效"
assert_eq "0" "$(grep -c 'backlog-lint.sh$' "$MB_FILE")" "marker 更新：舊內容已被替換"

# --- [K1] kit_marker_block：雙模組共存互不 clobber
kit_marker_block "$MB_FILE" "rtm" "bash /kit/gates/require-requirements-sync.sh"
assert_eq "1" "$(grep -c '^# >>> kit:backlog >>>$' "$MB_FILE")" "雙模組：backlog 區塊仍在"
assert_eq "1" "$(grep -c '^# >>> kit:rtm >>>$' "$MB_FILE")" "雙模組：rtm 區塊新增"
kit_marker_block "$MB_FILE" "rtm" "updated-rtm-content"
assert_eq "1" "$(grep -c 'backlog-lint.sh --strict' "$MB_FILE")" "雙模組：更新 rtm 不動 backlog 內容"
assert_eq "1" "$(grep -c 'updated-rtm-content' "$MB_FILE")" "雙模組：rtm 更新生效"

# --- [K1] kit_marker_block：content 含 sed 替換特殊字元（/ & \）不變形
kit_marker_block "$MB_FILE" "special" 'path=/a/b && echo "x\\y" & wait'
assert_eq "1" "$(grep -cF 'path=/a/b && echo "x\\y" & wait' "$MB_FILE")" "特殊字元 / & 反斜線逐位元組原樣"

# --- [K1] kit_marker_block：多行 content
kit_marker_block "$MB_FILE" "multi" "$(printf 'line-one\nline-two')"
assert_eq "1" "$(grep -c '^line-one$' "$MB_FILE")" "多行 content：第一行"
assert_eq "1" "$(grep -c '^line-two$' "$MB_FILE")" "多行 content：第二行"

rm -rf "$DECL_SANDBOX"

rm -rf "$SANDBOX"
