#!/usr/bin/env bash
# Stop hook — 清除已完成的波（不是搬移，是刪除 + 索引留一行可回溯的指令）。
#
# 只處理「frontmatter 明確標 status: done 且 closed 早於 archive_after_days」者。
# 無 frontmatter 的舊檔一律不動（交由一次性大掃除人工裁決）——自動化不碰
# 判斷不了的東西，是這套機制敢跑在 Stop hook 上的前提。
#
# 2026-07-25 起改為刪除（非搬移到 archive/）：archive 目錄只是把堆積換個
# 位置，一年後又是幾百檔。刪除前把「取回指令」（git show <hash>:<path>）
# 寫進 wave-INDEX.md，需要時複製貼上即可拿回內容——git history 本身就是備份。
#
# 用 git rm 不用 rm：資料仍留在 git history，且刪除必先有可用的 commit hash
# 才會動手（沒有 commit 歷史 = 無法回溯 = 不刪，安全第一）。
#
# 順序關鍵：先讀內容萃取摘要、算好取回指令、寫進 INDEX，最後才刪檔。
# 順序顛倒會得到只有檔名沒有內容的索引。

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
        printf '> 由 kit/hooks/archive.sh 自動維護。原檔已刪除；內容仍在 git history，用「取回」欄的指令可還原。\n\n'
        printf '| wave | 期間 | 一句話結果 | 取回 |\n'
        printf '|---|---|---|---|\n'
    } > "$index"
fi

# 加鎖：避免並發時重複寫 INDEX / 重複刪
lockdir="${dev}/.archive.lock"
if ! kit_lock_acquire "$lockdir"; then
    exit 0
fi
trap "kit_lock_release '$lockdir'" EXIT

# rel_path <絕對路徑> — 轉成相對 repo root 的路徑，供 git show <hash>:<path> 用
rel_path() {
    printf '%s' "${1#"$root"/}"
}

removed=0
for f in "${dev}"/wave-*.md; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in wave-INDEX.md) continue ;; esac
    case "$base" in *-ledger.md) continue ;; esac   # ledger 隨其 dashboard 一起處理

    # 驗證該檔有合法的 frontmatter（成對 --- ）再進行
    first="$(sed -n '1p' "$f")"
    [ "$first" = "---" ] || continue
    if ! sed -n '2,$p' "$f" | grep -q '^---$'; then
        continue
    fi

    status="$(kit_fm_get "$f" status)"
    [ "$status" = "done" ] || continue

    closed="$(kit_fm_get "$f" closed)"
    [ -n "$closed" ] || continue

    # 驗證 closed 的日期格式（YYYY-MM-DD）
    case "$closed" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) continue ;;
    esac

    # 字典序比較對 YYYY-MM-DD 等價於時間序
    [ "$closed" \< "$cutoff" ] || continue

    wave_id="$(kit_fm_get "$f" wave_id)"
    [ -n "$wave_id" ] || wave_id="$(printf '%s' "$base" | sed 's/^wave-//; s/\.md$//')"

    # 已在 INDEX 就不重複（冪等）
    if grep -q "| ${wave_id} |" "$index" 2>/dev/null; then continue; fi

    # 沒有 commit 歷史就無法提供取回指令——寧可不刪，也不留下刪不回的檔
    hash="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
    [ -n "$hash" ] || continue

    opened="$(kit_fm_get "$f" opened)"
    [ -n "$opened" ] || opened="?"

    # 摘要取內文第一個非空、非標題、非 frontmatter 的段落首行（刪除前萃取）
    summary="$(sed -n '/^---$/,/^---$/!p' "$f" \
        | grep -v '^#' \
        | grep -v '^[[:space:]]*$' \
        | sed -n '1p' \
        | cut -c1-80)"
    [ -n "$summary" ] || summary="（無摘要）"

    # 收集本波要一併刪除的檔案：dashboard 本身 + ledger + 同 wave_id 的 spec/plan
    files_to_remove=("$f")
    retrieve_cmds="\`git show ${hash}:$(rel_path "$f")\`"

    ledger="${dev}/wave-${wave_id}-ledger.md"
    if [ -f "$ledger" ]; then
        files_to_remove+=("$ledger")
        retrieve_cmds="${retrieve_cmds}、\`git show ${hash}:$(rel_path "$ledger")\`"
    fi

    for specdir in "${root}/docs/superpowers/specs" "${root}/docs/superpowers/plans" "${root}/docs/plans"; do
        [ -d "$specdir" ] || continue
        for sf in "$specdir"/*.md; do
            [ -f "$sf" ] || continue
            sf_wave="$(kit_fm_get "$sf" wave_id)"
            [ -n "$sf_wave" ] || continue
            [ "$sf_wave" = "$wave_id" ] || continue
            files_to_remove+=("$sf")
            retrieve_cmds="${retrieve_cmds}、\`git show ${hash}:$(rel_path "$sf")\`"
        done
    done

    # 先寫 INDEX，後刪檔——順序不可顛倒（刪完就讀不到內文摘要了）
    printf '| %s | %s~%s | %s | %s |\n' \
        "$wave_id" "$opened" "$closed" "$summary" "$retrieve_cmds" >> "$index"

    for rf in "${files_to_remove[@]}"; do
        git -C "$root" rm -q -- "$rf" 2>/dev/null || rm -f "$rf" 2>/dev/null
    done
    removed=$((removed + 1))
done

kit_lock_release "$lockdir"
trap - EXIT

[ "$removed" -gt 0 ] && echo "已清除 ${removed} 個完成的波（wave-INDEX.md 已記錄取回指令）。"
exit 0
