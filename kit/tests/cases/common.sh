. "$KIT_ROOT/lib/common.sh"

# --- kit_decl_get：flat-key 宣告檔讀取
DECL_SANDBOX="$(mktemp -d)"
cat > "$DECL_SANDBOX/kit.yaml" <<'EOF'
kit_root: "/Users/x/projects/skills/kit"
modules: "intake backlog rtm"   # 已安裝模組
baseline_file: quality-baseline.json
stale_days: 60   # 行內註解（未加引號值）
plain_hash: foo#bar
empty_field: ""
bare_empty:
EOF
assert_eq "/Users/x/projects/skills/kit" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" kit_root '')" "decl 引號值去引號"
assert_eq "intake backlog rtm" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" modules '')" "decl 引號值含空格＋行內註解不截斷"
assert_eq "quality-baseline.json" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" baseline_file '')" "decl 裸值"
# 2026-07-25 行內註解 bug 的迴歸覆蓋（原以真實 template 為 fixture；template 已移除，語意內聯於此）
assert_eq "60" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" stale_days '999')" "decl 未加引號值去行內註解"
assert_eq "foo#bar" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" plain_hash '')" "decl 無前置空白的 # 是值的一部分（YAML 語意）"
assert_eq "DEF" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" not_there 'DEF')" "decl 缺 key 回 default"
assert_eq "" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" empty_field 'DEF')" "decl key 存在但空引號值→回空字串（欄位留空＝降級，不吃 default）"
assert_eq "" "$(kit_decl_get "$DECL_SANDBOX/kit.yaml" bare_empty 'DEF')" "decl key 存在但無值（key: 後空白）→回空字串（降級）"
assert_eq "DEF" "$(kit_decl_get "$DECL_SANDBOX/no-such-file.yaml" kit_root 'DEF')" "decl 缺檔 fail-open 回 default"
rm -rf "$DECL_SANDBOX"
