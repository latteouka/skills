# backlog-tools.sh — kit/tools 五支（dfaa 吸收版）行為驗證
TOOLS="$KIT_ROOT/tools"

# 共用 fixture writer：合法 backlog 檔
_bt_write_item() {
    # $1=path $2=id $3=status $4=extra_fm(可空) $5=proof內容(可空)
    {
        printf -- '---\n'
        printf -- 'id: %s\n' "$2"
        printf -- 'type: BUG\n'
        printf -- 'pri: P2\n'
        printf -- 'flow: direct\n'
        printf -- 'status: "%s"\n' "$3"
        printf -- 'matrix: "—"\n'
        [ -n "$4" ] && printf -- '%s\n' "$4"
        printf -- 'created: 2026-07-30\n'
        printf -- '---\n\n'
        printf -- '# %s 測試項\n\n' "$2"
        printf -- '## evidence\n證據\n\n'
        printf -- '## proof\n'
        [ -n "$5" ] && printf -- '%s\n' "$5"
        printf -- '\n## notes\n'
    } > "$1"
}

# ── ① next-id：並發不同號 + --touch placeholder + B-099→B-100 進位 ──

NID="$(kit_test_sandbox)"
mkdir -p "$NID/.claude/dev/backlog"
bash "$TOOLS/next-id.sh" --repo-root "$NID" --touch B > "$NID/o1" 2>&1 &
_p1=$!
bash "$TOOLS/next-id.sh" --repo-root "$NID" --touch B > "$NID/o2" 2>&1 &
_p2=$!
wait "$_p1"
wait "$_p2"
ID1="$(cat "$NID/o1")"
ID2="$(cat "$NID/o2")"
assert_contains "$ID1" "B-0" "並發取號輸出 1 是 B-NNN（${ID1}）"
assert_contains "$ID2" "B-0" "並發取號輸出 2 是 B-NNN（${ID2}）"
assert_eq "1" "$([ "$ID1" != "$ID2" ] && echo 1 || echo 0)" "並發兩發取號不同號（${ID1} vs ${ID2}）"
assert_eq "1" "$([ -f "$NID/.claude/dev/backlog/${ID1}.md" ] && echo 1 || echo 0)" "--touch 建佔位檔 $ID1"
assert_contains "$(cat "$NID/.claude/dev/backlog/${ID1}.md")" 'status: "placeholder"' "佔位檔 status=placeholder"
rm -rf "$NID"

NID2="$(kit_test_sandbox)"
mkdir -p "$NID2/.claude/dev/backlog"
: > "$NID2/.claude/dev/backlog/B-099.md"
assert_eq "B-100" "$(bash "$TOOLS/next-id.sh" --repo-root "$NID2" B)" "B-099 → B-100 進位"
rm -rf "$NID2"

# ── ② backlog-lint：逐規則獨立 violation + clean + 編碼 + python3 缺席 ──

# clean 過
LC="$(kit_test_sandbox)"
mkdir -p "$LC/.claude/dev/backlog"
_bt_write_item "$LC/.claude/dev/backlog/B-001.md" "B-001" "ready" 'touches:
  - "src/a.ts"' ""
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LC" 2>&1)"
lint_rc=$?
assert_eq "0" "$lint_rc" "clean fixture lint exit 0"
assert_contains "$lint_out" "backlog-lint PASS" "clean fixture 印 PASS"
rm -rf "$LC"

# done 無 proof
LD="$(kit_test_sandbox)"
mkdir -p "$LD/.claude/dev/backlog"
_bt_write_item "$LD/.claude/dev/backlog/B-002.md" "B-002" "done:w1" "" ""
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LD" 2>&1)"
lint_rc=$?
assert_eq "1" "$lint_rc" "done 無 proof → exit 1"
assert_contains "$lint_out" "proof 區塊為空" "done 無 proof 報對規則"
rm -rf "$LD"

# 檢查 8（B-376）：ready＋非空 proof＝派發矛盾單 → 必擋；
# 反向（ready＋空骨架不擋）由上面 clean fixture 覆蓋（_bt_write_item proof 參數空
# ＝留空 ## proof 標題，lint 仍 PASS）
LP="$(kit_test_sandbox)"
mkdir -p "$LP/.claude/dev/backlog"
_bt_write_item "$LP/.claude/dev/backlog/B-003.md" "B-003" "ready" 'touches:
  - "src/a.ts"' "使用者裁定 drop（測試 fixture）。"
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LP" 2>&1)"
lint_rc=$?
assert_eq "1" "$lint_rc" "ready＋非空 proof → exit 1（檢查 8）"
assert_contains "$lint_out" "結項裁定沒同步翻 status" "檢查 8 報對規則"
rm -rf "$LP"

# id 與檔名不一致
LM="$(kit_test_sandbox)"
mkdir -p "$LM/.claude/dev/backlog"
_bt_write_item "$LM/.claude/dev/backlog/B-010.md" "B-011" "ready" 'touches:
  - "src/a.ts"' ""
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LM" 2>&1)"
lint_rc=$?
assert_eq "1" "$lint_rc" "id 檔名不一致 → exit 1"
assert_contains "$lint_out" "不一致" "id 檔名不一致報對規則"
rm -rf "$LM"

# 重複 id
LU="$(kit_test_sandbox)"
mkdir -p "$LU/.claude/dev/backlog"
_bt_write_item "$LU/.claude/dev/backlog/B-020.md" "B-020" "done:w1" "" "abc1234"
_bt_write_item "$LU/.claude/dev/backlog/B-021.md" "B-020" "done:w1" "" "abc1234"
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LU" 2>&1)"
lint_rc=$?
assert_eq "1" "$lint_rc" "重複 id → exit 1"
assert_contains "$lint_out" "重複" "重複 id 報對規則"
rm -rf "$LU"

# 多位元組截斷：UTF-8 中文中間截斷位元組必紅
LT="$(kit_test_sandbox)"
mkdir -p "$LT/.claude/dev/backlog"
_bt_write_item "$LT/.claude/dev/backlog/B-030.md" "B-030" "ready" 'touches:
  - "src/a.ts"' ""
printf '\xe4\xb8' >> "$LT/.claude/dev/backlog/B-030.md"   # 「中」的前 2/3 位元組
lint_out="$(bash "$TOOLS/backlog-lint.sh" --repo-root "$LT" 2>&1)"
lint_rc=$?
assert_eq "1" "$lint_rc" "多位元組截斷 → exit 1"
assert_contains "$lint_out" "含非法 UTF-8" "多位元組截斷報編碼規則"
rm -rf "$LT"

# python3 缺席（PATH 沙盒）→ 明確報錯，不誤報每檔非法 UTF-8
LP="$(kit_test_sandbox)"
mkdir -p "$LP/.claude/dev/backlog"
_BASH_BIN="$(command -v bash)"
lint_out="$(env PATH="/var/empty" "$_BASH_BIN" "$TOOLS/backlog-lint.sh" --repo-root "$LP" 2>&1)"
lint_rc=$?
assert_eq "1" "$([ "$lint_rc" -ne 0 ] && echo 1 || echo 0)" "python3 缺席 → exit 非 0"
assert_contains "$lint_out" "python3 未安裝" "python3 缺席明確報錯"
assert_not_contains "$lint_out" "含非法 UTF-8" "python3 缺席不誤報編碼錯誤"
rm -rf "$LP"

# ── ③ backlog-ls：--status ready 過濾 + --count + status prefix match ──

BL="$(kit_test_sandbox)"
mkdir -p "$BL/.claude/dev/backlog"
_bt_write_item "$BL/.claude/dev/backlog/B-001.md" "B-001" "ready" 'touches:
  - "src/a.ts"' ""
_bt_write_item "$BL/.claude/dev/backlog/B-002.md" "B-002" "done:w1" "" "abc1234"
_bt_write_item "$BL/.claude/dev/backlog/B-003.md" "B-003" "ready" 'touches:
  - "src/b.ts"' ""
ls_out="$(bash "$TOOLS/backlog-ls.sh" --repo-root "$BL" --status ready 2>&1)"
assert_contains "$ls_out" "B-001" "--status ready 含 B-001"
assert_contains "$ls_out" "B-003" "--status ready 含 B-003"
assert_not_contains "$ls_out" "B-002" "--status ready 不含 done 項"
assert_contains "$ls_out" "共 2 筆" "--status ready 計數 2"
assert_eq "2" "$(bash "$TOOLS/backlog-ls.sh" --repo-root "$BL" --status ready --count)" "--count 只輸出數字"
assert_eq "1" "$(bash "$TOOLS/backlog-ls.sh" --repo-root "$BL" --status done --count)" "status prefix match：done 涵蓋 done:w1"
rm -rf "$BL"

# ── ④ retention --dry-run 不動檔 ──

RT="$(kit_test_sandbox)"
mkdir -p "$RT/.claude/dev/backlog"
_bt_write_item "$RT/.claude/dev/backlog/B-001.md" "B-001" "done:w1" "closed: 2020-01-01" "abc1234"
_bt_write_item "$RT/.claude/dev/backlog/B-002.md" "B-002" "ready" 'touches:
  - "src/a.ts"' ""
# ready 的 created 改成過期日期（觸發 STALE 標記）
sed -i '' 's/^created: 2026-07-30$/created: 2020-01-01/' "$RT/.claude/dev/backlog/B-002.md"
sum_before="$(cksum "$RT/.claude/dev/backlog/B-001.md" "$RT/.claude/dev/backlog/B-002.md")"
rt_out="$(bash "$TOOLS/backlog-retention.sh" --repo-root "$RT" --dry-run 2>&1)"
rt_rc=$?
assert_eq "0" "$rt_rc" "retention --dry-run exit 0"
assert_contains "$rt_out" "B-001" "dry-run 列出過期清理候選 B-001"
assert_contains "$rt_out" "STALE: B-002" "dry-run 標記 stale ready 項"
assert_contains "$rt_out" "乾跑模式" "dry-run 明示不動手"
sum_after="$(cksum "$RT/.claude/dev/backlog/B-001.md" "$RT/.claude/dev/backlog/B-002.md")"
assert_eq "$sum_before" "$sum_after" "dry-run 不動檔（cksum 前後一致）"
rm -rf "$RT"

# ── ⑤ migrate --dry-run：NEL 轉換 + 0x85 continuation byte 中文不劈斷 ──

MG="$(kit_test_sandbox)"
_NEL="$(printf '\xc2\x85')"   # U+0085 NEL
# 「侅」U+4F85 = E4 BE 85——含 0x85 continuation byte 的迴歸錨字元
{
    printf -- '# Backlog\n\n'
    printf -- '| id | type | pri | flow | matrix | status | summary |\n'
    printf -- '|---|---|---|---|---|---|---|\n'
    printf -- '| B-001 | BUG | P2 | direct | — | ready | 測試項A |\n'
    printf -- '| B-002 | CHORE | P3 | direct | — | done:w1 | 侅字守恆測試 |\n'
    printf -- '\n## 明細區\n\n'
    printf -- '### B-001\n\n'
    printf -- '- **touches**: `src/a.ts`\n'
    printf -- '- **evidence**: 證據A\n'
    printf -- '\n### B-002\n\n'
    printf -- '- **proof**: abc1234\n'
    printf -- '- **evidence**: 前段%s後段含侅字\n' "$_NEL"
} > "$MG/.claude/dev/backlog.md"
mg_out="$(bash "$TOOLS/migrate-backlog-to-files.sh" --repo-root "$MG" --dry-run "$MG/outdry" 2>&1)"
mg_rc=$?
assert_eq "0" "$mg_rc" "migrate --dry-run 守恆對帳 exit 0"
assert_contains "$mg_out" "守恆對帳表" "migrate 輸出守恆對帳表"
assert_contains "$mg_out" "乾跑完成" "migrate 乾跑完成"
assert_eq "1" "$([ -f "$MG/outdry/B-001.md" ] && echo 1 || echo 0)" "產出 B-001.md"
assert_eq "1" "$([ -f "$MG/outdry/B-002.md" ] && echo 1 || echo 0)" "產出 B-002.md"
# 字元級截斷修正的迴歸錨：strict decode 過 + 侅 完整 + NEL 已轉換
assert_eq "0" "$(python3 -c 'import sys
open(sys.argv[1],"rb").read().decode("utf-8")' "$MG/outdry/B-002.md" 2>/dev/null; echo $?)" "B-002.md strict decode 過（中文未劈斷）"
assert_contains "$(cat "$MG/outdry/B-002.md")" "侅字守恆測試" "0x85 continuation byte 中文字完整保留"
assert_eq "0" "$(python3 -c 'import sys
d=open(sys.argv[1],"rb").read()
sys.exit(1 if b"\xc2\x85" in d else 0)' "$MG/outdry/B-002.md"; echo $?)" "NEL（C2 85）已轉換為 LF"
assert_contains "$(cat "$MG/outdry/B-002.md")" "closed: 2026-07-29" "closed fallback＝遷移日期常數（verbatim 保留）"
rm -rf "$MG"

unset -f _bt_write_item
