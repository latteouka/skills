#!/usr/bin/env bash
set -euo pipefail

# backlog-retention.sh — done/dropped 保留期清理 + ready 過期標記
#
# 用法：
#   bash kit/tools/backlog-retention.sh --dry-run    # 列出候選，不動手
#   bash kit/tools/backlog-retention.sh --apply       # 真跑 git rm + INDEX 取回指令
#   --repo-root <path>：目標 repo 根目錄；未指定時用 git rev-parse --show-toplevel
#
# 規則：
#   done/dropped + closed 超過 retention_days → git rm（git history 即封存）
#   ready + created 超過 stale_days → 只標 STALE 提醒，不刪
#
# 讀 .claude/dev/intake.config.yaml 的 retention_days（預設 30）和 stale_days（已有 60）

REPO_ROOT=""
if [ "${1:-}" = "--repo-root" ]; then
  REPO_ROOT="${2:?--repo-root 需要路徑}"
  shift 2
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG_DIR="${REPO_ROOT}/.claude/dev/backlog"
CONFIG="${REPO_ROOT}/.claude/dev/intake.config.yaml"
INDEX="${REPO_ROOT}/.claude/dev/wave-INDEX.md"

MODE="${1:?用法: [--repo-root <path>] --dry-run | --apply}"

# 讀 config
retention_days=30
stale_days=60
if [ -f "$CONFIG" ]; then
  rd=$(grep '^retention_days:' "$CONFIG" 2>/dev/null | awk '{print $2}' || true)
  sd=$(grep '^stale_days:' "$CONFIG" 2>/dev/null | awk '{print $2}' || true)
  case "$rd" in ''|*[!0-9]*) ;; *) retention_days=$rd ;; esac
  case "$sd" in ''|*[!0-9]*) ;; *) stale_days=$sd ;; esac
fi

echo "retention_days=$retention_days, stale_days=$stale_days"

today=$(date +%s)

date_to_epoch() {
  # macOS date -j -f vs GNU date -d
  if date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null; then
    return
  fi
  date -d "$1" +%s 2>/dev/null || echo 0
}

days_since() {
  local d
  d=$(date_to_epoch "$1")
  if [ "$d" -eq 0 ]; then
    echo 999999
    return
  fi
  echo $(( (today - d) / 86400 ))
}

to_remove=()
stale_items=()

for f in "$BACKLOG_DIR"/B-*.md; do
  [ -f "$f" ] || continue
  fname=$(basename "$f" .md)

  # 快速抽取 frontmatter 欄位
  status=$(LC_ALL=C grep -am1 '^status:' "$f" 2>/dev/null | LC_ALL=C sed 's/^status: *"*//;s/"*$//' || true)
  closed=$(LC_ALL=C grep -am1 '^closed:' "$f" 2>/dev/null | LC_ALL=C sed 's/^closed: *//' || true)
  created=$(LC_ALL=C grep -am1 '^created:' "$f" 2>/dev/null | LC_ALL=C sed 's/^created: *//' || true)

  case "$status" in
    done*|dropped*)
      if [ -n "$closed" ]; then
        age=$(days_since "$closed")
        if [ "$age" -gt "$retention_days" ]; then
          to_remove+=("$fname|$status|$closed|${age}d")
        fi
      fi
      ;;
    ready)
      if [ -n "$created" ]; then
        age=$(days_since "$created")
        if [ "$age" -gt "$stale_days" ]; then
          stale_items+=("$fname|${age}d since created")
        fi
      fi
      ;;
  esac
done

echo ""
echo "=== 過期清理候選（done/dropped + closed > ${retention_days}d）==="
if [ ${#to_remove[@]} -eq 0 ]; then
  echo "（無）"
else
  for item in "${to_remove[@]}"; do
    echo "  $item"
  done
  echo "共 ${#to_remove[@]} 筆"
fi

echo ""
echo "=== Stale 標記（ready + created > ${stale_days}d）==="
if [ ${#stale_items[@]} -eq 0 ]; then
  echo "（無）"
else
  for item in "${stale_items[@]}"; do
    echo "  STALE: $item"
  done
fi

if [ "$MODE" = "--dry-run" ]; then
  echo ""
  echo "（乾跑模式，不動手。用 --apply 執行清理。）"
  exit 0
fi

if [ "$MODE" != "--apply" ]; then
  echo "ERROR: 未知模式 '$MODE'（--dry-run | --apply）" >&2
  exit 1
fi

if [ ${#to_remove[@]} -eq 0 ]; then
  echo ""
  echo "無需清理。"
  exit 0
fi

echo ""
echo "=== 執行清理 ==="
for item in "${to_remove[@]}"; do
  fname=$(echo "$item" | cut -d'|' -f1)
  fpath=".claude/dev/backlog/${fname}.md"
  commit_hash=$(git log -1 --format='%h' -- "$fpath" 2>/dev/null || echo "unknown")
  git rm -q "$fpath"
  echo "  git rm $fpath (取回: git show ${commit_hash}:${fpath})"

  # 寫取回指令到 INDEX
  if [ -f "$INDEX" ]; then
    echo "- \`git show ${commit_hash}:${fpath}\` — ${fname} (retention cleanup $(date +%Y-%m-%d))" >> "$INDEX"
  fi
done

echo ""
echo "已清理 ${#to_remove[@]} 筆。取回指令已寫入 wave-INDEX.md。"
echo "請 commit: git commit -m 'chore(backlog): retention cleanup'"
