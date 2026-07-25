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
# 安全守衛（2026-07-25 補）：光是「repo 有 HEAD」不代表「這個檔案」真的已
# 提交——gitignore 掉、剛建立還沒 commit、或已提交但有未提交的修改，這三種
# 情況「取回指令」都拿不回真正該還的內容（git show 對未提交過的路徑直接
# fatal；有未提交修改的檔案只能拿回舊版，未提交那部分永久消失且無警告）。
# 因此每個要刪的檔都必須先驗證①在算出的 commit 存在②相對 HEAD 沒有未提交
# 的修改，任一檔不符就整個波跳過不刪。git rm 失敗時也不 fallback 到 rm -f
# ——git 拒絕刪除就代表有異常，應該停手而不是照刪。
#
# 順序關鍵：先讀內容萃取摘要、算好取回指令；守衛通過、確認刪除成功後，
# 才寫 INDEX——避免刪除失敗時留下「INDEX 說已歸檔，檔案其實還在」的孤兒
# 記錄（冪等檢查看 INDEX 有沒有這行，孤兒記錄會讓該波永遠不再被重試）。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

cat >/dev/null 2>&1 || true

root="$(kit_repo_root)" || exit 0
[ -n "$root" ] || exit 0
dev="${root}/.claude/dev"
[ -d "$dev" ] || exit 0

# wave-*.md 的掃描／刪除留在「目前所在」的 checkout（worktree 或主
# checkout）——波檔物理上就在那裡完成，git rm 也該對那個 repo 的檔案動手。
# 但 wave-INDEX.md 是跨 worktree 共用的單一歷史，不能各自寫一份（否則各
# worktree 各自累積、merge 時互相蓋掉對方獨有的取回紀錄；2026-07-25 實測：
# dfaa 主 checkout + 3 worktree，wave-INDEX.md 各處 157/157/157/6 行，已
# 分裂到無法合併）。因此 INDEX 檔本體與保護它的鎖都改落在主 checkout；
# 若主 checkout 不可用（不存在／非 git repo／缺 .claude/dev），fail-open
# 退回用目前 checkout 自己的 dev（維持舊行為，不中斷功能）。
main_root="$(kit_main_repo_root)"
[ -n "$main_root" ] || main_root="$root"
main_dev="${main_root}/.claude/dev"
[ -d "$main_dev" ] || { main_root="$root"; main_dev="$dev"; }

after_days="$(kit_config_get archive_after_days 7)"
case "$after_days" in ''|*[!0-9]*) after_days=7 ;; esac

# 取 N 天前的日期（BSD date 與 GNU date 兩種語法）
cutoff="$(date -v-"${after_days}"d '+%Y-%m-%d' 2>/dev/null \
    || date -d "${after_days} days ago" '+%Y-%m-%d' 2>/dev/null)" || exit 0
[ -n "$cutoff" ] || exit 0

index="${main_dev}/wave-INDEX.md"
if [ ! -f "$index" ]; then
    {
        printf '# Wave 歷史索引\n\n'
        printf '> 由 kit/hooks/archive.sh 自動維護。原檔已刪除；內容仍在 git history，用「取回」欄的指令可還原。\n\n'
        printf '| wave | 期間 | 一句話結果 | 取回 |\n'
        printf '|---|---|---|---|\n'
    } > "$index"
fi

# 加鎖：避免並發時重複寫 INDEX / 重複刪（鎖落在主 checkout，跨 worktree
# 同時觸發 Stop hook 時也能正確互斥，不會兩邊同時搶寫同一份 INDEX）
lockdir="${main_dev}/.archive.lock"
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

    # 形狀合法不等於曆法合法——2026-01-99、2026-02-30 這種值形狀對但日期不存在。
    # BSD 與 GNU 的 date 對超出範圍的日期常常不是直接失敗，而是靜默進位成
    # 別的合法日期（如 2026-02-30 → 2026-03-02，exit code 仍是 0）。
    # 因此不能只看 exit code：把解析結果轉回同格式跟原字串逐字比對，
    # 對不上就代表原輸入不是真實存在的日期——不合法就跳過，不冒險刪檔。
    parsed_closed="$(date -j -f '%Y-%m-%d' "$closed" +%Y-%m-%d 2>/dev/null)"
    [ -n "$parsed_closed" ] || parsed_closed="$(date -d "$closed" +%Y-%m-%d 2>/dev/null)"
    [ "$parsed_closed" = "$closed" ] || continue

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

    # 安全守衛：每個要刪的檔都必須①在 $hash（此刻的 HEAD）已提交
    # ②相對 HEAD 沒有未提交的修改。任一檔不符就整個波跳過——不冒險刪掉
    # 「取回指令救不回」的內容。
    safe=1
    for rf in "${files_to_remove[@]}"; do
        rel="$(rel_path "$rf")"
        if ! git -C "$root" cat-file -e "${hash}:${rel}" 2>/dev/null; then
            safe=0; break
        fi
        if ! git -C "$root" diff --quiet HEAD -- "$rf" 2>/dev/null; then
            safe=0; break
        fi
    done
    [ "$safe" -eq 1 ] || continue

    # 逐一 git rm；沒有 rm -f 兜底——上面的守衛已確保正常情況下 git rm 一定
    # 成功，萬一仍失敗（權限異常等）就整個波跳過，不留半刪狀態。
    rm_ok=1
    for rf in "${files_to_remove[@]}"; do
        git -C "$root" rm -q -- "$rf" 2>/dev/null || { rm_ok=0; break; }
    done
    [ "$rm_ok" -eq 1 ] || continue

    # 確認全部刪除成功後才寫 INDEX——避免刪除失敗留下孤兒索引行
    printf '| %s | %s~%s | %s | %s |\n' \
        "$wave_id" "$opened" "$closed" "$summary" "$retrieve_cmds" >> "$index"
    removed=$((removed + 1))
done

kit_lock_release "$lockdir"
trap - EXIT

[ "$removed" -gt 0 ] && echo "已清除 ${removed} 個完成的波（wave-INDEX.md 已記錄取回指令）。"

# 熱區檔名清單有變動才重生 README（快照比對，避免每 turn 改檔）
snapshot="${dev}/.readme-snapshot"
current="$(ls "${dev}"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | sort | tr '\n' ' ')"
if [ ! -f "$snapshot" ] || [ "$current" != "$(cat "$snapshot" 2>/dev/null)" ]; then
    printf '%s' "$current" > "$snapshot"
    bash "${KIT_ROOT}/scripts/gen-readme.sh" 2>/dev/null || true
fi

exit 0
