#!/usr/bin/env bash
# hook-wiring-check.sh — hook 接線存活檢查（eng-guards 接線驗證教訓，2026-07-26）
#
# 母題：canary 驗「gate 邏輯對不對」，本檢查驗「gate 有沒有真的被掛上」——
# eng-guards 波實證：worktree 裡改 settings.json 不生效、.husky 改了沒 push
# 就沒跑到，五條 gate 的 canary 全綠但整個 session 零接線觸發。
# 同族前例：pathspec-liveness.sh（pathspec 恆 0 命中的 8 天假 PASS）。
#
# 檢查兩個註冊面（fail-closed，任一缺失 exit 1 並具名）：
#   1. .claude/settings.json 所有 command 型 hook → 路徑存在且可執行
#      （${CLAUDE_PROJECT_DIR} 展開為 repo 根；repo 外絕對路徑照驗存在性）
#   2. .husky/* 引用的 *.sh → 存在且可執行（相對路徑以 repo 根與 hook 檔內
#      「cd <目錄>」自動發現的基準解析——上游 dfaa 硬編碼 apps/web 的通用化：
#      其 pre-push 首行 cd apps/web，引用寫法兩種都有）
#
# kit 通用化 seam：--repo-root <path>（預設 git rev-parse --show-toplevel）。
# 測試用 override：--settings <path> / --husky-dir <path>（canary 餵 fixture）。
# 輸出 inspected:N（N=實際檢查的引用數，防假 PASS）；inspected:0 自身紅。
# jq 缺席明確報「jq 未裝」exit 1——不得誤報成 settings.json 非法 JSON。

set -u
set -o pipefail

repo_root=""
settings_file=""
husky_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --settings) settings_file="$2"; shift 2 ;;
    --husky-dir) husky_dir="$2"; shift 2 ;;
    *) echo "hook-wiring-check: 未知參數 $1" >&2; exit 1 ;;
  esac
done

if [ -z "${repo_root}" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "❌ hook-wiring-check: 不在 git repo 內且未給 --repo-root" >&2
    exit 1
  }
fi
project_root="${repo_root}"

[ -n "${settings_file}" ] || settings_file="${project_root}/.claude/settings.json"
[ -n "${husky_dir}" ] || husky_dir="${project_root}/.husky"

inspected=0
missing=""

check_path() {
  # $1=來源標籤 $2=原始引用 $3...=候選絕對路徑（任一存在即過）
  local label="$1" ref="$2"
  shift 2
  inspected=$((inspected + 1))
  local p
  for p in "$@"; do
    if [ -f "$p" ]; then
      if [ ! -x "$p" ]; then
        missing="${missing}\n  ${label}: ${ref}（存在但不可執行——chmod +x）"
      fi
      return 0
    fi
  done
  missing="${missing}\n  ${label}: ${ref}（檔案不存在）"
}

# --- 1. settings.json 的 command 型 hook ---
if [ -f "${settings_file}" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ hook-wiring-check: jq 未裝——無法解析 ${settings_file}（先安裝 jq）" >&2
    exit 1
  fi
  if ! jq empty "${settings_file}" 2>/dev/null; then
    echo "❌ hook-wiring-check: ${settings_file} 不是合法 JSON" >&2
    exit 1
  fi
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    # 去引號、展開 ${CLAUDE_PROJECT_DIR}
    cleaned="$(printf '%s' "$cmd" | sed -e 's/"//g' -e "s|\${CLAUDE_PROJECT_DIR}|${project_root}|g")"
    check_path "settings.json" "$cmd" "$cleaned"
  done << EOF
$(jq -r '.hooks // {} | to_entries[].value[] | .hooks[]? | select(.type=="command") | .command' "${settings_file}" 2>/dev/null)
EOF
fi

# --- 2. .husky 引用的 shell scripts ---
if [ -d "${husky_dir}" ]; then
  for hf in "${husky_dir}"/*; do
    [ -f "$hf" ] || continue
    hf_name="$(basename "$hf")"
    # 自動發現 hook 檔內的 cd 目標作為額外解析基準（取代上游硬編碼 apps/web）
    cd_bases="$(grep -vE '^[[:space:]]*#' "$hf" | grep -ohE '(^|[[:space:];&|])cd[[:space:]]+[A-Za-z0-9_./-]+' | sed -E 's/^[[:space:];&|]?cd[[:space:]]+//' | sort -u)"
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      norm="${ref#../../}"
      candidates=("${project_root}/${norm}")
      while IFS= read -r base; do
        [ -z "$base" ] && continue
        candidates=("${candidates[@]}" "${project_root}/${base}/${norm}")
      done << EOF_BASES
${cd_bases}
EOF_BASES
      check_path ".husky/${hf_name}" "$ref" "${candidates[@]}"
    done << EOF
$(grep -vE '^[[:space:]]*#' "$hf" | grep -ohE '[A-Za-z0-9_./-]+\.sh' | sort -u)
EOF
  done
fi

if [ -n "${missing}" ]; then
  echo "❌ hook-wiring-check: 有 hook 引用失聯（inspected:${inspected}）" >&2
  printf "%b\n" "${missing}" >&2
  exit 1
fi

if [ "${inspected}" -eq 0 ]; then
  echo "❌ hook-wiring-check: inspected:0——檢查對象為空，本身即異常（settings/.husky 缺失？）" >&2
  exit 1
fi

echo "hook-wiring-check: PASS inspected:${inspected}"
exit 0
