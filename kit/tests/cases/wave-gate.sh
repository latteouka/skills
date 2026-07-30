# wave-gate.sh — engines/wave-gate.sh 骨架合約八場景（scratch git repo + 假 stub）
#
# ①收尾 tierA 紅 → 早退（tierB marker 不存在）且鎖保持
# ②baseline：tierA 紅仍跑完 tierB（marker 存在）且不取鎖
# ③兩態分測：branch 全綠 → preauth＋鎖保持；base branch 全綠 → stamp＋鎖釋放
# ④STALE：branch 落後 base → 紅且鎖保持
# ⑤零改動 branch → exit 1 輸出含 baseline 提示
# ⑥鎖被他 branch 占 → 等待逾時紅（WAVE_LOCK_WAIT_SECONDS=2）
# ⑦tierA.d 零 stub → exit 2 fail-closed（附帶：tierB 零 stub 允許且明示）
# ⑧環境變數四項傳遞（stub dump 到檔案驗證）＋字典序（10- 先於 20-）

WG_ENGINE="$KIT_ROOT/engines/wave-gate.sh"
WG_LOCK="$KIT_ROOT/gates/merge-train/wave-closure-lock.sh"

wg_new_repo() {
    local d
    d="$(mktemp -d)"
    d="$(cd "$d" && pwd -P)"
    git -C "$d" init -q -b main
    git -C "$d" config user.email t@local
    git -C "$d" config user.name t
    git -C "$d" commit --allow-empty -qm init
    mkdir -p "$d/.claude/kit/gates.d/tierA.d" "$d/.claude/kit/gates.d/tierB.d"
    echo "$d"
}

# wg_stub <repo> <tierA|tierB> <NN-name.sh> <body>
wg_stub() {
    printf '#!/usr/bin/env bash\n%s\n' "$4" > "$1/.claude/kit/gates.d/$2.d/$3"
    chmod +x "$1/.claude/kit/gates.d/$2.d/$3"
}

# wg_branch <repo> <name> — 從 main 開 branch 並帶一個 commit（收尾取鎖資格）
wg_branch() {
    git -C "$1" checkout -q -b "$2"
    echo work >> "$1/w.txt"
    git -C "$1" add w.txt
    git -C "$1" commit -qm "wave work"
}

# wg_run <repo> <phase> — 跑引擎（鎖等待縮到 2 秒），輸出入 WG_OUT、rc 入 WG_RC
wg_run() {
    WG_OUT="$(cd "$1" && env WAVE_LOCK_WAIT_SECONDS=2 WAVE_LOCK_POLL_SECONDS=1 \
        bash "$WG_ENGINE" "$2" 2>&1)"
    WG_RC=$?
}

# ── ① 收尾 tierA 紅 → 早退跳過 tierB 且鎖保持 ──────────────────────
WG_R1="$(wg_new_repo)"
wg_stub "$WG_R1" tierA 10-red.sh 'echo "紅燈樣本"; exit 1'
wg_stub "$WG_R1" tierB 10-mark.sh 'touch "${PROJECT_ROOT}/tb-ran.marker"; exit 0'
wg_branch "$WG_R1" worktree-wave-a
wg_run "$WG_R1" 收尾
assert_eq "1" "$WG_RC" "①收尾 tierA 紅 exit 1"
assert_contains "$WG_OUT" "已跳過 Tier B" "①輸出明示早退"
if [ -f "$WG_R1/tb-ran.marker" ]; then
    assert_eq "tierB stub 未執行" "marker 存在（tierB 被執行了）" "①早退證據：tierB marker 不存在"
else
    assert_eq "yes" "yes" "①早退證據：tierB marker 不存在"
fi
if [ -d "$WG_R1/.git/wave-closure.lock" ]; then
    assert_eq "yes" "yes" "①FAIL 路徑鎖保持（鎖目錄仍在）"
else
    assert_eq "鎖目錄仍在" "鎖目錄不見了" "①FAIL 路徑鎖保持（鎖目錄仍在）"
fi

# ── ② baseline：tierA 紅仍跑完 tierB 且不取鎖 ──────────────────────
WG_R2="$(wg_new_repo)"
wg_stub "$WG_R2" tierA 10-red.sh 'echo "既存紅燈"; exit 1'
wg_stub "$WG_R2" tierB 10-mark.sh 'touch "${PROJECT_ROOT}/tb-ran.marker"; exit 0'
wg_run "$WG_R2" baseline
assert_eq "1" "$WG_RC" "②baseline 有紅 exit 1（基線如實反映紅燈）"
if [ -f "$WG_R2/tb-ran.marker" ]; then
    assert_eq "yes" "yes" "②baseline 不早退：tierB marker 存在"
else
    assert_eq "tierB marker 存在" "不存在（baseline 早退了）" "②baseline 不早退：tierB marker 存在"
fi
if [ -d "$WG_R2/.git/wave-closure.lock" ]; then
    assert_eq "baseline 不取鎖" "鎖目錄出現了" "②baseline 不取鎖"
else
    assert_eq "yes" "yes" "②baseline 不取鎖"
fi

# ── ③ 兩態分測：branch 全綠 → preauth＋鎖保持；main 全綠 → stamp＋鎖釋放 ──
WG_R3="$(wg_new_repo)"
wg_stub "$WG_R3" tierA 10-green.sh 'echo "inspected:1"; exit 0'
wg_stub "$WG_R3" tierB 10-green.sh 'echo "inspected:1"; exit 0'
wg_branch "$WG_R3" worktree-wave-c
wg_run "$WG_R3" 收尾
assert_eq "0" "$WG_RC" "③a branch 全綠 exit 0"
if [ -f "$WG_R3/.git/wave-regate-preauth" ]; then
    assert_eq "yes" "yes" "③a branch 全綠 → preauth 寫入"
else
    assert_eq "preauth 檔存在" "不存在" "③a branch 全綠 → preauth 寫入"
fi
if [ -d "$WG_R3/.git/wave-closure.lock" ]; then
    assert_eq "yes" "yes" "③a branch 全綠 → 鎖保持"
else
    assert_eq "鎖目錄仍在" "鎖被釋放了" "③a branch 全綠 → 鎖保持"
fi
git -C "$WG_R3" checkout -q main
git -C "$WG_R3" merge -q --no-ff worktree-wave-c -m "Merge worktree-wave-c — test"
wg_run "$WG_R3" 收尾
assert_eq "0" "$WG_RC" "③b main（base_branch）全綠 exit 0"
if [ -f "$WG_R3/.git/wave-regate-pass" ]; then
    assert_eq "yes" "yes" "③b main 全綠 → stamp 檔寫入"
else
    assert_eq "stamp 檔存在" "不存在" "③b main 全綠 → stamp 檔寫入"
fi
if [ -d "$WG_R3/.git/wave-closure.lock" ]; then
    assert_eq "鎖已釋放" "鎖目錄仍在" "③b main 全綠 → 鎖釋放（conditional-release）"
else
    assert_eq "yes" "yes" "③b main 全綠 → 鎖釋放（conditional-release）"
fi

# ── ④ STALE：branch 落後 base → 紅且鎖保持 ─────────────────────────
WG_R4="$(wg_new_repo)"
wg_stub "$WG_R4" tierA 10-green.sh 'exit 0'
wg_branch "$WG_R4" worktree-wave-d
git -C "$WG_R4" checkout -q main
echo advance >> "$WG_R4/m.txt"
git -C "$WG_R4" add m.txt
git -C "$WG_R4" commit -qm "main advances"
git -C "$WG_R4" checkout -q worktree-wave-d
wg_run "$WG_R4" 收尾
assert_eq "1" "$WG_RC" "④STALE exit 1"
assert_contains "$WG_OUT" "STALE" "④輸出含 STALE"
if [ -d "$WG_R4/.git/wave-closure.lock" ]; then
    assert_eq "yes" "yes" "④STALE 鎖保持（先取鎖再驗新鮮度）"
else
    assert_eq "鎖目錄仍在" "鎖不在" "④STALE 鎖保持（先取鎖再驗新鮮度）"
fi

# ── ⑤ 零改動 branch → exit 1 含 baseline 提示 ──────────────────────
WG_R5="$(wg_new_repo)"
wg_stub "$WG_R5" tierA 10-green.sh 'exit 0'
git -C "$WG_R5" checkout -q -b worktree-wave-e
wg_run "$WG_R5" 收尾
assert_eq "1" "$WG_RC" "⑤零改動 branch exit 1"
assert_contains "$WG_OUT" "baseline" "⑤輸出含 baseline 提示"

# ── ⑥ 鎖被他 branch 占 → 等待逾時紅 ────────────────────────────────
WG_R6="$(wg_new_repo)"
wg_stub "$WG_R6" tierA 10-green.sh 'exit 0'
git -C "$WG_R6" checkout -q -b holder
(cd "$WG_R6" && bash "$WG_LOCK" acquire) >/dev/null 2>&1
git -C "$WG_R6" checkout -q main
wg_branch "$WG_R6" worktree-wave-f
wg_run "$WG_R6" 收尾
assert_eq "1" "$WG_RC" "⑥他 branch 持鎖 → 等待逾時 exit 1"
assert_contains "$WG_OUT" "TIMEOUT" "⑥輸出含 TIMEOUT"
if [ -d "$WG_R6/.git/wave-closure.lock" ]; then
    assert_eq "yes" "yes" "⑥他人的鎖未被動到"
else
    assert_eq "他人的鎖仍在" "鎖不見了" "⑥他人的鎖未被動到"
fi

# ── ⑦ tierA.d 零 stub → exit 2 fail-closed；tierB 零 stub 允許且明示 ──
WG_R7="$(wg_new_repo)"
wg_run "$WG_R7" baseline
assert_eq "2" "$WG_RC" "⑦tierA.d 零 stub exit 2（fail-closed）"
assert_contains "$WG_OUT" "0 支 gate" "⑦輸出明示跑了 0 支 gate ≠ 全綠"
wg_stub "$WG_R7" tierA 10-green.sh 'exit 0'
wg_run "$WG_R7" baseline
assert_eq "0" "$WG_RC" "⑦b tierA 有 stub、tierB 空 → exit 0"
assert_contains "$WG_OUT" "tierB: 0 stubs" "⑦b tierB 零 stub 明示（不與漏跑混同）"

# ── ⑧ 環境變數四項傳遞＋字典序 ─────────────────────────────────────
WG_R8="$(wg_new_repo)"
printf 'app_workspace: "sub/app"\n' > "$WG_R8/.claude/kit/kit.yaml"
wg_stub "$WG_R8" tierA 10-first.sh \
    'echo A10 >> "${PROJECT_ROOT}/wg-order.txt"
{ echo "PROJECT_ROOT=${PROJECT_ROOT}"; echo "APP_WORKSPACE=${APP_WORKSPACE}"
  echo "GATE_PHASE=${GATE_PHASE}"; echo "TIER_B_ALREADY_RED=${TIER_B_ALREADY_RED}"
} > "${PROJECT_ROOT}/wg-a-env.txt"'
wg_stub "$WG_R8" tierA 20-second.sh 'echo A20 >> "${PROJECT_ROOT}/wg-order.txt"'
wg_stub "$WG_R8" tierB 10-dump.sh \
    '{ echo "PROJECT_ROOT=${PROJECT_ROOT}"; echo "APP_WORKSPACE=${APP_WORKSPACE}"
  echo "GATE_PHASE=${GATE_PHASE}"; echo "TIER_B_ALREADY_RED=${TIER_B_ALREADY_RED}"
} > "${PROJECT_ROOT}/wg-b-env.txt"'
wg_run "$WG_R8" baseline
assert_eq "0" "$WG_RC" "⑧baseline 全綠 exit 0"
WG_A_ENV="$(cat "$WG_R8/wg-a-env.txt" 2>/dev/null || echo MISSING)"
WG_B_ENV="$(cat "$WG_R8/wg-b-env.txt" 2>/dev/null || echo MISSING)"
assert_contains "$WG_A_ENV" "PROJECT_ROOT=$WG_R8" "⑧tierA PROJECT_ROOT 傳遞"
assert_contains "$WG_A_ENV" "APP_WORKSPACE=sub/app" "⑧tierA APP_WORKSPACE 傳遞（kit.yaml 宣告）"
assert_contains "$WG_A_ENV" "GATE_PHASE=baseline" "⑧tierA GATE_PHASE 傳遞"
assert_contains "$WG_A_ENV" "TIER_B_ALREADY_RED=0" "⑧tierA TIER_B_ALREADY_RED=0"
assert_contains "$WG_B_ENV" "PROJECT_ROOT=$WG_R8" "⑧tierB PROJECT_ROOT 傳遞"
assert_contains "$WG_B_ENV" "APP_WORKSPACE=sub/app" "⑧tierB APP_WORKSPACE 傳遞"
assert_contains "$WG_B_ENV" "GATE_PHASE=baseline" "⑧tierB GATE_PHASE 傳遞"
assert_contains "$WG_B_ENV" "TIER_B_ALREADY_RED=0" "⑧tierB 全綠時 TIER_B_ALREADY_RED=0"
WG_ORDER="$(cat "$WG_R8/wg-order.txt" 2>/dev/null | tr '\n' ' ')"
assert_eq "A10 A20 " "$WG_ORDER" "⑧字典序：10- 的 marker 早於 20-"

rm -rf "$WG_R1" "$WG_R2" "$WG_R3" "$WG_R4" "$WG_R5" "$WG_R6" "$WG_R7" "$WG_R8"
