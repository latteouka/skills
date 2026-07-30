# kit-doctor.sh — 消費者宣告健檢（全 scratch 隔離，不碰真 kit 宣告）
#
# seam：--decl-dir（宣告 fixture）＋ --kit-root（scratch kit：templates 複本＋
# git repo 供 pin 驗證——pin 對的是 rev-parse HEAD，必須是可控的 scratch commit）。
# 紅 case 各一（合約 2/3）＋綠 case（合約 4）＋缺鍵不攔的反向對照。

DOCTOR="$KIT_ROOT/tools/kit-doctor.sh"

# --- scratch kit root：templates 複本 + git commit（pin 錨點）
KD_KIT="$(mktemp -d)"
mkdir -p "$KD_KIT/templates/gates.d/tierA.d" "$KD_KIT/templates/gates.d/tierB.d"
cp "$KIT_ROOT/templates/gates.d/tierA.d/10-example.sh" "$KD_KIT/templates/gates.d/tierA.d/"
cp "$KIT_ROOT/templates/gates.d/tierB.d/10-example.sh" "$KD_KIT/templates/gates.d/tierB.d/"
git -C "$KD_KIT" init -q
git -C "$KD_KIT" -c user.email=t@t -c user.name=t add -A
git -C "$KD_KIT" -c user.email=t@t -c user.name=t commit -qm v1
KD_HEAD_SHORT="$(git -C "$KD_KIT" rev-parse --short HEAD)"

_kd_mkdecl() { # 完整綠宣告：客製 stub + 對應 canary fixture + 必要欄位齊
    local d
    d="$(mktemp -d)"
    mkdir -p "$d/gates.d/tierA.d" "$d/canary.d/tierA-mygate"
    printf '#!/usr/bin/env bash\necho "custom project check"\necho "inspected:1"\nexit 0\n' \
        > "$d/gates.d/tierA.d/10-mygate.sh"
    cat > "$d/kit.yaml" <<'EOF'
contract_version: "1"
kit_pin: ""
modules: "ratchet rtm"
baseline_file: "quality-baseline.json"
matrix_dir: "docs/rtm/matrix"
EOF
    echo "$d"
}
_kd_run() { # decl_dir [extra flags…]
    local d="$1"; shift
    bash "$DOCTOR" --decl-dir "$d" --kit-root "$KD_KIT" "$@" 2>&1
}

# --- 綠 case：完整宣告 → exit 0＋inspected:N（N 精確值：cv1+pin1+stub1+canary1+對帳1+必要2=7）
KD1="$(_kd_mkdecl)"
KD1_OUT="$(_kd_run "$KD1")"
assert_eq "0" "$?" "綠 case exit 0"
assert_contains "$KD1_OUT" "inspected:7" "綠 case inspected 精確值 7"
assert_contains "$KD1_OUT" "FAIL 0" "綠 case 匯總 0 FAIL"
assert_contains "$KD1_OUT" "滾動模式" "綠 case pin 空值明示滾動"

# --- 紅 case 1：未知 contract_version
KD2="$(_kd_mkdecl)"
sed 's/^contract_version: "1"/contract_version: "99"/' "$KD2/kit.yaml" > "$KD2/kit.yaml.tmp"
mv "$KD2/kit.yaml.tmp" "$KD2/kit.yaml"
KD2_OUT="$(_kd_run "$KD2")"
KD2_RC=$?
assert_eq "1" "$KD2_RC" "紅1 未知 contract_version exit 1"
assert_contains "$KD2_OUT" "contract_version 不支援" "紅1 訊息指名 contract_version"
assert_contains "$KD2_OUT" "[99]" "紅1 訊息附宣告值"

# contract_version 缺席也必紅（缺鍵不吃 default 放行）
grep -v '^contract_version:' "$KD2/kit.yaml" > "$KD2/kit.yaml.tmp"
mv "$KD2/kit.yaml.tmp" "$KD2/kit.yaml"
KD2B_OUT="$(_kd_run "$KD2")"
KD2B_RC=$?
assert_eq "1" "$KD2B_RC" "紅1b contract_version 缺席 exit 1"
assert_contains "$KD2B_OUT" "contract_version 缺席" "紅1b 訊息指名缺席"

# --- 紅 case 2：恆綠 example gate（stub＝模板字面複本；補 canary fixture 隔離對帳因素）
KD3="$(_kd_mkdecl)"
cp "$KD_KIT/templates/gates.d/tierA.d/10-example.sh" "$KD3/gates.d/tierA.d/10-example.sh"
mkdir -p "$KD3/canary.d/tierA-example"
KD3_OUT="$(_kd_run "$KD3")"
KD3_RC=$?
assert_eq "1" "$KD3_RC" "紅2 恆綠 example gate exit 1"
assert_contains "$KD3_OUT" "恆綠 example gate 未客製" "紅2 訊息指名未客製"
assert_contains "$KD3_OUT" "tierA.d/10-example.sh" "紅2 點名 stub 檔"
assert_contains "$KD3_OUT" "gate stub 已客製：tierA.d/10-mygate.sh" "紅2 客製 stub 不被誤殺（雙向）"

# --- 紅 case 3：空 canary.d（gates.d 拿掉隔離對帳因素——SKIP 不誤殺）
KD4="$(_kd_mkdecl)"
rm -rf "$KD4/gates.d" "$KD4/canary.d/tierA-mygate"
KD4_OUT="$(_kd_run "$KD4")"
KD4_RC=$?
assert_eq "1" "$KD4_RC" "紅3 空 canary.d exit 1"
assert_contains "$KD4_OUT" "0 個 gate fixture" "紅3 訊息指名 0 fixture"
assert_contains "$KD4_OUT" "SKIP(恆綠 example gate)" "紅3 gates.d 缺席 example 檢查 SKIP 明示"

# --- 紅 case 4：gate↔fixture 不對帳（孤兒 stub 無 fixture 無豁免）
KD5="$(_kd_mkdecl)"
printf '#!/usr/bin/env bash\necho "another custom check"\necho "inspected:1"\nexit 0\n' \
    > "$KD5/gates.d/tierA.d/20-orphan.sh"
KD5_OUT="$(_kd_run "$KD5")"
KD5_RC=$?
assert_eq "1" "$KD5_RC" "紅4 對帳失敗 exit 1"
assert_contains "$KD5_OUT" "對帳失敗" "紅4 訊息指名對帳"
assert_contains "$KD5_OUT" "tierA-orphan" "紅4 點名缺 fixture 的 gate"

# 有效 .skip 豁免 → 回綠（對帳重用 canary_reconcile_gates 的豁免契約）
printf 'fixture 建構需 K6 真環境\n' > "$KD5/canary.d/tierA-orphan.skip"
KD5B_OUT="$(_kd_run "$KD5")"
assert_eq "0" "$?" "紅4b .skip 有效豁免後 exit 0"

# --- 紅 case 5：必要欄位空降級（ratchet 消費者 baseline_file 空值）
KD6="$(_kd_mkdecl)"
sed 's/^baseline_file: .*/baseline_file: ""/' "$KD6/kit.yaml" > "$KD6/kit.yaml.tmp"
mv "$KD6/kit.yaml.tmp" "$KD6/kit.yaml"
KD6_OUT="$(_kd_run "$KD6")"
KD6_RC=$?
assert_eq "1" "$KD6_RC" "紅5 必要欄位空值 exit 1"
assert_contains "$KD6_OUT" "必要欄位空降級：baseline_file" "紅5 訊息指名 baseline_file"

# 缺鍵＝引擎預設 → 不攔（兩態語意反向對照）
grep -v '^baseline_file:' "$KD6/kit.yaml" > "$KD6/kit.yaml.tmp"
mv "$KD6/kit.yaml.tmp" "$KD6/kit.yaml"
KD6B_OUT="$(_kd_run "$KD6")"
assert_eq "0" "$?" "紅5b 缺鍵（引擎預設）exit 0 不攔"
assert_contains "$KD6B_OUT" "缺鍵＝引擎預設" "紅5b 明示缺鍵語意"

# 未宣告 ratchet/rtm 模組 → 必要欄位檢查不跑（inspected 少 2）
KD6C="$(_kd_mkdecl)"
sed 's/^modules: .*/modules: "intake"/' "$KD6C/kit.yaml" > "$KD6C/kit.yaml.tmp"
mv "$KD6C/kit.yaml.tmp" "$KD6C/kit.yaml"
KD6C_OUT="$(_kd_run "$KD6C")"
assert_eq "0" "$?" "未裝 ratchet/rtm 模組 exit 0"
assert_contains "$KD6C_OUT" "inspected:5" "必要欄位檢查依 modules 判定（7-2=5）"

# --- 合約 3：kit_pin——預設 WARN 綠 case／--strict-pin FAIL 紅 case／pin 相符綠
KD7="$(_kd_mkdecl)"
sed 's/^kit_pin: ""/kit_pin: "0000000"/' "$KD7/kit.yaml" > "$KD7/kit.yaml.tmp"
mv "$KD7/kit.yaml.tmp" "$KD7/kit.yaml"
KD7_OUT="$(_kd_run "$KD7")"
KD7_RC=$?
assert_eq "0" "$KD7_RC" "pin 不符預設 WARN——exit 0"
assert_contains "$KD7_OUT" "⚠ kit_pin 不符" "pin 不符預設輸出警告行"
assert_contains "$KD7_OUT" "WARN 1" "pin 不符匯總計 1 WARN"

KD7S_OUT="$(_kd_run "$KD7" --strict-pin)"
KD7S_RC=$?
assert_eq "1" "$KD7S_RC" "pin 不符 --strict-pin exit 1"
assert_contains "$KD7S_OUT" "kit_pin 不符（--strict-pin）" "strict-pin 訊息指名"

sed "s/^kit_pin: \"0000000\"/kit_pin: \"${KD_HEAD_SHORT}\"/" "$KD7/kit.yaml" > "$KD7/kit.yaml.tmp"
mv "$KD7/kit.yaml.tmp" "$KD7/kit.yaml"
KD7G_OUT="$(_kd_run "$KD7" --strict-pin)"
assert_eq "0" "$?" "pin 相符（短 hash）--strict-pin exit 0"
assert_contains "$KD7G_OUT" "當前 kit HEAD" "pin 相符明示比對結果"

# --- K5.5 sharp-edges 修：pin 最小長度（<7 hex＝無效宣告 FAIL，防 1 字元前綴矇中）
KD_HEAD_C1="$(printf '%s' "${KD_HEAD_SHORT}" | cut -c1)"
sed "s/^kit_pin: \".*\"/kit_pin: \"${KD_HEAD_C1}\"/" "$KD7/kit.yaml" > "$KD7/kit.yaml.tmp"
mv "$KD7/kit.yaml.tmp" "$KD7/kit.yaml"
KD8_OUT="$(_kd_run "$KD7")"
KD8_RC=$?
assert_eq "1" "$KD8_RC" "1 字元 pin（即使是 HEAD 首字）＝無效宣告 exit 1"
assert_contains "$KD8_OUT" "kit_pin 無效" "短 pin 訊息指名無效"

# --- K5.5 sharp-edges 修：tier 模板目錄零 *.sh＝無法驗證 FAIL（防比對空轉靜默通過）
sed "s/^kit_pin: \".*\"/kit_pin: \"\"/" "$KD7/kit.yaml" > "$KD7/kit.yaml.tmp"
mv "$KD7/kit.yaml.tmp" "$KD7/kit.yaml"
rm -f "$KD_KIT/templates/gates.d/tierA.d"/*.sh
KD9_OUT="$(_kd_run "$KD7")"
KD9_RC=$?
assert_eq "1" "$KD9_RC" "模板目錄零 *.sh → exit 1（不得靜默報已客製）"
assert_contains "$KD9_OUT" "模板目錄零 *.sh" "零模板訊息指名"

rm -rf "$KD_KIT" "$KD1" "$KD2" "$KD3" "$KD4" "$KD5" "$KD6" "$KD6C" "$KD7"
