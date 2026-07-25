#!/usr/bin/env bash
# Stop hook — 自動歸檔已完成的波。
#
# 只處理「frontmatter 明確標 status: done 且 closed 早於 archive_after_days」者。
# 無 frontmatter 的舊檔一律不動（交由一次性大掃除人工裁決）——自動化不碰
# 判斷不了的東西，是這套機制敢跑在 Stop hook 上的前提。
#
# 用 git mv 不用 mv：保留 rename 歷史，且誤動可 git checkout 還原。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

cat >/dev/null 2>&1 || true

root="$(kit_repo_root)" || exit 0
[ -n "$root" ] || exit 0
dev="${root}/.claude/dev"
[ -d "$dev" ] || exit 0

after_days="$(kit_config_get archive_after_days 7)"
case "$after_days" in ''|*[!0-9]*) after_days=7 ;; esac

# 取 N 天前的日期（BSD date 與 GNU date 兩種語法）
cutoff="$(date -v-"${after_days}"d '+%Y-%m-%d' 2>/dev/null \
    || date -d "${after_days} days ago" '+%Y-%m-%d' 2>/dev/null)" || exit 0
[ -n "$cutoff" ] || exit 0

index="${dev}/wave-INDEX.md"
if [ ! -f "$index" ]; then
    {
        printf '# Wave 歷史索引\n\n'
        printf '> 由 kit/hooks/archive.sh 自動維護。原檔在 archive/{年月}/。\n\n'
        printf '| wave | 期間 | 一句話結果 | 檔案 |\n'
        printf '|---|---|---|---|\n'
    } > "$index"
fi

moved=0
for f in "${dev}"/wave-*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in wave-INDEX.md) continue ;; esac
    case "$base" in *-ledger.md) continue ;; esac   # ledger 隨其 dashboard 一起搬

    status="$(kit_fm_get "$f" status)"
    [ "$status" = "done" ] || continue

    closed="$(kit_fm_get "$f" closed)"
    [ -n "$closed" ] || continue
    # 字典序比較對 YYYY-MM-DD 等價於時間序
    [ "$closed" \< "$cutoff" ] || continue

    wave_id="$(kit_fm_get "$f" wave_id)"
    [ -n "$wave_id" ] || wave_id="$(printf '%s' "$base" | sed 's/^wave-//; s/\.md$//')"

    # 已在 INDEX 就不重複（冪等）
    if grep -q "| ${wave_id} |" "$index" 2>/dev/null; then continue; fi

    month="$(printf '%s' "$closed" | cut -c1-7)"
    destdir="${dev}/archive/${month}"
    mkdir -p "$destdir"

    opened="$(kit_fm_get "$f" opened)"
    [ -n "$opened" ] || opened="?"

    # 摘要取內文第一個非空、非標題、非 frontmatter 的段落首行
    summary="$(sed -n '/^---$/,/^---$/!p' "$f" \
        | grep -v '^#' \
        | grep -v '^[[:space:]]*$' \
        | sed -n '1p' \
        | cut -c1-80)"
    [ -n "$summary" ] || summary="（無摘要）"

    printf '| %s | %s~%s | %s | archive/%s/ |\n' \
        "$wave_id" "$opened" "$closed" "$summary" "$month" >> "$index"

    git -C "$root" mv "$f" "${destdir}/${base}" 2>/dev/null || mv "$f" "${destdir}/${base}"
    ledger="${dev}/wave-${wave_id}-ledger.md"
    if [ -f "$ledger" ]; then
        git -C "$root" mv "$ledger" "${destdir}/$(basename "$ledger")" 2>/dev/null \
            || mv "$ledger" "${destdir}/$(basename "$ledger")"
    fi
    moved=$((moved + 1))
done

[ "$moved" -gt 0 ] && echo "已歸檔 ${moved} 個完成的波至 archive/（wave-INDEX.md 已更新）。"
exit 0
