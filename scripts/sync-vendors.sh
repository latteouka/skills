#!/usr/bin/env bash
# Sync vendored skills from their upstream repos (see vendors.conf).
#
# Usage:
#   scripts/sync-vendors.sh [check]         dry-run: 顯示上游更新與本地漂移，不寫入（預設）
#   scripts/sync-vendors.sh apply           實際同步：覆蓋本地成上游版本
#   scripts/sync-vendors.sh apply --force    連本地已改動的也覆蓋（危險）
#   scripts/sync-vendors.sh <mode> --only NAME   只處理某一個 skill
#
# 安全設計：
#   - 預設 check（dry-run），要寫入必須明打 apply
#   - vendors.lock 記錄上次同步的 (上游 SHA + 本地內容 hash)。apply 前若偵測到
#     本地內容 hash 與 lock 不符 = 你手動改過 → 跳過該項並警告，除非 --force
#   - apply 後請 git diff 審查再 commit

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$ROOT/vendors.conf"
LOCK="$ROOT/vendors.lock"

MODE="check"
FORCE=false
ONLY=""
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[i]}" in
    check|apply) MODE="${args[i]}" ;;
    --force)     FORCE=true ;;
    --only)      ONLY="${args[i+1]:-}"; ((i++)) ;;
    *) echo "未知參數：${args[i]}"; exit 1 ;;
  esac
done

command -v rsync >/dev/null || { echo "需要 rsync"; exit 1; }
command -v shasum >/dev/null || { echo "需要 shasum"; exit 1; }
[[ -f "$CONF" ]] || { echo "找不到 $CONF"; exit 1; }
touch "$LOCK"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 內容 hash：進到目錄、用相對路徑列檔，對「檔名+內容」整體取單一 sha256
content_hash() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "MISSING"; return; }
  ( cd "$dir" && find . -type f -not -path './.git/*' | LC_ALL=C sort \
      | xargs shasum -a 256 2>/dev/null | shasum -a 256 | awk '{print $1}' )
}

lock_get() { awk -F' *\\| *' -v n="$1" '$1==n{print $2"|"$3}' "$LOCK"; }
lock_set() {
  local name="$1" sha="$2" hash="$3" tmp="$TMP/lock.new"
  grep -v -E "^[[:space:]]*$name[[:space:]]*\|" "$LOCK" 2>/dev/null > "$tmp" || true
  echo "$name | $sha | $hash" >> "$tmp"
  LC_ALL=C sort "$tmp" -o "$tmp"
  mv "$tmp" "$LOCK"
}

# 每個 repo 只 clone 一次（trailofbits 三個共用；用目錄存在與否判斷，免關聯陣列）
clone_repo() {
  local url="$1" ref="$2" slug dst
  slug="$(echo "$url" | shasum -a 256 | awk '{print $1}')"
  dst="$TMP/$slug"
  if [[ ! -d "$dst/.git" ]]; then
    git clone --quiet --depth 1 --branch "$ref" "$url" "$dst" 2>/dev/null \
      || { echo "  ✗ clone 失敗：$url ($ref)"; return 1; }
  fi
  echo "$dst"
}

echo "模式：$MODE${FORCE:+ }$([[ $FORCE == true ]] && echo '(--force)')${ONLY:+  只處理 $ONLY}"
echo "════════════════════════════════════════"

changed=0; drifted=0; synced=0; uptodate=0

while IFS= read -r line; do
  line="${line%%#*}"
  [[ -z "${line// }" ]] && continue
  IFS='|' read -r name url ref subpath <<< "$line"
  name="$(echo "$name" | xargs)"; url="$(echo "$url" | xargs)"
  ref="$(echo "$ref" | xargs)"; subpath="$(echo "$subpath" | xargs)"
  [[ -n "$ONLY" && "$name" != "$ONLY" ]] && continue

  local_dir="$ROOT/$name"
  clone="$(clone_repo "$url" "$ref")" || { continue; }
  up_dir="$clone/$subpath"
  up_sha="$(git -C "$clone" rev-parse HEAD)"
  [[ -d "$up_dir" ]] || { echo "✗ ${name}：上游子路徑不存在 $subpath"; continue; }

  # 比對上游 vs 本地
  up_hash="$( content_hash "$up_dir" )"
  local_hash="$( content_hash "$local_dir" )"
  IFS='|' read -r lock_sha lock_hash <<< "$(lock_get "$name")"

  if [[ "$up_hash" == "$local_hash" ]]; then
    echo "✓ $name  已是最新（${up_sha}）"
    ((uptodate++)); [[ "$MODE" == apply ]] && lock_set "$name" "$up_sha" "$up_hash"
    continue
  fi

  ((changed++))
  # 本地漂移偵測：lock 有紀錄且本地 hash 與 lock 不符 = 被人改過
  local_modified=false
  if [[ -n "${lock_hash:-}" && "$local_hash" != "$lock_hash" && "$local_hash" != "MISSING" ]]; then
    local_modified=true
  fi

  # 上游變更檔案摘要
  diff_summary="$(diff -qr "$local_dir" "$up_dir" 2>/dev/null \
    | sed 's,'"$up_dir"',<上游>,; s,'"$local_dir"',<本地>,' | head -12 || true)"

  echo "△ $name  有更新（上游 ${up_sha}）"
  [[ "$local_modified" == true ]] && echo "   ⚠ 本地曾手動修改（hash 與 lock 不符）"
  [[ -n "$diff_summary" ]] && echo "$diff_summary" | sed 's/^/     /'

  if [[ "$MODE" == apply ]]; then
    if [[ "$local_modified" == true && "$FORCE" != true ]]; then
      echo "   ↳ 跳過（本地有改動；要強蓋加 --force）"; ((drifted++)); continue
    fi
    rsync -a --delete --exclude='.git' "$up_dir/" "$local_dir/"
    new_hash="$( content_hash "$local_dir" )"
    lock_set "$name" "$up_sha" "$new_hash"
    echo "   ↳ 已同步 → $up_sha"; ((synced++))
  fi
done < "$CONF"

echo "════════════════════════════════════════"
if [[ "$MODE" == apply ]]; then
  echo "同步 ${synced}／最新 ${uptodate}／跳過(本地改動) $drifted"
  [[ "$synced" -gt 0 ]] && echo "→ 請 git diff 審查後 commit"
else
  echo "有更新 ${changed}／最新 ${uptodate}。實際套用：scripts/sync-vendors.sh apply"
fi
