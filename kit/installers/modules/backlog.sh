#!/usr/bin/env bash
# modules/backlog.sh — 一筆一檔 backlog 機制安裝模組。
# 冪等：已存在的目錄／檔案／marker 段一律 skip 不覆寫，重跑 diff 零。
#
# 安裝內容：
#   1. .claude/dev/backlog/ 目錄 + INDEX.md（目錄索引模板）
#   2. kit/tools 五支可用性檢查（test -x 不實跑——空 backlog 目錄下
#      backlog-ls 的 B-*.md glob 無命中會讓 awk 開檔失敗非 0，實跑會誤報）
#   3. .husky/pre-commit 掛 backlog-lint marker 段（staged 有 backlog/ 改動才跑）
#
# 存量單檔 backlog.md 的專案：先跑 kit/tools/migrate-backlog-to-files.sh 遷移。

set -u

MODULE_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || { echo "找不到 lib/common.sh"; exit 1; }
. "${MODULE_DIR}/_shared.sh"  2>/dev/null || { echo "找不到 modules/_shared.sh"; exit 1; }

root="$(kit_repo_root)"
if [ -z "$root" ]; then echo "錯誤：不在 git repo 內，無法安裝。"; exit 1; fi

kit_module_begin

# --- 1. tools 五支可用性檢查（先驗環境再動手）
missing=""
for t in next-id backlog-ls backlog-retention migrate-backlog-to-files backlog-lint; do
    [ -x "${KIT_ROOT}/tools/${t}.sh" ] || missing="${missing} tools/${t}.sh"
done
if [ -n "$missing" ]; then
    echo "錯誤：kit tools 缺檔或不可執行：${missing}" >&2
    exit 1
fi

# --- 2. scaffold：backlog/ 目錄 + INDEX.md
kit_scaffold_dir  "${root}/.claude/dev/backlog" ".claude/dev/backlog/"
kit_scaffold_file "${KIT_ROOT}/templates/backlog/INDEX.md" \
                  "${root}/.claude/dev/backlog/INDEX.md" "backlog/INDEX.md"

# --- 3. pre-commit 掛 backlog-lint（marker 段，冪等）
hook_content="# backlog schema + 編碼驗證（staged 有 backlog/ 改動才跑）
if git diff --cached --name-only | grep -q '\\.claude/dev/backlog/'; then
  bash \"${KIT_ROOT}/tools/backlog-lint.sh\" || exit 1
fi"
kit_module_husky_marker "$root" "pre-commit" "backlog" "$hook_content"

kit_module_report "backlog"
exit 0
