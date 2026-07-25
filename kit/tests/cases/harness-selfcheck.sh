# N2：tests/run.sh 的 assertion 總數下限守衛必須真的能抓到「測試檔被截斷」
# 這種失效模式（截斷後跑起來跟正常全部通過長得一模一樣：exit 0、0 failed）。
#
# 做法：複製一份獨立的 run.sh + 兩個假 case 檔到隔離的暫存目錄，先跑一次
# 建立 baseline，再把其中一個 case 檔清空模擬「被截斷」，驗證第二次跑
# 會被守衛攔下（exit 1 + FAIL 訊息），而不是靜默通過。

HARNESS_TMP="$(mktemp -d)"
mkdir -p "$HARNESS_TMP/tests/cases"
cp "$KIT_ROOT/tests/run.sh" "$HARNESS_TMP/tests/run.sh"

cat > "$HARNESS_TMP/tests/cases/a.sh" <<'EOF'
assert_eq "1" "1" "a1"
assert_eq "1" "1" "a2"
EOF

cat > "$HARNESS_TMP/tests/cases/b.sh" <<'EOF'
assert_eq "1" "1" "b1"
EOF

# 第一次跑：檔案都完整，建立 baseline（3 assertions），應正常通過
first_out="$(bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
first_rc=$?
assert_eq "0" "$first_rc" "harness 自檢：初次完整跑建立 baseline 應成功"
assert_contains "$first_out" "3 assertions" "harness 自檢：初次跑計數正確（3 個 assertion）"
assert_eq "3" "$(cat "$HARNESS_TMP/tests/assertion-baseline.txt" 2>/dev/null)" "harness 自檢：baseline 檔正確寫入"

# 模擬「測試檔被截斷」：b.sh 被清空（等同截斷成只剩空白）
: > "$HARNESS_TMP/tests/cases/b.sh"

second_out="$(bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
second_rc=$?
assert_eq "1" "$second_rc" "harness 自檢：assertion 數比 baseline 低必須 fail（截斷不能靜默通過）"
assert_contains "$second_out" "FAIL" "harness 自檢：輸出含 FAIL 訊息"
assert_contains "$second_out" "assertion 總數從" "harness 自檢：訊息說明是總數下降"

rm -rf "$HARNESS_TMP"
