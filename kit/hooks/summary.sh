#!/usr/bin/env bash
# SessionStart hook — intake 積壓摘要。
#
# 噪音紀律：無積壓則靜默；有積壓印「一行」（不是每項一行）。
# Claude Code 契約：SessionStart hook 的 stdout（exit 0）直接注入 context，
# 純文字即可，不需 JSON 包裝。
#
# settings.json 的 matcher 必須含 compact——context 壓縮後原注入內容會消失，
# 不重注入則長 session 後半段完全失去積壓感知。

set -u

KIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "${KIT_ROOT}/lib/common.sh" 2>/dev/null || exit 0

cat >/dev/null 2>&1 || true

root="$(kit_repo_root)" || exit 0
[ -n "$root" ] || exit 0
dev="${root}/.claude/dev"
[ -d "$dev" ] || exit 0

inbox_alert="$(kit_config_get inbox_alert 8)"
hot_limit="$(kit_config_get hot_zone_limit 20)"
stale_days="$(kit_config_get stale_days 60)"
case "$inbox_alert" in ''|*[!0-9]*) inbox_alert=8 ;; esac
case "$hot_limit"   in ''|*[!0-9]*) hot_limit=20 ;; esac
case "$stale_days"  in ''|*[!0-9]*) stale_days=60 ;; esac

parts=""
add_part() { if [ -n "$parts" ]; then parts="${parts}；$1"; else parts="$1"; fi }

# 未整理筆數（inbox.md 的 INB- 條目 ＋ inbox.d/ 分片的 CAP- 條目）
if [ -f "${dev}/inbox.md" ]; then
    n="$(grep -c '^## INB-' "${dev}/inbox.md" 2>/dev/null || echo 0)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    shard_n=0
    if [ -d "${dev}/inbox.d" ]; then
        shard_n="$(cat "${dev}/inbox.d"/*.md 2>/dev/null | grep -c '^## CAP-' || echo 0)"
        case "$shard_n" in ''|*[!0-9]*) shard_n=0 ;; esac
    fi
    total=$((n + shard_n))
    if [ "$total" -ge "$inbox_alert" ]; then
        if [ "$shard_n" -gt 0 ]; then
            add_part "收件匣 ${total} 筆未整理（含分片 ${shard_n} 筆；開波時會自動 triage，或手動 /triage）"
        else
            add_part "收件匣 ${total} 筆未整理（開波時會自動 triage，或手動 /triage）"
        fi
    fi
fi

# backlog stale 項
if [ -f "${dev}/backlog.md" ]; then
    stale="$(grep -c '| ready |' "${dev}/backlog.md" 2>/dev/null || echo 0)"
    case "$stale" in ''|*[!0-9]*) stale=0 ;; esac
    if [ "$stale" -gt 0 ]; then
        add_part "backlog ${stale} 項待排波"
    fi
fi

# 熱區檔數
hot="$(ls "${dev}"/*.md 2>/dev/null | wc -l | tr -d ' ')"
case "$hot" in ''|*[!0-9]*) hot=0 ;; esac
if [ "$hot" -gt "$hot_limit" ]; then
    add_part "熱區 ${hot} 檔超過上限 ${hot_limit}（歸檔未跟上）"
fi

[ -n "$parts" ] || exit 0
echo "Intake 摘要：${parts}。"
exit 0
