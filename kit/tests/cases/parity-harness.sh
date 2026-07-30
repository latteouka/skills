# parity-harness.sh — 隔離 parity harness selftest（K5.5 必修①）
#
# 核心價值證明（紅）：狀態型腳本對在同樹串行下假等價（舊版先跑把 stamp 寫好，
# 替新版「修好」環境），parity-run 隔離雙 clone 下必報 DIFF。另覆蓋五面向各自
# 命中、正規化防假 DIFF、shim-probe 四項 round-trip＋tsx 缺席 SKIP、真 Husky
# （hooksPath）hook 鏈等價、fail-closed。

# scratch repo 手法重用 canary-harness（不重寫）；lib 會開 pipefail，
# case 在 run.sh 進程內 source，用完即還原，不污染 full-suite 後續 case。
. "$KIT_ROOT/lib/canary-harness.sh"
set +o pipefail

PR_TOOL="$KIT_ROOT/tools/parity-run.sh"
SP_TOOL="$KIT_ROOT/tools/shim-probe.sh"

PR_TMP="$(canary_tmp_init kit-parity-selftest)"

# --- 固定 source repo：全部案例腳本一次 commit（隔離 scratch，不在 worktree 內建 repo）
PR_SRC="${PR_TMP}/src"
canary_new_scratch_repo "${PR_SRC}"
(
    cd "${PR_SRC}" || exit 1
    echo "base" > tracked.txt
    echo "out.log" > .gitignore
    mkdir -p .claude/dev
    echo "keep" > .claude/dev/placeholder.txt

    # 狀態型腳本對（design selftest 第一條）：A＝無 stamp 則寫 stamp 後 exit 1、
    # 有 stamp 則 exit 0；B＝恆 exit 0
    cat > stampy-a.sh <<'EOF'
#!/usr/bin/env bash
if [ -f .claude/dev/.wave-stamp ]; then exit 0; fi
mkdir -p .claude/dev
echo "stamped" > .claude/dev/.wave-stamp
exit 1
EOF
    printf '#!/usr/bin/env bash\nexit 0\n' > always-zero.sh
    # 兩版寫不同內容到同一 state 檔
    printf '#!/usr/bin/env bash\nmkdir -p .claude/dev\necho "AAA" > .claude/dev/.wave-lock\nexit 0\n' > lock-a.sh
    printf '#!/usr/bin/env bash\nmkdir -p .claude/dev\necho "BBB" > .claude/dev/.wave-lock\nexit 0\n' > lock-b.sh
    # 輸出不同（output 面向）
    printf '#!/usr/bin/env bash\necho foo\nexit 0\n' > out-foo.sh
    printf '#!/usr/bin/env bash\necho bar\nexit 0\n' > out-bar.sh
    # 改 tracked 檔（working-tree 面向）
    printf '#!/usr/bin/env bash\necho "extra" >> tracked.txt\nexit 0\n' > mut.sh
    # 寫 gitignore 蓋住的檔（untracked 守恆面向——porcelain 看不到，唯 untracked-set 抓得到）
    printf '#!/usr/bin/env bash\necho "artifact" > out.log\nexit 0\n' > ignored-out.sh
    # 輸出含自己的絕對路徑、HOME 與時間戳（正規化面向）
    cat > norm.sh <<'EOF'
#!/usr/bin/env bash
echo "root=$(pwd) home=${HOME} at $(date +%H:%M:%S)"
exit 0
EOF
    git add -A && git commit -q -m "parity selftest fixtures"
) >/dev/null 2>&1
PR_REF="$(git -C "${PR_SRC}" rev-parse HEAD)"

# --- 核心紅：同樹串行假等價 → 隔離雙 clone 必 DIFF（本 harness 存在的理由）
PR_SERIAL="${PR_TMP}/serial"
git clone --no-hardlinks -q "${PR_SRC}" "${PR_SERIAL}"
(cd "${PR_SERIAL}" && bash stampy-a.sh) >/dev/null 2>&1
PR_RC_FIRST=$?
(cd "${PR_SERIAL}" && bash stampy-a.sh) >/dev/null 2>&1
PR_RC_A2=$?
(cd "${PR_SERIAL}" && bash always-zero.sh) >/dev/null 2>&1
PR_RC_B=$?
assert_eq "1" "${PR_RC_FIRST}" "狀態型腳本 A 首跑：寫 stamp 後 exit 1"
assert_eq "0" "${PR_RC_A2}" "同樹二跑：stamp 已在 → A exit 0（舊版先跑替環境『修好』）"
assert_eq "${PR_RC_A2}" "${PR_RC_B}" "同樹串行 A→B 假等價（0=0，行為差異被狀態污染遮蔽）"

PR_OUT1="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash stampy-a.sh" --cmd-b "bash always-zero.sh" 2>&1)"
PR_RC1=$?
assert_eq "1" "${PR_RC1}" "隔離雙 clone：同一腳本對必報 DIFF（exit 1）"
assert_contains "${PR_OUT1}" "[1/5 exit-code] DIFF (A=1 B=0)" "exit-code 面向命中（A 在乾淨 clone exit 1 ≠ B exit 0）"
assert_contains "${PR_OUT1}" "PARITY:DIFF" "整體判定 PARITY:DIFF"

# --- 紅：輸出不同 → output(normalized) 面向命中（exit 面向同時 PASS 佐證面向獨立）
PR_OUT2="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash out-foo.sh" --cmd-b "bash out-bar.sh" 2>&1)"
assert_eq "1" "$?" "輸出不同 → exit 1"
assert_contains "${PR_OUT2}" "[1/5 exit-code] PASS" "exit-code 面向獨立 PASS"
assert_contains "${PR_OUT2}" "[2/5 output(normalized)] DIFF" "output(normalized) 面向命中"

# --- 紅：改 tracked 檔 → working-tree 面向命中
PR_OUT3="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash mut.sh" --cmd-b "bash always-zero.sh" 2>&1)"
assert_eq "1" "$?" "tracked 檔副作用不同 → exit 1"
assert_contains "${PR_OUT3}" "[3/5 working-tree] DIFF" "working-tree 面向命中"

# --- 紅：兩版寫不同內容到同一 state 檔 → state-glob 面向命中（untracked 面向
#     同時 PASS：已比對的 state 檔被排除，證明守恆面向不重複記帳）
PR_OUT4="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash lock-a.sh" --cmd-b "bash lock-b.sh" 2>&1)"
assert_eq "1" "$?" "state 檔內容不同 → exit 1"
assert_contains "${PR_OUT4}" "[4/5 state-glob] DIFF" "state-glob 面向命中（AAA≠BBB）"
assert_contains "${PR_OUT4}" "[5/5 untracked-set] PASS" "state-glob 已比對者排除於 untracked 守恆之外"
assert_contains "${PR_OUT4}" "[1/5 exit-code] PASS" "exit 同為 0——只有 state 面向抓得到這對"

# --- 紅：寫 gitignore 蓋住的檔 → untracked-set 面向命中（working-tree 面向盲）
PR_OUT5="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash ignored-out.sh" --cmd-b "bash always-zero.sh" 2>&1)"
assert_eq "1" "$?" "ignored 產出檔不守恆 → exit 1"
assert_contains "${PR_OUT5}" "[5/5 untracked-set] DIFF" "untracked 守恆面向命中（含 ignored 檔）"
assert_contains "${PR_OUT5}" "[3/5 working-tree] PASS" "porcelain 看不到 ignored 檔——唯 untracked-set 抓得到"

# --- 綠＋正規化：同一腳本自比，輸出各含自己的絕對路徑／HOME／時間戳 →
#     正規化後 EQUIV（防假 DIFF）
PR_OUT6="$(bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "bash norm.sh" --cmd-b "bash norm.sh" 2>&1)"
assert_eq "0" "$?" "同腳本自比（含路徑/時間戳輸出）→ exit 0"
assert_contains "${PR_OUT6}" "[2/5 output(normalized)] PASS" "兩邊絕對路徑與時間戳正規化後相等"
assert_contains "${PR_OUT6}" "inspected:5" "尾行 inspected:5（五面向都跑了）"
assert_contains "${PR_OUT6}" "PARITY:EQUIV" "整體判定 PARITY:EQUIV"

# --- fail-closed
PR_NOREPO="$(mktemp -d)"
bash "${PR_TOOL}" --source "${PR_NOREPO}" --ref HEAD --cmd-a "true" --cmd-b "true" >/dev/null 2>&1
assert_eq "2" "$?" "--source 非 git repo → exit 2"
rm -rf "${PR_NOREPO}"
bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" \
    --cmd-a "definitely-not-a-cmd-parity-xyz" --cmd-b "true" >/dev/null 2>&1
assert_eq "2" "$?" "cmd 起不來（exit 127）→ exit 2"
bash "${PR_TOOL}" --source "${PR_SRC}" --ref "${PR_REF}" --cmd-a "true" >/dev/null 2>&1
assert_eq "2" "$?" "--cmd-b 缺 → exit 2（參數缺 fail-closed）"

# --- shim probe：argv（含空白/引號）/cwd/env/exit 四項 round-trip
SP_OUT="$(bash "${SP_TOOL}" 2>&1)"
SP_RC=$?
assert_eq "0" "${SP_RC}" "shim-probe 全過 exit 0"
assert_contains "${SP_OUT}" "✓ bash-shim: argv round-trip（含空白與引號參數）" "argv 逐位保真（a b／x\"y）"
assert_contains "${SP_OUT}" "✓ bash-shim: cwd round-trip" "cwd 保真"
assert_contains "${SP_OUT}" "✓ bash-shim: env round-trip" "env 白名單穿透"
assert_contains "${SP_OUT}" "✓ bash-shim: exit-code round-trip" "exit code 直通"
assert_contains "${SP_OUT}" "SHIM-PROBE:PASS" "shim-probe 總結 PASS"
# tsx 缺席 → .ts 子測 SKIP 明示（PATH 收窄到必無 tsx，確定性觸發）
SP_OUT2="$(PATH=/usr/bin:/bin bash "${SP_TOOL}" 2>&1)"
assert_contains "${SP_OUT2}" "SKIP(ts-shim)" "tsx 缺席 → .ts 子測 SKIP 明示（未驗≠通過）"

# --- 真 Husky 面向：hooksPath＋真 git commit 觸發攔截，證明 hook 鏈與直呼等價
#     （不裝 npm husky——hooksPath 機制與 husky 一致；kit 測試無 node 依賴）
HK="${PR_TMP}/husky"
canary_new_scratch_repo "${HK}"
cat > "${HK}/check.sh" <<'EOF'
#!/bin/sh
if [ -f bad.txt ]; then
    echo "husky-gate: blocked (bad.txt present)"
    exit 1
fi
echo "husky-gate: clean"
exit 0
EOF
mkdir -p "${HK}/.husky"
printf '#!/bin/sh\nsh check.sh\n' > "${HK}/.husky/pre-commit"
chmod +x "${HK}/.husky/pre-commit" "${HK}/check.sh"
(cd "${HK}" && git config core.hooksPath .husky)
(cd "${HK}" && git add -A && git commit -q -m "init") >/dev/null 2>&1
assert_eq "0" "$?" "hooksPath 接線後 clean commit 通過（hook 有跑且放行）"
HK_OUT="$( (cd "${HK}" && touch bad.txt && git add bad.txt && git commit -m "violation") 2>&1 )"
HK_COMMIT_RC=$?
(cd "${HK}" && sh check.sh) >/dev/null 2>&1
HK_DIRECT_RC=$?
assert_contains "${HK_OUT}" "husky-gate: blocked" "gate 輸出經真 git hook 鏈透傳（證明 hook 真的跑了）"
assert_eq "1" "${HK_DIRECT_RC}" "直呼 gate：violation exit 1"
HK_HOOK_BLOCKED=0; [ "${HK_COMMIT_RC}" -ne 0 ] && HK_HOOK_BLOCKED=1
assert_eq "1" "${HK_HOOK_BLOCKED}" "真 git commit 被 pre-commit 攔下（違規側：hook 鏈與直呼同判紅）"
(cd "${HK}" && git reset -q && rm -f bad.txt && echo "ok" > ok.txt && git add ok.txt && git commit -q -m "clean") >/dev/null 2>&1
HK_CLEAN_RC=$?
(cd "${HK}" && sh check.sh) >/dev/null 2>&1
HK_DIRECT_CLEAN_RC=$?
assert_eq "0" "${HK_CLEAN_RC}" "clean commit 經真 hook 鏈通過"
assert_eq "${HK_DIRECT_CLEAN_RC}" "${HK_CLEAN_RC}" "hook 鏈 vs 直呼等價（clean 側同判 0）"

# --- checklist 存在且含 UNVERIFIABLE 區
PR_CL_PATH="$KIT_ROOT/references/parity-checklist.md"
PR_CL_EXISTS=1; [ -f "${PR_CL_PATH}" ] && PR_CL_EXISTS=0
assert_eq "0" "${PR_CL_EXISTS}" "references/parity-checklist.md 存在"
PR_CL="$(cat "${PR_CL_PATH}" 2>/dev/null)"
assert_contains "${PR_CL}" "UNVERIFIABLE" "checklist 含 UNVERIFIABLE 手動清單區"
assert_contains "${PR_CL}" "parity-run" "checklist 含 parity-run 用法"
assert_contains "${PR_CL}" "--state-glob" "checklist 含 state-glob 對照建議"

rm -rf "${PR_TMP}"
