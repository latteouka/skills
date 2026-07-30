#!/usr/bin/env bash
# append-req-sync-skip-trailer.sh — 把 REQ_SYNC_SKIP="具體理由" 寫成 commit
# trailer `Req-Sync-Skip: <理由>`（吸收自 dfaa scripts/hooks/append-req-sync-skip-trailer.sh，K5）。
#
# 背景：上游實查曾有真行為變更誤用裸 REQ_SYNC_SKIP=1（無留痕）。
# require-requirements-sync.sh 已收緊為「裸 1／空白不算理由」，本 script 負責把
# 通過的具體理由寫進 commit trailer——讓 skip 變成「有記錄的自報」：收波稽核
# 可以 `git log --grep '^Req-Sync-Skip:'` 或 `git log --format=%(trailers:key=Req-Sync-Skip)`
# 一次掃完所有理由，唬爛會現形（gate 本身仍是提醒閘，不驗理由真偽）。
#
# 掛載點：prepare-commit-msg（$1 = 訊息檔路徑，git 標準傳參）。
# 為何用 prepare-commit-msg 而非 pre-commit：pre-commit 階段訊息檔還不存在
# （-m 尚未寫入、editor 尚未開啟），prepare-commit-msg 是第一個能改訊息內容的掛載點。
#
# [kit 吸收] 邏輯與上游逐位相同（無專案硬編碼，無需參數化）；僅頭註改記 kit 脈絡。
# bash 3.2 注意：一律 ${var} 形式。

set -u
set -o pipefail

msg_file="${1:-}"
[ -z "${msg_file}" ] && exit 0
[ -f "${msg_file}" ] || exit 0

skip_val="${REQ_SYNC_SKIP:-}"
[ -z "${skip_val}" ] && exit 0
[ "${skip_val}" = "1" ] && exit 0 # 裸值已停用；pre-commit 早已擋下，此處防禦性跳過

# amend／hook 重跑等情境避免重複寫入同一 trailer
grep -q "^Req-Sync-Skip:" "${msg_file}" 2>/dev/null && exit 0

# 確保訊息檔以換行結尾再接 trailer，讓新行與既有 Co-Authored-By/Claude-Session
# trailer 區塊相鄰（git interpret-trailers 認的是「結尾連續 Key: value 區塊」）
last_byte="$(tail -c1 "${msg_file}" 2>/dev/null)"
if [ -n "${last_byte}" ]; then
  printf '\n' >> "${msg_file}"
fi
printf 'Req-Sync-Skip: %s\n' "${skip_val}" >> "${msg_file}"
