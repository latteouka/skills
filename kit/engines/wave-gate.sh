#!/usr/bin/env bash
# engines/wave-gate.sh — wave 收尾品質閘門骨架（宣告驅動；wave skill 的唯一品質介面）
#
# 吸收自 dfaa scripts/hooks/wave-gate.sh（K2 拆分）：流程結構（收尾鎖 → 新鮮度
# → merge-prep 自癒 → 工具就緒 → pathspec liveness → Tier A 快篩紅燈早退 →
# Tier B 重型 → 收口兩態分流）逐段保留；內容 gate 外移為專案宣告
# <decl-dir>/gates.d/ 的 stub。本檔只剩骨架＝執行順序＋鎖策略＋早退政策＋
# fail-closed 防假 0。stub 契約見 kit/references/declaration-formats.md 與
# kit/templates/gates.d/。
#
# 用法：bash engines/wave-gate.sh [收尾|baseline] [--decl-dir <path>]
#   收尾＝閘門判定：取收尾鎖 → base 新鮮度（stale 立即紅，不燒任何重檢查）
#         → Tier A 快篩（任一紅 → 早退跳過 Tier B）→ Tier B → 收口：
#         base branch 上 PASS＝merge re-gate 完成 → regate stamp ＋條件式放鎖；
#         其他 branch 上 PASS → regate preauth ＋鎖保持持有直到 merge re-gate。
#   baseline＝開工時記錄既存紅燈：不取鎖、不查新鮮度、不早退——跑全套，
#         留完整基線供之後紅燈歸因（本波引入 vs 既存）。
#   --decl-dir 宣告目錄，預設 <repo>/.claude/kit（測試 seam。注意：本檔轉呼叫
#         的 merge-train gate 自行讀 <repo>/.claude/kit/kit.yaml，不吃此覆寫）。
#   wave skill 只看本 script 的 exit code，不解析 gate 細節：
#         0=全綠；1=有紅（收尾 FAIL 路徑鎖保持，不 release）；
#         2=gates.d 宣告缺失 fail-closed／用法錯誤。
#   環境：WAVE_LOCK_WAIT_SECONDS／WAVE_LOCK_POLL_SECONDS 原樣傳遞給收尾鎖
#         （selftest／測試把預設 45 分鐘等待縮到秒級）。
#
# 結構事故脈絡（上游 2026-07-26 重排的教訓，骨架政策的存在理由，全數保留）：
#   - wave gate-governance 收尾重跑 9 輪（/tmp/dfaa-gate-governance-final1..9.log）
#     ——①並行波互推 main，收尾證據反覆 stale → 收尾鎖＋新鮮度先於一切，
#     證據保鮮期從 gate 開跑起算；②秒級可查的跨波 drift 紅燈排在十幾分鐘的
#     重檢查之後才跑到 → Tier A 快篩先行、收尾 phase 紅燈早退。
#   - 假 0 三大源（依賴未裝、config 解析失敗、binary 路徑錯）：工具沒裝好時
#     grep/lint 照回漂亮的 0——假 PASS 比真 FAIL 危險 → 工具就緒檢查先於 gate。
#   - pathspec 空轉（上游 commit 7c904ee47，空轉 8 天全程綠燈）：「gate 跑了、
#     exit 0、但檢查了 0 個檔」是最危險的失效模式 → pathspec liveness 前置；
#     同款母題套在宣告自身＝tierA.d 零 stub fail-closed（跑了 0 支 gate ≠ 全綠）。
#   - pipefail 必開：gate 內有 `cmd | tail` 管線，無 pipefail 時 exit code＝
#     tail 的 0，測試 FAIL 會被吞成 PASS（上游 gov-p0 收尾稽核抓到的缺陷）。
#   - 全部用 ${var} 形式（macOS bash 3.2 + set -u 裸 $var 接全形標點會誤判
#     unbound variable，見上游 dev-ref claude-code--hooks-quality-gates）。
#
# 上游 tier 內容對照表（dfaa scripts/hooks/wave-gate.sh；細節不搬，供 K6 遷移
# 參照——dfaa 側逐項改寫成 gates.d stub 時的建議落點）：
#   0.6 docs-machine-read-guard → 專案 tierA stub（歸 K7，不進骨架）
#   A1 registry drift           → tierA.d/10-registry-drift.sh
#   A2 測試登記表 drift         → tierA.d/20-test-registry.sh
#   A2.5 測試準入快篩           → tierA.d/25-test-admission.sh（注意 cwd：上游
#                                 腳本以 app workspace 為工作目錄，stub 內自行 cd）
#   A3 RTM 一致性               → tierA.d/30-rtm-check.sh
#   A4 coverage 新鮮度          → tierA.d/40-coverage-freshness.sh（上游 FAIL＝
#                                 立即停止；stub 協定下以紅燈表達，收尾 phase 的
#                                 早退由骨架 Tier A 收口承擔）
#   A5 ratchet 品質債           → tierA.d/50-ratchet.sh
#   B1 typecheck                → tierB.d/10-typecheck.sh
#   B2 fast tier 測試           → tierB.d/20-test.sh
#   B3 gate canary（把關自測）  → tierB.d/30-gate-canary.sh
#   B4 全量 type-aware lint     → tierB.d/40-lint.sh
#   B5 production build         → tierB.d/50-build.sh（條件觸發＋
#                                 TIER_B_ALREADY_RED 自行 SKIP，見 stub 範例）

set -u -o pipefail

usage() {
  echo "用法: wave-gate.sh [收尾|baseline] [--decl-dir <path>]" >&2
  exit 2
}

phase="收尾"
decl_dir=""
while [ $# -gt 0 ]; do
  case "${1}" in
    收尾|baseline)
      phase="${1}"; shift ;;
    --decl-dir)
      [ $# -ge 2 ] || usage
      decl_dir="${2}"; shift 2 ;;
    *)
      usage ;;
  esac
done

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "wave-gate: 找不到 kit/lib/common.sh" >&2; exit 1; }

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${root}" ]; then
  echo "wave-gate: 不在 git 工作目錄內" >&2
  exit 1
fi
cd "${root}" || exit 1

[ -n "${decl_dir}" ] || decl_dir="${root}/.claude/kit"
kit_yaml="${decl_dir}/kit.yaml"
base_branch="$(kit_decl_get "${kit_yaml}" base_branch main)"
app_workspace="$(kit_decl_get "${kit_yaml}" app_workspace '')"
tool_readiness="$(kit_decl_get "${kit_yaml}" tool_readiness '')"

lock_sh="${kit_root}/gates/merge-train/wave-closure-lock.sh"
regate_sh="${kit_root}/gates/merge-train/wave-regate-guard.sh"
prep_sh="${kit_root}/gates/merge-train/wave-merge-prep.sh"

fail=0
branch="$(git rev-parse --abbrev-ref HEAD)"

section() {
  echo ""
  echo "=== [wave-gate:${phase}] ${1} ==="
}

# FAIL／fail-closed 路徑一律鎖保持（不 release）——臨界區涵蓋
# gate 開跑 → merge → merge re-gate PASS，中途紅燈不代表臨界區結束。
lock_keep_note() {
  if [ "${phase}" = "收尾" ] && [ "${branch}" != "${base_branch}" ]; then
    echo "closure-lock: 鎖保持持有（棄波請手動 bash ${lock_sh} release）。"
  fi
}

# ── 收尾前置：收尾鎖 ＋ base 新鮮度 ─────────────────────────────
# 鎖先於一切：證據的保鮮期從 gate 開跑起算，快篩也不例外。
# base branch 上收尾＝merge re-gate——不取鎖，PASS 時收口條件式釋放。
if [ "${phase}" = "收尾" ]; then
  section "收尾前置：收尾鎖＋${base_branch} 新鮮度"
  if [ "${branch}" = "${base_branch}" ]; then
    echo "closure-lock: ${base_branch} 上收尾＝merge re-gate，不取鎖（PASS 時條件式釋放既有鎖）"
  else
    # 取鎖資格：零改動 branch 不得跑收尾（上游 🤖-3）
    ahead="$(git rev-list --count "${base_branch}..HEAD" 2>/dev/null || echo 0)"
    if [ "${ahead}" -eq 0 ]; then
      echo "closure-lock: 本 branch 相對 ${base_branch} 零 commit——"
      echo "  這是開工 baseline 吧？改跑 bash ${kit_root}/engines/wave-gate.sh baseline（不取鎖）。"
      exit 1
    fi
    if ! bash "${lock_sh}" acquire; then
      echo "closure-lock: FAIL（取鎖失敗——持有者資訊見上）"
      exit 1
    fi
    if git rev-parse --verify -q "${base_branch}" >/dev/null; then
      behind="$(git rev-list --count "HEAD..${base_branch}")"
      if [ "${behind}" -ne 0 ]; then
        echo "freshness: STALE——${base_branch} 已前進 ${behind} 個 commit。"
        echo "  先 git merge ${base_branch}（解衝突）再重跑收尾 gate。收尾鎖已持有，"
        echo "  merge 與重跑期間他波無法再推進 ${base_branch}。生成物不用手動追——"
        echo "  重跑時 merge-prep 自動補（見 0.1）。"
        exit 1
      fi
      echo "freshness: PASS（HEAD..${base_branch}=0）"
    else
      echo "freshness: SKIP（無 ${base_branch} ref）"
    fi
  fi
fi

# ── 0.1：merge-prep 自癒 ────────────────────────────────────────
# 排在工具就緒之前：prep 本身就是「把工具裝好」的機器化。healer 定位：
# 修不動才紅，紅了立即停（生成物不可信時下游 gate 全是噪音）。兩 phase 都跑，
# fresh worktree 的 baseline 也不摻 stale 生成物噪音。自癒指令由專案宣告
# kit.yaml merge_prep_cmd 提供（無宣告時 gate 自行 SKIP 明示）。
section "0.1 merge-prep 自癒（宣告 merge_prep_cmd）"
if bash "${prep_sh}"; then
  :  # PASS／SKIP 訊息由 merge-prep 自己印
else
  echo "merge-prep: FAIL（生成物無法同步——訊息見上，立即停止）"
  lock_keep_note
  exit 1
fi

# ── 0：工具就緒檢查 ─────────────────────────────────────────────
# ERRATA 級教訓：工具沒裝好時 grep/lint 照回漂亮的 0——假 PASS 比真 FAIL 危險。
# 在任何 gate 之前先驗宣告的關鍵 binary 存在且可執行（kit.yaml tool_readiness，
# 空白分隔清單）。查找順序＝上游做法的通用化：PATH（command -v）→
# <app_workspace>/node_modules/.bin → <repo 根>/node_modules/.bin。
section "0 工具就緒檢查"
if [ -z "${tool_readiness}" ]; then
  echo "tool-readiness: SKIP(無 tool_readiness 宣告)"
else
  tool_ready=1
  for bin in ${tool_readiness}; do
    if command -v "${bin}" >/dev/null 2>&1; then
      continue
    fi
    if [ -n "${app_workspace}" ] && [ -x "${root}/${app_workspace}/node_modules/.bin/${bin}" ]; then
      continue
    fi
    if [ -x "${root}/node_modules/.bin/${bin}" ]; then
      continue
    fi
    echo "  ✗ ${bin} 不可用（依賴安裝了嗎？）"
    tool_ready=0
  done
  if [ "${tool_ready}" -eq 0 ]; then
    echo "工具未就緒: FAIL（先在 ${app_workspace:-repo 根} 安裝依賴再重跑）"
    lock_keep_note
    exit 1
  fi
  echo "工具就緒: PASS"
fi

# ── 0.5：pathspec liveness（hook 基建防空轉） ────────────────────
# 「gate 跑了、exit 0、但檢查了 0 個檔」防護（上游 7c904ee47 空轉 8 天）。
# 宣告檔屬選配模組——無 pathspec-targets.conf 時 SKIP 明示（本骨架唯一例外
# 容許 SKIP 的宣告：conf 缺席＝專案未裝該模組，非引擎假 0）。
section "0.5 pathspec liveness（hook 基建）"
if [ -f "${decl_dir}/pathspec-targets.conf" ]; then
  if bash "${kit_root}/engines/pathspec-liveness.sh" --decl-dir "${decl_dir}" --repo-root "${root}"; then
    echo "pathspec-liveness: PASS"
  else
    echo "pathspec-liveness: FAIL（有 pathspec 恆 0 命中——gate 正在空轉）"
    fail=1
  fi
else
  echo "pathspec-liveness: SKIP(無 pathspec-targets.conf 宣告——選配模組)"
fi

# ═══ Tier A 快篩（<decl-dir>/gates.d/tierA.d/NN-*.sh 字典序） ═══════
# 防假 0：tierA.d 不存在或零 stub → fail-closed exit 2——「跑了 0 支 gate」
# 與全綠必須可區分（同 pathspec 空轉母題，套在宣告自身）。

tierA_dir="${decl_dir}/gates.d/tierA.d"
section "Tier A 快篩（gates.d/tierA.d）"
tierA_count=0
if [ -d "${tierA_dir}" ]; then
  for stub in "${tierA_dir}"/*.sh; do
    [ -f "${stub}" ] || continue
    tierA_count=$((tierA_count + 1))
  done
fi
if [ "${tierA_count}" -eq 0 ]; then
  echo "gates.d: FAIL-CLOSED——tierA.d 不存在或零 stub（跑了 0 支 gate ≠ 全綠）。"
  echo "  至少放一支 tierA stub 收尾才有語意；範例見 ${kit_root}/templates/gates.d/。"
  lock_keep_note
  exit 2
fi
for stub in "${tierA_dir}"/*.sh; do
  [ -f "${stub}" ] || continue
  stub_name="$(basename "${stub}")"
  echo "--- tierA/${stub_name} ---"
  if env PROJECT_ROOT="${root}" APP_WORKSPACE="${app_workspace}" \
       GATE_PHASE="${phase}" TIER_B_ALREADY_RED=0 bash "${stub}"; then
    echo "tierA/${stub_name}: PASS"
  else
    echo "tierA/${stub_name}: FAIL"
    fail=1
  fi
done

# ── Tier A 收口：收尾 phase 紅燈早退（baseline 不早退，留完整基線） ──
if [ "${fail}" -ne 0 ] && [ "${phase}" = "收尾" ]; then
  echo ""
  echo "[wave-gate:${phase}] Tier A 快篩 FAIL——已跳過 Tier B。"
  echo "  單輪全綠才算收尾證據，快篩紅燈注定重跑；修復後重跑全套。"
  lock_keep_note
  exit 1
fi

# ═══ Tier B 重型（<decl-dir>/gates.d/tierB.d/NN-*.sh 字典序） ═══════
# 零 stub 允許（有些專案只有快篩）但必須明示，不與全綠混同。
# TIER_B_ALREADY_RED：執行到該 stub 時已有紅燈＝1（收尾 phase Tier A 紅已
# 早退，故等價於「tier 內已有紅」；baseline 含 Tier A 紅——對齊上游 B5 的
# 「已紅就不白燒 build」條件）；重型 stub 據此自行決定 SKIP。

tierB_dir="${decl_dir}/gates.d/tierB.d"
section "Tier B 重型（gates.d/tierB.d）"
tierB_count=0
if [ -d "${tierB_dir}" ]; then
  for stub in "${tierB_dir}"/*.sh; do
    [ -f "${stub}" ] || continue
    tierB_count=$((tierB_count + 1))
  done
fi
if [ "${tierB_count}" -eq 0 ]; then
  echo "tierB: 0 stubs（允許——有些專案只有快篩；重型把關缺席是宣告出來的，不是漏跑）"
else
  for stub in "${tierB_dir}"/*.sh; do
    [ -f "${stub}" ] || continue
    stub_name="$(basename "${stub}")"
    tb_red=0
    if [ "${fail}" -ne 0 ]; then tb_red=1; fi
    echo "--- tierB/${stub_name} ---"
    if env PROJECT_ROOT="${root}" APP_WORKSPACE="${app_workspace}" \
         GATE_PHASE="${phase}" TIER_B_ALREADY_RED="${tb_red}" bash "${stub}"; then
      echo "tierB/${stub_name}: PASS"
    else
      echo "tierB/${stub_name}: FAIL"
      fail=1
    fi
  done
fi

# ═══ 收口：兩態分流（上游行為逐段保留） ═════════════════════════
# base branch 上 PASS＝merge re-gate 完成 → regate stamp（pre-push 唯一入口
# 擋門的放行憑證）＋條件式釋放收尾鎖；其他 branch 上 PASS → regate preauth
# （freshness 已強制 HEAD..base=0，本輪驗的就是 merge 後會出現的合體樹——
# merge --no-ff 未帶新內容時 pre-push 樹比對放行＋自動補戳，免掉一輪重複
# re-gate）＋鎖保持持有直到 merge re-gate。

echo ""
if [ "${fail}" -eq 0 ]; then
  echo "[wave-gate:${phase}] 全部 gate PASS（SKIP 項如上列）"
  if [ "${phase}" = "收尾" ]; then
    if [ "${branch}" = "${base_branch}" ]; then
      bash "${regate_sh}" stamp || true
      bash "${lock_sh}" conditional-release || true
    else
      bash "${regate_sh}" preauth || true
      echo "closure-lock: 鎖保持持有——merge --no-ff 進 ${base_branch} 後直接 push："
      echo "  merge 樹與本輪相同 → pre-push preauth 放行（免重跑 re-gate）；"
      echo "  樹不同（${base_branch} 已前進）→ 在 ${base_branch} 上跑 bash ${kit_root}/engines/wave-gate.sh 收尾。"
    fi
  fi
else
  echo "[wave-gate:${phase}] 有 gate FAIL——修復後重跑，不得標波完成"
  lock_keep_note
fi
exit "${fail}"
