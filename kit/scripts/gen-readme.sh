#!/usr/bin/env bash
# 生成 .claude/dev/README.md — 機制索引，回答「這專案有哪些東西」。
# 自動生成，不手寫（手寫必過期）。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

root="$(kit_repo_root)" || exit 0
[ -n "$root" ] || exit 0
dev="${root}/.claude/dev"
[ -d "$dev" ] || exit 0

out="${dev}/README.md"
tmp="$(mktemp)"

{
    printf '# .claude/dev 機制索引\n\n'
    printf '> 由 kit/scripts/gen-readme.sh 自動生成，勿手動編輯。\n\n'

    printf '## 熱區檔案\n\n| 檔案 | 狀態／用途 |\n|---|---|\n'
    for f in "$dev"/*.md; do
        [ -f "$f" ] || continue
        b="$(basename "$f")"
        case "$b" in README.md) continue ;; esac
        status_text="$(kit_fm_get "$f" status)"
        if [ -n "$status_text" ]; then
            desc="wave ($status_text)"
        else
            desc="$(grep -m1 '^> ' "$f" 2>/dev/null | cut -c3-60)"
            [ -n "$desc" ] || desc="$(grep -m1 '^# ' "$f" 2>/dev/null | cut -c3-60)"
            [ -n "$desc" ] || desc="-"
        fi
        printf '| `%s` | %s |\n' "$b" "$desc"
    done

    printf '\n## 已安裝的 Claude Code hook\n\n'
    if [ -f "${root}/.claude/settings.json" ] && command -v jq >/dev/null 2>&1; then
        printf '| 事件 | 指令 |\n|---|---|\n'
        jq -r '.hooks // {} | to_entries[] | .key as $e | .value[]?
               | (.hooks // [])[]? | "| \($e) | \(.command // "?") |"' \
            "${root}/.claude/settings.json" 2>/dev/null | sed 's|/Users/[^/]*/|~/|g'
    else
        printf '（無 settings.json 或缺 jq）\n'
    fi

    printf '\n## pre-commit 閘門\n\n'
    if [ -f "${root}/.husky/pre-commit" ]; then
        grep -oE '[a-zA-Z0-9_/.-]+\.sh' "${root}/.husky/pre-commit" 2>/dev/null \
            | sort -u | sed 's/^/- `/; s/$/`/'
    else
        printf '（無 .husky/pre-commit）\n'
    fi

    printf '\n## 歷史索引\n\n'
    if [ -f "${dev}/wave-INDEX.md" ]; then
        # 計算 INDEX 中資料列數（複合條件：表格行 + 取回指令）
        # 單一條件失效情境：
        # - git show 出現在說明文字（多算）
        # - ^| 匹配表頭（多算）
        # - 分隔線無法完全排除（結構差異）
        # 必須同時要求「行首為 | 」與「含 git show」才能精確識別資料列
        count="$(grep -c '^|.*git show' "${dev}/wave-INDEX.md" 2>/dev/null || echo 0)"
        if [ "$count" -gt 0 ]; then
            printf '已刪除 %d 個完成的波。\n\n' "$count"
            printf '內容存於 `wave-INDEX.md`；各波取回指令已記錄在該檔案的「取回」欄。\n\n'
            printf '例：`git show <hash>:<path>` 還原某波的內容。\n'
        else
            printf '（尚無歸檔）\n'
        fi
    else
        printf '（尚無歸檔）\n'
    fi
} > "$tmp"

# 內容無變化則不覆寫（避免每個 turn 都製造 git 噪音）
if [ -f "$out" ] && cmp -s "$tmp" "$out"; then
    rm -f "$tmp"
    exit 0
fi
mv "$tmp" "$out"
exit 0
