# merge-train.sh — dfaa merge-train 六支 gate 的吸收驗證
#
# 核心主張：無 kit.yaml 宣告環境的預設態＝dfaa 現行為。
# ① 五支自帶 selftest（雙向：違規必攔、近似合法必放）——在「無 .claude/kit/
#    宣告」的 sandbox cwd 逐支跑，斷言輸出含 PASS 且無任何失敗訊號，
#    防「selftest 綠、真專案全紅」反轉。
# ② wave-merge-prep 無 selftest → 兩態 fixture：無宣告→SKIP 明示 exit 0；
#    有宣告→於 repo 根執行宣告指令；宣告指令失敗→exit 1。
# ③ base_branch 宣告消費驗證（wave-close-guard 代表——六支同一條
#    kit_decl_get 讀取線）：無宣告時 trunk 不是基底分支→放行；宣告
#    base_branch=trunk 後同一 repo 必攔——證明宣告是活的、預設是對的。

MT_DIR="$KIT_ROOT/gates/merge-train"

# ── ① 五支 selftest（無宣告環境：sandbox 無 .claude/kit/）──────────
MT_SANDBOX="$(kit_test_sandbox)"
git -C "$MT_SANDBOX" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m init

for mt_name in wave-regate-guard closure-lock-guard wave-closure-lock wave-close-guard backlog-writeback-guard; do
    MT_OUT="$(cd "$MT_SANDBOX" && bash "$MT_DIR/${mt_name}.sh" selftest 2>&1)"
    MT_RC=$?
    assert_eq "0" "$MT_RC" "${mt_name} selftest exit 0"
    assert_contains "$MT_OUT" "selftest: PASS" "${mt_name} selftest 輸出含 PASS"
    assert_not_contains "$MT_OUT" "selftest: FAIL" "${mt_name} selftest 無 FAIL"
    assert_not_contains "$MT_OUT" "✗" "${mt_name} selftest 無失敗斷言（✗）"
done

# ── ② wave-merge-prep 兩態 fixture ─────────────────────────────────
# ②a 無宣告 → SKIP 明示 exit 0（sandbox 此刻仍無 .claude/kit/）
MP_OUT="$(cd "$MT_SANDBOX" && bash "$MT_DIR/wave-merge-prep.sh" 2>&1)"
MP_RC=$?
assert_eq "0" "$MP_RC" "merge-prep 無宣告 exit 0"
assert_contains "$MP_OUT" "SKIP(無 merge_prep_cmd 宣告)" "merge-prep 無宣告明示 SKIP"

# ②b 有宣告 → 於 repo 根執行宣告指令（marker 檔落在 repo 根＝cwd 正確）
mkdir -p "$MT_SANDBOX/.claude/kit"
printf 'merge_prep_cmd: "echo MT-PREP-MARKER && touch mt-prep-ran.txt"\n' \
    > "$MT_SANDBOX/.claude/kit/kit.yaml"
MP_OUT2="$(cd "$MT_SANDBOX/.claude" && bash "$MT_DIR/wave-merge-prep.sh" 2>&1)"
MP_RC2=$?
assert_eq "0" "$MP_RC2" "merge-prep 有宣告且指令成功 exit 0"
assert_contains "$MP_OUT2" "MT-PREP-MARKER" "merge-prep 執行了宣告指令"
assert_contains "$MP_OUT2" "PASS" "merge-prep 成功輸出 PASS"
if [ -f "$MT_SANDBOX/mt-prep-ran.txt" ]; then
    assert_eq "yes" "yes" "merge-prep 宣告指令於 repo 根執行（子目錄呼叫仍落根）"
else
    assert_eq "repo 根有 mt-prep-ran.txt" "沒有" "merge-prep 宣告指令於 repo 根執行（子目錄呼叫仍落根）"
fi

# ②c 宣告指令失敗 → exit 1 + FAIL 訊息
printf 'merge_prep_cmd: "false"\n' > "$MT_SANDBOX/.claude/kit/kit.yaml"
MP_OUT3="$(cd "$MT_SANDBOX" && bash "$MT_DIR/wave-merge-prep.sh" 2>&1)"
MP_RC3=$?
assert_eq "1" "$MP_RC3" "merge-prep 宣告指令失敗 exit 1"
assert_contains "$MP_OUT3" "FAIL" "merge-prep 失敗輸出 FAIL"

# ── ③ base_branch 宣告消費驗證（wave-close-guard 代表六支讀取線）────
MT_BB="$(mktemp -d)"
git -C "$MT_BB" init -q -b trunk
git -C "$MT_BB" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m init
git -C "$MT_BB" update-ref refs/remotes/origin/trunk HEAD
git -C "$MT_BB" checkout -q -b worktree-wave-t
mkdir -p "$MT_BB/.claude/dev"
echo "# wave t" > "$MT_BB/.claude/dev/wave-t.md"
git -C "$MT_BB" add -A
git -C "$MT_BB" -c user.email=t@local -c user.name=t commit -q -m "wave t"
git -C "$MT_BB" checkout -q trunk
git -C "$MT_BB" -c user.email=t@local -c user.name=t \
    merge -q --no-ff worktree-wave-t -m "Merge worktree-wave-t — bb test"

(cd "$MT_BB" && bash "$MT_DIR/wave-close-guard.sh" check) >/dev/null 2>&1
assert_eq "0" "$?" "無宣告：trunk≠預設 main → 放行（預設態＝dfaa 現行為）"

mkdir -p "$MT_BB/.claude/kit"
printf 'base_branch: "trunk"\n' > "$MT_BB/.claude/kit/kit.yaml"
(cd "$MT_BB" && bash "$MT_DIR/wave-close-guard.sh" check) >/dev/null 2>&1
assert_eq "1" "$?" "宣告 base_branch=trunk：wave merge＋dashboard 殘留 → 必攔（宣告線活的）"

rm -rf "$MT_SANDBOX" "$MT_BB"
