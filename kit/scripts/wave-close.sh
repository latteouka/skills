#!/usr/bin/env bash
# wave-close.sh <wave-id> [--dry-run] — 波收尾時當場清除自己的產物。
#
# 為什麼是「當場清除」而不是「標記等 hook 歸檔」：
#   舊設計要求收尾時寫 frontmatter（status/closed），交由 Stop hook 的
#   archive.sh 在 N 天後刪除。實測 2026-07-25：dfaa 有 52 個 wave-*.md，
#   **0 個有 frontmatter**——包含當天剛完成、走完整流程且收尾稽核 VERIFIED
#   的 5 個波。條文寫得再明確（原文「這不是格式建議，是歸檔機制能否辨識
#   本波的前提」）也沒有被執行，於是熱區只增不減。
#
#   把「寫一段 YAML 給未來的 hook 讀」換成「呼叫一個指令當場刪」，消掉了
#   兩個失敗點：①收尾者要記得寫、且格式要對 ②hook 要在 N 天後正確觸發。
#   archive.sh 仍保留，角色降為漏網補救（處理沒跑本腳本的殘留）。
#
# 安全設計（與 archive.sh 同源，刪除前一律先確保能取回）：
#   1. 每個要刪的檔必須①在目前 HEAD 已提交 ②相對 HEAD 無未提交修改；
#      任一不符 → 整個波中止（未提交的內容 git show 救不回來）。
#   2. 取回指令先算好，確認刪除全數成功後才寫 INDEX——順序顛倒會留下
#      「INDEX 說已清除、檔案其實還在」的孤兒記錄。
#   3. 用 git rm 不用 rm：git 拒絕刪除代表有異常，該停手而不是照刪。
#   4. --dry-run 只印計畫、不動檔。
#
# INDEX 落在主 checkout（非目前 worktree）——它是跨 worktree 共用的單一
# 歷史，各自寫一份會在 merge 時互相蓋掉（2026-07-25 實測已分裂成
# 157/157/157/6 行）。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || {
    echo "wave-close: 找不到 kit/lib/common.sh" >&2; exit 1; }

wave_id=""
dry_run=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        -*) echo "wave-close: 未知選項 $arg" >&2; exit 2 ;;
        *)  if [ -n "$wave_id" ]; then
                echo "wave-close: 只接受一個 wave-id" >&2; exit 2
            fi
            wave_id="$arg" ;;
    esac
done

[ -n "$wave_id" ] || { echo "用法: wave-close.sh <wave-id> [--dry-run]" >&2; exit 2; }

root="$(kit_repo_root)"
[ -n "$root" ] || { echo "wave-close: 不在 git repo 內" >&2; exit 1; }
dev="${root}/.claude/dev"
[ -d "$dev" ] || { echo "wave-close: 找不到 ${dev}" >&2; exit 1; }

dash="${dev}/wave-${wave_id}.md"
[ -f "$dash" ] || { echo "wave-close: 找不到 ${dash}" >&2; exit 1; }

main_root="$(kit_main_repo_root)"
[ -n "$main_root" ] || main_root="$root"
main_dev="${main_root}/.claude/dev"
[ -d "$main_dev" ] || { main_root="$root"; main_dev="$dev"; }

hash="$(git -C "$root" rev-parse HEAD 2>/dev/null)"
[ -n "$hash" ] || {
    echo "wave-close: 取不到 HEAD——無 commit 歷史就給不出取回指令，不刪。" >&2; exit 1; }

rel_path() { printf '%s' "${1#"$root"/}"; }

# --- 收集本波產物：dashboard + ledger + 同 wave_id 的 spec/plan ---
files="$dash"
ledger="${dev}/wave-${wave_id}-ledger.md"
[ -f "$ledger" ] && files="${files}
${ledger}"

for specdir in "${root}/docs/superpowers/specs" "${root}/docs/superpowers/plans" "${root}/docs/plans"; do
    [ -d "$specdir" ] || continue
    for sf in "$specdir"/*.md; do
        [ -f "$sf" ] || continue
        [ "$(kit_fm_get "$sf" wave_id)" = "$wave_id" ] || continue
        files="${files}
${sf}"
    done
done

# --- 安全守衛：全部必須已提交且無未提交修改，否則整波中止 ---
blocked=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="$(rel_path "$f")"
    if ! git -C "$root" cat-file -e "${hash}:${rel}" 2>/dev/null; then
        blocked="${blocked}
  - ${rel}（尚未提交——git show 取不回）"
    elif ! git -C "$root" diff --quiet HEAD -- "$f" 2>/dev/null; then
        blocked="${blocked}
  - ${rel}（有未提交的修改——會永久遺失）"
    fi
done <<EOF
$files
EOF

if [ -n "$blocked" ]; then
    echo "wave-close: 中止，以下檔案無法安全取回：${blocked}" >&2
    echo "先 commit 這些檔案再跑一次。" >&2
    exit 1
fi

# --- 摘要與取回指令（刪除前萃取）---
#
# 優先取狀態行（`## 狀態：` 或 `**狀態**:`）——那是波的一句話結果，正是
# INDEX 想留下的東西。退而求其次才取首個內容段落；後者常常是 Metadata 的
# 「涉及檔案/目錄」，對日後查閱幾乎沒有價值（archive.sh 的舊行為即如此）。
summary="$(grep -m1 '^## 狀態' "$dash" 2>/dev/null | sed 's/^## 狀態[:：][[:space:]]*//')"
[ -n "$summary" ] || summary="$(grep -m1 '^\*\*狀態\*\*' "$dash" 2>/dev/null | sed 's/^\*\*狀態\*\*[:：][[:space:]]*//')"
[ -n "$summary" ] || summary="$(sed -n '/^---$/,/^---$/!p' "$dash" \
    | grep -v '^#' | grep -v '^[[:space:]]*$' | sed -n '1p')"
# 表格分隔字元會破壞 INDEX 的欄位結構，換成全形
summary="$(printf '%s' "$summary" | tr '|' '｜' | cut -c1-100)"
[ -n "$summary" ] || summary="（無摘要）"

opened="$(kit_fm_get "$dash" opened)"
[ -n "$opened" ] || opened="$(head -1 "$dash" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)"
[ -n "$opened" ] || opened="$(git -C "$root" log --diff-filter=A --format=%ad --date=short -1 -- "$dash" 2>/dev/null)"
[ -n "$opened" ] || opened="?"
closed="$(date '+%Y-%m-%d')"

retrieve=""
count=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count + 1))
    [ -n "$retrieve" ] && retrieve="${retrieve}、"
    retrieve="${retrieve}\`git show ${hash}:$(rel_path "$f")\`"
done <<EOF
$files
EOF

if [ "$dry_run" -eq 1 ]; then
    echo "wave-close --dry-run: 將清除 ${count} 個檔案"
    while IFS= read -r f; do
        [ -n "$f" ] && echo "  - $(rel_path "$f")"
    done <<EOF
$files
EOF
    echo "INDEX 將寫入 ${main_dev}/wave-INDEX.md："
    echo "  | ${wave_id} | ${opened}~${closed} | ${summary} | …取回指令…（${count} 條）|"
    exit 0
fi

# --- 加鎖（與 archive.sh 同一把，避免同時寫 INDEX）---
lockdir="${main_dev}/.archive.lock"
kit_lock_acquire "$lockdir" || { echo "wave-close: 取鎖失敗，稍後再試。" >&2; exit 1; }
trap "kit_lock_release '$lockdir'" EXIT

index="${main_dev}/wave-INDEX.md"
if [ ! -f "$index" ]; then
    {
        printf '# Wave 歷史索引\n\n'
        printf '> 原檔已刪除；內容仍在 git history，用「取回」欄的指令可還原。\n\n'
        printf '| wave | 期間 | 一句話結果 | 取回 |\n'
        printf '|---|---|---|---|\n'
    } > "$index"
fi

if grep -q "| ${wave_id} |" "$index" 2>/dev/null; then
    echo "wave-close: ${wave_id} 已在 INDEX，跳過（冪等）。"
    exit 0
fi

# --- 刪除；任一失敗就停手，不留半刪狀態 ---
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! git -C "$root" rm -q -- "$f" 2>/dev/null; then
        echo "wave-close: git rm 失敗於 $(rel_path "$f")，已停手（可能有未預期狀態）。" >&2
        exit 1
    fi
done <<EOF
$files
EOF

# --- 全部刪除成功後才寫 INDEX ---
printf '| %s | %s~%s | %s | %s |\n' \
    "$wave_id" "$opened" "$closed" "$summary" "$retrieve" >> "$index"

kit_lock_release "$lockdir"
trap - EXIT

echo "wave-close: 已清除 ${count} 個檔案，取回指令寫入 ${index#"$main_root"/}"
while IFS= read -r f; do
    [ -n "$f" ] && echo "  - $(rel_path "$f")"
done <<EOF
$files
EOF
echo "記得把 INDEX 與刪除一起 commit。"
exit 0
