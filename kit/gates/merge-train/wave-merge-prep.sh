#!/usr/bin/env bash
# wave-merge-prep.sh — 收尾自癒 regen（merge train 的「自癒」性質）
#
# 解決的問題：收尾鎖（wave-closure-lock.sh）解掉「gate 證據追著 main 跑」的
# 串行化問題後，stale → merge main 帶進他波的 lockfile／prisma schema 變更時，
# install 與 prisma generate 仍靠人記得跑。忘了任何一樣就是假紅燈：stale
# prisma client 讓 B1 typecheck 噴一堆與本波無關的錯誤（實證 2026-07-26：
# SSO 波 cibCode 欄位進 main 未 generate，他波收尾 typecheck 紅、人工歸因
# 半天才確認「不是我的」）。
#
# 定位：healer 不是 gate——把生成物修到與 working tree 一致再讓 gate 判定，
# 自己只在「修不動」（lockfile 與 package.json 矛盾、generate 失敗）時紅。
# 由 wave-gate.sh 自動呼叫（收尾 phase 在鎖內、freshness 之後；baseline 也跑，
# 讓 fresh worktree 的基線不摻 stale 生成物噪音）；也可手動跑。
# coverage 的自癒已由 coverage-freshness.sh（無參數模式）承擔，本檔不重複。
#
# 冪等成本：同步狀態下 install 秒級（--prefer-offline no-op）、generate ~5-10s
# ——相對 10-20 分鐘的收尾 gate 可忽略，換到的是整類假紅燈物理消失。
#
# [kit 參數化] 自癒指令原為 dfaa 硬編碼兩步（pnpm install --frozen-lockfile
# --prefer-offline ＋ apps/web 內 pnpm exec prisma generate），改由專案宣告
# `.claude/kit/kit.yaml` 的 `merge_prep_cmd` 提供，於 repo 根執行。例：
#   merge_prep_cmd: "pnpm install --frozen-lockfile --prefer-offline && (cd apps/web && pnpm exec prisma generate)"
# 無宣告 → SKIP exit 0（該專案無自癒需求，明示不裝忙）。
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 裸 $var 接全形標點會誤判
# unbound variable）。

set -u
set -o pipefail

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "[merge-prep] 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
merge_prep_cmd="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" merge_prep_cmd '')"

if [ -z "${merge_prep_cmd}" ]; then
  echo "[merge-prep] SKIP(無 merge_prep_cmd 宣告)"
  exit 0
fi

cd "${repo_root}" || exit 1

echo "[merge-prep] 執行宣告自癒指令：${merge_prep_cmd}"
if ! bash -c "${merge_prep_cmd}"; then
  echo "[merge-prep] FAIL——merge_prep_cmd 執行失敗（healer 修不動，需人工收斂）。"
  echo "  常見原因：lockfile 與 package.json 不一致（install 後把 lockfile 一起 commit）、"
  echo "  schema 有 merge 衝突殘渣（<<<<<<< 標記）——先解掉再重跑。"
  exit 1
fi

echo "[merge-prep] PASS（依賴與生成物已與 working tree 同步）"
exit 0
