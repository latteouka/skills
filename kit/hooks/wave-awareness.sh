#!/usr/bin/env bash
# SessionStart hook — 多波感知注入（「開」的機器面）。
#
# 為什麼是 hook：wave SKILL.md 條文叫 Claude 在 Phase 0/4 跑 wave-registry
# 看交集，但條文依賴 session 記得跑——與 frontmatter 同構的失敗模式
# （2026-07-25 實測 0/52 執行）。SessionStart 每次開 session 必觸發，
# 把「還有誰在跑、跟我有沒有需裁定的交集」直接餵進 context，
# 感知不再依賴任何人記得做任何事。
#
# 輸出紀律（避免每 session 噪音）：
#   - 「其他」worktree 為 0 → 完全靜默（自己不需要感知自己）
#   - 有其他 → 一行清單
#   - ≥2 個活躍 worktree 且 intersect 有需裁定交集 → 只列需裁定檔，
#     可自動合併級一律不印（列了只是噪音——與 wave SKILL.md Phase 4 同判準）
#
# 邏輯全部委派 kit/scripts/wave-registry.sh（單一真相源），本 hook 只做
# 過濾與壓縮。fail-open：任何一步失敗都靜默 exit 0，不擋 session。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="${KIT_ROOT}/scripts/wave-registry.sh"
[ -x "$REGISTRY" ] || exit 0

. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

cat >/dev/null 2>&1 || true

root="$(kit_repo_root)" || exit 0
[ -n "$root" ] || exit 0

# 目前 session 若在 worktree 內，它自己的 branch 不列入「其他」
current_branch=""
case "$root" in
    */.claude/worktrees/*)
        current_branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
        ;;
esac

list="$(bash "$REGISTRY" list 2>/dev/null)" || exit 0

# 取資料列（去表頭與「無活躍」提示），過濾掉自己
rows="$(printf '%s\n' "$list" | sed -n '2,$p' | grep -v '^（' || true)"
others="$rows"
if [ -n "$current_branch" ]; then
    others="$(printf '%s\n' "$rows" | grep -v "^${current_branch} " || true)"
fi
[ -n "$others" ] || exit 0

n_others="$(printf '%s\n' "$others" | grep -c . || true)"
echo "多波感知：另有 ${n_others} 個活躍 worktree——"
printf '%s\n' "$others" | awk '{printf "  %s（已改 %s 檔、未 commit %s、最後 commit %s %s）\n", $1, $2, $3, $4, $5}'

# 交集只在「全體 ≥2」時有意義（intersect 自己會處理 <2 的情況）
n_all="$(printf '%s\n' "$rows" | grep -c . || true)"
[ "$n_all" -ge 2 ] || exit 0

out="$(bash "$REGISTRY" intersect 2>/dev/null)"
rc=$?
if [ "$rc" -eq 1 ]; then
    # 只抽需裁定區塊：配對標題（有需裁定者）＋其下的檔案行
    printf '%s\n' "$out" | awk '
        /^════/      { hdr=$0; printed=0; inr=0 }
        /⚠️ 需裁定：/ { if (!printed) { sub(/：交集.*/, "", hdr); sub(/^════ /, "", hdr); print "  ⚠️ 需裁定交集（" hdr "）："; printed=1 }
                        inr=1; next }
        /^  可自動合併：/ { inr=0 }
        inr && /^    - / { print "  " $0 }
    '
    echo "  詳：bash ${REGISTRY} intersect"
fi
exit 0
