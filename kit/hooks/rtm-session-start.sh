#!/usr/bin/env bash
# rtm-session-start.sh — Claude Code SessionStart hook。K5 新作。
#
# 兩個職責：
#   ① rtm-index 缺失/過期 → 用 engines/rtm-check.ts --emit-index 重生
#      （SessionStart 一次性 node/tsx 成本 OK——熱路徑的 rtm-touch-reminder
#      只讀不生）。重生失敗（matrix 紅燈等）印一行不擋 session。
#   ② seen 檔 GC：.claude/kit/.rtm-seen/ 內 mtime >7 天者刪
#      （find -mtime +7——現役 session 檔 mtime 新，天然不清）。
#
# runtime 選擇（與 tests/cases/rtm-check.sh 的偵測同判準）：
#   node ≥23.6（type stripping 直跑 .ts）→ PATH 上的 tsx →
#   專案 node_modules/.bin/tsx → 皆無：明示無法重生後 exit 0（fail-open）。
#
# matrix hash 公式與 rtm-touch-reminder.sh／引擎 --emit-index 三處同步
# （內聯原因見 rtm-touch-reminder.sh 頭註；改動必三處同改）。
#
# fail-open：非 rtm 專案（matrix_dir 不存在）／找不到 repo 根 → 靜默 exit 0；
# index 新鮮 → 靜默 exit 0（噪音紀律）。bash 3.2：一律 ${var} 形式。

set -u

cat >/dev/null 2>&1 || true

project_dir="${CLAUDE_PROJECT_DIR:-}"
[ -n "${project_dir}" ] || project_dir="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "${project_dir}" ] || exit 0

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kit_root="$(cd "${script_dir}/.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || exit 0

matrix_dir="$(kit_decl_get "${project_dir}/.claude/kit/kit.yaml" matrix_dir docs/rtm/matrix)"
matrix_dir="${matrix_dir%/}"
matrix_abs="${project_dir}/${matrix_dir}"
[ -d "${matrix_abs}" ] || exit 0

# --- ② seen 檔 GC（先做——即使 index 新鮮也要清舊帳）------------------------
seen_dir="${project_dir}/.claude/kit/.rtm-seen"
if [ -d "${seen_dir}" ]; then
  find "${seen_dir}" -maxdepth 1 -type f -mtime +7 -exec rm -f {} + 2>/dev/null || true
fi

# --- ① index 新鮮度 → 必要時重生 -------------------------------------------
index="${project_dir}/.claude/kit/rtm-index.tsv"

# 與 rtm-touch-reminder.sh／引擎 --emit-index 同公式（見頭註）
matrix_hash_now() {
  (cd "${matrix_abs}" 2>/dev/null \
    && LC_ALL=C find . -maxdepth 1 -name '*.yaml' 2>/dev/null | LC_ALL=C sort \
    | while IFS= read -r mf; do cat "${mf}"; done) \
    | shasum -a 256 | awk '{print $1}'
}

if [ -f "${index}" ]; then
  header_hash="$(head -1 "${index}" | sed -n 's/.*matrix_hash=sha256:\([0-9a-f]*\).*/\1/p')"
  if [ -n "${header_hash}" ] && [ "${header_hash}" = "$(matrix_hash_now)" ]; then
    exit 0
  fi
fi

engine="${kit_root}/engines/rtm-check.ts"
[ -f "${engine}" ] || exit 0

# linked worktree 通常不重裝 node_modules。git common dir 在主 checkout 是
# <repo>/.git，在 linked worktree 也指回同一處；因此只把主 checkout
# 當作 js-yaml 依賴解析基準。engine 仍從 project_dir 讀 matrix/code 並
# 把 index 寫回 project_dir，不共用 worktree 產物。
dependency_root=""
git_common_dir="$(git -C "${project_dir}" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "${git_common_dir}" ]; then
  case "${git_common_dir}" in
    /*) ;;
    *) git_common_dir="${project_dir}/${git_common_dir}" ;;
  esac
  git_common_dir="$(cd "${git_common_dir}" 2>/dev/null && pwd -P)" || git_common_dir=""
  [ -z "${git_common_dir}" ] || dependency_root="$(dirname "${git_common_dir}")"
fi

runtime=""
node_ver="$(node --version 2>/dev/null || true)"
if [ -n "${node_ver}" ]; then
  node_major="${node_ver#v}"; node_major="${node_major%%.*}"
  node_minor="${node_ver#v*.}"; node_minor="${node_minor%%.*}"
  case "${node_major}" in ''|*[!0-9]*) node_major=0 ;; esac
  case "${node_minor}" in ''|*[!0-9]*) node_minor=0 ;; esac
  if [ "${node_major}" -gt 23 ] || { [ "${node_major}" -eq 23 ] && [ "${node_minor}" -ge 6 ]; }; then
    runtime="node"
  fi
fi
if [ -z "${runtime}" ]; then
  if command -v tsx >/dev/null 2>&1; then
    runtime="tsx"
  elif [ -x "${project_dir}/node_modules/.bin/tsx" ]; then
    runtime="${project_dir}/node_modules/.bin/tsx"
  fi
fi
if [ -z "${runtime}" ]; then
  echo "rtm-session-start: rtm-index 缺失/過期但無可用 runtime（node ≥23.6 或 tsx）——無法重生；rtm-touch-reminder 將以過期模式提醒"
  exit 0
fi

engine_args=(--repo-root "${project_dir}")
if [ -n "${dependency_root}" ] && [ "${dependency_root}" != "${project_dir}" ]; then
  engine_args+=(--dependency-root "${dependency_root}")
fi
engine_args+=(--emit-index)
out="$("${runtime}" "${engine}" "${engine_args[@]}" 2>&1)"
rc=$?
if [ "${rc}" -eq 0 ]; then
  line="$(printf '%s\n' "${out}" | grep '^rtm-check: index' | head -1)"
  suffix=""
  [ -n "${line}" ] && suffix="（${line#"rtm-check: "}）"
  echo "rtm-session-start: rtm-index 已重生${suffix}"
  exit 0
fi
echo "rtm-session-start: rtm-index 重生失敗（rtm-check 紅燈？）——$(printf '%s\n' "${out}" | head -2 | tr '\n' ' ')"
exit 0
