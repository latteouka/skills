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

# 鎖與 claims 一律放 git common-dir——同 repo 的所有 worktree/checkout 共用，
# 否則各 worktree 各自持鎖＝互斥失效（0803 實證：B-391/396/398 三度撞號，
# 手動 checkout 與 supervisor mat-wt 並行取到同號）。非 git repo 時退回原路徑。
GIT_COMMON="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [ -n "$GIT_COMMON" ] && [ -d "$GIT_COMMON" ]; then
  LOCK_FILE="${GIT_COMMON}/.next-id.lock"
  CLAIMS_FILE="${GIT_COMMON}/.next-id-claims"
else
  LOCK_FILE="${REPO_ROOT}/.claude/dev/.next-id.lock"
  CLAIMS_FILE="${REPO_ROOT}/.claude/dev/.next-id-claims"
fi

scan_max_B() {
  local max=0 num
  # 本地檔
  for f in "${REPO_ROOT}/.claude/dev/backlog"/B-*.md; do
    [ -f "$f" ] || continue
    num=$(basename "$f" .md | sed 's/^B-//')
    num=$((10#$num))
    [ "$num" -gt "$max" ] && max=$num
  done
  # origin/main tree（fetch best-effort——別的 checkout 已 push 的號）
  git -C "$REPO_ROOT" fetch -q origin 2>/dev/null || true
  while IFS= read -r name; do
    num=$(printf '%s' "$name" | sed -e 's/^B-//' -e 's/\.md$//')
    case "$num" in *[!0-9]*|'') continue ;; esac
    num=$((10#$num))
    [ "$num" -gt "$max" ] && max=$num
  done <<EOF_TREE
$(git -C "$REPO_ROOT" ls-tree --name-only origin/main:.claude/dev/backlog 2>/dev/null | grep -E '^B-[0-9]+\.md$' || true)
EOF_TREE
  # claims 帳（同機其他 checkout 已取號但未 push 的）
  if [ -f "$CLAIMS_FILE" ]; then
    while IFS= read -r line; do
      case "$line" in B\ *) num="${line#B }" ;; *) continue ;; esac
      num="${num%% *}"
      case "$num" in *[!0-9]*|'') continue ;; esac
      num=$((10#$num))
      [ "$num" -gt "$max" ] && max=$num
    done < "$CLAIMS_FILE"
  fi
  echo "$max"
}

scan_max_INB() {
  local max=0 num
  # 收集所有 INB-NNN 到一個 pipe（避免 process substitution）
  {
    grep -oE 'INB-[0-9]+' "${REPO_ROOT}/.claude/dev/inbox.md" 2>/dev/null || true
    # origin/main 版 inbox（別的 checkout 已 push 的號；fetch 已在 scan_max_B 做過，
    # INB 單獨呼叫時自行 fetch）
    git -C "$REPO_ROOT" fetch -q origin 2>/dev/null || true
    git -C "$REPO_ROOT" show origin/main:.claude/dev/inbox.md 2>/dev/null | grep -oE 'INB-[0-9]+' || true
    # claims 帳
    [ -f "$CLAIMS_FILE" ] && grep -E '^INB ' "$CLAIMS_FILE" 2>/dev/null | sed 's/^INB /INB-/' | cut -d' ' -f1 || true
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
  # claims 帳：鎖內記下取走的號（含時間戳），同機他 checkout 掃得到——
  # 未 push 前的跨 checkout race 由此關閉；7 天前的舊 claim 順手清
  {
    [ -f "$CLAIMS_FILE" ] && awk -v cutoff="$(( $(date +%s) - 604800 ))" \
      '{ if ($3+0 >= cutoff) print }' "$CLAIMS_FILE" 2>/dev/null || true
    printf '%s %s %s\n' "$PREFIX" "$next" "$(date +%s)"
  } > "${CLAIMS_FILE}.tmp" && mv "${CLAIMS_FILE}.tmp" "$CLAIMS_FILE"
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
    CLAIMS_FILE='$CLAIMS_FILE'
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
