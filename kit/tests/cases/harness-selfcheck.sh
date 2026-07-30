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

# 第零次跑：無 UPDATE_BASELINE → 不得自動寫 baseline 檔（預設唯讀，
# 防止跑一次測試就靜默自改寫守衛門檻）
zero_out="$(UPDATE_BASELINE=0 bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
zero_rc=$?
assert_eq "0" "$zero_rc" "harness 自檢：無旗標完整跑應成功"
assert_eq "no" "$([ -f "$HARNESS_TMP/tests/assertion-baseline.txt" ] && echo yes || echo no)" "harness 自檢：無 UPDATE_BASELINE 不寫 baseline 檔"

# 第一次跑：UPDATE_BASELINE=1 明示建立 baseline（3 assertions），應正常通過
first_out="$(UPDATE_BASELINE=1 bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
first_rc=$?
assert_eq "0" "$first_rc" "harness 自檢：UPDATE_BASELINE=1 完整跑建立 baseline 應成功"
assert_contains "$first_out" "3 assertions" "harness 自檢：初次跑計數正確（3 個 assertion）"
assert_eq "3" "$(cat "$HARNESS_TMP/tests/assertion-baseline.txt" 2>/dev/null)" "harness 自檢：baseline 檔正確寫入"

# 無旗標重跑：baseline 檔內容必須原封不動（即使總數相同也不重寫）
noflag_out="$(UPDATE_BASELINE=0 bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
noflag_rc=$?
assert_eq "0" "$noflag_rc" "harness 自檢：建立 baseline 後無旗標重跑應成功"
assert_eq "3" "$(cat "$HARNESS_TMP/tests/assertion-baseline.txt" 2>/dev/null)" "harness 自檢：無旗標重跑 baseline 不變"

# 模擬「測試檔被截斷」：b.sh 被清空（等同截斷成只剩空白）
: > "$HARNESS_TMP/tests/cases/b.sh"

second_out="$(UPDATE_BASELINE=0 bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
second_rc=$?
assert_eq "1" "$second_rc" "harness 自檢：assertion 數比 baseline 低必須 fail（截斷不能靜默通過）"
assert_contains "$second_out" "FAIL" "harness 自檢：輸出含 FAIL 訊息"
assert_contains "$second_out" "assertion 總數從" "harness 自檢：訊息說明是總數下降"

# case 中途 exit：子 shell 提早終止必須記 FAIL 並點名（不得靜默吞掉該 case
# 其餘斷言——exit 後的斷言全沒跑，跟被截斷是同一種失效）
cat > "$HARNESS_TMP/tests/cases/c.sh" <<'EOF'
assert_eq "1" "1" "c1"
exit 0
assert_eq "1" "1" "c2-never-runs"
EOF
exit_out="$(UPDATE_BASELINE=0 bash "$HARNESS_TMP/tests/run.sh" 2>&1)"
exit_rc=$?
assert_eq "1" "$exit_rc" "harness 自檢：case 中途 exit 整套必 fail"
assert_contains "$exit_out" "提早終止" "harness 自檢：輸出點名子 shell 提早終止"
assert_contains "$exit_out" "c.sh" "harness 自檢：訊息點名肇事 case 檔"

rm -rf "$HARNESS_TMP"
