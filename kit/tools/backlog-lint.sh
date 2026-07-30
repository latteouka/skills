#!/usr/bin/env bash
set -euo pipefail

# backlog-lint.sh — backlog/B-NNN.md frontmatter schema 驗證
#
# 檢查：
#   1. frontmatter 必要欄位齊全（id/type/pri/flow/status/matrix/created）
#   2. enum 合法（type/pri/flow/status prefix）
#   3. status=ready 必有 touches
#   4. status 以 done:/dropped: 開頭必有 ## proof 區塊且非空
#   5. id 與檔名一致
#   6. 無重複 id
#
# --repo-root <path>：目標 repo 根目錄；未指定時用 git rev-parse --show-toplevel

REPO_ROOT=""
if [ "${1:-}" = "--repo-root" ]; then
  REPO_ROOT="${2:?--repo-root 需要路徑}"
  shift 2
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG_DIR="${REPO_ROOT}/.claude/dev/backlog"

# python3 前置檢查（kit 版唯一行為修正）：上游把檢查 7 的 stderr 導 /dev/null，
# python3 未裝時 127 被吞掉，每檔都誤報「含非法 UTF-8」。缺就明講、exit 非 0。
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 未安裝——UTF-8 編碼驗證（檢查 7）需要 python3" >&2
  exit 1
fi

ERRORS=0
CHECKED=0

err() {
  echo "FAIL: $1" >&2
  ERRORS=$((ERRORS + 1))
}

# 重複 id 檢查（全域）
seen_ids=$(mktemp)
trap 'rm -f "$seen_ids"' EXIT

for f in "$BACKLOG_DIR"/B-*.md; do
  [ -f "$f" ] || continue
  CHECKED=$((CHECKED + 1))
  fname=$(basename "$f" .md)

  # 解析 frontmatter（--- 到 ---）
  in_fm=false
  fm_id="" fm_type="" fm_pri="" fm_flow="" fm_status="" fm_matrix="" fm_created=""
  fm_touches=false
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if $in_fm; then break; fi
      in_fm=true
      continue
    fi
    $in_fm || continue

    key=$(echo "$line" | LC_ALL=C sed -n 's/^\([a-z_]*\):.*/\1/p')
    val=$(echo "$line" | LC_ALL=C sed -n 's/^[a-z_]*: *//p' | LC_ALL=C sed 's/^"//;s/"$//')

    case "$key" in
      id)      fm_id="$val" ;;
      type)    fm_type="$val" ;;
      pri)     fm_pri="$val" ;;
      flow)    fm_flow="$val" ;;
      status)  fm_status="$val" ;;
      matrix)  fm_matrix="$val" ;;
      created) fm_created="$val" ;;
      touches) fm_touches=true ;;
    esac
  done < "$f"

  # 1. 必要欄位
  [ -z "$fm_id" ]      && err "$fname: 缺 id"
  [ -z "$fm_type" ]    && err "$fname: 缺 type"
  [ -z "$fm_pri" ]     && err "$fname: 缺 pri"
  [ -z "$fm_flow" ]    && err "$fname: 缺 flow"
  [ -z "$fm_status" ]  && err "$fname: 缺 status"
  [ -z "$fm_matrix" ]  && err "$fname: 缺 matrix"
  [ -z "$fm_created" ] && err "$fname: 缺 created"

  # 2. enum
  case "$fm_type" in
    BUG|NEW|CHORE|SPEC_CHANGE|"") ;;
    *) err "$fname: type '$fm_type' 不合法（BUG/NEW/CHORE/SPEC_CHANGE）" ;;
  esac

  case "$fm_pri" in
    P0|P1|P2|P3|P4|"") ;;
    *) err "$fname: pri '$fm_pri' 不合法（P0-P4）" ;;
  esac

  case "$fm_flow" in
    direct|spec|"") ;;
    *) err "$fname: flow '$fm_flow' 不合法（direct/spec）" ;;
  esac

  # status: ready / done:* / dropped:* / orphan-review / ⚠️需客戶確認 / placeholder
  case "$fm_status" in
    ready|orphan-review|placeholder|done) ;;
    done:*|dropped:*) ;;
    *需客戶確認*) ;;
    "") ;;
    *) err "$fname: status '$fm_status' 不合法" ;;
  esac

  # 3. ready 必有 touches
  if [ "$fm_status" = "ready" ] && ! $fm_touches; then
    err "$fname: status=ready 但缺 touches"
  fi

  # 4. done/dropped 必有 proof
  case "$fm_status" in
    done|done:*|dropped:*)
      proof_content=$(LC_ALL=C awk '/^## proof/{found=1; next} /^## /{if(found) exit} found && /[^ \t]/{print; exit}' "$f" 2>/dev/null || true)
      if [ -z "$proof_content" ]; then
        err "$fname: status=${fm_status} 但 ## proof 區塊為空"
      fi
      ;;
  esac

  # 5. id 與檔名一致
  if [ -n "$fm_id" ] && [ "$fm_id" != "$fname" ]; then
    err "$fname: id='$fm_id' 與檔名 '$fname' 不一致"
  fi

  # 6. 重複 id 檢查
  if [ -n "$fm_id" ]; then
    if grep -qxF "$fm_id" "$seen_ids" 2>/dev/null; then
      err "$fname: id='$fm_id' 重複"
    else
      echo "$fm_id" >> "$seen_ids"
    fi
  fi
done

# 7. UTF-8 編碼驗證（python3 strict decode，macOS iconv 有假陽性）
for f in "$BACKLOG_DIR"/B-*.md; do
  [ -f "$f" ] || continue
  if ! python3 -c "
import sys
with open(sys.argv[1], 'rb') as fh:
    fh.read().decode('utf-8')
" "$f" 2>/dev/null; then
    err "$(basename "$f" .md): 含非法 UTF-8 位元組"
  fi
done

echo "backlog-lint: 檢查 $CHECKED 個檔案，$ERRORS 個錯誤"

if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
echo "✅ backlog-lint PASS"
