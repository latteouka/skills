#!/usr/bin/env bash
# gates.d stub 契約範例（tierA＝快篩：秒～分級的 drift／一致性檢查）
#
# 引擎（kit/engines/wave-gate.sh）消費契約：
#   - exit code 唯一介面：0=PASS，非 0=FAIL。stdout 只給人看，引擎不解析
#     （唯一例外：`inspected:N` 行選填，canary 引擎消費——N>0 證明本輪真的
#      檢查了 N 個對象，防「跑了 exit 0 但檢查 0 個檔」的假 0）。
#   - cwd＝repo 根；檔名 NN-<name>.sh，NN 前綴決定 tier 內字典序執行順位。
#   - 引擎注入環境變數：
#       PROJECT_ROOT        repo 根絕對路徑
#       APP_WORKSPACE       kit.yaml app_workspace 值（無 monorepo 為空字串）
#       GATE_PHASE          收尾|baseline（stub 通常無感；需區分時可用）
#       TIER_B_ALREADY_RED  tierA stub 恆拿到 0（早退政策在引擎，不在 stub）
#   - 收尾 phase 任一 tierA 紅 → 引擎早退跳過 Tier B；baseline 不早退。
#     紅燈早退、鎖、re-gate 戳記全在引擎骨架——stub 只管自己的檢查。
#   - 條件觸發：不適用時自行 exit 0 並印 SKIP(原因)，例：
#       if [ ! -d "${PROJECT_ROOT}/docs/rtm" ]; then
#         echo "SKIP(本專案無 rtm 模組)"; exit 0
#       fi
set -u -o pipefail

echo "example-gate: 把本檔換成專案自己的快篩檢查（本範例恆綠）"
echo "inspected:1"
exit 0
