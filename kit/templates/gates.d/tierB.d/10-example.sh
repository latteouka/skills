#!/usr/bin/env bash
# gates.d stub 契約範例（tierB＝重型：typecheck／測試／build 等分鐘級檢查）
#
# 引擎（kit/engines/wave-gate.sh）消費契約（與 tierA 相同者從略，見
# tierA.d/10-example.sh）：
#   - exit code 唯一介面：0=PASS，非 0=FAIL；`inspected:N` 行選填（canary 消費）。
#   - cwd＝repo 根；NN- 前綴字典序；環境變數 PROJECT_ROOT／APP_WORKSPACE／
#     GATE_PHASE（收尾|baseline）同 tierA。
#   - TIER_B_ALREADY_RED＝執行到本 stub 時是否已有紅燈（0|1）。收尾 phase
#     Tier A 紅已由引擎早退，故 1 等價「Tier B 內前面的 stub 已紅」；baseline
#     不早退，1 也可能來自 Tier A 既存紅。成本高的 stub（如 production build）
#     據此自行 SKIP——已紅注定重跑，不白燒重型檢查：
#       if [ "${TIER_B_ALREADY_RED:-0}" = "1" ]; then
#         echo "SKIP(已有 gate FAIL——修復後重跑時自然觸發)"; exit 0
#       fi
#   - 條件觸發同 tierA：不適用時自行 exit 0 ＋印 SKIP(原因)，例（只在 push
#     範圍有 source 變更時才跑）：
#       range="${PUSH_RANGE:-origin/${BASE_BRANCH:-main}...HEAD}"
#       if ! git diff --name-only "${range}" 2>/dev/null | grep -qE '\.(ts|tsx)$'; then
#         echo "SKIP(push 範圍無 source 變更)"; exit 0
#       fi
set -u -o pipefail

echo "example-gate: 把本檔換成專案自己的重型檢查（本範例恆綠）"
echo "inspected:1"
exit 0
