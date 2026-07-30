#!/usr/bin/env bash
set -euo pipefail

# migrate-backlog-to-files.sh — backlog.md → backlog/B-NNN.md 一筆一檔
#
# 用法：
#   bash kit/tools/migrate-backlog-to-files.sh --dry-run /tmp/backlog-dry   # 乾跑到暫存目錄
#   bash kit/tools/migrate-backlog-to-files.sh                              # 真跑到 .claude/dev/backlog/
#   --repo-root <path>：目標 repo 根目錄；未指定時用 git rev-parse --show-toplevel

REPO_ROOT=""
if [ "${1:-}" = "--repo-root" ]; then
  REPO_ROOT="${2:?--repo-root 需要路徑}"
  shift 2
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG_MD="${REPO_ROOT}/.claude/dev/backlog.md"

DRY_RUN=false
OUT_DIR="${REPO_ROOT}/.claude/dev/backlog"

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  OUT_DIR="${2:?用法: --dry-run <output-dir>}"
  shift 2
fi

if [ ! -f "$BACKLOG_MD" ]; then
  echo "ERROR: $BACKLOG_MD 不存在" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ── Phase 1: 解析表格 ──────────────────────────────────────────────

TABLE_DIR="$WORK_DIR/table"
mkdir -p "$TABLE_DIR"

table_count=0
while IFS= read -r line; do
  # 跳過表頭和分隔列
  case "$line" in
    '| id |'*|'|---|'*) continue ;;
  esac

  # 解析 pipe-delimited 欄位
  bid=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
  btype=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
  bpri=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $4); print $4}')
  bflow=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $5); print $5}')
  bmatrix=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6}')
  bstatus=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $7); print $7}')
  bsummary=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $8); print $8}')

  case "$bid" in
    B-[0-9]*) ;;
    *) continue ;;
  esac

  mkdir -p "$TABLE_DIR/$bid"
  printf '%s\n' "$btype" > "$TABLE_DIR/$bid/type"
  printf '%s\n' "$bpri" > "$TABLE_DIR/$bid/pri"
  printf '%s\n' "$bflow" > "$TABLE_DIR/$bid/flow"
  printf '%s\n' "$bmatrix" > "$TABLE_DIR/$bid/matrix"
  printf '%s\n' "$bstatus" > "$TABLE_DIR/$bid/status"
  printf '%s\n' "$bsummary" > "$TABLE_DIR/$bid/summary"
  table_count=$((table_count + 1))
done < <(grep -E '^\| B-[0-9]+ \|' "$BACKLOG_MD")

echo "表列解析完成：$table_count 筆"

# ── Phase 2: 解析明細區 ─────────────────────────────────────────────

DETAIL_DIR="$WORK_DIR/detail"
mkdir -p "$DETAIL_DIR"

detail_count=0
current_id=""
current_file=""

while IFS= read -r line; do
  if [[ "$line" =~ ^###\ (B-[0-9]+) ]]; then
    current_id="${BASH_REMATCH[1]}"
    current_file="$DETAIL_DIR/${current_id}.md"
    detail_count=$((detail_count + 1))
    # 清空或建立檔案（不寫 heading 本身）
    : > "$current_file"
    continue
  fi

  # 遇到 ## 層級標題，結束當前明細（不停止解析，因為有多個 ## 區）
  if [[ "$line" =~ ^##\  ]] && [ -n "$current_id" ]; then
    current_id=""
    current_file=""
    continue
  fi

  # 累積內容
  if [ -n "$current_file" ]; then
    printf '%s\n' "$line" >> "$current_file"
  fi
done < "$BACKLOG_MD"

echo "明細解析完成：$detail_count 筆"

# ── Phase 3: 合併並產出檔案 ──────────────────────────────────────────

# 收集所有 unique IDs
{
  ls "$TABLE_DIR" 2>/dev/null
  ls "$DETAIL_DIR" 2>/dev/null | sed 's/\.md$//'
} | sort -t- -k2 -n -u > "$WORK_DIR/all_ids.txt"

total_unique=$(wc -l < "$WORK_DIR/all_ids.txt" | tr -d ' ')
both_count=0
table_only_count=0
detail_only_count=0
file_count=0

extract_closed_date() {
  local status_val="$1"
  local body_file="$2"
  local date=""

  # 從 status 欄位抓日期 (2026-MM-DD)
  if [[ "$status_val" =~ \(([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
    date="${BASH_REMATCH[1]}"
  fi

  # 從 body 抓 ✅ 行的日期（全形括號）
  if [ -z "$date" ] && [ -f "$body_file" ]; then
    date=$(grep -oE '（([0-9]{4}-[0-9]{2}-[0-9]{2})）' "$body_file" 2>/dev/null | head -1 | tr -d '（）')
  fi

  # 從 body 抓半形括號日期
  if [ -z "$date" ] && [ -f "$body_file" ]; then
    date=$(grep -oE '\(([0-9]{4}-[0-9]{2}-[0-9]{2})\)' "$body_file" 2>/dev/null | head -1 | tr -d '()')
  fi

  # fallback: 遷移日期
  if [ -z "$date" ]; then
    date="2026-07-29"
  fi

  echo "$date"
}

extract_from() {
  local body_file="$1"
  if [ -f "$body_file" ]; then
    grep -m1 '^\- \*\*from\*\*:' "$body_file" 2>/dev/null | sed 's/^- \*\*from\*\*: *//' || true
  fi
}

extract_touches() {
  local body_file="$1"
  if [ -f "$body_file" ]; then
    grep -m1 '^\- \*\*touches\*\*:' "$body_file" 2>/dev/null | sed 's/^- \*\*touches\*\*: *//' || true
  fi
}

while IFS= read -r bid; do
  has_table=false
  has_detail=false
  source_type=""

  [ -d "$TABLE_DIR/$bid" ] && has_table=true
  [ -f "$DETAIL_DIR/${bid}.md" ] && has_detail=true

  if $has_table && $has_detail; then
    source_type="both"
    both_count=$((both_count + 1))
  elif $has_table; then
    source_type="table-only"
    table_only_count=$((table_only_count + 1))
  else
    source_type="detail-only"
    detail_only_count=$((detail_only_count + 1))
  fi

  # ── 讀取表格欄位（有表列時）──
  if $has_table; then
    btype=$(cat "$TABLE_DIR/$bid/type")
    bpri=$(cat "$TABLE_DIR/$bid/pri")
    bflow=$(cat "$TABLE_DIR/$bid/flow")
    bmatrix=$(cat "$TABLE_DIR/$bid/matrix")
    bstatus=$(cat "$TABLE_DIR/$bid/status")
    bsummary=$(cat "$TABLE_DIR/$bid/summary")
  else
    # orphan：推測 type/pri/flow from body，或用預設值
    btype="CHORE"
    bpri="P4"
    bflow="direct"
    bmatrix="—"
    bstatus="orphan-review"
    bsummary=""
    # 嘗試從 body 第一行非空行取摘要
    if [ -f "$DETAIL_DIR/${bid}.md" ]; then
      _raw=$(sed -n '/\S/{s/^- \*\*[a-z]*\*\*: *//;p;q;}' "$DETAIL_DIR/${bid}.md" 2>/dev/null || true)
      bsummary="${_raw:0:200}"
    fi
  fi

  # ── orphan 處理：保留原 status 到 notes ──
  orphan_note=""
  if [ "$source_type" = "detail-only" ]; then
    orphan_note="無對應表列"
    bstatus="orphan-review"
  fi

  # ── closed 日期（done/dropped 才有）──
  closed_line=""
  case "$bstatus" in
    done:*|dropped:*)
      detail_file="$DETAIL_DIR/${bid}.md"
      closed_date=$(extract_closed_date "$bstatus" "$detail_file")
      closed_line="closed: $closed_date"
      ;;
  esac

  # ── from 欄位 ──
  from_val=""
  if [ -f "$DETAIL_DIR/${bid}.md" ]; then
    from_val=$(extract_from "$DETAIL_DIR/${bid}.md")
  fi

  # ── touches 欄位（表格有時用 body 的 touches）──
  touches_val=""
  if [ -f "$DETAIL_DIR/${bid}.md" ]; then
    touches_val=$(extract_touches "$DETAIL_DIR/${bid}.md")
  fi

  # ── 清理 matrix 特殊字元（YAML 安全）──
  safe_matrix=$(printf '%s' "$bmatrix" | sed 's/"/\\"/g')

  # ── 產出檔案 ──
  outfile="$OUT_DIR/${bid}.md"
  {
    echo "---"
    echo "id: $bid"
    echo "type: $btype"
    echo "pri: $bpri"
    echo "flow: $bflow"
    printf 'status: "%s"\n' "$bstatus"
    printf 'matrix: "%s"\n' "$safe_matrix"
    if [ -n "$closed_line" ]; then
      echo "$closed_line"
    fi
    if [ -n "$from_val" ]; then
      _escaped_from=$(printf '%s' "$from_val" | sed 's/"/\\"/g')
      printf 'from: "%s"\n' "${_escaped_from:0:500}"
    fi
    if [ -n "$touches_val" ] && [ "$bstatus" = "ready" ]; then
      echo "touches:"
      # 簡化：把 touches 當一行文字存
      printf '  - "%s"\n' "$(printf '%s' "$touches_val" | sed 's/"/\\"/g')"
    fi
    echo "created: 2026-07-29"
    echo "source: $source_type"
    echo "---"
    echo ""

    # summary 作為一級標題
    if [ -n "$bsummary" ]; then
      echo "# $bsummary"
      echo ""
    fi

    # evidence / notes / proof 區塊
    if $has_detail; then
      # 讀 body 內容，分出結構化區塊
      body_file="$DETAIL_DIR/${bid}.md"

      # 先輸出 evidence（從 body 中所有 **evidence** 行收集）
      echo "## evidence"
      grep -i '^\- \*\*evidence\*\*:' "$body_file" 2>/dev/null | sed 's/^- \*\*evidence\*\*: *//' || true
      echo ""

      # proof
      echo "## proof"
      proof_lines=""
      proof_lines=$(grep -i '^\- \*\*proof\*\*:' "$body_file" 2>/dev/null | sed 's/^- \*\*proof\*\*: *//' || true)
      done_lines=$(grep '^\- \*\*✅' "$body_file" 2>/dev/null || true)
      if [ -n "$proof_lines" ]; then
        echo "$proof_lines"
      fi
      if [ -n "$done_lines" ]; then
        echo "$done_lines"
      fi
      # done/dropped 且 proof 為空→回填 —
      if [ -z "$proof_lines" ] && [ -z "$done_lines" ]; then
        case "$bstatus" in
          done*|dropped*) echo "—" ;;
        esac
      fi
      echo ""

      # notes：剩餘所有內容
      echo "## notes"
      if [ "$source_type" = "detail-only" ]; then
        echo "[orphan] ${orphan_note} (待 triage 裁決)"
        echo ""
      fi
      # 輸出 body 中非 evidence/proof/from/touches/matrix 的行
      grep -v -E '^\- \*\*(evidence|proof|from|touches|matrix|✅|wave|repro)\*\*:' "$body_file" 2>/dev/null | \
        sed '/^$/{ N; /^\n$/d; }' || true
    else
      # table-only：空區塊
      echo "## evidence"
      echo ""
      echo "## proof"
      case "$bstatus" in
        done*|dropped*) echo "—" ;;
      esac
      echo ""
      echo "## notes"
      echo "[table-only] 僅有表列記錄，無明細內容。"
    fi
  } > "$outfile"

  # NEL (U+0085, UTF-8: C2 85) → LF，確保 grep 正常
  # 注意：perl -CS 的 \x{0085} 匹配 Unicode codepoint U+0085（C2 85），
  # 但實測會誤劈中文字中的 0x85 continuation byte。改用精確匹配 C2 85 兩位元組。
  LC_ALL=C perl -i -0777 -pe 's/\xc2\x85/\n/g' "$outfile" 2>/dev/null || true

  file_count=$((file_count + 1))
done < "$WORK_DIR/all_ids.txt"

# ── Phase 4: 守恆對帳 ──────────────────────────────────────────────

echo ""
echo "════════════════════════════════════════════"
echo "  守恆對帳表"
echo "════════════════════════════════════════════"
echo "  表列 unique ID:     $table_count"
echo "  明細 unique ID:     $detail_count"
echo "  ─────────────────────────"
echo "  both（表列＋明細）: $both_count"
echo "  table-only:         $table_only_count"
echo "  detail-only:        $detail_only_count"
echo "  ─────────────────────────"
echo "  合併後 unique ID:   $total_unique"
echo "  產出檔案數:         $file_count"
echo "  差異:               $((total_unique - file_count))"
echo "════════════════════════════════════════════"

if [ "$total_unique" -ne "$file_count" ]; then
  echo "ERROR: 守恆對帳失敗！unique ID ($total_unique) ≠ 檔案數 ($file_count)" >&2
  exit 1
fi

echo ""
if $DRY_RUN; then
  echo "✅ 乾跑完成，檔案在 $OUT_DIR"
else
  echo "✅ 遷移完成，檔案在 $OUT_DIR"
fi
