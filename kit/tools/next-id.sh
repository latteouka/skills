#!/usr/bin/env bash
set -euo pipefail

# next-id.sh — 原子取號器（lockf/flock 互斥鎖）
#
# 用法：bash kit/tools/next-id.sh [--repo-root <path>] [--touch] <prefix>
#   prefix=B    → 掃 .claude/dev/backlog/B-*.md，輸出下一個 B-NNN
#   prefix=INB  → 掃 .claude/dev/inbox.md 的 INB-NNN high-water mark
#
# --repo-root：目標 repo 根目錄；未指定時用 git rev-parse --show-toplevel。
#（kit 吸收 seam：上游以 script 位置推導 ..，五支推導深度不一，統一參數化）

REPO_ROOT=""
if [ "${1:-}" = "--repo-root" ]; then
  REPO_ROOT="${2:?--repo-root 需要路徑}"
  shift 2
fi
TOUCH=false
if [ "${1:-}" = "--touch" ]; then
  TOUCH=true
  shift
fi
PREFIX="${1:?用法: next-id.sh [--repo-root <path>] [--touch] <B|INB>}"
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"

LOCK_FILE="${REPO_ROOT}/.claude/dev/.next-id.lock"

scan_max_B() {
  local max=0
  for f in "${REPO_ROOT}/.claude/dev/backlog"/B-*.md; do
    [ -f "$f" ] || continue
    local num
    num=$(basename "$f" .md | sed 's/^B-//')
    num=$((10#$num))
    [ "$num" -gt "$max" ] && max=$num
  done
  echo "$max"
}

scan_max_INB() {
  local max=0 num
  # 收集所有 INB-NNN 到一個 pipe（避免 process substitution）
  {
    grep -oE 'INB-[0-9]+' "${REPO_ROOT}/.claude/dev/inbox.md" 2>/dev/null || true
    # inbox.d 分片
    for f in "${REPO_ROOT}/.claude/dev/inbox.d"/*.md; do
      [ -f "$f" ] && grep -oE 'INB-[0-9]+' "$f" 2>/dev/null || true
    done
    # backlog/ 的 from 欄位引用
    for f in "${REPO_ROOT}/.claude/dev/backlog"/B-*.md; do
      [ -f "$f" ] && grep -aoE 'INB-[0-9]+' "$f" 2>/dev/null || true
    done
  } | sort -t- -k2 -n -u | while IFS= read -r id; do
    num=$(echo "$id" | sed 's/^INB-//')
    num=$((10#$num))
    [ "$num" -gt "$max" ] && max=$num
    echo "$max"
  done | tail -1

  # 如果 pipe 沒輸出（0 筆），fallback
}

scan_max() {
  local result
  case "$PREFIX" in
    B)   result=$(scan_max_B) ;;
    INB) result=$(scan_max_INB) ;;
  esac
  echo "${result:-0}"
}

do_allocate() {
  local max next new_id
  max=$(scan_max)
  next=$((max + 1))
  case "$PREFIX" in
    B)   new_id=$(printf 'B-%03d' "$next") ;;
    INB) new_id=$(printf 'INB-%03d' "$next") ;;
  esac
  # --touch: 在鎖內建佔位檔，防止並行取號 race
  if [ "$TOUCH" = "true" ] && [ "$PREFIX" = "B" ]; then
    printf -- '---\nid: %s\nstatus: "placeholder"\ncreated: %s\n---\n' \
      "$new_id" "$(date +%Y-%m-%d)" \
      > "${REPO_ROOT}/.claude/dev/backlog/${new_id}.md"
  fi
  echo "$new_id"
}

case "$PREFIX" in
  B|INB) ;;
  *)
    echo "ERROR: 不支援的 prefix '$PREFIX'（支援 B / INB）" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$LOCK_FILE")"

# 鎖策略：lockf (BSD/macOS) / flock (Linux) / mkdir fallback
if command -v lockf >/dev/null 2>&1; then
  # lockf -k 持鎖到 child 結束；用 bash（非 sh）以支援全功能
  # （REPO_ROOT 內嵌值來自上方 seam，--repo-root 參數化跟著生效）
  lockf -k "$LOCK_FILE" bash -c "
    set -euo pipefail
    REPO_ROOT='$REPO_ROOT'
    PREFIX='$PREFIX'
    TOUCH='$TOUCH'
    $(declare -f scan_max_B scan_max_INB scan_max do_allocate)
    do_allocate
  "
elif command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  flock -x 9
  do_allocate
else
  while ! mkdir "${LOCK_FILE}.d" 2>/dev/null; do sleep 0.05; done
  trap 'rmdir "${LOCK_FILE}.d" 2>/dev/null' EXIT
  do_allocate
fi
