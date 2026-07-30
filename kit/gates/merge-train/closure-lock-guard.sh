#!/usr/bin/env bash
# closure-lock-guard.sh — main commit 的收尾鎖守門（pre-commit 呼叫）
#
# 三個職責：
#   1. 原始功能：鎖存在時凍結 main 非 docs commit（防直接 commit stale 收尾證據）
#   2. 🤖-1 merge 旁路執法：worktree-* branch merge 進 main 必須先取鎖——
#      即使無鎖也擋（防「不走 wave-gate 直接 merge」的旁路；三擋門在 push 才攔，
#      但 working tree 已被半 merge 佔住。實證 2026-07-26 upload-pipeline 波）
#   3. 🤖-4 docs 豁免：鎖存在時 staged 全部為 docs pattern → 放行（不影響
#      品質證據——typecheck/test/ratchet 不掃 .md。防死結：docs session 等鎖 ×
#      持鎖波等 docs commit。實證 2026-07-26 gate-governance 死結①）
#
# 邏輯（毫秒級）：
#   - 非 main → 放行
#   - MERGE_HEAD 是 worktree-* branch：
#     - 無鎖 → 擋（exit 2，提示先取鎖）
#     - 鎖持有者＝被 merge 的 branch → 放行
#     - 鎖被他波持有 → 擋（exit 2）
#   - MERGE_HEAD 非 worktree-*（git pull 等）→ 放行（不誤傷日常 pull）
#   - 無 MERGE_HEAD 的一般 commit：
#     - 無鎖 → 放行
#     - BYPASS=1 → 放行（帶警告）
#     - 純 docs staged → 放行
#     - 其他 → 擋（exit 1）
#
# 已知限制：無衝突的 git merge 自動 commit 不觸發 pre-commit，本守門攔不到。
# 但協議 merge 本來就該由鎖持有者執行；主要洩漏源已覆蓋。
#
# 全部用 ${var} 形式（macOS bash 3.2 + set -u 陷阱，同 wave-gate.sh 註記）。
#
# [kit 參數化] ①基底分支原硬編碼 main，改讀專案宣告 `.claude/kit/kit.yaml`
# 的 `base_branch`（預設 main）②docs 豁免 pattern（`*.md|.claude/dev/*`）
# 可由 kit.yaml `lock_docs_exempt` 覆寫（`|` 分隔多個 glob；無宣告時預設
# 保留 dfaa 原值）③worktree merge 偵測的 branch glob 原硬編碼
# refs/heads/worktree-*，改讀 `wave_branch_patterns`（空白分隔多 glob；
# 缺鍵 → 預設 "worktree-*"，與本檔原行為逐位元組相同——注意此檔歷史預設
# 不含 wave/*，與 wave-regate-guard／wave-close-guard 的預設不同，故各自
# 傳入各自的歷史預設值，宣告值一旦顯式給出則三檔共用同一份宣告）。宣告
# 空值＝關閉本段偵測（明示降級，該次 merge 視為日常 merge 不擋）。

set -u -o pipefail

# ── selftest 模式 ────────────────────────────────────────────────
if [ "${1:-}" = "selftest" ]; then
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  lock_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wave-closure-lock.sh"
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  git -C "${tmp}" init -q -b main
  git -C "${tmp}" -c user.email=test@local -c user.name=test \
    commit --allow-empty -q -m init

  git -C "${tmp}" checkout -q -b worktree-wave-test
  echo "code change" > "${tmp}/test.ts"
  git -C "${tmp}" add test.ts
  git -C "${tmp}" -c user.email=test@local -c user.name=test \
    commit -q -m "feat: test"
  wt_tip="$(git -C "${tmp}" rev-parse HEAD)"

  git -C "${tmp}" checkout -q main

  st_fail=0
  assert_rc() {
    local want="${1}" desc="${2}" rc
    shift 2
    ( cd "${tmp}" && "$@" ) >/dev/null 2>&1
    rc=$?
    if [ "${rc}" -eq "${want}" ]; then
      echo "  ✓ ${desc}"
    else
      echo "  ✗ ${desc}（期望 exit ${want}，實得 ${rc}）"
      st_fail=1
    fi
  }

  echo "selftest（temp repo: ${tmp}）"

  # ① 無鎖 + merge worktree branch → 擋（exit 2）
  echo "${wt_tip}" > "${tmp}/.git/MERGE_HEAD"
  echo "merged content" > "${tmp}/test.ts"
  git -C "${tmp}" add test.ts
  assert_rc 2 "① 無鎖 + merge worktree branch → 擋" bash "${self}"
  rm -f "${tmp}/.git/MERGE_HEAD"
  git -C "${tmp}" reset -q HEAD -- test.ts
  rm -f "${tmp}/test.ts"

  # ② 持鎖者 merge 自己的 branch → 放
  git -C "${tmp}" checkout -q worktree-wave-test
  ( cd "${tmp}" && bash "${lock_sh}" acquire ) >/dev/null 2>&1
  git -C "${tmp}" checkout -q main
  echo "${wt_tip}" > "${tmp}/.git/MERGE_HEAD"
  echo "merged content" > "${tmp}/test.ts"
  git -C "${tmp}" add test.ts
  assert_rc 0 "② 持鎖者 merge 自己的 worktree branch → 放" bash "${self}"
  rm -f "${tmp}/.git/MERGE_HEAD"
  git -C "${tmp}" reset -q HEAD -- test.ts
  git -C "${tmp}" checkout -q -- test.ts 2>/dev/null || true

  # ③ 非 worktree branch merge → 放（日常 pull 不誤傷）
  git -C "${tmp}" checkout -q -b feature-regular
  echo "feature" > "${tmp}/feature.ts"
  git -C "${tmp}" add feature.ts
  git -C "${tmp}" -c user.email=test@local -c user.name=test \
    commit -q -m "feat: regular"
  feat_tip="$(git -C "${tmp}" rev-parse HEAD)"
  git -C "${tmp}" checkout -q main
  echo "${feat_tip}" > "${tmp}/.git/MERGE_HEAD"
  echo "feature" > "${tmp}/feature.ts"
  git -C "${tmp}" add feature.ts
  assert_rc 0 "③ 非 worktree branch merge → 放（有鎖也不擋）" bash "${self}"
  rm -f "${tmp}/.git/MERGE_HEAD"
  git -C "${tmp}" reset -q HEAD -- feature.ts
  rm -f "${tmp}/feature.ts"

  # ④ 有鎖 + 純 docs staged → 放
  mkdir -p "${tmp}/.claude/dev"
  echo "docs content" > "${tmp}/readme.md"
  echo "wave data" > "${tmp}/.claude/dev/wave.md"
  git -C "${tmp}" add readme.md .claude/dev/wave.md
  assert_rc 0 "④ 有鎖 + 純 docs staged → 放" bash "${self}"
  git -C "${tmp}" reset -q HEAD

  # ⑤ 有鎖 + 混合 staged（docs + code）→ 擋
  echo "code" > "${tmp}/app.ts"
  git -C "${tmp}" add readme.md app.ts
  assert_rc 1 "⑤ 有鎖 + 混合 staged（docs + code）→ 擋" bash "${self}"
  git -C "${tmp}" reset -q HEAD

  # 清鎖（--force 強制釋放，不需切 branch）
  ( cd "${tmp}" && bash "${lock_sh}" release --force ) >/dev/null 2>&1

  # ⑥ 無鎖 + 一般 commit → 放
  git -C "${tmp}" add readme.md
  assert_rc 0 "⑥ 無鎖 + 一般 commit → 放" bash "${self}"
  git -C "${tmp}" reset -q HEAD

  if [ "${st_fail}" -eq 0 ]; then
    echo "selftest: PASS（6/6）"
    exit 0
  fi
  echo "selftest: FAIL"
  exit 1
fi

# ── 正式邏輯 ─────────────────────────────────────────────────────

kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "${kit_root}/lib/common.sh" 2>/dev/null || {
  echo "closure-lock-guard: 找不到 kit/lib/common.sh" >&2; exit 1; }

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
base_branch="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" base_branch main)"
lock_docs_exempt="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" lock_docs_exempt '*.md|.claude/dev/*')"
# 本檔歷史預設只含 worktree-*（不含 wave/*——與另兩支 merge-subject 判別
# 的預設不同，見上方 [kit 參數化] 註記）；宣告值一旦顯式給出即與其他檔
# 共用同一組 pattern。
wave_branch_patterns="$(kit_decl_get "${repo_root}/.claude/kit/kit.yaml" wave_branch_patterns 'worktree-*')"

# docs 豁免比對：宣告值以 `|` 分隔多個 glob，逐一 case 比對。
# for 展開時關 glob（set -f）防 pattern 被 cwd 檔名意外展開；case 比對
# 本身不受 noglob 影響。
docs_exempt_match() {
  local f="${1}" p
  local IFS='|'
  set -f
  for p in ${lock_docs_exempt}; do
    case "${f}" in
      ${p}) set +f; return 0 ;;
    esac
  done
  set +f
  return 1
}

branch="$(git rev-parse --abbrev-ref HEAD)"
if [ "${branch}" != "${base_branch}" ]; then
  exit 0
fi

common_dir="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
lock_dir="${common_dir}/wave-closure.lock"
info_file="${lock_dir}/info"
has_lock=0
if [ -d "${lock_dir}" ]; then
  has_lock=1
fi

holder=""
holder_epoch=""
age_min=0
if [ "${has_lock}" -eq 1 ]; then
  holder="$(awk -F'=' -v k=branch '$1==k {print substr($0, length(k)+2); exit}' "${info_file}" 2>/dev/null || true)"
  holder_epoch="$(awk -F'=' -v k=epoch '$1==k {print substr($0, length(k)+2); exit}' "${info_file}" 2>/dev/null || true)"
  age_min=$(( ($(date +%s) - ${holder_epoch:-0}) / 60 ))
fi

# ── 🤖-1 worktree merge 偵測（lock-hardening 缺陷 A）────────────
merge_head_path="$(git rev-parse --git-path MERGE_HEAD)"
merge_worktree_branch=""
if [ -f "${merge_head_path}" ] && [ -n "${wave_branch_patterns}" ]; then
  merge_head_val="$(cat "${merge_head_path}")"
  ref_patterns=()
  for p in ${wave_branch_patterns}; do
    ref_patterns+=("refs/heads/${p}")
  done
  while IFS= read -r ref; do
    ref_tip="$(git rev-parse --verify -q "${ref}" || true)"
    if [ -n "${ref_tip}" ] && [ "${ref_tip}" = "${merge_head_val}" ]; then
      merge_worktree_branch="${ref}"
      break
    fi
  done < <(git for-each-ref --format='%(refname:short)' "${ref_patterns[@]}")
elif [ -f "${merge_head_path}" ]; then
  echo "closure-lock-guard: wave_branch_patterns 宣告為空——worktree merge 偵測已停用（降級，本次 merge 視為日常 merge 不擋）。"
fi

if [ -n "${merge_worktree_branch}" ]; then
  if [ "${has_lock}" -eq 0 ]; then
    echo "closure-lock-guard: BLOCKED——merge worktree branch（${merge_worktree_branch}）需要先取收尾鎖。"
    echo "  跑 bash ~/projects/skills/kit/engines/wave-gate.sh 收尾 取鎖後再 merge。"
    exit 2
  fi
  if [ "${holder:-}" = "${merge_worktree_branch}" ]; then
    echo "closure-lock-guard: PASS（持有波 ${merge_worktree_branch} 的 merge）"
    exit 0
  fi
  echo "closure-lock-guard: BLOCKED——merge worktree branch（${merge_worktree_branch}）但鎖被 ${holder:-?} 持有。"
  echo "  等 ${holder:-?} 收尾完成（通常 <20 分鐘），或確認要搶：先清鎖再取。"
  exit 2
fi

# 非 worktree branch 的 merge（日常 git pull 等）→ 不擋
if [ -f "${merge_head_path}" ]; then
  exit 0
fi

# ── 一般 commit（非 merge）───────────────────────────────────────

if [ "${has_lock}" -eq 0 ]; then
  exit 0
fi

if [ "${WAVE_LOCK_BYPASS:-0}" = "1" ]; then
  echo "closure-lock-guard: ⚠️ BYPASS——收尾鎖被 ${holder:-?} 持有中仍強制 commit，"
  echo "  該波收尾證據將 stale、需整輪重跑。"
  exit 0
fi

# ── 🤖-4 docs 豁免（lock-hardening 缺陷——訊息與行為不一致）───────
# staged 全部命中 docs pattern → 放行（不影響品質證據）
all_docs=1
staged_count=0
while IFS= read -r staged_file; do
  staged_count=$(( staged_count + 1 ))
  if ! docs_exempt_match "${staged_file}"; then
    all_docs=0
    break
  fi
done < <(git diff --cached --name-only)

if [ "${staged_count}" -gt 0 ] && [ "${all_docs}" -eq 1 ]; then
  echo "closure-lock-guard: PASS（純 docs commit，不影響收尾品質證據）"
  exit 0
fi

echo "closure-lock-guard: BLOCKED——wave 收尾進行中，main 暫時凍結。"
echo "  持有者：${holder:-?}（已持有 ${age_min} 分鐘）"
echo "  選項："
echo "    1. 等收尾完成再 commit（通常 <20 分鐘）"
echo "    2. 確定要插隊：WAVE_LOCK_BYPASS=1 git commit ...（收尾波會被打回重跑）"
echo "    3. 疑似殘鎖（持有 >6 小時）：bash ~/projects/skills/kit/gates/merge-train/wave-closure-lock.sh release --force"
exit 1
