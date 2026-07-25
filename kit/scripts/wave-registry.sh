#!/usr/bin/env bash
# wave-registry.sh — 多波並行的檔案交集偵測（無狀態，git 即 registry）。
#
#   wave-registry.sh list
#       所有活躍 worktree：branch、已改檔數（vs base）、未 commit 數、最後 commit 時間。
#
#   wave-registry.sh intersect [<id|branch> <id|branch>]
#       兩兩比對 `git diff --name-only <base>...HEAD` 的交集並分級。
#       不帶參數＝所有 worktree 兩兩比對；帶兩個參數＝只比那一對
#       （接受裸 id「foo」或完整 branch 名「worktree-foo」）。
#       exit 0＝無「需裁定」交集；exit 1＝有（可供 Phase 4 機器判斷）。
#
# 為什麼無狀態：原探索曾定位 registry 於 `.claude/worktrees/.registry/`，
# 但同時裁定「不宣告 scope——宣告會 drift，git diff 直接算得出實際改動」。
# 既然沒有任何宣告要落盤，就沒有目錄要建：branch 身分來自 `git worktree
# list`，改動集來自 diff，交集分級來自 merge-tree——全部即時計算，
# 不存在「registry 與現實不同步」這種狀態。
#
# 交集分級（判準＝「merge 時需不需要使用者裁定改法」）：
#   1. append-only 檔（wave-INDEX.md、*-ledger.md、inbox.md）→ 可自動合併。
#      這類檔 merge-tree 幾乎必報衝突（兩邊都在檔尾加行），但兩邊都是純
#      append、三秒可解，列「需裁定」只是噪音（2026-07-25 實測 41 處衝突
#      全是這種）。所以 allowlist 要在 merge-tree 之前判。
#   2. 其餘共同改動檔 → `git merge-tree --write-tree` 實際試合併：
#      git 能自動合（不同區域各自加行、各自新增獨立區塊）→ 可自動合併。
#      不用「行號區間重疊」之類的自製啟發式——merge-tree 就是 merge 當天
#      會發生的事，用它預演比任何近似都準。
#   3. merge-tree 衝突的檔再細分：
#      a. base 沒有這個檔（兩邊各自新建同名檔）→ 需裁定——內容是兩套
#         獨立實作，拼起來不見得是誰要的。
#      b. 兩邊 diff 皆純加行（無刪改 base 的行）→ 可自動合併——衝突只是
#         「都在同一位置 append」（設定檔尾端各自加行的典型樣態），
#         機械可解，列需裁定只是噪音。
#      c. 其餘（至少一邊改／刪了 base 的行）→ 需裁定——同一行／同段邏輯。
#
# 身分用 branch 名（worktree-<id>），不用 wave-*.md 檔名——實測兩個
# worktree 會同時帶著同一個 merge 帶進來的舊波檔，檔名身分會誤判。
#
# 需要 git >= 2.38（merge-tree --write-tree）；不支援時交集全列「需裁定
# （無法預演）」——寧可保守也不給假的「可自動合併」。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || {
    echo "wave-registry: 找不到 kit/lib/common.sh" >&2; exit 1; }

cmd="${1:-}"
case "$cmd" in
    list|intersect) shift ;;
    *) echo "用法: wave-registry.sh list | intersect [<id|branch> <id|branch>]" >&2; exit 2 ;;
esac

root="$(kit_main_repo_root)"
[ -n "$root" ] || { echo "wave-registry: 不在 git repo 內" >&2; exit 1; }

# base branch：main → master fallback
if git -C "$root" rev-parse --verify -q main >/dev/null 2>&1; then
    base=main
elif git -C "$root" rev-parse --verify -q master >/dev/null 2>&1; then
    base=master
else
    echo "wave-registry: 找不到 main/master 基準分支" >&2; exit 1
fi

# --- 收集 worktree（排除主 checkout；分隔符用 tab）---
# 輸出行：<path>\t<branch>
collect_worktrees() {
    git -C "$root" worktree list --porcelain | awk -v main="$root" '
        /^worktree /  { path=substr($0, 10) }
        /^branch /    { branch=substr($0, 8); sub("^refs/heads/", "", branch) }
        /^$/          { if (path != main && branch != "") printf "%s\t%s\n", path, branch
                        path=""; branch="" }
        END           { if (path != "" && path != main && branch != "")
                            printf "%s\t%s\n", path, branch }
    '
}

# --- resolve <id|branch> → branch 名（驗證存在）---
resolve_branch() {
    local q="$1"
    if git -C "$root" rev-parse --verify -q "refs/heads/$q" >/dev/null 2>&1; then
        printf '%s' "$q"; return 0
    fi
    if git -C "$root" rev-parse --verify -q "refs/heads/worktree-$q" >/dev/null 2>&1; then
        printf 'worktree-%s' "$q"; return 0
    fi
    return 1
}

# --- 某 branch 相對 base 的改動檔集合 ---
changed_files() {
    git -C "$root" diff --name-only "${base}...$1" 2>/dev/null | sort -u
}

if [ "$cmd" = list ]; then
    printf '%-36s %8s %8s  %s\n' BRANCH 已改檔 未commit 最後commit
    found=0
    while IFS="$(printf '\t')" read -r path branch; do
        [ -n "$branch" ] || continue
        found=1
        changed="$(changed_files "$branch" | grep -c . || true)"
        uncommitted="$(git -C "$path" status --porcelain 2>/dev/null | grep -c . || true)"
        last="$(git -C "$root" log -1 --format='%ad' --date=format:'%Y-%m-%d %H:%M' "$branch" 2>/dev/null)"
        printf '%-36s %8s %8s  %s\n' "$branch" "$changed" "$uncommitted" "${last:-?}"
    done <<EOF
$(collect_worktrees)
EOF
    [ "$found" -eq 1 ] || echo "（無活躍 worktree）"
    exit 0
fi

# ============ intersect ============

# 比對對象：兩個參數＝指定一對；否則全部 worktree branch
branches=""
if [ $# -eq 2 ]; then
    b1="$(resolve_branch "$1")" || { echo "wave-registry: 找不到 branch「$1」" >&2; exit 2; }
    b2="$(resolve_branch "$2")" || { echo "wave-registry: 找不到 branch「$2」" >&2; exit 2; }
    [ "$b1" = "$b2" ] && { echo "wave-registry: 兩個參數是同一條 branch" >&2; exit 2; }
    branches="$b1
$b2"
elif [ $# -eq 0 ]; then
    branches="$(collect_worktrees | cut -f2)"
else
    echo "用法: wave-registry.sh intersect [<id|branch> <id|branch>]" >&2; exit 2
fi

n="$(printf '%s\n' "$branches" | grep -c . || true)"
if [ "$n" -lt 2 ]; then
    echo "（活躍 worktree 少於 2 個，無交集可比）"
    exit 0
fi

merge_tree_ok=1
git -C "$root" merge-tree --write-tree "$base" "$base" >/dev/null 2>&1 || merge_tree_ok=0

is_append_only() {
    case "$(basename "$1")" in
        wave-INDEX.md|*-ledger.md|inbox.md) return 0 ;;
        *) return 1 ;;
    esac
}

# pure_addition <branch> <file> — 該 branch 對該檔的改動是否純加行
# （diff 無任何 `-` 開頭的內容行；`---` 檔頭除外）
pure_addition() {
    ! git -C "$root" diff "${base}...$1" -- "$2" 2>/dev/null \
        | grep '^-' | grep -qv '^---'
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

need_ruling_total=0
pair_count=0

# 兩兩配對（bash 3.2：無陣列切片，用行號迴圈）
i=1
while [ "$i" -le "$n" ]; do
    b1="$(printf '%s\n' "$branches" | sed -n "${i}p")"
    j=$((i + 1))
    while [ "$j" -le "$n" ]; do
        b2="$(printf '%s\n' "$branches" | sed -n "${j}p")"
        pair_count=$((pair_count + 1))

        changed_files "$b1" > "$tmpdir/f1"
        changed_files "$b2" > "$tmpdir/f2"
        comm -12 "$tmpdir/f1" "$tmpdir/f2" > "$tmpdir/common"

        if ! [ -s "$tmpdir/common" ]; then
            echo "════ ${b1} ✕ ${b2}：無交集"
            j=$((j + 1)); continue
        fi

        # merge-tree 預演：取衝突檔清單（首行是 tree oid，其後為衝突檔名）
        : > "$tmpdir/conflicts"
        if [ "$merge_tree_ok" -eq 1 ]; then
            git -C "$root" merge-tree --write-tree --name-only "$b1" "$b2" \
                2>/dev/null | tail -n +2 | sort -u > "$tmpdir/conflicts" || true
        fi

        auto=""
        ruling=""
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            if is_append_only "$f"; then
                auto="${auto}
    - ${f}（append-only）"
            elif [ "$merge_tree_ok" -eq 0 ]; then
                ruling="${ruling}
    - ${f}（git 過舊，無法 merge-tree 預演——保守列需裁定）"
            elif ! grep -qxF "$f" "$tmpdir/conflicts"; then
                auto="${auto}
    - ${f}（git 可自動合併）"
            elif ! git -C "$root" cat-file -e "${base}:${f}" 2>/dev/null; then
                ruling="${ruling}
    - ${f}（兩邊各自新建同名檔——兩套獨立實作）"
            elif pure_addition "$b1" "$f" && pure_addition "$b2" "$f"; then
                auto="${auto}
    - ${f}（兩邊皆純加行，衝突為相鄰 append，機械可解）"
            else
                ruling="${ruling}
    - ${f}（merge-tree 衝突——同一行／同段邏輯）"
            fi
        done < "$tmpdir/common"

        total="$(grep -c . "$tmpdir/common" || true)"
        echo "════ ${b1} ✕ ${b2}：交集 ${total} 檔"
        if [ -n "$auto" ]; then
            printf '  可自動合併：%s\n' "$auto"
        fi
        if [ -n "$ruling" ]; then
            printf '  ⚠️ 需裁定：%s\n' "$ruling"
            need_ruling_total=$((need_ruling_total + 1))
        fi
        j=$((j + 1))
    done
    i=$((i + 1))
done

if [ "$need_ruling_total" -gt 0 ]; then
    echo ""
    echo "⚠️ ${need_ruling_total}/${pair_count} 組配對有需裁定的交集（exit 1）。"
    exit 1
fi
exit 0
