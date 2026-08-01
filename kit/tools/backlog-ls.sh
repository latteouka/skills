#!/usr/bin/env bash
set -euo pipefail

# backlog-ls.sh — backlog/ 查詢 API（awk 批次，250 檔 <1 秒）
#
# 用法：
#   bash kit/tools/backlog-ls.sh                    # 全部項
#   bash kit/tools/backlog-ls.sh --status ready      # 按 status 篩選（prefix match: done 包含 done:xxx）
#   bash kit/tools/backlog-ls.sh --type BUG          # 按 type 篩選
#   bash kit/tools/backlog-ls.sh --pri P0            # 按 pri 篩選
#   bash kit/tools/backlog-ls.sh --status ready --count  # 只輸出數字
#   --repo-root <path>：目標 repo 根目錄；未指定時用 git rev-parse --show-toplevel

REPO_ROOT=""
FILTER_STATUS=""
FILTER_TYPE=""
FILTER_PRI=""
COUNT_ONLY=false

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --status) FILTER_STATUS="$2"; shift 2 ;;
    --type)   FILTER_TYPE="$2"; shift 2 ;;
    --pri)    FILTER_PRI="$2"; shift 2 ;;
    --count)  COUNT_ONLY=true; shift ;;
    *) echo "ERROR: 未知參數 '$1'" >&2; exit 1 ;;
  esac
done

[ -n "$REPO_ROOT" ] || REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG_DIR="${REPO_ROOT}/.claude/dev/backlog"

# 空 backlog：glob 不展開時 awk 會收到字面 B-*.md 路徑而 exit 2——先短路回 0 筆
if ! compgen -G "${BACKLOG_DIR}/B-*.md" > /dev/null; then
  if [ "$COUNT_ONLY" = "true" ]; then echo 0; else printf '\n共 0 筆\n'; fi
  exit 0
fi

# 用 awk 一次掃描所有檔案，提取 frontmatter 欄位
LC_ALL=C awk -v fstatus="$FILTER_STATUS" -v ftype="$FILTER_TYPE" -v fpri="$FILTER_PRI" -v count_only="$COUNT_ONLY" '
BEGIN {
  n = 0
  in_fm = 0
}

FNR == 1 {
  # 新檔案開始
  if (id != "" && in_fm_done) {
    process()
  }
  in_fm = 0; in_fm_done = 0
  id = ""; type = ""; pri = ""; flow = ""; status = ""; summary = ""
}

/^---$/ {
  if (!in_fm) { in_fm = 1; next }
  if (in_fm) { in_fm_done = 1; in_fm = 0; next }
}

in_fm && /^id: / { gsub(/^id: *"?|"?$/, ""); id = $0; next }
in_fm && /^type: / { gsub(/^type: *"?|"?$/, ""); type = $0; next }
in_fm && /^pri: / { gsub(/^pri: *"?|"?$/, ""); pri = $0; next }
in_fm && /^flow: / { gsub(/^flow: *"?|"?$/, ""); flow = $0; next }
in_fm && /^status: / { gsub(/^status: *"?|"?$/, ""); status = $0; next }

in_fm_done && /^# / && summary == "" {
  sub(/^# /, "")
  summary = substr($0, 1, 60)
}

function process() {
  # 篩選
  if (fstatus != "") {
    if (status != fstatus && index(status, fstatus ":") != 1) return
  }
  if (ftype != "" && type != ftype) return
  if (fpri != "" && pri != fpri) return

  n++
  if (count_only != "true") {
    printf "| %-7s | %-12s | %-3s | %-6s | %-25s | %s\n", id, type, pri, flow, status, summary
  }
}

END {
  if (id != "" && in_fm_done) process()
  if (count_only == "true") {
    print n
  } else {
    printf "\n共 %d 筆\n", n
  }
}
' "$BACKLOG_DIR"/B-*.md
