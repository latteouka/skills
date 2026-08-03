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
printf '%s\n' 'merge_prep_cmd: "test x${CI:-} = xtrue && echo MT-PREP-MARKER-CI-TRUE && touch mt-prep-ran.txt"' \
    > "$MT_SANDBOX/.claude/kit/kit.yaml"
MP_OUT2="$(cd "$MT_SANDBOX/.claude" && bash "$MT_DIR/wave-merge-prep.sh" 2>&1)"
MP_RC2=$?
assert_eq "0" "$MP_RC2" "merge-prep 有宣告且指令成功 exit 0"
assert_contains "$MP_OUT2" "MT-PREP-MARKER" "merge-prep 執行了宣告指令"
assert_contains "$MP_OUT2" "PASS" "merge-prep 成功輸出 PASS"
assert_contains "$MP_OUT2" "CI-TRUE" "merge-prep 非 TTY 時注入 CI=true"
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

# ── ④ wave_branch_patterns 宣告消費驗證（K55 task-9）───────────────
# 盤點結果：merge-train 六支中三支寫死 worktree-/wave/ 判別——
# wave-regate-guard（merge subject 交替比對）、wave-close-guard（id 抽取）、
# closure-lock-guard（branch glob 餵 for-each-ref）。三支改讀宣告
# `wave_branch_patterns`，缺鍵時各自套用各自的歷史預設值（逐位元組＝現行
# 為）。本節驗證：④a-e 紅→綠切換＋空值降級（wave-regate-guard 代表）；
# ④f-g id 抽取線活的（wave-close-guard）；④h-j branch glob 線活的＋空值
# 降級（closure-lock-guard）。

# ④a-e：未宣告時 feature/x 不被視為 wave merge；宣告 "feature/*" 後被
# 辨識；宣告空值後判別停用（即使有 feature/x merge 也放行，且明示降級）。
MT_WBP="$(mktemp -d)"
git -C "$MT_WBP" init -q -b main
git -C "$MT_WBP" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m init
git -C "$MT_WBP" update-ref refs/remotes/origin/main HEAD

git -C "$MT_WBP" checkout -q -b feature/x
git -C "$MT_WBP" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m "feature work"
git -C "$MT_WBP" checkout -q main
git -C "$MT_WBP" -c user.email=t@local -c user.name=t \
    merge -q --no-ff feature/x -m "Merge branch 'feature/x'"

(cd "$MT_WBP" && bash "$MT_DIR/wave-regate-guard.sh" check) >/dev/null 2>&1
assert_eq "0" "$?" "④a 未宣告 wave_branch_patterns：feature/x merge 不被視為 wave merge（現行為）→ 放行"

mkdir -p "$MT_WBP/.claude/kit"
printf 'wave_branch_patterns: "feature/*"\n' > "$MT_WBP/.claude/kit/kit.yaml"
WBP_OUT="$(cd "$MT_WBP" && bash "$MT_DIR/wave-regate-guard.sh" check 2>&1)"
WBP_RC=$?
assert_eq "1" "$WBP_RC" "④b 宣告 wave_branch_patterns=feature/*：同一 feature/x merge 被辨識為 wave merge → 必攔（新行為）"
assert_contains "$WBP_OUT" "BLOCK" "④c 宣告後輸出含 BLOCK"

printf 'wave_branch_patterns: ""\n' > "$MT_WBP/.claude/kit/kit.yaml"
WBP_OUT2="$(cd "$MT_WBP" && bash "$MT_DIR/wave-regate-guard.sh" check 2>&1)"
WBP_RC2=$?
assert_eq "0" "$WBP_RC2" "④d 宣告 wave_branch_patterns 空值：判別停用 → 放行（即使有 feature/x merge）"
assert_contains "$WBP_OUT2" "已停用" "④e 空值降級輸出明示已停用"

rm -rf "$MT_WBP"

# ④f-g：wave-close-guard 用自訂 pattern 抽出 wave id，對應 dashboard 判定
MT_WCG="$(mktemp -d)"
git -C "$MT_WCG" init -q -b main
mkdir -p "$MT_WCG/.claude/dev" "$MT_WCG/.claude/kit"
printf 'wave_branch_patterns: "feature/*"\n' > "$MT_WCG/.claude/kit/kit.yaml"
git -C "$MT_WCG" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m init
git -C "$MT_WCG" update-ref refs/remotes/origin/main HEAD

git -C "$MT_WCG" checkout -q -b feature/zeta
echo "# wave zeta" > "$MT_WCG/.claude/dev/wave-zeta.md"
git -C "$MT_WCG" add -A
git -C "$MT_WCG" -c user.email=t@local -c user.name=t \
    commit -q -m "feature zeta work + dashboard"
git -C "$MT_WCG" checkout -q main
git -C "$MT_WCG" -c user.email=t@local -c user.name=t \
    merge -q --no-ff feature/zeta -m "Merge branch 'feature/zeta'"

(cd "$MT_WCG" && bash "$MT_DIR/wave-close-guard.sh" check) >/dev/null 2>&1
assert_eq "1" "$?" "④f 宣告 feature/*：feature/zeta merge＋dashboard 殘留 → 必攔（id 抽取線活的）"

git -C "$MT_WCG" rm -q .claude/dev/wave-zeta.md
git -C "$MT_WCG" -c user.email=t@local -c user.name=t commit -q -m "wave-close 清理"
(cd "$MT_WCG" && bash "$MT_DIR/wave-close-guard.sh" check) >/dev/null 2>&1
assert_eq "0" "$?" "④g dashboard 已清 → 放行"

rm -rf "$MT_WCG"

# ④h-j：closure-lock-guard 用自訂 pattern 要求先取鎖；宣告空值降級
MT_CLG="$(mktemp -d)"
git -C "$MT_CLG" init -q -b main
git -C "$MT_CLG" -c user.email=t@local -c user.name=t \
    commit --allow-empty -q -m init
mkdir -p "$MT_CLG/.claude/kit"
printf 'wave_branch_patterns: "feature/*"\n' > "$MT_CLG/.claude/kit/kit.yaml"

git -C "$MT_CLG" checkout -q -b feature/omega
echo "code" > "$MT_CLG/omega.ts"
git -C "$MT_CLG" add omega.ts
git -C "$MT_CLG" -c user.email=t@local -c user.name=t commit -q -m "feat: omega"
MT_OMEGA_TIP="$(git -C "$MT_CLG" rev-parse HEAD)"
git -C "$MT_CLG" checkout -q main

echo "${MT_OMEGA_TIP}" > "$MT_CLG/.git/MERGE_HEAD"
echo "merged" > "$MT_CLG/omega.ts"
git -C "$MT_CLG" add omega.ts
(cd "$MT_CLG" && bash "$MT_DIR/closure-lock-guard.sh") >/dev/null 2>&1
assert_eq "2" "$?" "④h 宣告 feature/*：merge feature branch 無鎖 → 擋（branch glob 判別線活的）"
rm -f "$MT_CLG/.git/MERGE_HEAD"
git -C "$MT_CLG" reset -q HEAD -- omega.ts
rm -f "$MT_CLG/omega.ts"

printf 'wave_branch_patterns: ""\n' > "$MT_CLG/.claude/kit/kit.yaml"
echo "${MT_OMEGA_TIP}" > "$MT_CLG/.git/MERGE_HEAD"
echo "merged" > "$MT_CLG/omega.ts"
git -C "$MT_CLG" add omega.ts
CLG_OUT="$(cd "$MT_CLG" && bash "$MT_DIR/closure-lock-guard.sh" 2>&1)"
CLG_RC=$?
assert_eq "0" "$CLG_RC" "④i 宣告空值：降級後放行（不誤擋，即使無鎖）"
assert_contains "$CLG_OUT" "已停用" "④j 空值降級輸出明示已停用"

rm -rf "$MT_CLG"
